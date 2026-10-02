// build.mjs -- builds the walk through the cave into assets/port/walk/ (+ assets/port/walk.lua,
// the manifest the Anchor build loads; port/walk.lua runs it):
//   node tools/walk/build.mjs [--quick] [--nobake]
// the geometry (the volume's rock surface, the floor, the formations) per area and material, its
// baked bounce light (per vertex) and each area's probe grid, the textures, the nav grid (where
// he can float, its floor, the distance to what stops him, which stretch of the walk each cell
// belongs to), the fixed cameras and the stretches each one watches, where the objects wait, and
// what moves (glow-worms, embers, floating stones, ...).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { AREAS, CHAMBERS, SHAFTS, ITEMS, START, SUN_DIR, SUN_XZ, CAMERAS } from './layout.mjs';
import { build_path } from './path.mjs';
import { make_field, mesh_volume, GRID, SEAM_Z } from './field.mjs';
import { make_textures, BIOMES } from './textures.mjs';
import { formations } from './rocks.mjs';
import { flat_normals, smooth_normals, world_uv } from './geo.mjs';
import { bake, intersect } from './bake.mjs';
import { make_rng, h3, room_ground_y, clamp, smoothstep } from './lib.mjs';
import { build_nav } from './nav.mjs';
import { place_cameras } from './cams.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const OUT = path.join(ROOT, 'assets', 'port', 'walk');
const argv = new Set(process.argv.slice(2));
const QUICK = argv.has('--quick'), NOBAKE = argv.has('--nobake');
const T0 = Date.now();
const log = (...a) => console.log(`[${((Date.now() - T0)/1000).toFixed(1)}s]`, ...a);

// ---------------------------------------------------------------- materials
// prog = the three.js program the material draws with (the final room's: cave.rock / cave.floor =
// flat Lambert one-sided, cave.wall = flat two-sided, cave.egg = smooth); tex = its map; emissive
// = HDR radiance (the bake gathers it too); bake_emit = a glow only the bake sees
const MATS = {};
for (const [bio, t] of Object.entries(BIOMES)) {
  MATS[bio + '.rock'] = { prog: 'cave.rock', tex: t.rock };
  MATS[bio + '.floor'] = { prog: 'cave.floor', tex: t.floor };
}
Object.assign(MATS, {
  lava: { prog: 'cave.floor', tex: 'lava_crust', emissive: [2.6, 0.75, 0.12] },
  lava_hot: { prog: 'cave.floor', tex: 'lava_crust', emissive: [6.0, 2.2, 0.45] },
  bone: { prog: 'cave.rock', tex: 'bone' },
  water: { prog: 'cave.floor', tex: 'water' },
  fungus_stem: { prog: 'cave.rock', tex: 'fungus' },
  fungus_cap: { prog: 'cave.egg', tex: 'fungus', emissive: [0.22, 0.95, 0.8], smooth: true },
  crystal: { prog: 'cave.rock', tex: 'crystal', emissive: [0.03, 0.045, 0.07] },
  glass: { prog: 'cave.floor', tex: 'glass' },
  glass_core: { prog: 'cave.floor', tex: 'glass', emissive: [6.0, 3.4, 1.1], bake_emit: [0.25, 0.12, 0.04] },
});

