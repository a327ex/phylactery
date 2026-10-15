#!/usr/bin/env python3
"""webbench/build.py -- Lich Survivors as ONE self-contained web page, for the performance benchmark (2026-10-15,
owner: "Performance is an issue on the web version it seems, so you should find an easy way to test that and fix it
generally").

The page holds the shared web engine (Anchor/engine/engine/build-web-engine/anchor.js + anchor.wasm, the build the
site's engine comes from) and every file the game ships (the same set the site's admin copy ships:
a327ex-site/renderer/tools/sync_lich_survivors.py wanted(), read straight from this folder), base64 in the page,
written into the engine's file system before it starts, plus `bench_on` (port/bench.lua: the benchmark runs and
prints its BENCH lines to the console). No request ever leaves the page: the owner's download manager intercepts any
binary a browser fetches, so the harness (run.mjs) opens it from file:// and fails every request inside Chrome.

  python tools/webbench/build.py [out.html]      (default scratch/webbench/bench.html, ~125 MB)
  BENCH_OFF=1 ...                                  the game without the benchmark (a plain page to look at)
"""
import base64, importlib.util, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, '..', '..'))
A327 = os.path.normpath(os.path.join(GAME, '..'))
ENGINE = os.path.join(A327, 'Anchor', 'engine', 'engine', 'build-web-engine')
ENGINE = os.environ.get('WEBBENCH_ENGINE') or ENGINE    # (2026-10-15) another web engine build's folder (anchor.js + anchor.wasm), e.g. the one the live site runs
SYNC = os.path.join(A327, 'a327ex-site', 'renderer', 'tools', 'sync_lich_survivors.py')
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(GAME, 'scratch', 'webbench', 'bench.html')

spec = importlib.util.spec_from_file_location('sync_lich', SYNC)
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)
files = sync.wanted()          # {relative path: absolute source}

parts = []
total = 0
for rel in sorted(files):
    with open(files[rel], 'rb') as fh:
        data = fh.read()
    total += len(data)
    parts.append((rel.replace(os.sep, '/'), base64.b64encode(data).decode('ascii')))
if os.environ.get('BENCH_OFF') != '1':
    parts.append(('bench_on', base64.b64encode(b'1').decode('ascii')))
    # (2026-10-15) WEBBENCH_SITE=1: the boot as the site hosts it (port/bench.lua B.host_emulation)
    if os.environ.get('WEBBENCH_SITE') == '1':
        parts.append(('bench_site', base64.b64encode(b'1').decode('ascii')))

with open(os.path.join(ENGINE, 'anchor.js'), encoding='utf-8') as fh:
    anchor_js = fh.read()
with open(os.path.join(ENGINE, 'anchor.wasm'), 'rb') as fh:
    wasm_b64 = base64.b64encode(fh.read()).decode('ascii')

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, 'w', encoding='utf-8', newline='\n') as o:
    o.write('<!doctype html><html><head><meta charset="utf-8"><title>Lich Survivors webbench</title>\n')
    o.write('<style>html,body{margin:0;background:#000;overflow:hidden}#canvas{width:1280px;height:720px;display:block}</style>\n')
    o.write('</head><body><canvas id="canvas" oncontextmenu="event.preventDefault()" tabindex="-1"></canvas>\n')
    # the files: one <script type="text/plain"> per file keeps each base64 string out of the JS parser
    o.write('<script>window.__FILES = [];</script>\n')
    for i, (rel, b64) in enumerate(parts):
        o.write('<script type="text/plain" id="f%d" data-path=%s>' % (i, json.dumps(rel)))
        o.write(b64)
        o.write('</script>\n')
    o.write('<script type="text/plain" id="wasm">' + wasm_b64 + '</script>\n')
    o.write('''<script>
(function () {
  function b64(s) {
    if (Uint8Array.fromBase64) return Uint8Array.fromBase64(s);
    var bin = atob(s), n = bin.length, u = new Uint8Array(n);
    for (var i = 0; i < n; i++) u[i] = bin.charCodeAt(i);
    return u;
  }
  window.BENCH = { lines: [], done: false, errors: [], t0: performance.now(), cb: [], gap: [] };
  // the engine's frame is one requestAnimationFrame callback: how long the callback runs (all of its JS and wasm,
  // the GL calls included) against how far apart callbacks come (anything else: the GPU, the browser)
  var raf = window.requestAnimationFrame.bind(window), lastStart = 0;
  window.requestAnimationFrame = function (f) {
    return raf(function (ts) {
      var s = performance.now();
      if (lastStart && window.BENCH.measure) window.BENCH.gap.push(s - lastStart);
      lastStart = s;
      f(ts);
      if (window.BENCH.measure) window.BENCH.cb.push(performance.now() - s);
    });
  };
  function pct(a, p) { var s = a.slice().sort(function (x, y) { return x - y; }); return s.length ? s[Math.min(s.length - 1, Math.floor(s.length*p))] : 0; }
  function log(t) {
    console.log(t);
    if (typeof t === 'string' && t.indexOf('BENCH') === 0) {
      window.BENCH.lines.push(t);
      if (t.indexOf('BENCH heap') === 0) window.BENCH.measure = false;
      if (t === 'BENCH DONE') {
        var B = window.BENCH;
        console.log('BENCH raf callback ms p50 ' + pct(B.cb, 0.5).toFixed(1) + ' p90 ' + pct(B.cb, 0.9).toFixed(1) + ' p99 ' + pct(B.cb, 0.99).toFixed(1) +
          '; between callbacks p50 ' + pct(B.gap, 0.5).toFixed(1) + ' p90 ' + pct(B.gap, 0.9).toFixed(1) + ' p99 ' + pct(B.gap, 0.99).toFixed(1) + ' (' + B.cb.length + ' callbacks)');
        B.done = true;
      }
    }
  }
  setTimeout(function () { window.BENCH.measure = true; }, 0);
  window.Module = {
    arguments: [],
    canvas: document.getElementById('canvas'),
    // (this engine build reads no Module.wasmBinary: it is handed the module through instantiateWasm)
    instantiateWasm: function (imports, done) {
      var bytes = b64(document.getElementById('wasm').textContent);
      WebAssembly.instantiate(bytes, imports).then(function (r) { done(r.instance, r.module); },
        function (e) { console.warn('webbench: wasm instantiate failed: ' + e); });
      return {};
    },
    locateFile: function (p) { return p; },
    print: log,
    printErr: function (t) { console.warn(t); },
    preRun: [function () {
      var t = performance.now();
      var n = 0, bytes = 0;
      document.querySelectorAll('script[data-path]').forEach(function (el) {
        var path = el.getAttribute('data-path');
        var slash = path.lastIndexOf('/');
        if (slash > 0) FS.createPath('/', path.substring(0, slash), true, true);
        var data = b64(el.textContent);
        FS.writeFile('/' + path, data);
        n++; bytes += data.length;
        el.textContent = '';
      });
      console.log('webbench: ' + n + ' files, ' + (bytes / 1e6).toFixed(1) + ' MB written in ' + Math.round(performance.now() - t) + ' ms');
    }],
  };
})();
</script>
''')
    o.write('<script>\n' + anchor_js + '\n</script>\n</body></html>\n')
print('webbench: %d files, %.1f MB of game -> %s (%.1f MB)' % (len(parts), total/1e6, OUT, os.path.getsize(OUT)/1e6))
