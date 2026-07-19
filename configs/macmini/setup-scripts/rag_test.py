import os
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK","1")
import torch
from sentence_transformers import SentenceTransformer, CrossEncoder
dev = "mps" if torch.backends.mps.is_available() else "cpu"
print("device:", dev)
RURI="/Users/gapul/rag-models/ruri-v3-310m"
RERANK="/Users/gapul/rag-models/japanese-reranker-base-v2"
docs = ["東京の天気は今日は晴れです。", "次回の定例会議は金曜日の午後に行います。", "猫はとても可愛い動物です。"]
query = "会議はいつ開催されますか"
print("[Ruri v3 埋め込み]", flush=True)
emb = SentenceTransformer(RURI, device=dev)
de = emb.encode(["文章: "+d for d in docs], normalize_embeddings=True)
qe = emb.encode(["クエリ: "+query], normalize_embeddings=True)
sims = (qe @ de.T)[0]
print("埋め込み類似度(高いほど関連):")
for i,d in enumerate(docs): print(f"  {sims[i]:.3f}  {d}")
print("[リランカー]", flush=True)
ce = CrossEncoder(RERANK, device=dev)
sc = ce.predict([[query,d] for d in docs])
print("リランクスコア:")
for i,d in enumerate(docs): print(f"  {sc[i]:.3f}  {d}")
print("RAG_TEST_OK")
