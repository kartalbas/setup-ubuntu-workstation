#!/usr/bin/env python3
"""opencode-llms.py TEMPLATE OUT — fill templates/opencode.json with the
user's own two LLM servers (OpenAI-compatible, e.g. llama-server): reads
"URL TOKEN" per server from stdin (llm1 first), asks each server for its model
and context size, writes OUT with mode 0600. Used by `./setup.sh opencode`."""
import json, os, sys, urllib.request

def get(url, token):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)

tmpl, out = sys.argv[1], sys.argv[2]
conf = json.load(open(tmpl))
for n, line in enumerate(sys.stdin.read().split("\n")[:2], 1):
    url, token = line.split(None, 1)
    url = url.rstrip("/")
    models = get(f"{url}/models", token)["data"]
    model = models[0]["id"]
    ctx = models[0].get("meta", {}).get("n_ctx_train") or 131072
    try:  # llama-server reports the context it actually serves
        ctx = get(f"{url.removesuffix('/v1')}/props", token)["default_generation_settings"]["n_ctx"]
    except Exception:
        pass
    p = conf["provider"][f"llm{n}"]
    p["options"] = {"baseURL": url, "apiKey": token.strip()}
    p["models"] = {model: {"name": model, "limit": {"context": ctx, "output": 32768}}}
    if n == 1:
        conf["model"] = f"llm1/{model}"
    print(f"llm{n}: {model} (context {ctx})", file=sys.stderr)
os.makedirs(os.path.dirname(out), exist_ok=True)
fd = os.open(out + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    json.dump(conf, f, indent=2)
    f.write("\n")
os.replace(out + ".tmp", out)
