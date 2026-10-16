#!/usr/bin/env python3
"""webbench/trace_frames.py -- what a long frame is made of, from a Chrome trace (2026-10-16, Phylactery 19).

Reads the trace run.mjs saves with WEBBENCH_TRACE=1 (12 s of the fight). On the page's main thread: the animation
frame callbacks (the engine's frame: the game's Lua + its GL calls), the time between them, V8's collections and any
other task; on the GPU process's main thread: how busy it was. For each gap between two callbacks over 25 ms it says
what ran in it.

  python tools/webbench/trace_frames.py [trace.json]
"""
import json, os, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', '..', 'scratch', 'webbench', 'trace.json')
ev = json.load(open(path))['traceEvents']
names = {}
for e in ev:
    if e.get('ph') == 'M' and e.get('name') == 'thread_name':
        names[(e['pid'], e['tid'])] = e['args']['name']
main = [k for k, n in names.items() if n == 'CrRendererMain']
gpu = [k for k, n in names.items() if n in ('CrGpuMain', 'VizCompositorThread')]
print('threads: main %s, gpu %s' % (main, [(k, names[k]) for k in gpu]))

def complete(evs):
    """X events as (start, end, name); B/E pairs folded"""
    out, stack = [], defaultdict(list)
    for e in evs:
        ph = e.get('ph')
        if ph == 'X' and 'dur' in e: out.append((e['ts'], e['ts'] + e['dur'], e['name'], e))
        elif ph == 'B': stack[e['name']].append(e)
        elif ph == 'E' and stack[e['name']]:
            b = stack[e['name']].pop(); out.append((b['ts'], e['ts'], e['name'], b))
    return out

by_thread = defaultdict(list)
for e in ev:
    if 'ts' in e: by_thread[(e['pid'], e['tid'])].append(e)
M = sorted(complete(by_thread[main[0]]), key=lambda x: x[0])
raf = [x for x in M if x[2] == 'FireAnimationFrame']
gc = [x for x in M if 'GC' in x[2] and x[2] not in ('V8.GCCompileLazy',)]
tasks = [x for x in M if x[2] in ('ThreadControllerImpl::RunTask', 'RunTask')]
print('main thread: %d animation frame callbacks, %d tasks, %d GC events' % (len(raf), len(tasks), len(gc)))
if raf:
    d = sorted(x[1] - x[0] for x in raf)
    print('callback ms: p50 %.1f p90 %.1f p99 %.1f max %.1f' % (d[len(d)//2]/1000, d[int(len(d)*0.9)]/1000, d[int(len(d)*0.99)]/1000, d[-1]/1000))
G = []
for k in gpu: G += complete(by_thread[k])
G.sort(key=lambda x: x[0])
gpu_top = [x for x in G if x[2] in ('ThreadControllerImpl::RunTask', 'RunTask', 'GpuChannel::ExecuteDeferredRequest', 'CommandBufferStub::OnAsyncFlush', 'GLES2DecoderImpl::HandleDrawElements')]

def busy(lst, a, b):
    t = 0
    for s, e, n, _ in lst:
        if e > a and s < b: t += min(e, b) - max(s, a)
    return t/1000

long_n = 0
gaps = []
for i in range(1, len(raf)):
    a, b = raf[i - 1][0], raf[i][0]
    gaps.append((b - a)/1000)
    if (b - a)/1000 > 25:
        long_n += 1
        if long_n <= 25:
            cb = (raf[i - 1][1] - raf[i - 1][0])/1000
            g = [(x[2], (x[1] - x[0])/1000) for x in gc if x[1] > a and x[0] < b and (x[1] - x[0]) > 300]
            other = busy([x for x in tasks], a, b)
            print('  gap %.1f ms: callback %.1f, main thread tasks %.1f, GC %s, GPU threads busy %.1f' % ((b - a)/1000, cb, other, g[:4], busy(gpu_top, a, b)))
gs = sorted(gaps)
if gs: print('gaps between callbacks: p50 %.1f p90 %.1f p99 %.1f; over 25 ms: %d of %d' % (gs[len(gs)//2], gs[int(len(gs)*0.9)], gs[int(len(gs)*0.99)], long_n, len(gs)))
tot_gc = sum(x[1] - x[0] for x in gc)/1000
print('GC on the main thread: %.1f ms in the trace (%.1f s)' % (tot_gc, (M[-1][1] - M[0][0])/1e6 if M else 0))
