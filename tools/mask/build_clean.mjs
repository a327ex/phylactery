// the burned mask's model without its marks, for the store art (2026-10-18): MASK_CLEAN=soot,blood,... chooses which.
// node --import ./tools/mask/register.mjs tools/mask/build_clean.mjs <out folder>  -> <out>/mask.{position,normal,color,aMR}.f32
// + mask.index.u32 + mask.json (counts, bounding sphere). Never touches assets/ (the game's mask stays as it is).
import fs from 'node:fs';
import path from 'node:path';
import { geometry } from './mask_v2.mjs';
const out = process.argv[2];
fs.mkdirSync(out, { recursive: true });
const t0 = Date.now();
const g = geometry();
const w = (name, arr) => fs.writeFileSync(path.join(out, 'mask.' + name), Buffer.from(arr.buffer, arr.byteOffset, arr.byteLength));
w('position.f32', new Float32Array(g.attributes.position.array));
w('normal.f32', new Float32Array(g.attributes.normal.array));
w('color.f32', new Float32Array(g.attributes.color.array));
w('aMR.f32', new Float32Array(g.attributes.aMR.array));
w('index.u32', new Uint32Array(g.index.array));
g.computeBoundingSphere();
const bs = g.boundingSphere;
fs.writeFileSync(path.join(out, 'mask.json'), JSON.stringify({ clean: process.env.MASK_CLEAN || '', vertices: g.attributes.position.count,
  triangles: g.index.count/3, bs: [bs.center.x, bs.center.y, bs.center.z, bs.radius] }));
console.log(`clean mask (${process.env.MASK_CLEAN || 'nothing removed'}): ${g.attributes.position.count} vertices, ${((Date.now() - t0)/1000).toFixed(1)} s -> ${out}`);