// ---------------------------------------------------------------- the geometry
const P = build_path();
P.biome_of_area = a => AREAS[a].biome;
log(`path: ${P.total.toFixed(0)} m, ${P.S.length} samples`);
for (let a = 0; a < AREAS.length; a++) log(`  ${AREAS[a].id}: s ${P.areas_s[a].s0.toFixed(0)}..${P.areas_s[a].s1.toFixed(0)} (${(P.areas_s[a].s1 - P.areas_s[a].s0).toFixed(0)} m)`);
// each object stands off the way (2.3 m from the centre line): he goes to it, he does not walk
// into it; a shaft that lights an object moves with it
for (const it of ITEMS) {
  const n = P.nearest(it.at[0], it.at[1], 30).p;
  let vx = it.at[0] - n.x, vz = it.at[1] - n.z;
  let l = Math.hypot(vx, vz);
  if (l < 1e-3) { vx = n.tz; vz = -n.tx; l = 1; }
  const OFF = 2.3;
  if (l < OFF) {
    const nx = n.x + vx/l*OFF, nz = n.z + vz/l*OFF;
    for (const sh of SHAFTS) if (Math.abs(sh.at[0] - it.at[0]) < 1e-6 && Math.abs(sh.at[1] - it.at[1]) < 1e-6) sh.at = [nx, nz];
    it.at = [nx, nz];
  }
}
const F = make_field(P);
// the warped pool (owner's scene: the orbs circle over a still black pool)
{
  const c = CHAMBERS.find(c => c.area === 4);
  // behind the orbs as seen from the way
  const it = ITEMS[3];
  const n = P.nearest(it.at[0], it.at[1], 30).p;
  const vx = it.at[0] - n.x, vz = it.at[1] - n.z, l = Math.hypot(vx, vz) || 1;
  const pool = { c: [it.at[0] + vx/l*3.4, it.at[1] + vz/l*3.4], r: [5.5, 3.0], depth: 0.9 };
  F.pools.push(pool);
  pool.level = c.h - 0.22;
}

const buckets = new Map();       // `${area}|${mat}` -> number[]
const add = (a, mat, T) => {
  if (!T || !T.length) return;
  if (!MATS[mat]) throw new Error('no material ' + mat);
  const k = a + '|' + mat;
  let b = buckets.get(k); if (!b) { b = []; buckets.set(k, b); }
  for (let i = 0; i < T.length; i++) b.push(T[i]);
};
const meshes_extra = [];         // pieces that move: { area, mat, T (local), at, kind }
const add_mesh = (a, mat, T, at, kind) => meshes_extra.push({ area: a, mat, T, at, kind });

// the rock surface
{
  const near = (x, z) => {
    const n = P.nearest(x, z, 16);
    if (n && n.d < n.p.w*1.6 + 8) return true;
    for (const c of CHAMBERS) if (Math.hypot(x - c.c[0], z - c.c[1]) < Math.max(c.r[0], c.r[1]) + 9) return true;
    for (const s of SHAFTS) if (Math.hypot(x - s.at[0], z - s.at[1]) < 14) return true;
    return false;
  };
  const vol = mesh_volume(F.field, GRID, near, log);
  const T = vol.tris;
  let kept = 0, under = 0, seam = 0;
  for (let i = 0; i < T.length; i += 9) {
    const cx = (T[i] + T[i + 3] + T[i + 6])/3, cy = (T[i + 1] + T[i + 4] + T[i + 7])/3, cz = (T[i + 2] + T[i + 5] + T[i + 8])/3;
    if (cz > SEAM_Z) { seam++; continue; }
    // the bowl under the floor (hidden by it): dropped
    if (cy < F.floor_y(cx, cz) - 0.3) {
      const ux = T[i + 3] - T[i], uy = T[i + 4] - T[i + 1], uz = T[i + 5] - T[i + 2], vx = T[i + 6] - T[i], vy = T[i + 7] - T[i + 1], vz = T[i + 8] - T[i + 2];
      const ny = uz*vx - ux*vz;
      void uy; void vy;
      if (ny > 0 || cy < F.floor_y(cx, cz) - 0.9) { under++; continue; }
    }
    const n = P.nearest(cx, cz, 40);
    const a = n ? n.p.area : 0;
    add(a, AREAS[a].biome + '.rock', T.subarray(i, i + 9));
    kept++;
  }
  log(`walls: ${kept} triangles (${under} under the floor, ${seam} past the seam dropped)`);
  F.volume = vol;
}

