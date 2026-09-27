// Bundle a game dir into ONE self-contained html (three.js still from the CDN in the importmap).
//
//   node harness/bundle.mjs <gameDir> <out.html>
//
// Contract (CONTRACT.md): index.html has one <script type="importmap"> mapping "game/" to "./src/",
// local modules import each other ONLY through "game/..." specifiers, and the entry is
// <script type="module" src="src/main.js"></script>. Every .js under src/ is embedded as JSON;
// a classic script turns each into a blob URL and injects the real importmap before the entry runs.
import fs from 'node:fs';
import path from 'node:path';

const [gameDir, out] = process.argv.slice(2).map(p => path.resolve(p));
if (!gameDir || !out) { console.error('usage: node harness/bundle.mjs <gameDir> <out.html>'); process.exit(64); }
let html = fs.readFileSync(path.join(gameDir, 'index.html'), 'utf8');

const mapRe = /<script type="importmap">([\s\S]*?)<\/script>/;
const m = html.match(mapRe);
if (!m) throw new Error('index.html has no <script type="importmap">');
const imports = JSON.parse(m[1]).imports;
delete imports['game/'];

const mods = {};
const walk = dir => {
  for (const f of fs.readdirSync(dir)) {
    const p = path.join(dir, f);
    if (fs.statSync(p).isDirectory()) walk(p);
    else if (f.endsWith('.js')) {
      const src = fs.readFileSync(p, 'utf8');
      if (/from\s+['"]\.\.?\//.test(src) || /import\(\s*['"]\.\.?\//.test(src)) throw new Error(`${p}: relative import; use "game/..." specifiers`);
      if (/import\.meta\.url/.test(src)) throw new Error(`${p}: import.meta.url is not bundle-safe`);
      mods['game/' + path.relative(path.join(gameDir, 'src'), p).split(path.sep).join('/')] = src;
    }
  }
};
walk(path.join(gameDir, 'src'));

const json = s => JSON.stringify(s).replace(/</g, '\\u003c');
const loader = `<script id="__mods" type="application/json">${json(mods)}</script>
<script>(function(){var mods=JSON.parse(document.getElementById('__mods').textContent);var imports=${json(imports)};
for(var k in mods)imports[k]=URL.createObjectURL(new Blob([mods[k]],{type:'text/javascript'}));
var s=document.createElement('script');s.type='importmap';s.textContent=JSON.stringify({imports:imports});
document.currentScript.after(s);})();</script>`;
html = html.replace(mapRe, () => loader);

const entryRe = /<script type="module" src="(?:\.\/)?src\/([^"]+)"><\/script>/;
if (!entryRe.test(html)) throw new Error('index.html has no <script type="module" src="src/..."> entry');
html = html.replace(entryRe, (_, f) => `<script type="module">import 'game/${f}';</script>`);

fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, html);
console.log(`bundle: ${Object.keys(mods).length} modules, ${(html.length / 1024).toFixed(1)} KB -> ${out}`);
