// Headless play-and-capture harness. No dependencies: Node 24 (global WebSocket + fetch) + installed Chrome.
//
//   node harness/shoot.mjs <gameDir> <script.json> <outDir> [--size 1280x720] [--realtime]
//
// Serves <gameDir> over http on a free port, opens it in headless Chrome (SwiftShader WebGL),
// waits for window.GAME.ready, calls GAME.setManual(true) (unless --realtime), then runs the
// script's steps. Writes PNGs, state JSON and log.json (console + page errors) into <outDir>.
//
// Script = JSON array of steps (or {"steps": [...]}):
//   {"eval": "js expression"}                         result goes to log.json
//   {"step": 60, "input": {...}}                       GAME.step(60, input)
//   {"shot": "name"}                                   name.png
//   {"state": "name"}                                  name.json = GAME.state()
//   {"burst": "name", "frames": 8, "every": 2, "input": {...}}
//                                                      name_00.png .. name_07.png + name_sheet.png
//   {"wait": 500}                                      real milliseconds (for --realtime scripts)
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const flags = new Set(argv.filter(a => a.startsWith('--') && !a.includes('=')));
const pos = [];
let size = [1280, 720];
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--size') { size = argv[++i].split('x').map(Number); continue; }
  if (!argv[i].startsWith('--')) pos.push(argv[i]);
}
if (pos.length < 3) {
  console.error('usage: node harness/shoot.mjs <gameDir> <script.json> <outDir> [--size WxH] [--realtime]');
  process.exit(64);
}
const [gameDir, scriptPath, outDir] = pos.map(p => path.resolve(p));
const realtime = flags.has('--realtime');
let steps = JSON.parse(fs.readFileSync(scriptPath, 'utf8'));
if (!Array.isArray(steps)) steps = steps.steps;
fs.mkdirSync(outDir, { recursive: true });

// Machine-load guards (owner, 2026-09-22: parallel agents made his PC slow).
// 1. This process and everything it spawns (Chrome + SwiftShader threads) run at below-normal priority.
// 2. At most SHOOT_SLOTS (default 3) harness runs render at once; the rest queue for a slot file.
try { os.setPriority(0, os.constants.priority.PRIORITY_BELOW_NORMAL); } catch { }
const SLOTS = Number(process.env.SHOOT_SLOTS || 3);
const SLOT_DIR = path.join(HERE, '..', 'scratch', 'render-slots');
const pid_alive = pid => { try { process.kill(pid, 0); return true; } catch (e) { return e.code === 'EPERM'; } };
let slot = null;
{
  fs.mkdirSync(SLOT_DIR, { recursive: true });
  let told = false;
  while (!slot) {
    for (let i = 0; i < SLOTS && !slot; i++) {
      const f = path.join(SLOT_DIR, `slot${i}`);
      try { fs.writeFileSync(f, String(process.pid), { flag: 'wx' }); slot = f; }
      catch (e) {
        if (e.code !== 'EEXIST') throw e;
        try { const pid = Number(fs.readFileSync(f, 'utf8')); if (pid && !pid_alive(pid)) fs.rmSync(f, { force: true }); } catch { }
      }
    }
    if (!slot) {
      if (!told) { console.log(`shoot: waiting for a render slot (${SLOTS} max at once; other agents are rendering)`); told = true; }
      await new Promise(r => setTimeout(r, 300 + (process.pid % 7) * 50));
    }
  }
  process.on('exit', () => { try { fs.rmSync(slot, { force: true }); } catch { } });
}

const CHROME = [
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
].find(p => fs.existsSync(p));

const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.wav': 'audio/wav', '.ogg': 'audio/ogg', '.css': 'text/css', '.glsl': 'text/plain' };

const server = http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (p.endsWith('/')) p += 'index.html';
  if (p === '/favicon.ico') { res.writeHead(204); res.end(); return; }
  const file = path.join(gameDir, p);
  if (!file.startsWith(gameDir) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': TYPES[path.extname(file)] || 'application/octet-stream', 'cache-control': 'no-store' });
  fs.createReadStream(file).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const pagePort = server.address().port;

const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'shoot-'));
const chrome = spawn(CHROME, [
  '--headless=new', '--remote-debugging-port=0', `--user-data-dir=${profile}`,
  '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
  '--autoplay-policy=no-user-gesture-required', '--mute-audio', '--no-first-run', '--no-default-browser-check',
  `--window-size=${size[0]},${size[1]}`, 'about:blank',
], { stdio: 'ignore' });

