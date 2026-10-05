// the burned mask, round 47 (mask_v2.mjs) -> assets/port/items/geo/obj_geo_0.* + the manifest's counts.
// The round-35 mask's files are kept once in scratch/r47/mask_r35/.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { geometry } from './mask_v2.mjs';
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const GEO = path.join(ROOT, 'assets', 'port', 'items', 'geo');
const KEEP = path.join(ROOT, 'scratch', 'r47', 'mask_r35');
fs.mkdirSync(KEEP, { recursive: true });
for (const f of fs.readdirSync(GEO).filter(f => f.startsWith('obj_geo_0.'))) {
  const dst = path.join(KEEP, f);
  if (!fs.existsSync(dst)) fs.copyFileSync(path.join(GEO, f), dst);
}
const t0 = Date.now();
const g = geometry();
const w = (name, arr) => fs.writeFileSync(path.join(GEO, 'obj_geo_0.' + name), Buffer.from(arr.buffer, arr.byteOffset, arr.byteLength));
const N = g.attributes.position.count;
w('position.f32', new Float32Array(g.attributes.position.array));
w('normal.f32', new Float32Array(g.attributes.normal.array));
w('color.f32', new Float32Array(g.attributes.color.array));
w('aMR.f32', new Float32Array(g.attributes.aMR.array));
const idx = new Uint32Array(g.index.array);
w('index.u32', idx);
g.computeBoundingSphere();
const bs = g.boundingSphere;
const man = path.join(ROOT, 'assets', 'port', 'items.lua');
let s = fs.readFileSync(man, 'utf8');
const re = /obj_geo_0=\{attrs=\{position=\{size=3,count=\d+\},normal=\{size=3,count=\d+\},color=\{size=3,count=\d+\},aMR=\{size=2,count=\d+\}\},order=\{"position","normal","color","aMR"\},index=\d+,bs=\{[^}]*\}/;
if (!re.test(s)) throw new Error('manifest entry for obj_geo_0 not found');
s = s.replace(re, `obj_geo_0={attrs={position={size=3,count=${N}},normal={size=3,count=${N}},color={size=3,count=${N}},aMR={size=2,count=${N}}},order={"position","normal","color","aMR"},index=${idx.length},bs={${bs.center.x},${bs.center.y},${bs.center.z},${bs.radius}}`);
fs.writeFileSync(man, s);
console.log(`mask v2: ${N} vertices, ${idx.length/3} triangles, ${((Date.now() - t0)/1000).toFixed(1)} s`);
