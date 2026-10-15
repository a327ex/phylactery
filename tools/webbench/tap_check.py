#!/usr/bin/env python3
"""webbench/tap_check.py -- what the browser played against what the engine mixed (2026-10-15, Phylactery 19).

Reads scratch/webbench/tap/ (run.mjs with WEBBENCH_TAP=1: eng.f32 = everything the engine mixed, in order, out.f32 =
every 128-frame quantum the browser played after the engine's output node, meta.json). It follows the engine's stream
through what was played, sample for sample: played in order, each quantum is the next 128 frames of the engine's
stream. Where it is not, the place the played sound continues from is found by its exact samples, and the jump says
what happened:
  REPEAT  sound the engine made earlier, played again (the old ScriptProcessorNode's late block)
  SKIP    engine sound never played
  GAP     the output ran dry (silence, or the 5 ms fade the worklet plays), then went on where it stopped
  UNKNOWN played sound found nowhere in the engine's stream near there (the 128-sample fade-in after a GAP is this)

  python tools/webbench/tap_check.py [tap dir] [--wav out.wav]     (--wav writes what was played, for listening)
"""
import json, os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[1:]
wav = None
if '--wav' in args:
    i = args.index('--wav'); wav = args[i + 1]; del args[i:i + 2]
TAP = args[0] if args else os.path.join(HERE, '..', '..', 'scratch', 'webbench', 'tap')
meta = json.load(open(os.path.join(TAP, 'meta.json')))
E = np.fromfile(os.path.join(TAP, 'eng.f32'), dtype=np.float32).reshape(-1, 2)
O = np.fromfile(os.path.join(TAP, 'out.f32'), dtype=np.float32).reshape(-1, 2)
rate = meta['rate']
Q = 128
ms = lambda frames: frames * 1000.0 / rate

sizes = [n for t, n in meta['eng_meta']]
frames = [q[0] for q in meta['out_meta']]
rec_gaps = sum(1 for i in range(1, len(frames)) if frames[i] - frames[i - 1] != Q)
print(f"tap: {meta['path']} output at {rate} Hz; engine {len(sizes)} chunks, {E.shape[0]} frames ({E.shape[0]/rate:.1f} s), "
      f"chunk {min(sizes) if sizes else 0}..{max(sizes) if sizes else 0} frames; played {O.shape[0]} frames "
      f"({O.shape[0]/rate:.1f} s); recorder gaps {rec_gaps}")
if meta.get('out_stats'): print('output counters: ' + json.dumps(meta['out_stats']))
print(f"engine stream: {int(np.any(E != 0, axis=1).sum())} of {E.shape[0]} frames carry sound")

def find(tail, lo, hi):
    """places p in E[lo:hi] where E[p:p+len(tail)] == tail exactly"""
    lo, hi = max(0, lo), min(E.shape[0] - tail.shape[0], hi)
    if hi <= lo: return []
    seg = E[lo:hi]
    c = np.nonzero((seg[:, 0] == tail[0, 0]) & (seg[:, 1] == tail[0, 1]))[0]
    return [lo + int(p) for p in c if np.array_equal(E[lo + p:lo + p + tail.shape[0]], tail)]

# lag = played frame - engine frame of the same sample. Played in order it stays put: a GAP (the output ran dry, then
# went on where it stopped) raises it by the dry frames, a REPEAT (earlier engine sound played again) raises it by how
# far back it went, a SKIP lowers it. max_e = the furthest engine frame played so far (the way back after a repeat).
lag, max_e = None, -1
events, unknown_q, silent_q, ok_q, before_sync = [], 0, 0, 0, 0
nq = O.shape[0] // Q
W = 1 << 15
for q in range(nq):
    o = O[q*Q:(q+1)*Q]
    if lag is not None:
        e0 = q*Q - lag
        if e0 >= 0 and e0 + Q <= E.shape[0] and np.array_equal(o, E[e0:e0 + Q]):
            ok_q += 1; max_e = max(max_e, e0 + Q); continue
    if not o[Q//2:].any():                  # silent (or a stall's fade into silence): the next sounding quantum decides
        silent_q += 1; continue
    tail = o[Q - 32:]
    if not tail.any() or len(np.unique(tail[:, 0])) < 4:   # too plain to place (quiet 8-bit sound)
        if lag is None: before_sync += 1
        else: unknown_q += 1
        continue
    t_out = q*Q + Q - 32                    # the tail's played frame
    exp = t_out - lag if lag is not None else None
    cands = find(tail, exp - W, exp + W) if exp is not None else find(tail, 0, E.shape[0])
    if not cands:
        unknown_q += 1
        events.append((q, 'UNKNOWN', 'played sound not found in the engine stream near here'))
        continue
    e_tail = min(cands, key=lambda c: abs(c - exp)) if exp is not None else cands[0]
    new_lag = t_out - e_tail
    if lag is not None and new_lag != lag:
        dL = new_lag - lag
        if dL > 0:
            # a whole quantum of engine sound from an earlier place = played again; a head that is not engine sound
            # (silence, the stall's fade, the fade-in after it) = the output ran dry and went on where it stopped
            head = o[:Q - 32]
            head_is_engine = head.any() and e_tail - (Q - 32) >= 0 and np.array_equal(head, E[e_tail - (Q - 32):e_tail])
            if head_is_engine and e_tail + 32 < max_e:
                events.append((q, 'REPEAT', f'went back {ms(dL):.1f} ms: engine sound played again'))
            else:
                # the stall's fade (the last sample dying away over ~5 ms) reads as UNKNOWN just before: it is the gap's
                while events and events[-1][1] == 'UNKNOWN' and q - events[-1][0] <= 8:
                    events.pop(); unknown_q -= 1
                events.append((q, 'GAP', f'{ms(dL):.1f} ms of output that was not engine sound (ran dry)'))
        else:
            land = e_tail - (Q - 32)          # the engine frame this quantum starts at
            if land <= max_e + Q:
                events.append((q, 'back', f'back where it was before the repeat ({ms(-dL):.1f} ms on)'))
            elif E[max_e:land].any():
                events.append((q, 'SKIP', f'{ms(land - max_e):.1f} ms of engine sound never played'))
            else:
                events.append((q, 'skip-silence', f'{ms(land - max_e):.1f} ms of engine silence not played'))
    lag = new_lag
    max_e = max(max_e, e_tail + 32)
    ok_q += 1

print(f'played quanta: {ok_q} in order, {silent_q} silent, {unknown_q} unknown; {before_sync} too plain to place before the first match')
kinds = {}
for _, k, _ in events: kinds[k] = kinds.get(k, 0) + 1
print('events: ' + (', '.join(f'{k} {v}' for k, v in sorted(kinds.items())) or 'none'))
for q, kind, what in events[:60]:
    print(f'  {(frames[q] - frames[0]) / rate:8.3f} s  {kind:12s} {what}')

if wav:
    import wave
    pcm = (np.clip(O, -1, 1) * 32767).astype('<i2')
    with wave.open(wav, 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate); w.writeframes(pcm.tobytes())
    print('wrote ' + wav)