// the floor: a jittered grid (cave.js's floor) wherever there is air above it
{
  const CELL = 0.7;
  const x0 = GRID.x0, x1 = GRID.x1, z0 = GRID.z0, z1 = -47.0;
  const nx = Math.round((x1 - x0)/CELL), nz = Math.round((z1 - z0)/CELL);
  const cz1 = (z1 - z0)/nz;                      // the last row lands exactly on z1 (the room's floor starts there)
  const jit = (i, j, s) => (h3(i, j, 0, s) - 0.5)*CELL*0.55;
  const vx = (i, j) => [x0 + i*CELL + (i > 0 && i < nx ? jit(i, j, 61) : 0), z0 + j*cz1 + (j > 0 && j < nz ? jit(i, j, 67) : 0)];
  const fy = new Map();
  const vy = (x, z) => { const k = x + ',' + z; let y = fy.get(k); if (y === undefined) { y = F.floor_y(x, z); fy.set(k, y); } return y; };
  let n = 0;
  for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) {
    const [ax, az] = vx(i, j), [bx, bz] = vx(i + 1, j), [cx, cz] = vx(i + 1, j + 1), [dx, dz] = vx(i, j + 1);
    const mx = (ax + cx)/2, mz = (az + cz)/2;
    const nn = P.nearest(mx, mz, 30);
    if (!nn) continue;
    let air = false;
    for (const [x, z] of [[mx, mz], [ax, az], [bx, bz], [cx, cz], [dx, dz]]) if (F.field(x, F.floor_y(x, z) + 0.7, z) < 0) { air = true; break; }
    if (!air) continue;
    const a = nn.p.area;
    add(a, AREAS[a].biome + '.floor', [ax, vy(ax, az), az, dx, vy(dx, dz), dz, cx, vy(cx, cz), cz, ax, vy(ax, az), az, cx, vy(cx, cz), cz, bx, vy(bx, bz), bz]);
    n++;
  }
  log(`floor: ${n} cells`);
}

// formations
// "behind" object i: a point d metres from it away from its camera (from layout CAMERAS)
const behind = (i, d) => {
  const man = CAMERAS.find(c => c.item === i);
  const it = ITEMS[i];
  const n = P.nearest(it.at[0], it.at[1], 20).p;
  const a = man.from*Math.PI/180;
  const ax = n.tx*Math.cos(a) - n.tz*Math.sin(a), az = n.tx*Math.sin(a) + n.tz*Math.cos(a);
  return [it.at[0] - ax*d, it.at[1] - az*d];
};
const FR = formations({ P, F, add, add_mesh, behind });
log(`formations: ${[...buckets.values()].reduce((s, b) => s + b.length/9, 0)} triangles in all, ${meshes_extra.length} moving pieces`);

// ---------------------------------------------------------------- textures and albedos
const TEX = make_textures();
const s2l = c => (c < 0.04045 ? c*0.0773993808 : Math.pow(c*0.9478672986 + 0.0521327014, 2.4));
const albedo = {};
for (const [name, px] of Object.entries(TEX)) {
  let r = 0, g = 0, b = 0;
  for (let i = 0; i < px.length; i += 4) { r += s2l(px[i]/255); g += s2l(px[i + 1]/255); b += s2l(px[i + 2]/255); }
  const n = px.length/4;
  albedo[name] = [r/n, g/n, b/n];
}

