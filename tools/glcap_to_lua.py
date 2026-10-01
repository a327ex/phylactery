"""glcap_to_lua.py <capture dir> -- the port to Anchor: a GL frame capture's frame.json
(web/src/glcapture.js) as frame.lua (`return {...}`), which the Anchor replay loads."""
import json, sys, os

LUA_KEYWORDS = {'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'goto', 'if', 'in', 'local', 'nil', 'not',
    'or', 'repeat', 'return', 'then', 'true', 'until', 'while'}

def lua(v, depth=0):
    if v is None: return 'nil'
    if v is True: return 'true'
    if v is False: return 'false'
    if isinstance(v, (int,)): return str(v)
    if isinstance(v, float):
        if v != v: return '0/0'
        if v in (float('inf'), float('-inf')): return ('1/0' if v > 0 else '-1/0')
        return repr(v)
    if isinstance(v, str):
        # glcapture.js writes non-finite uniform values as these strings (JSON has no Infinity)
        if v in ('Infinity', '-Infinity', 'NaN'): return {'Infinity': 'math.huge', '-Infinity': '-math.huge', 'NaN': '(0/0)'}[v]
        return json.dumps(v)
    if isinstance(v, list): return '{' + ','.join(lua(x, depth + 1) for x in v) + '}'
    if isinstance(v, dict):
        parts = []
        for k, x in v.items():
            key = k if (isinstance(k, str) and k.isidentifier() and k not in LUA_KEYWORDS) else '[' + json.dumps(str(k)) + ']'
            parts.append(f'{key}={lua(x, depth + 1)}')
        return '{' + ','.join(parts) + '}'
    raise TypeError(type(v))

if __name__ == '__main__':
    d = sys.argv[1]
    f = json.load(open(os.path.join(d, 'frame.json')))
    open(os.path.join(d, 'frame.lua'), 'w', encoding='utf-8').write('return ' + lua(f) + '\n')
    print('frame.lua', os.path.getsize(os.path.join(d, 'frame.lua')))
