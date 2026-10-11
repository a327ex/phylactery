"""sfx_bake.py -- my sound picks into the game (2026-10-10, "Lich Survivors 13": the owner asked me to pick the sounds
myself, megablock's way; slots I am not sure of stay without a file and are marked unsure, which the game shows red).

  python tools/sfx_spec.py            # the picks (tools/sfx_spec.py) -> tools/sfx_picks.json, every path checked
  python tools/sfx_bake.py            # convert what changed, write sound_picks.lua
  python tools/sfx_bake.py --list     # the picks as a table (slot, unsure, files, why)

Each picked file becomes assets/sfx/<slot>_<n>.ogg (ffmpeg libvorbis -q:a 10, full length and channels, no trims: the
owner's rule). sound_picks.lua is written in the format megablock's in-game editor writes (shared with "Megablock 2",
2026-10-10): slot -> files, src, vol, and for a red slot unsure = true + candidates (pack paths the editor offers to
audition, never played); the editor's own fields (pitch_lo/hi, delay, bits, sr, mute, the 3D ones) are kept as set.

His edits win: tools/.sfx_baked.json remembers what the last bake wrote for each slot; a slot whose entry in
sound_picks.lua no longer matches it (he re-picked it, changed anything about it in the editor) is kept exactly as he
left it, and slots the json doesn't name stay too.
"""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
ROOT = os.path.join(os.environ.get('USERPROFILE', r'C:\Users\a327e'), 'Desktop', 'sound packs')
PICKS_JSON = os.path.join(HERE, 'sfx_picks.json')
PICKS_LUA = os.path.join(GAME, 'sound_picks.lua')
BAKED = os.path.join(HERE, '.sfx_baked.json')
LUA = os.path.join(GAME, '..', 'Anchor', 'workflow', 'tools', 'lua54.exe')
CAVE_KEYS = ('reverb', 'width', 'rolloff', 'near', 'far', 'air', 'occlusion', 'doppler', 'travel', 'lowcut')

# sound_picks.lua -> JSON on stdout, read by Lua itself (any fields: strings, numbers, booleans, lists, tables)
DUMP_LUA = r'''
local function enc(v)
  local t = type(v)
  if t == 'string' then return '"' .. v:gsub('[%c\\"]', function(c)
      if c == '\\' or c == '"' then return '\\' .. c end
      return string.format('\\u%04x', c:byte()) end) .. '"'
  elseif t == 'number' then
    if v ~= v or v == math.huge or v == -math.huge then return 'null' end
    return (math.type(v) == 'integer') and tostring(v) or string.format('%.17g', v)
  elseif t == 'boolean' then return tostring(v)
  elseif t == 'table' then
    local n = #v
    local is_list = n > 0 or next(v) == nil
    if is_list then for k in pairs(v) do if type(k) ~= 'number' then is_list = false break end end end
    local out = {}
    if is_list and n > 0 then
      for i = 1, n do out[i] = enc(v[i]) end
      return '[' .. table.concat(out, ',') .. ']'
    end
    if next(v) == nil then return '[]' end
    for k, x in pairs(v) do out[#out + 1] = enc(tostring(k)) .. ':' .. enc(x) end
    return '{' .. table.concat(out, ',') .. '}'
  end
  return 'null'
end
io.write(enc(dofile(arg[1])))
'''


def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


def lua_val(v, ind):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        if not v:
            return '{}'
        return '{\n' + ''.join(f'{ind}  {lua_val(x, ind + "  ")},\n' for x in v) + ind + '}'
    if isinstance(v, dict):
        if not v:
            return '{}'
        return '{\n' + ''.join(f'{ind}  [{lua_str(k)}] = {lua_val(v[k], ind + "  ")},\n' for k in sorted(v)) + ind + '}'
    return 'nil'


