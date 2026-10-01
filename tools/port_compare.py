"""port_compare.py <capture dir> <lua trace.json> -- the port to Anchor: three.js's draws (a GL
capture, web/src/glcapture.js) against the Anchor renderer's (port_trace_frame in port/debug.lua),
matched by program (the i-th draw of a program on one side with the i-th on the other), with the
uniforms that differ and by how much."""
import json, sys, os, hashlib, re, collections

cap_dir, lua_path = sys.argv[1], sys.argv[2]
root = os.path.join(os.path.dirname(__file__), '..')
lib_dir = os.path.join(root, 'assets', 'port', 'programs')
H = lambda vs, fs: hashlib.sha1((vs + '\n----\n' + fs).encode()).hexdigest()[:12]

F = json.load(open(os.path.join(cap_dir, 'frame.json')))
prog_hash_cap = {}
for gid, tid in F['programs'].items():
    vs = open(os.path.join(cap_dir, 'programs', f'{tid}_vs.glsl'), encoding='utf-8').read()
    fs = open(os.path.join(cap_dir, 'programs', f'{tid}_fs.glsl'), encoding='utf-8').read()
    prog_hash_cap[int(gid)] = H(vs, fs)
index = {}
for line in open(os.path.join(lib_dir, 'programs.lua'), encoding='utf-8'):
    m = re.match(r'\s*\["(.*)"\] = (\d+),', line)
    if m: index[m.group(1)] = int(m.group(2))
lib_hash = {}
for key, n in index.items():
    vs = open(os.path.join(lib_dir, f'{n:02d}.vs.glsl'), encoding='utf-8').read()
    fs = open(os.path.join(lib_dir, f'{n:02d}.fs.glsl'), encoding='utf-8').read()
    lib_hash[key] = H(vs, fs)
name_of_hash = collections.defaultdict(set)
for k, h in lib_hash.items(): name_of_hash[h].add(k)

js = [c for c in F['commands'] if c['op'] == 'draw']
lua = [e for e in json.load(open(lua_path)) if e.get('op') == 'draw']
by_js, by_lua = collections.defaultdict(list), collections.defaultdict(list)
for c in js: by_js[prog_hash_cap[c['prog']]].append(c)
for e in lua: by_lua[lib_hash.get(e['key'], 'missing:' + e['key'])].append(e)

def flat(v):
    if isinstance(v, bool): return [1.0 if v else 0.0]
    if isinstance(v, (int, float)): return [float(v)]
    if isinstance(v, str):
        return [{'Infinity': float('inf'), '-Infinity': float('-inf'), 'NaN': float('nan')}.get(v, 0.0)]
    if isinstance(v, list): return [x for e in v for x in flat(e)]
    return []

print(f'draws: three.js {len(js)}, anchor {len(lua)}')
for h in sorted(set(by_js) | set(by_lua), key=lambda h: sorted(name_of_hash.get(h, {h}))[0]):
    a, b = by_js.get(h, []), by_lua.get(h, [])
    name = ','.join(sorted(name_of_hash.get(h, {'(not in library)'})))
    flag = '' if len(a) == len(b) else '   <-- COUNT DIFFERS'
    print(f'\n{name}: three.js {len(a)} draws, anchor {len(b)}{flag}')
    worst = collections.Counter()
    missing_l, missing_j = set(), set()
    for c, e in zip(a, b):
        units = set(c['units'].keys())
        for k, v in c['uniforms'].items():
            if k in units: continue
            if k not in e['uniforms']: missing_l.add(k); continue
            x, y = flat(v), flat(e['uniforms'][k])
            if len(x) != len(y): worst[k] = max(worst[k], 99); continue
            d = max((abs(p - q) if (p == p and q == q and abs(p) != float('inf')) else (0 if p == q or (p != p and q != q) else 99)) for p, q in zip(x, y)) if x else 0
            if d > 0: worst[k] = max(worst[k], d)
        for k in e['uniforms']:
            if k not in c['uniforms'] and k not in units: missing_j.add(k)
    for k, d in sorted(worst.items(), key=lambda kv: -kv[1])[:12]:
        if d > 1e-5: print(f'   {k}: max |diff| {d:.6g}')
    if missing_l: print('   set by three.js only:', sorted(missing_l)[:12])
    if missing_j: print('   set by anchor only:', sorted(missing_j)[:12])
