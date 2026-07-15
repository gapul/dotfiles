import sys, json, urllib.request
model = sys.argv[1]
prompt = sys.argv[2] if len(sys.argv) > 2 else sys.stdin.read()
body = json.dumps({"model": model, "prompt": prompt, "think": False, "stream": False}).encode()
req = urllib.request.Request("http://127.0.0.1:11434/api/generate", data=body, headers={"Content-Type": "application/json"})
try:
    print(json.load(urllib.request.urlopen(req, timeout=900)).get("response", "(no response)").strip())
except Exception as e:
    # think未対応モデル等でエラーなら think抜きで再試行
    body = json.dumps({"model": model, "prompt": prompt, "stream": False}).encode()
    req = urllib.request.Request("http://127.0.0.1:11434/api/generate", data=body, headers={"Content-Type": "application/json"})
    print(json.load(urllib.request.urlopen(req, timeout=900)).get("response", "(err: %s)" % e).strip())
