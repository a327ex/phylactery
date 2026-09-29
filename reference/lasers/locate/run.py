# locate the best beam moment in each candidate (Gemini 3 Flash over the YouTube URL, 1 fps, low res), 4 at a time
import json, os, subprocess
from concurrent.futures import ThreadPoolExecutor
G = r'C:\Users\a327e\Desktop\tools\gemini'
q = open('locate/q.txt').read()
def one(c):
    out = f"locate/{c['id']}.txt"
    if os.path.exists(out) and os.path.getsize(out) > 20: return c['id'] + ' (had it)'
    r = subprocess.run([os.path.join(G, 'venv', 'Scripts', 'python.exe'), os.path.join(G, 'gemini.py'), 'ask', c['url'], q % c['title'],
                        '--fps', '1', '--res', 'low', '--model', 'gemini-3-flash-preview', '--slug', 'laser-' + c['id'], '--out', out], capture_output=True, text=True)
    return c['id'] + ('' if r.returncode == 0 else ' FAIL ' + r.stderr[-200:])
with ThreadPoolExecutor(4) as ex:
    for m in ex.map(one, json.load(open('candidates.json'))): print(m, flush=True)
