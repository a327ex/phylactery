"""gemini_image.py -- images from Gemini's image models (Nano Banana Pro / 2.x) with input images, for the store art
(Phylactery 20, 2026-10-18; the fal.ai balance ran out). Run with the Gemini tool's venv:

    C:/Users/a327e/Desktop/tools/gemini/venv/Scripts/python tools/gemini_image.py jobs.json [--only key ...]

jobs.json: {"models": {name: {"id": model id, "aspect": "16:9", "size": "2K"}},
            "jobs": [{"key", "prompt_file" | "prompt", "images": [paths relative to the jobs file], "models": [names]}]}
Saves out/<model name>/<key>.png next to the jobs file; every call (tokens, seconds, errors) appended to log-gemini.jsonl.
The key comes from the Gemini tool (Desktop/tools/gemini/api_key.txt) and is never printed.
"""
import argparse, json, pathlib, sys, time
sys.path.insert(0, 'C:/Users/a327e/Desktop/tools/gemini')
import gemini                                   # noqa: E402  (its api_key() only)
from google import genai                        # noqa: E402
from google.genai import types                  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('jobs')
    ap.add_argument('--only', nargs='*')
    ap.add_argument('--model', nargs='*')
    a = ap.parse_args()
    jp = pathlib.Path(a.jobs).resolve()
    base = jp.parent
    spec = json.loads(jp.read_text(encoding='utf-8'))
    client = genai.Client(api_key=gemini.api_key())
    log = base / 'log-gemini.jsonl'
    for mname, m in spec['models'].items():
        if a.model and mname not in a.model:
            continue
        for j in spec['jobs']:
            if a.only and j['key'] not in a.only:
                continue
            if j.get('models') and mname not in j['models']:
                continue
            prompt = j.get('prompt') or (base / j['prompt_file']).read_text(encoding='utf-8').strip()
            parts = [prompt]
            for f in j.get('images', []):
                p = (base / f).resolve()
                mime = 'image/png' if p.suffix.lower() == '.png' else 'image/jpeg'
                parts.append(types.Part.from_bytes(data=p.read_bytes(), mime_type=mime))
            cfg = types.GenerateContentConfig(response_modalities=['IMAGE', 'TEXT'],
                                              image_config=types.ImageConfig(aspect_ratio=j.get('aspect', m.get('aspect', '16:9')),
                                                                             image_size=j.get('size', m.get('size', '2K'))))
            t0 = time.time()
            rec = {'time': time.strftime('%Y-%m-%dT%H:%M:%S'), 'model': mname, 'model_id': m['id'], 'key': j['key'],
                   'images': j.get('images', [])}
            try:
                r = client.models.generate_content(model=m['id'], contents=parts, config=cfg)
                rec['seconds'] = round(time.time() - t0, 1)
                um = r.usage_metadata
                rec['tokens'] = {'in': getattr(um, 'prompt_token_count', None), 'out': getattr(um, 'candidates_token_count', None)}
                saved = None
                text = []
                for part in (r.candidates[0].content.parts if r.candidates and r.candidates[0].content else []):
                    if part.inline_data and part.inline_data.data and not saved:
                        out = base / 'out' / mname / f"{j['key']}.png"
                        out.parent.mkdir(parents=True, exist_ok=True)
                        out.write_bytes(part.inline_data.data)
                        saved = out
                    elif part.text:
                        text.append(part.text)
                rec['ok'] = saved is not None
                if saved:
                    rec['out'] = str(saved.relative_to(base)).replace('\\', '/')
                    print(f"OK      {mname:10} {j['key']:22} {rec['seconds']}s  tokens {rec['tokens']}")
                else:
                    reason = r.candidates[0].finish_reason if r.candidates else getattr(r, 'prompt_feedback', None)
                    rec['error'] = f'no image; finish={reason}; text={" ".join(text)[:300]}'
                    print(f"NOIMAGE {mname:10} {j['key']:22} {rec['error']}")
            except Exception as e:                          # noqa: BLE001  (logged, next job)
                rec['ok'] = False
                rec['seconds'] = round(time.time() - t0, 1)
                rec['error'] = repr(e)[:600]
                print(f"ERROR   {mname:10} {j['key']:22} {rec['error'][:300]}")
            with log.open('a', encoding='utf-8') as f:
                f.write(json.dumps(rec, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    main()