// ---------------------------------------------------------------- the bake
const SUN_E = 9.0, SUN_COL = [1, 0.791, 0.479];          // the final room's sun (cave.js: 0xffe6b8, x9), linear
const SKY_L = [2.4, 2.5, 2.7];
const BEAM_L = [1.0*0.5*0.022, 0.8*0.5*0.022, 0.46*0.5*0.022];
const recs = [];
const order = [...buckets.keys()].sort();
for (const k of order) {
  const [a, mat] = k.split('|');
  const M = MATS[mat];
  const T = new Float32Array(buckets.get(k));
  recs.push({ key: k, area: +a, mat, T, albedo: albedo[M.tex], emit: M.bake_emit || M.emissive || null, receive: true });
}
for (const m of meshes_extra) {
  const T = new Float32Array(m.T.length);
  for (let i = 0; i < m.T.length; i += 3) { T[i] = m.T[i] + m.at[0]; T[i + 1] = m.T[i + 1] + m.at[1]; T[i + 2] = m.T[i + 2] + m.at[2]; }
  recs.push({ key: 'extra', piece: m, area: m.area, mat: m.mat, T, albedo: albedo[MATS[m.mat].tex], emit: null, receive: true });
}
// bake-only glow: the glow-worms' ceiling (a small patch at each worm, facing down)
{
  const G = [];
  const G2 = [];
  for (const w of FR.glowworms) {
    // a patch the size of the worm's glow; the passages' sparse worms glow less
    const n = P.nearest(w[0], w[2], 30);
    const inch = CHAMBERS.some(c => c.area === 2 && Math.hypot(w[0] - c.c[0], w[2] - c.c[1]) < Math.max(c.r[0], c.r[1])*1.1);
    const s = 0.14*Math.sqrt(w[3])*(inch ? 1 : 0.7);
    (inch ? G : G2).push(w[0] - s, w[1] - 0.01, w[2] - s, w[0] + s, w[1] - 0.01, w[2] - s, w[0], w[1] - 0.01, w[2] + s);
    void n;
  }
  recs.push({ key: 'bake_only', T: new Float32Array(G), albedo: [0, 0, 0], emit: [0.02, 0.09, 0.22], receive: false });
  recs.push({ key: 'bake_only', T: new Float32Array(G2), albedo: [0, 0, 0], emit: [0.03, 0.08, 0.14], receive: false });
}
const skies = [], beams = [];
for (const sh of SHAFTS) {
  const y = GRID.y1 - 0.3;
  skies.push({ y, cx: sh.at[0] + SUN_XZ[0]*(y - sh.h0), cz: sh.at[1] + SUN_XZ[1]*(y - sh.h0), r: sh.r*1.05, L: SKY_L });
  beams.push({ x: sh.at[0], z: sh.at[1], y0: sh.h0, r: sh.r*0.95, h: y - sh.h0, L: BEAM_L });
}
// probe grids: one per area, over its stretch of the walk
const boxes = AREAS.map(() => ({ x0: Infinity, x1: -Infinity, z0: Infinity, z1: -Infinity, y0: Infinity, y1: -Infinity }));
for (const p of P.S) {
  const b = boxes[p.area];
  b.x0 = Math.min(b.x0, p.x - p.w - 3); b.x1 = Math.max(b.x1, p.x + p.w + 3); b.z0 = Math.min(b.z0, p.z - p.w - 3); b.z1 = Math.max(b.z1, p.z + p.w + 3);
  b.y0 = Math.min(b.y0, p.h - 0.3); b.y1 = Math.max(b.y1, p.h + 5.5);
}
for (const c of CHAMBERS) {
  const b = boxes[c.area], R = Math.max(c.r[0], c.r[1]) + 1;
  b.x0 = Math.min(b.x0, c.c[0] - R); b.x1 = Math.max(b.x1, c.c[0] + R); b.z0 = Math.min(b.z0, c.c[1] - R); b.z1 = Math.max(b.z1, c.c[1] + R);
}
const grids = boxes.map(b => {
  const n = [clamp(Math.round((b.x1 - b.x0)/1.6) + 1, 4, 30), clamp(Math.round((b.y1 - b.y0)/1.2) + 1, 3, 8), clamp(Math.round((b.z1 - b.z0)/1.6) + 1, 4, 30)];
  return { min: [b.x0, b.y0, b.z0], max: [b.x1, b.y1, b.z1], n, rays: QUICK ? 16 : 48 };
});
let BK;
if (NOBAKE) {
  for (const r of recs) if (r.receive) r.gi = new Float32Array(r.T.length).fill(0.05);
  BK = { grids: grids.map(g => ({ up: new Float32Array(g.n[0]*g.n[1]*g.n[2]*4).fill(0.05), dn: new Float32Array(g.n[0]*g.n[1]*g.n[2]*4).fill(0.05) })) };
  BK.B = (await import('./bake.mjs')).make_bvh(recs.filter(r => r.receive).map(r => r.T));
} else {
  BK = bake(recs, { sun_dir: SUN_DIR, sun_E: SUN_COL.map(c => c*SUN_E), skies, beams, rays: QUICK ? 12 : 48, bounces: QUICK ? 2 : 3, seed: 5, denoise: 0.9, grids, log,
    debug_sun: process.env.DEBUG_SUN !== undefined ? +process.env.DEBUG_SUN : undefined, field: F.field,
    air: (x, y, z) => F.field(x, y, z) < 0.15 });
}

// ---------------------------------------------------------------- nav, cameras
const NAV = build_nav({ P, F, recs, log });
const CAMS = place_cameras({ P, F, B: BK.B, NAV, FR, log });