def read_lua_picks():
    if not os.path.exists(PICKS_LUA):
        return {}
    dump = os.path.join(HERE, '_picks_dump.lua')
    with open(dump, 'w', encoding='utf-8', newline='\n') as f:
        f.write(DUMP_LUA)
    try:
        p = subprocess.run([LUA, dump, PICKS_LUA], capture_output=True, text=True, encoding='utf-8')
    finally:
        os.remove(dump)
    if p.returncode != 0:
        sys.exit('cannot read sound_picks.lua: ' + p.stderr.strip()[:300])
    t = json.loads(p.stdout or '{}')
    return t if isinstance(t, dict) else {}


def convert(src_rel, out_rel):
    src = os.path.join(ROOT, src_rel)
    out = os.path.join(GAME, out_rel)
    if not os.path.exists(src):
        print('  !! missing in the packs:', src_rel)
        return False
    if os.path.exists(out) and os.path.getmtime(out) >= os.path.getmtime(src):
        return True
    os.makedirs(os.path.dirname(out), exist_ok=True)
    p = subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', src, '-c:a', 'libvorbis', '-q:a', '10', out],
                       capture_output=True, text=True)
    if p.returncode != 0:
        print('  !! ffmpeg failed on', src_rel, p.stderr.strip()[:200])
        return False
    return True


def norm(v):
    """numbers compared as values (Lua writes 1.0 as 1 and 0.55 as 0.55000000000000004)"""
    if isinstance(v, bool):
        return v
    if isinstance(v, (int, float)):
        return round(float(v), 9)
    if isinstance(v, list):
        return [norm(x) for x in v]
    if isinstance(v, dict):
        return {k: norm(x) for k, x in v.items()}
    return v


def same(a, b):
    return json.dumps(norm(a), sort_keys=True) == json.dumps(norm(b), sort_keys=True)


def main():
    picks = json.load(open(PICKS_JSON, encoding='utf-8'))
    if '--list' in sys.argv:
        for slot in sorted(picks):
            p = picks[slot]
            print(f"{slot:22} {'RED' if p.get('unsure') else '   '} {len(p.get('files', [])):2}  {p.get('why', '')}")
        return
    mine = {}
    for slot in sorted(picks):
        p = picks[slot]
        files, src = [], []
        for i, rel in enumerate(p.get('files', [])):
            out_rel = f'assets/sfx/{slot}_{i + 1}.ogg'
            if convert(rel, out_rel):
                files.append(out_rel)
                src.append(rel)
        e = {'files': files, 'src': src, 'vol': p.get('vol', 1.0)}
        for k in CAVE_KEYS:              # the cave's levers (sfx_spec.py CAVE): the editor's own 3D fields
            if k in p:
                e[k] = p[k]
        if p.get('unsure'):
            e['unsure'] = True
            e['candidates'] = p.get('candidates', [])
        mine[slot] = e
    theirs = read_lua_picks()
    baked = json.load(open(BAKED, encoding='utf-8')) if os.path.exists(BAKED) else {}
    slots, kept = dict(mine), 0
    for slot, t in theirs.items():
        if slot not in mine:
            slots[slot] = t                       # a slot he made in the game
        elif slot in baked and not same(t, baked[slot]):
            slots[slot] = t                       # he changed it since the last bake: his
            kept += 1
    text = ('-- the sound picks: slot -> files (converted copies in assets/sfx/), src = the pack files they came from\n'
            '-- (attribution), vol = the slot volume; unsure = no file fits yet (shown red, silent), candidates = pack\n'
            '-- files the editor offers for it. First written by tools/sfx_bake.py (tools/sfx_spec.py); the in-game\n'
            '-- editor rewrites it.\n'
            'return ' + lua_val(slots, '') + '\n')
    with open(PICKS_LUA, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    with open(BAKED, 'w', encoding='utf-8') as f:
        json.dump(slots, f, indent=1, sort_keys=True, ensure_ascii=False)
    n_unsure = sum(1 for s in slots.values() if s.get('unsure'))
    print(f'{len(slots)} slots written ({n_unsure} unsure), {sum(len(s.get("files", [])) for s in slots.values())} files'
          + (f'; {kept} changed in the game since the last bake, kept as he set them' if kept else ''))


if __name__ == '__main__':
    main()
