"""port_digest_cmp.py <js.txt> <lua.txt> -- the port to Anchor: compare digests (tools/port_digest.js
and .lua, blocks separated by =====) line by line at 1e-13; prints identical / which lines differ."""
import sys
def parse(path):
    blocks = open(path).read().split('\n=====\n')
    return [[l.split() for l in b.split('\n')] for b in blocks]
def same(a, b):
    try:
        fa, fb = float(a), float(b)
        return fa == fb or abs(fa - fb) <= 1e-13*max(1, abs(fa))
    except ValueError:
        return a == b
J, L = parse(sys.argv[1]), parse(sys.argv[2])
for bj, bl in zip(J, L):
    tick = bj[0][1]
    diffs = []
    for k, (lj, ll) in enumerate(zip(bj, bl)):
        if len(lj) != len(ll) or not all(same(a, b) for a, b in zip(lj, ll)):
            diffs.append((k, ' '.join(lj)[:120], ' '.join(ll)[:120]))
    if len(bj) != len(bl): diffs.append(('lines', len(bj), len(bl)))
    print(f'tick {tick}: {"identical" if not diffs else str(len(diffs)) + " lines differ"}')
    for d in diffs[:3]: print('   ', d)