// ---------------------------------------------------------------- a map (top-down): areas, cameras, objects
{
  const k = 2, nx = Math.floor(NAV.nx/k), nz = Math.floor(NAV.nz/k);
  const img = Buffer.alloc(nx*nz*3);
  const AC = [[150, 120, 90], [200, 80, 40], [150, 180, 220], [190, 90, 70], [60, 190, 160], [190, 200, 240], [230, 190, 120], [140, 110, 80], [120, 120, 120]];
  const area = NAV.blobs.area;
  for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) {
    const c = (j*k)*NAV.nx + i*k;
    const o = ((nz - 1 - j)*nx + i)*3;
    if (NAV.blocked[c]) { img[o] = 18; img[o + 1] = 16; img[o + 2] = 15; continue; }
    const a = AC[area[c]] || [255, 0, 255];
    img[o] = a[0]*0.7; img[o + 1] = a[1]*0.7; img[o + 2] = a[2]*0.7;
  }
  const put = (x, z, col, r = 1) => {
    const i = Math.floor((x - NAV.meta.x0)/NAV.meta.cell/k), j = Math.floor((z - NAV.meta.z0)/NAV.meta.cell/k);
    for (let dj = -r; dj <= r; dj++) for (let di = -r; di <= r; di++) {
      const ii = i + di, jj = j + dj;
      if (ii < 0 || jj < 0 || ii >= nx || jj >= nz) continue;
      const o = ((nz - 1 - jj)*nx + ii)*3; img[o] = col[0]; img[o + 1] = col[1]; img[o + 2] = col[2];
    }
  };
  for (const p of P.S) put(p.x, p.z, [90, 90, 90], 0);
  for (const c of CAMS) {
    for (let t = 0; t <= 1; t += 0.02) put(c.eye[0] + (c.tgt[0] - c.eye[0])*t, c.eye[2] + (c.tgt[2] - c.eye[2])*t, [200, 200, 60], 0);
    put(c.eye[0], c.eye[2], [255, 255, 255], 1);
  }
  for (const it of ITEMS) put(it.at[0], it.at[1], [255, 60, 200], 2);
  fs.mkdirSync(path.join(ROOT, 'scratch'), { recursive: true });
  fs.writeFileSync(path.join(ROOT, 'scratch', 'walk_map.ppm'), Buffer.concat([Buffer.from(`P6
${nx} ${nz}
255
`), img]));
}

