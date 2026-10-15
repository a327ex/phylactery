// webbench/run.mjs -- runs the benchmark page (build.py) in headless Chrome on the GPU and prints its BENCH lines
// (2026-10-15). No dependencies: Node 24 (global WebSocket + fetch) + the installed Chrome, raw CDP, as
// megablock/tools/harness/shoot.mjs. The page opens from file:// and EVERY request but the page itself, data: and
// blob: is failed inside Chrome (CDP Fetch), so nothing reaches the owner's download manager. One run at a time,
// below-normal priority (his machine is in use); WEBBENCH_GL=swiftshader forces software WebGL.
//
//   node tools/webbench/run.mjs [page.html] [--shot out.png] [--timeout 240]      (WEBBENCH_UNCAPPED=1: no vsync)
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
let page = path.resolve(HERE, '..', '..', 'scratch', 'webbench', 'bench.html'), shotFile = null, timeout = 240;
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--shot') shotFile = path.resolve(argv[++i]);
  else if (argv[i] === '--timeout') timeout = Number(argv[++i]);
  else page = path.resolve(argv[i]);
}
try { os.setPriority(0, os.constants.priority.PRIORITY_BELOW_NORMAL); } catch { }

const CHROME = ['C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(p => fs.existsSync(p));
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'webbench-'));
const chrome = spawn(CHROME, [
  '--headless=new', '--remote-debugging-port=0', `--user-data-dir=${profile}`,
  ...(process.env.WEBBENCH_GL === 'swiftshader' ? ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] : ['--use-angle=d3d11', '--enable-gpu']),
  // (2026-10-15) audio: --mute-audio left the page's audio unpulled (no callbacks at all); a fake output stream (no
  // sound out of the speakers) pulls it on a real-time clock, as a device would; WEBBENCH_AUDIO=mute for the old way
  '--ignore-gpu-blocklist', ...(process.env.WEBBENCH_AUDIO === 'mute' ? ['--mute-audio'] : ['--disable-audio-output']),
  '--autoplay-policy=no-user-gesture-required', '--no-first-run',
  '--no-default-browser-check', '--disable-background-timer-throttling', '--disable-renderer-backgrounding',
  '--js-flags=--max-old-space-size=4096', '--window-size=1280,720',
  // WEBBENCH_UNCAPPED=1: no vsync, no frame-rate cap: frames come as fast as the CPU and the GPU allow, so the frame
  // time is what a frame costs (capped, the browser's pacing hides anything under its 16.7 ms)
  ...(process.env.WEBBENCH_UNCAPPED === '1' ? ['--disable-gpu-vsync', '--disable-frame-rate-limit'] : []),
  'about:blank',
], { stdio: 'ignore' });

