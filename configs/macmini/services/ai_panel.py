import os, subprocess, tempfile, glob, shutil
from fastapi import FastAPI, UploadFile, File, Form
from fastapi.responses import HTMLResponse, FileResponse, PlainTextResponse
from starlette.background import BackgroundTask

HOME = os.path.expanduser("~")
BIN = f"{HOME}/.local/bin"
ENV = dict(os.environ, PATH=f"{BIN}:/opt/homebrew/bin:/run/current-system/sw/bin:/usr/bin:/bin", HOME=HOME, PYTORCH_ENABLE_MPS_FALLBACK="1")
app = FastAPI(title="macmini AI panel")

def run(cmd, timeout=1200):
    r = subprocess.run(cmd, env=ENV, capture_output=True, text=True, timeout=timeout)
    return r.stdout, r.stderr, r.returncode

def save(up: UploadFile, d):
    p = os.path.join(d, up.filename.replace("/", "_"))
    with open(p, "wb") as f: shutil.copyfileobj(up.file, f)
    return p

@app.get("/", response_class=HTMLResponse)
def home():
    return HTML

@app.get("/status")
def status():
    disk = shutil.disk_usage(HOME)
    return {"disk_free_gb": round(disk.free / 1024 ** 3, 1)}

@app.post("/transcribe", response_class=PlainTextResponse)
async def transcribe(file: UploadFile = File(...), model: str = Form("fast"), diarize: str = Form("no")):
    d = tempfile.mkdtemp(); p = save(file, d)
    tool = f"{BIN}/transcribe-diarize" if diarize == "yes" else f"{BIN}/transcribe"
    args = [tool, p, "ja", model] if diarize == "yes" else [tool, p, "ja", "txt", model]
    out, err, rc = run(args)
    base = os.path.splitext(p)[0]
    res = ""
    for ext in (".diarized.txt", ".txt"):
        if os.path.exists(base + ext): res = open(base + ext).read(); break
    shutil.rmtree(d, ignore_errors=True)
    return res or (out + "\n" + err)

@app.post("/tts")
async def tts(text: str = Form(...), style: str = Form("Neutral")):
    d = tempfile.mkdtemp(); out_wav = os.path.join(d, "tts.wav")
    run([f"{BIN}/tts", text, out_wav, style])
    return FileResponse(out_wav, media_type="audio/wav", filename="tts.wav",
                        background=BackgroundTask(shutil.rmtree, d, True))

@app.post("/clone")
async def clone(ref: UploadFile = File(...), text: str = Form(...)):
    d = tempfile.mkdtemp(); rp = save(ref, d); out_wav = os.path.join(d, "cloned.wav")
    run([f"{BIN}/voice-clone", rp, text, out_wav])
    return FileResponse(out_wav, media_type="audio/wav", filename="cloned.wav",
                        background=BackgroundTask(shutil.rmtree, d, True))

@app.post("/vision", response_class=PlainTextResponse)
async def vision(image: UploadFile = File(...), mode: str = Form("describe"), prompt: str = Form("")):
    d = tempfile.mkdtemp(); p = save(image, d)
    args = [f"{BIN}/ocr", p] if mode == "ocr" else ([f"{BIN}/describe", p, prompt] if prompt else [f"{BIN}/describe", p])
    out, err, rc = run(args)
    shutil.rmtree(d, ignore_errors=True)
    return out.strip() or err

@app.post("/separate")
async def separate(audio: UploadFile = File(...)):
    d = tempfile.mkdtemp(); p = save(audio, d)
    run([f"{BIN}/separate", p, d])
    stems = [f for f in glob.glob(d + "/*") if f != p and (f.endswith(".flac") or f.endswith(".wav"))]
    zd = tempfile.mkdtemp(); zp = os.path.join(zd, "stems.zip")
    import zipfile
    with zipfile.ZipFile(zp, "w") as z:
        for s in stems: z.write(s, os.path.basename(s))
    shutil.rmtree(d, ignore_errors=True)
    return FileResponse(zp, media_type="application/zip", filename="stems.zip",
                        background=BackgroundTask(shutil.rmtree, zd, True))