// ---------------------------------------------------------------- write
fs.rmSync(OUT, { recursive: true, force: true });
for (const d of ['geo', 'tex', 'nav']) fs.mkdirSync(path.join(OUT, d), { recursive: true });
const manifest = { geometries: {}, textures: {} };
const wf = (rel, arr) => fs.writeFileSync(path.join(OUT, rel), Buffer.from(arr.buffer, arr.byteOffset, arr.byteLength));
function geometry(name, T, gi, smooth) {
  const pos = T instanceof Float32Array ? T : new Float32Array(T);
  const nrm = smooth ? smooth_normals(pos) : flat_normals(pos);
  const uv = world_uv(pos, 2);
  wf(`geo/${name}.position.f32`, pos); wf(`geo/${name}.normal.f32`, nrm); wf(`geo/${name}.uv.f32`, uv); wf(`geo/${name}.gi.f32`, gi);
  let cx = 0, cy = 0, cz = 0;
  const n = pos.length/3;
  let x0 = Infinity, y0 = Infinity, z0 = Infinity, x1 = -Infinity, y1 = -Infinity, z1 = -Infinity;
  for (let i = 0; i < pos.length; i += 3) { x0 = Math.min(x0, pos[i]); x1 = Math.max(x1, pos[i]); y0 = Math.min(y0, pos[i + 1]); y1 = Math.max(y1, pos[i + 1]); z0 = Math.min(z0, pos[i + 2]); z1 = Math.max(z1, pos[i + 2]); }
  cx = (x0 + x1)/2; cy = (y0 + y1)/2; cz = (z0 + z1)/2;
  let r = 0;
  for (let i = 0; i < pos.length; i += 3) r = Math.max(r, Math.hypot(pos[i] - cx, pos[i + 1] - cy, pos[i + 2] - cz));
  manifest.geometries[name] = { attrs: { position: { size: 3, count: n }, normal: { size: 3, count: n }, uv: { size: 2, count: n }, gi: { size: 3, count: n } },
    order: ['position', 'normal', 'uv', 'gi'], bs: [cx, cy, cz, r], draw_range: [0, -1], groups: [] };
  return name;
}
for (const [name, px] of Object.entries(TEX)) {
  fs.writeFileSync(path.join(OUT, 'tex', name + '.rgba'), px);
  manifest.textures[name] = { kind: 'rgba8', w: 64, h: 64, srgb: true, min: 'nearest_mipmap_nearest', mag: 'nearest', wrap_s: 'repeat', wrap_t: 'repeat', mipmaps: true, offset: [0, 0], repeat: [1, 1] };
}
const W = { areas: [], meshes: [], pieces: [], mats: {}, cameras: CAMS, items: [], start: START, nav: NAV.meta, points: {}, path: { total: P.total, pts: [] } };
// the centre line every metre (the harness walks him along it)
for (let i = 0; i < P.S.length; i += 4) W.path.pts.push(+P.S[i].x.toFixed(3), +P.S[i].z.toFixed(3));
for (const [k, m] of Object.entries(MATS)) W.mats[k] = { prog: m.prog, tex: m.tex, emissive: m.emissive || [0, 0, 0] };
// split big buckets so frustum culling has something to cull (chunks of ~20 m)
for (const r of recs) {
  if (r.key === 'extra' || r.key === 'bake_only') continue;
  const CH = 20;
  const parts = new Map();
  for (let i = 0; i < r.T.length; i += 9) {
    const cx = (r.T[i] + r.T[i + 3] + r.T[i + 6])/3, cz = (r.T[i + 2] + r.T[i + 5] + r.T[i + 8])/3;
    const k = Math.floor(cx/CH) + ',' + Math.floor(cz/CH);
    let p = parts.get(k); if (!p) { p = []; parts.set(k, p); } p.push(i);
  }
  let pi = 0;
  for (const idx of parts.values()) {
    const T = new Float32Array(idx.length*9), G = new Float32Array(idx.length*9);
    idx.forEach((i, q) => { T.set(r.T.subarray(i, i + 9), q*9); G.set(r.gi.subarray(i, i + 9), q*9); });
    const name = `w${r.area}_${r.mat.replace('.', '_')}_${pi++}`;
    geometry(name, T, G, MATS[r.mat].smooth);
    W.meshes.push({ geo: name, area: r.area, mat: r.mat });
  }
}
// moving pieces: geometry in their own frame (gi baked where they rest)
let pn = 0;
for (const r of recs) {
  if (r.key !== 'extra') continue;
  const m = r.piece;
  const name = `wp${pn++}`;
  geometry(name, new Float32Array(m.T), r.gi, false);
  W.pieces.push({ geo: name, area: m.area, mat: m.mat, at: m.at, kind: m.kind });
}
// the lid: a shadow-only sheet over the whole walk, holed where each shaft reaches the sky (as
// the final room's): outside the rock shell nothing would stop the sun in the shadow map, and the
// air of the columns is marched through that map
{
  const C = 2.0, y = GRID.y1 - 0.5, L = [];
  const holes = SHAFTS.map(sh => [sh.at[0] + SUN_XZ[0]*(y - sh.h0), sh.at[1] + SUN_XZ[1]*(y - sh.h0), sh.r*1.6 + C*0.75]);
  for (let x = GRID.x0 - 30; x < GRID.x1 + 30; x += C) for (let z = GRID.z0 - 30; z < GRID.z1 + 30; z += C) {
    const cx = x + C/2, cz = z + C/2;
    if (holes.some(h => Math.hypot(cx - h[0], cz - h[1]) < h[2])) continue;
    L.push(x, y, z, x, y, z + C, x + C, y, z + C, x, y, z, x + C, y, z + C, x + C, y, z);
  }
  const pos = new Float32Array(L);
  wf('geo/walk_lid.position.f32', pos); wf('geo/walk_lid.normal.f32', flat_normals(pos)); wf('geo/walk_lid.uv.f32', world_uv(pos, 2));
  const n = pos.length/3;
  manifest.geometries.walk_lid = { attrs: { position: { size: 3, count: n }, normal: { size: 3, count: n }, uv: { size: 2, count: n } }, order: ['position', 'normal', 'uv'],
    bs: [(GRID.x0 + GRID.x1)/2, y, (GRID.z0 + GRID.z1)/2, 200], draw_range: [0, -1], groups: [] };
  W.lid = 'walk_lid';
}
// probe grids
grids.forEach((g, a) => {
  const up = BK.grids[a].up, dn = BK.grids[a].dn;
  wf(`tex/gi_up_${a}.f32`, up); wf(`tex/gi_down_${a}.f32`, dn);
  for (const nm of ['gi_up_' + a, 'gi_down_' + a]) manifest.textures[nm] = { kind: 'f32_3d', w: g.n[0], h: g.n[1], d: g.n[2], format: 'rgba', min: 'linear', mag: 'linear', wrap_s: 'clamp', wrap_t: 'clamp', wrap_r: 'clamp' };
  W.areas[a] = { id: AREAS[a].id, name: AREAS[a].name, biome: AREAS[a].biome, s0: P.areas_s[a].s0, s1: P.areas_s[a].s1,
    gi: { up: 'gi_up_' + a, down: 'gi_down_' + a, min: g.min, max: g.max }, box: boxes[a],
    shafts: SHAFTS.filter(s => s.area === a).map(sh => ({ at: sh.at, r: sh.r, h0: sh.h0, top: GRID.y1 })) };
});
// nav blobs
for (const [k, arr] of Object.entries(NAV.blobs)) wf(`nav/${k}.bin`, arr);
// objects
for (const it of ITEMS) {
  const y = F.floor_y(it.at[0], it.at[1]);
  const n = P.nearest(it.at[0], it.at[1], 20);
  W.items.push({ power: it.power, area: it.area, at: [it.at[0], y + it.lift, it.at[1]], floor: y, stand: it.stand, s: n.p.s });
}
W.points.glowworms = FR.glowworms.flat();
W.points.embers = FR.embers.flat();
W.points.caps = FR.caps.flat();
W.floaters = FR.floaters.map((f, i) => ({ piece: W.pieces.findIndex(p => p.kind === 'floater' && p.at === f.at), s: f.s, d: f.d }));
W.anchors = { altar_top: FR.altar_top, stalagmite_top: FR.stalagmite_top, lodestone_y: FR.lodestone_y, pool_y: FR.pool_y, water: FR.water,
  gem_top: FR.gem_top, ring_y: FR.ring_y, burn: FR.burn };