const sleep = ms => new Promise(r => setTimeout(r, ms));
let ws, nextId = 1;
const pending = new Map();
const send = (method, params = {}) => new Promise((resolve, reject) => {
  const id = nextId++;
  pending.set(id, { resolve, reject, method });
  ws.send(JSON.stringify({ id, method, params }));
});
const out = { console: [], errors: [], blocked: [] };
let code = 0;
try {
  let port;
  for (let i = 0; i < 100 && !port; i++) {
    const f = path.join(profile, 'DevToolsActivePort');
    if (fs.existsSync(f)) port = fs.readFileSync(f, 'utf8').split('\n')[0].trim(); else await sleep(100);
  }
  if (!port) throw new Error('chrome did not open a DevTools port');
  const target = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find(t => t.type === 'page');
  ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  const pageUrl = 'file:///' + page.split(path.sep).join('/');
  ws.onmessage = e => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) {
      const p = pending.get(m.id); pending.delete(m.id);
      m.error ? p.reject(new Error(p.method + ': ' + m.error.message)) : p.resolve(m.result);
    } else if (m.method === 'Fetch.requestPaused') {
      const u = m.params.request.url;
      const ok = u.split('?')[0] === pageUrl || u.startsWith('data:') || u.startsWith('blob:');
      if (!ok) out.blocked.push(u);
      ws.send(JSON.stringify({ id: nextId++, method: ok ? 'Fetch.continueRequest' : 'Fetch.failRequest',
        params: ok ? { requestId: m.params.requestId } : { requestId: m.params.requestId, errorReason: 'BlockedByClient' } }));
    } else if (m.method === 'Runtime.consoleAPICalled') {
      const t = m.params.args.map(a => a.value !== undefined ? String(a.value) : (a.description || a.type)).join(' ');
      out.console.push(t);
      if (t.startsWith('BENCH') || t.startsWith('webbench')) console.log(t);
    } else if (m.method === 'Runtime.exceptionThrown') {
      const d = m.params.exceptionDetails;
      out.errors.push((d.exception && d.exception.description) || d.text);
    }
  };
  await send('Runtime.enable'); await send('Page.enable');
  await send('Fetch.enable', { patterns: [{ urlPattern: '*' }] });
  await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url: pageUrl });
  const t0 = Date.now();
  let done = false, keyed = false, tapped = process.env.WEBBENCH_TAP !== '1';
  while (!done && Date.now() - t0 < timeout*1000) {
    await sleep(1000);
    // (2026-10-15, Phylactery 19) WEBBENCH_TAP=1: what the browser really plays, sample for sample (tap.js: an
    // AudioWorklet after the ScriptProcessorNode) next to every block the engine mixed; saved at the end for
    // tools/webbench/tap_check.py
    if (!tapped) {
      try {
        const r = await send('Runtime.evaluate', { awaitPromise: true, returnByValue: true,
          expression: fs.readFileSync(path.join(HERE, 'tap.js'), 'utf8') });
        const v = r.result && r.result.value;
        if (r.exceptionDetails) {
          tapped = true;
          const d = r.exceptionDetails;
          console.log('webbench: tap failed: ' + ((d.exception && d.exception.description) || d.text));
        } else if (v && v !== 'no device') { tapped = true; console.log('webbench: tap ' + v); }
      } catch (e) { tapped = true; console.log('webbench: tap failed: ' + e.message); }
    }
    // (2026-10-15) the engine starts its audio only on a user's input (audio_try_unlock): one key nothing is bound to,
    // so the audio device runs (muted: --mute-audio) and audio_stats sees its callbacks
    if (!keyed && Date.now() - t0 > 3000 && process.env.WEBBENCH_NOAUDIO !== '1') {
      keyed = true;
      try {
        await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'F13', code: 'F13', windowsVirtualKeyCode: 124, nativeVirtualKeyCode: 124 });
        await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'F13', code: 'F13', windowsVirtualKeyCode: 124, nativeVirtualKeyCode: 124 });
      } catch (e) { console.log('webbench: key for the audio failed: ' + e.message); }
    }
    try {
      const r = await send('Runtime.evaluate', { expression: 'window.BENCH && window.BENCH.done', returnByValue: true });
      done = !!(r.result && r.result.value);
    } catch { }
  }
  if (shotFile) {
    const r = await send('Page.captureScreenshot', { format: 'png' });
    fs.writeFileSync(shotFile, Buffer.from(r.data, 'base64'));
  }
  const gl = await send('Runtime.evaluate', { expression: `(function(){ try { var g = document.createElement('canvas').getContext('webgl2'); var e = g.getExtension('WEBGL_debug_renderer_info'); return e ? g.getParameter(e.UNMASKED_RENDERER_WEBGL) : g.getParameter(g.RENDERER); } catch (x) { return String(x) } })()`, returnByValue: true });
  console.log('webbench: GL ' + (gl.result && gl.result.value));
  const au = await send('Runtime.evaluate', { expression: `(function(){ try { var A = window.Module && Module.__aud; if (A) return 'engine output ' + A.mode + ', context ' + A.ctx.state + ' at ' + A.ctx.sampleRate + ' Hz, base latency ' + A.ctx.baseLatency + ', lead ' + (A.lead*1000/A.rate).toFixed(0) + ' ms, gaps heard ' + A.heardRuns; var m = window.miniaudio; if (!m) return 'no miniaudio'; var o = []; for (var i = 0; i < m.devices.length; i++) { var d = m.devices[i]; if (d) o.push('device ' + i + ': state ' + d.state + ', context ' + (d.webaudio && d.webaudio.state) + ' at ' + (d.webaudio && d.webaudio.sampleRate) + ' Hz, base latency ' + (d.webaudio && d.webaudio.baseLatency)); } return o.join('; ') || 'no devices'; } catch (x) { return String(x) } })()`, returnByValue: true });
  console.log('webbench: audio ' + (au.result && au.result.value));
  const ct = await send('Runtime.evaluate', { awaitPromise: true, returnByValue: true, expression: `new Promise(function(res){ try { var d = window.miniaudio.devices[0]; var a = d.webaudio.currentTime, n0 = d.webaudio_cb_n || 0; var orig = d.scriptNode.onaudioprocess; var k = 0; d.scriptNode.onaudioprocess = function(e){ k++; return orig(e); }; setTimeout(function(){ res('currentTime +' + (d.webaudio.currentTime - a).toFixed(3) + ' s in 1 s; onaudioprocess fired ' + k + ' times; buffer ' + d.scriptNode.bufferSize); }, 1000); } catch (x) { res(String(x)); } })` });
  console.log('webbench: audio clock ' + (ct.result && ct.result.value));
  if (process.env.WEBBENCH_TAP === '1') {
    // the tap's two streams, packed in the page (window.__TAP.pack) and pulled over in base64 slices
    const tapDir = path.join(path.dirname(page), 'tap');
    fs.mkdirSync(tapDir, { recursive: true });
    const meta = await send('Runtime.evaluate', { returnByValue: true, expression: 'window.__TAP ? window.__TAP.pack() : null' });
    const m = meta.result && meta.result.value;
    if (meta.exceptionDetails) console.log('webbench: tap pack failed: ' + (meta.exceptionDetails.exception && meta.exceptionDetails.exception.description));
    if (!m) console.log('webbench: tap: nothing recorded');
    else {
      for (const name of ['eng', 'out']) {
        const chunks = [];
        for (let off = 0; off < m[name + '_bytes']; off += 3 << 20) {
          const r = await send('Runtime.evaluate', { returnByValue: true, expression: `window.__TAP.slice(${JSON.stringify(name)}, ${off}, ${3 << 20})` });
          chunks.push(Buffer.from(r.result.value, 'base64'));
        }
        fs.writeFileSync(path.join(tapDir, name + '.f32'), Buffer.concat(chunks));
      }
      fs.writeFileSync(path.join(tapDir, 'meta.json'), JSON.stringify(m));
      console.log(`webbench: tap saved to ${tapDir}: ${m.path}, ${m.eng_chunks} engine chunks, ${m.out_quanta} output quanta at ${m.rate} Hz`);
    }
  }
  if (!done) { console.log('webbench: no BENCH DONE within ' + timeout + ' s'); code = 1; }
} catch (e) {
  console.log('webbench FATAL: ' + (e && e.stack || e));
  code = 1;
} finally {
  fs.writeFileSync(path.join(path.dirname(page), 'run-log.json'), JSON.stringify(out, null, 1));
  try { ws && ws.close(); } catch { }
  chrome.kill();
  await sleep(300);
  try { fs.rmSync(profile, { recursive: true, force: true }); } catch { }
}
if (out.blocked.length) console.log(`webbench: blocked ${out.blocked.length} requests, e.g. ${out.blocked.slice(0, 3).join(' ')}`);
for (const e of out.errors.slice(0, 5)) console.log('webbench page error: ' + e.split('\n')[0]);
process.exit(code);
