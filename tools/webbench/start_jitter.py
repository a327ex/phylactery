#!/usr/bin/env python3
"""webbench/start_jitter.py -- how far the web moves each sound's start (2026-10-15, Phylactery 19).

A sound the game starts is mixed from the first frame of the next chunk the engine mixes after the request: with
miniaudio's old web device a whole 85 ms block at a time (every request in between starts at the same block edge),
with the engine's own output (Anchor 2026-10-15) a few ms at a time after every frame. Reads a bench run made with
WEBBENCH_TAP=1 WEBBENCH_SOUNDLOG=1: the SNDLOG lines in run-log.json (each play's main-thread time + sound id) and
the tap's chunk times (meta.json). Prints the spread of the start error and the plays of one sound close together
whose spacing changed (a pair 30 ms apart heard 85 ms apart sounds like the sound repeating).

  python tools/webbench/start_jitter.py <run-log.json> <tap dir>
"""
import bisect, json, sys
import numpy as np

log = json.load(open(sys.argv[1]))
meta = json.load(open(sys.argv[2] + '/meta.json'))
rate = meta['rate']
plays = []
for line in log['console']:
    if line.startswith('SNDLOG '):
        f = line.split()
        plays.append((float(f[3]) if len(f) > 3 else float(f[1]), int(f[2])))   # the page's clock, appended by bench.html
times, starts, f = [], [], 0
for t, n in meta['eng_meta']:
    times.append(t); starts.append(f); f += n
print(f"{meta['path']}: {len(plays)} plays logged, {len(times)} chunks ({times[0]:.0f}..{times[-1]:.0f} ms); "
      f"plays {plays[0][0]:.0f}..{plays[-1][0]:.0f} ms" if plays else 'no plays logged')
heard = []          # (request ms, heard ms on the stream's clock, id)
for r, k in plays:
    i = bisect.bisect_right(times, r)       # the first chunk mixed after the request
    if i >= len(times): continue
    heard.append((r, starts[i] * 1000.0 / rate, k))
if not heard: sys.exit(0)
err = np.array([h - r for r, h, k in heard])
err -= np.median(err)
print(f'start error around its median over {len(heard)} plays: p5 {np.percentile(err, 5):+.1f} ms, '
      f'p95 {np.percentile(err, 95):+.1f} ms, spread (max-min) {err.max() - err.min():.1f} ms')
by = {}
for r, h, k in heard: by.setdefault(k, []).append((r, h))
pairs, moved = 0, []
for k, v in by.items():
    for (r1, h1), (r2, h2) in zip(v, v[1:]):
        if r2 - r1 > 150: continue
        pairs += 1
        if abs((h2 - h1) - (r2 - r1)) > 20: moved.append((r1, k, r2 - r1, h2 - h1))
print(f'plays of one sound under 150 ms apart: {pairs}; spacing changed by over 20 ms: {len(moved)}')
for r1, k, asked, got in moved[:12]:
    print(f'  at {r1/1000:7.2f} s sound #{k}: asked {asked:5.1f} ms apart, heard {got:5.1f} ms apart')