W.sun = { dir: SUN_DIR, color: SUN_COL, E: SUN_E };
manifest.walk = W;
manifest.dir = 'assets/port/walk';

// the manifest as a Lua table
function lua(v, ind = '') {
  if (v === null || v === undefined) return 'nil';
  if (typeof v === 'number') return Number.isFinite(v) ? (Number.isInteger(v) ? String(v) : String(+v.toPrecision(9))) : (v > 0 ? 'math.huge' : '-math.huge');
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'string') return JSON.stringify(v);
  if (Array.isArray(v)) return '{' + v.map(x => lua(x, ind)).join(',') + '}';
  const KW = new Set(['and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'goto', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while']);
  return '{' + Object.entries(v).filter(([, x]) => x !== undefined && x !== null).map(([k, x]) => (/^[A-Za-z_][A-Za-z0-9_]*$/.test(k) && !KW.has(k) ? k : '[' + JSON.stringify(k) + ']') + '=' + lua(x, ind)).join(',') + '}';
}
fs.writeFileSync(path.join(ROOT, 'assets', 'port', 'walk.lua'), '-- generated by tools/walk/build.mjs (the walk through the cave)\nreturn ' + lua(manifest) + '\n');
let files = 0, bytes = 0;
for (const d of ['geo', 'tex', 'nav']) for (const f of fs.readdirSync(path.join(OUT, d))) { files++; bytes += fs.statSync(path.join(OUT, d, f)).size; }
log(`wrote ${files} files (${(bytes/1e6).toFixed(1)} MB), ${W.meshes.length} meshes, ${W.pieces.length} pieces, ${CAMS.length} cameras`);