HTML = """<!doctype html><html lang=ja><head><meta charset=utf-8>
<meta name=viewport content=\"width=device-width,initial-scale=1\">
<title>macmini AI</title><style>
body{font-family:-apple-system,sans-serif;margin:0;background:#191724;color:#e0def4}
h1{font-size:20px;padding:14px;margin:0;background:#1f1d2e}
.card{background:#26233a;margin:10px;border-radius:12px;padding:14px}
.card h2{font-size:16px;margin:0 0 10px}
input,textarea,select,button{width:100%;box-sizing:border-box;padding:11px;margin:5px 0;border-radius:8px;border:1px solid #403d52;background:#1f1d2e;color:#e0def4;font-size:16px}
button{background:#31748f;color:#fff;border:none;font-weight:600}
.out{white-space:pre-wrap;background:#1f1d2e;padding:10px;border-radius:8px;margin-top:8px;font-size:14px}
audio{width:100%;margin-top:8px}
@media (prefers-color-scheme:light){
body{background:#faf4ed;color:#575279}
h1,input,textarea,select,.out{background:#fffaf3;color:#575279}
.card{background:#f2e9e1}
input,textarea,select,button{border-color:#dfdad9}
button{background:#286983;color:#fffaf3}
}
</style></head><body><h1>macmini AI パネル</h1>

<div class=card><h2>システム状態</h2>
<button onclick=status()>更新</button><div class=out id=sto>読み込み中...</div></div>

<div class=card><h2>文字起こし</h2>
<input type=file id=trf accept=\"audio/*,video/*\">
<select id=trm><option value=fast>fast(turbo)</option><option value=accurate>accurate(large-v3)</option></select>
<label><input type=checkbox id=trd style=\"width:auto\"> 話者分離</label>
<button onclick=transcribe()>実行</button><div class=out id=tro></div></div>

<div class=card><h2>読み上げ TTS</h2>
<textarea id=ttt rows=2 placeholder=喋らせる文章></textarea>
<select id=tts><option>Neutral</option><option>Happy</option><option>Sad</option><option>Angry</option><option>Fear</option><option>Surprise</option></select>
<button onclick=dotts()>生成</button><div id=tto></div></div>

<div class=card><h2>画像理解 / OCR</h2>
<input type=file id=vif accept=\"image/*\">
<select id=vim><option value=describe>説明</option><option value=ocr>文字抽出(OCR)</option></select>
<input id=vip placeholder=\"質問(任意)\">
<button onclick=vision()>実行</button><div class=out id=vio></div></div>

<div class=card><h2>声クローン</h2>
<input type=file id=clr accept=\"audio/*\"> <span style=font-size:12px>参照音声3-10秒</span>
<textarea id=clt rows=2 placeholder=喋らせる文章></textarea>
<button onclick=doclone()>生成</button><div id=clo></div></div>

<div class=card><h2>音声分離(ボーカル/BGM)</h2>
<input type=file id=spf accept=\"audio/*\">
<button onclick=dosep()>分離(zipで取得)</button><div class=out id=spo></div></div>

<script>
function fd(o){let f=new FormData();for(let k in o)f.append(k,o[k]);return f}
async function status(){let r=await fetch("/status");let s=await r.json();sto.textContent="空き容量: "+s.disk_free_gb+" GB"}
async function transcribe(){tro.textContent=\"...\";let f=trf.files[0];let r=await fetch(\"/transcribe\",{method:\"POST\",body:fd({file:f,model:trm.value,diarize:trd.checked?\"yes\":\"no\"})});tro.textContent=await r.text()}
async function dotts(){tto.textContent=\"...\";let r=await fetch(\"/tts\",{method:\"POST\",body:fd({text:ttt.value,style:tts.value})});let b=await r.blob();tto.innerHTML=\"<audio controls src=\"+URL.createObjectURL(b)+\"></audio>\"}
async function vision(){vio.textContent=\"...\";let r=await fetch(\"/vision\",{method:\"POST\",body:fd({image:vif.files[0],mode:vim.value,prompt:vip.value})});vio.textContent=await r.text()}
async function doclone(){clo.textContent=\"...\";let r=await fetch(\"/clone\",{method:\"POST\",body:fd({ref:clr.files[0],text:clt.value})});let b=await r.blob();clo.innerHTML=\"<audio controls src=\"+URL.createObjectURL(b)+\"></audio>\"}
async function dosep(){spo.textContent=\"分離中(数十秒)...\";let r=await fetch(\"/separate\",{method:\"POST\",body:fd({audio:spf.files[0]})});let b=await r.blob();let u=URL.createObjectURL(b);spo.innerHTML=\"<a href=\"+u+\" download=stems.zip style=color:#c4a7e7>stems.zip をダウンロード</a>\"}
status()</script></body></html>"""