const log = { console: [], errors: [], evals: [], steps: 0 };
let ws, nextId = 1;
const pending = new Map();
const send = (method, params = {}) => new Promise((resolve, reject) => {
  const id = nextId++;
  pending.set(id, { resolve, reject, method });
  ws.send(JSON.stringify({ id, method, params }));
});
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function evaluate(expression) {
  const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) {
    const d = r.exceptionDetails;
    throw new Error((d.exception && (d.exception.description || d.exception.value)) || d.text);
  }
  return r.result.value;
}

async function shot(name) {
  const r = await send('Page.captureScreenshot', { format: 'png' });
  const file = path.join(outDir, name + '.png');
  fs.writeFileSync(file, Buffer.from(r.data, 'base64'));
  return file;
}

let exitCode = 0;
try {
  // DevTools port
  let port;
  for (let i = 0; i < 100 && !port; i++) {
    const f = path.join(profile, 'DevToolsActivePort');
    if (fs.existsSync(f)) port = fs.readFileSync(f, 'utf8').split('\n')[0].trim();
    else await sleep(100);
  }
  if (!port) throw new Error('chrome did not open a DevTools port');
  const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const page = targets.find(t => t.type === 'page');
  ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  ws.onmessage = e => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) {
      const p = pending.get(m.id); pending.delete(m.id);
      m.error ? p.reject(new Error(p.method + ': ' + m.error.message)) : p.resolve(m.result);
    } else if (m.method === 'Runtime.consoleAPICalled') {
      const text = m.params.args.map(a => a.value !== undefined ? String(a.value) : (a.description || a.type)).join(' ');
      log.console.push(`[${m.params.type}] ${text}`);
    } else if (m.method === 'Runtime.exceptionThrown') {
      const d = m.params.exceptionDetails;
      log.errors.push((d.exception && d.exception.description) || d.text);
    } else if (m.method === 'Log.entryAdded' && m.params.entry.level === 'error') {
      log.errors.push(`[${m.params.entry.source}] ${m.params.entry.text} ${m.params.entry.url || ''}`);
    }
  };
  await send('Page.enable'); await send('Runtime.enable'); await send('Log.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: size[0], height: size[1], deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url: `http://127.0.0.1:${pagePort}/` });

  let ready = false;
  for (let i = 0; i < 300 && !ready; i++) {
    try { ready = await evaluate('!!(window.GAME && window.GAME.ready)'); } catch { }
    if (!ready) await sleep(100);
  }
  if (!ready) {
    await shot('NOT_READY');
    throw new Error('window.GAME.ready never became true within 30 s (see NOT_READY.png and log.json errors)');
  }
  if (!realtime) await evaluate('window.GAME.setManual && window.GAME.setManual(true)');

  for (const s of steps) {
    log.steps++;
    if (s.eval !== undefined) log.evals.push({ expr: s.eval, value: await evaluate(s.eval) });
    else if (s.step !== undefined) await evaluate(`window.GAME.step(${s.step | 0}, ${JSON.stringify(s.input || {})})`);
    else if (s.shot !== undefined) await shot(s.shot);
    else if (s.state !== undefined) fs.writeFileSync(path.join(outDir, s.state + '.json'), JSON.stringify(await evaluate('window.GAME.state()'), null, 1));
    else if (s.wait !== undefined) await sleep(s.wait);
    else if (s.burst !== undefined) {
      const files = [];
      for (let k = 0; k < (s.frames || 8); k++) {
        if (k > 0 || s.first_step) await evaluate(`window.GAME.step(${(s.every || 2) | 0}, ${JSON.stringify(s.input || {})})`);
        files.push(await shot(`${s.burst}_${String(k).padStart(2, '0')}`));
      }
      spawnSync('python', [path.join(HERE, 'sheet.py'), path.join(outDir, s.burst + '_sheet.png'), ...files], { stdio: 'inherit' });
    } else throw new Error('unknown step: ' + JSON.stringify(s));
  }
} catch (e) {
  log.fatal = String(e && e.stack || e);
  exitCode = 1;
} finally {
  fs.writeFileSync(path.join(outDir, 'log.json'), JSON.stringify(log, null, 1));
  try { ws && ws.close(); } catch { }
  chrome.kill();
  server.close();
  await sleep(300);
  try { fs.rmSync(profile, { recursive: true, force: true }); } catch { }
  try { fs.rmSync(slot, { force: true }); } catch { }
}
const pngs = fs.readdirSync(outDir).filter(f => f.endsWith('.png')).length;
console.log(`shoot: ${log.steps} steps, ${pngs} png in ${outDir}, ${log.errors.length} page errors, ${log.console.length} console lines${log.fatal ? '\nFATAL: ' + log.fatal : ''}`);
for (const e of log.errors.slice(0, 5)) console.log('  error: ' + e.split('\n')[0]);
process.exit(exitCode);
