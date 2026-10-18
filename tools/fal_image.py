"""Generate images with fal.ai models, one request at a time.
(Copied from brutal-behavior/tools/fal_image.py on 2026-10-18 for the store art; adds "image_files", a list sent as image_urls.)

Key: the FAL_KEY environment variable, else the first line of
C:/Users/a327e/Desktop/tools/fal/api_key.txt. The key is never printed or logged.

  python tools/fal_image.py --jobs jobs-fal.json [--only KEY ...] [--model MODEL ...]

A jobs file is a JSON object {"models": {name: {"id": fal model id, "args": {...}}},
"jobs": [{"key", "prompt_file" | "prompt"}]}. Every job runs on every model (or the
--model subset, or the job's own "models" list), saving out/<model name>/<key>.<ext>.
A job may add "args" (merged over the model's) and "image_file" (sent as a base64 data
URI in image_url, for image-to-image models). Model args are passed through unchanged,
so any provider setting (size, safety options) lives in the jobs file, in plain view.
Every outcome (image, flagged image, or error with fal's message) is appended to
log-fal.jsonl next to the jobs file.
"""
import argparse
import base64
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request

KEY_FILE = pathlib.Path(r"C:\Users\a327e\Desktop\tools\fal\api_key.txt")


def api_key():
    k = os.environ.get("FAL_KEY", "").strip()
    if not k and KEY_FILE.exists():
        lines = KEY_FILE.read_text(encoding="utf-8").strip().splitlines()
        k = lines[0].strip() if lines else ""
    if not k:
        sys.exit(f"no API key: set FAL_KEY or put the key on the first line of {KEY_FILE}")
    return k


def http_json(key, url, method="GET", payload=None, timeout=60):
    req = urllib.request.Request(url, method=method, data=json.dumps(payload).encode() if payload is not None else None,
                                 headers={"Authorization": "Key " + key, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def call(key, model_id, payload, max_wait=900):
    """Submit through fal's queue API, poll the status every few seconds, return the result.
    Returns (result, error, seconds)."""
    t0 = time.time()
    secs = lambda: round(time.time() - t0, 1)
    try:
        sub = http_json(key, "https://queue.fal.run/" + model_id, "POST", payload)
        status_url, response_url = sub["status_url"], sub["response_url"]
        while True:
            st = http_json(key, status_url)
            if st.get("status") == "COMPLETED":
                break
            if time.time() - t0 > max_wait:
                return None, {"status": None, "body": f"gave up after {max_wait}s, last status {st.get('status')}"}, secs()
            time.sleep(4)
        return http_json(key, response_url, timeout=120), None, secs()
    except urllib.error.HTTPError as e:
        try:
            body = e.read().decode("utf-8", "replace")
        except Exception:
            body = ""
        return None, {"status": e.code, "body": body[:2000]}, secs()
    except urllib.error.URLError as e:
        return None, {"status": None, "body": f"network error: {e.reason}"}, secs()
    except (TimeoutError, OSError, KeyError, ValueError) as e:
        return None, {"status": None, "body": f"error: {e!r}"}, secs()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", required=True)
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--model", nargs="*")
    a = ap.parse_args()

    jobs_path = pathlib.Path(a.jobs).resolve()
    base = jobs_path.parent
    spec = json.loads(jobs_path.read_text(encoding="utf-8"))
    models = {n: m for n, m in spec["models"].items() if not a.model or n in a.model}
    jobs = [j for j in spec["jobs"] if not a.only or j["key"] in a.only]
    key = api_key()
    log = base / "log-fal.jsonl"

    for name, m in models.items():
        for j in jobs:
            if j.get("models") and name not in j["models"]:
                continue
            prompt = j.get("prompt") or (base / j["prompt_file"]).read_text(encoding="utf-8").strip()
            args = {**m.get("args", {}), **j.get("args", {})}
            payload = {"prompt": prompt, **args}
            if j.get("image_files"):
                uris = []
                for f in j["image_files"]:
                    ip = (base / f).resolve()
                    mime = "image/png" if ip.suffix.lower() == ".png" else "image/jpeg"
                    uris.append(f"data:{mime};base64," + base64.b64encode(ip.read_bytes()).decode())
                payload["image_urls"] = uris
            elif j.get("image_file"):
                img_path = (base / j["image_file"]).resolve()
                mime = "image/png" if img_path.suffix.lower() == ".png" else "image/jpeg"
                uri = f"data:{mime};base64," + base64.b64encode(img_path.read_bytes()).decode()
                if j.get("image_field") == "image_urls":   # e.g. alibaba/qwen-image-3/edit takes a list
                    payload["image_urls"] = [uri]
                else:
                    payload["image_url"] = uri
            data, err, secs = call(key, m["id"], payload)
            rec = {"time": time.strftime("%Y-%m-%dT%H:%M:%S"), "model": name, "model_id": m["id"],
                   "args": args, "image_file": j.get("image_file"), "key": j["key"], "seconds": secs}
            if err:
                rec.update(ok=False, error=err)
                print(f"ERROR   {name:12} {j['key']:20} status={err['status']}  {err['body'][:300]}")
            else:
                img = (data.get("images") or [{}])[0]
                nsfw = data.get("has_nsfw_concepts")
                rec.update(ok=bool(img.get("url")), width=img.get("width"), height=img.get("height"),
                           nsfw=nsfw, seed=data.get("seed"))
                if img.get("url"):
                    ext = (img.get("content_type") or "image/png").split("/")[-1].replace("jpeg", "jpg")
                    out = base / "out" / name / f"{j['key']}.{ext}"
                    out.parent.mkdir(parents=True, exist_ok=True)
                    try:
                        with urllib.request.urlopen(img["url"], timeout=180) as r:
                            out.write_bytes(r.read())
                    except (urllib.error.URLError, TimeoutError, OSError) as e:
                        rec.update(ok=False, error={"status": None, "body": f"download failed: {e!r}"})
                        print(f"ERROR   {name:12} {j['key']:20} download failed: {e!r}")
                        with log.open("a", encoding="utf-8") as f:
                            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
                        continue
                    rec["out"] = str(out.relative_to(base)).replace("\\", "/")
                    print(f"OK      {name:12} {j['key']:20} {img.get('width')}x{img.get('height')}  "
                          f"{secs}s  nsfw={nsfw}")
                else:
                    print(f"NOIMAGE {name:12} {j['key']:20} {json.dumps(data)[:300]}")
            with log.open("a", encoding="utf-8") as f:
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
