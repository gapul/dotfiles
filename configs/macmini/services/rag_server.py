import os
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
import torch
from fastapi import FastAPI
from pydantic import BaseModel
from sentence_transformers import SentenceTransformer, CrossEncoder

DEV = "mps" if torch.backends.mps.is_available() else "cpu"
RURI = os.path.expanduser("~/ai/models/rag/ruri-v3-310m")
RERANK = os.path.expanduser("~/ai/models/rag/japanese-reranker-base-v2")
print("loading models on", DEV, flush=True)
emb = SentenceTransformer(RURI, device=DEV)
rer = CrossEncoder(RERANK, device=DEV)
app = FastAPI()

class EmbReq(BaseModel):
    input: object
    model: str = "ruri-v3-310m"

@app.post("/v1/embeddings")
def embeddings(r: EmbReq):
    texts = r.input if isinstance(r.input, list) else [r.input]
    # Ruri作法: 文書は「文章: 」前置(検索クエリ側はクライアントが「クエリ: 」を付ける想定だが自動判定なしなので文書扱い)
    vecs = emb.encode(texts, normalize_embeddings=True)  # 汎用API=無プレフィックス対称
    data = [{"object": "embedding", "index": i, "embedding": v.tolist()} for i, v in enumerate(vecs)]
    return {"object": "list", "data": data, "model": r.model,
            "usage": {"prompt_tokens": 0, "total_tokens": 0}}

class QEmbReq(BaseModel):
    input: object
@app.post("/v1/embeddings_query")
def embeddings_query(r: QEmbReq):
    texts = r.input if isinstance(r.input, list) else [r.input]
    vecs = emb.encode(["クエリ: " + t for t in texts], normalize_embeddings=True)
    return {"object": "list", "data": [{"object": "embedding", "index": i, "embedding": v.tolist()} for i, v in enumerate(vecs)]}

class RerankReq(BaseModel):
    query: str
    documents: list
    top_n: int = 0
@app.post("/rerank")
def rerank(r: RerankReq):
    scores = rer.predict([[r.query, d] for d in r.documents])
    ranked = sorted([{"index": i, "document": r.documents[i], "relevance_score": float(scores[i])} for i in range(len(r.documents))], key=lambda x: -x["relevance_score"])
    return {"results": ranked[:r.top_n] if r.top_n else ranked}

@app.get("/health")
def health(): return {"status": "ok", "device": DEV}
