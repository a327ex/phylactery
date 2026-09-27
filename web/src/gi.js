// gi.js -- baked global illumination for a static scene with one static light.
//
// The cave never moves and neither does the sun, so the light bouncing around it can be
// computed once: every triangle of the static meshes gathers light by casting rays over its
// hemisphere against a BVH of the whole cave. What a ray sees is the radiance of the surface it
// hits (albedo x the irradiance there / pi) or, if it leaves through the shaft, the sky.
// Direct sunlight is NOT baked (the real directional light and its shadow map draw it, sharp);
// only the indirect light is, stored per vertex as an attribute `gi` (irradiance, linear, in
// three.js light units: a lambert surface shows gi * albedo / pi).
//
// For things that move (the lich, the snakes) a grid of probes stores the irradiance an
// upward-facing and a downward-facing surface would receive; their materials sample it by world
// position and blend by the normal's y.
//
// Units: the sun's irradiance on a surface facing it is sun_E (= the directional light's
// intensity), matching three.js's RE_Direct for directional lights.
import * as THREE from 'three';
import { make_rng } from 'game/util.js';

// ---------------------------------------------------------------- BVH over triangles
function build_bvh(P) {             // P: Float32Array, 9 floats per triangle
  const N = P.length/9;
  const cx = new Float32Array(N), cy = new Float32Array(N), cz = new Float32Array(N);
  const bmin = new Float32Array(N*3), bmax = new Float32Array(N*3);
  for (let i = 0; i < N; i++) {
    const o = i*9;
    let x0 = Infinity, y0 = Infinity, z0 = Infinity, x1 = -Infinity, y1 = -Infinity, z1 = -Infinity;
    for (let k = 0; k < 3; k++) {
      const x = P[o + k*3], y = P[o + k*3 + 1], z = P[o + k*3 + 2];
      if (x < x0) x0 = x; if (y < y0) y0 = y; if (z < z0) z0 = z;
      if (x > x1) x1 = x; if (y > y1) y1 = y; if (z > z1) z1 = z;
    }
    bmin[i*3] = x0; bmin[i*3 + 1] = y0; bmin[i*3 + 2] = z0; bmax[i*3] = x1; bmax[i*3 + 1] = y1; bmax[i*3 + 2] = z1;
    cx[i] = (x0 + x1)/2; cy[i] = (y0 + y1)/2; cz[i] = (z0 + z1)/2;
  }
  const idx = new Uint32Array(N);
  for (let i = 0; i < N; i++) idx[i] = i;
  // nodes: min(3) max(3) left/first, count (count > 0 = leaf)
  const nb = [], nc = [];
  const LEAF = 4;
  const C = [cx, cy, cz];
  function build(first, count) {
    const ni = nc.length/2;
    let x0 = Infinity, y0 = Infinity, z0 = Infinity, x1 = -Infinity, y1 = -Infinity, z1 = -Infinity;
    let c0x = Infinity, c0y = Infinity, c0z = Infinity, c1x = -Infinity, c1y = -Infinity, c1z = -Infinity;
    for (let i = first; i < first + count; i++) {
      const t = idx[i];
      if (bmin[t*3] < x0) x0 = bmin[t*3]; if (bmin[t*3 + 1] < y0) y0 = bmin[t*3 + 1]; if (bmin[t*3 + 2] < z0) z0 = bmin[t*3 + 2];
      if (bmax[t*3] > x1) x1 = bmax[t*3]; if (bmax[t*3 + 1] > y1) y1 = bmax[t*3 + 1]; if (bmax[t*3 + 2] > z1) z1 = bmax[t*3 + 2];
      if (cx[t] < c0x) c0x = cx[t]; if (cy[t] < c0y) c0y = cy[t]; if (cz[t] < c0z) c0z = cz[t];
      if (cx[t] > c1x) c1x = cx[t]; if (cy[t] > c1y) c1y = cy[t]; if (cz[t] > c1z) c1z = cz[t];
    }
    nb.push(x0, y0, z0, x1, y1, z1);
    nc.push(0, 0);
    if (count <= LEAF) { nc[ni*2] = first; nc[ni*2 + 1] = count; return ni; }
    const ex = c1x - c0x, ey = c1y - c0y, ez = c1z - c0z;
    const ax = ex >= ey && ex >= ez ? 0 : ey >= ez ? 1 : 2;
    const mid = ax === 0 ? (c0x + c1x)/2 : ax === 1 ? (c0y + c1y)/2 : (c0z + c1z)/2;
    const A = C[ax];
    let i = first, j = first + count - 1;
    while (i <= j) { if (A[idx[i]] < mid) i++; else { const t = idx[i]; idx[i] = idx[j]; idx[j] = t; j--; } }
    let nl = i - first;
    if (nl === 0 || nl === count) nl = count >> 1;
    const l = build(first, nl);
    const r = build(first + nl, count - nl);
    void l;
    nc[ni*2] = r; nc[ni*2 + 1] = 0;           // interior: left child is ni+1, right is r
    return ni;
  }
  build(0, N);
  // reorder triangles into leaf order for locality
  const T = new Float32Array(P.length);
  for (let i = 0; i < N; i++) T.set(P.subarray(idx[i]*9, idx[i]*9 + 9), i*9);
  return { T, idx, box: new Float32Array(nb), node: new Int32Array(nc), N };
}

const EPS = 1e-7;
// closest hit: returns t (Infinity if none) and writes the hit into out = {tri, u, v}
function intersect(B, ox, oy, oz, dx, dy, dz, tmax, out, any = false) {
  const { T, box, node } = B;
  const ix = 1/dx, iy = 1/dy, iz = 1/dz;
  const stack = intersect.stack || (intersect.stack = new Int32Array(128));
  let sp = 0, best = tmax, hit = -1, hu = 0, hv = 0;
  stack[sp++] = 0;
  while (sp > 0) {
    const n = stack[--sp];
    const b = n*6;
    let t0 = (box[b] - ox)*ix, t1 = (box[b + 3] - ox)*ix;
    if (t0 > t1) { const q = t0; t0 = t1; t1 = q; }
    let s0 = (box[b + 1] - oy)*iy, s1 = (box[b + 4] - oy)*iy;
    if (s0 > s1) { const q = s0; s0 = s1; s1 = q; }
    if (s0 > t0) t0 = s0; if (s1 < t1) t1 = s1;
    let r0 = (box[b + 2] - oz)*iz, r1 = (box[b + 5] - oz)*iz;
    if (r0 > r1) { const q = r0; r0 = r1; r1 = q; }
    if (r0 > t0) t0 = r0; if (r1 < t1) t1 = r1;
    if (t1 < t0 || t1 < 0 || t0 > best) continue;
    const cnt = node[n*2 + 1];
    if (cnt > 0) {
      const first = node[n*2];
      for (let k = first; k < first + cnt; k++) {
        const o = k*9;
        const ax = T[o], ay = T[o + 1], az = T[o + 2];
        const e1x = T[o + 3] - ax, e1y = T[o + 4] - ay, e1z = T[o + 5] - az;
        const e2x = T[o + 6] - ax, e2y = T[o + 7] - ay, e2z = T[o + 8] - az;
        const px = dy*e2z - dz*e2y, py = dz*e2x - dx*e2z, pz = dx*e2y - dy*e2x;
        const det = e1x*px + e1y*py + e1z*pz;
        if (det > -EPS && det < EPS) continue;
        const inv = 1/det;
        const tx = ox - ax, ty = oy - ay, tz = oz - az;
        const u = (tx*px + ty*py + tz*pz)*inv;
        if (u < 0 || u > 1) continue;
        const qx = ty*e1z - tz*e1y, qy = tz*e1x - tx*e1z, qz = tx*e1y - ty*e1x;
        const v = (dx*qx + dy*qy + dz*qz)*inv;
        if (v < 0 || u + v > 1) continue;
        const t = (e2x*qx + e2y*qy + e2z*qz)*inv;
        if (t > 1e-4 && t < best) { best = t; hit = k; hu = u; hv = v; if (any) return t; }
      }
    } else {
      stack[sp++] = node[n*2];               // right
      stack[sp++] = n + 1;                   // left
    }
  }
  if (out) { out.tri = hit; out.u = hu; out.v = hv; }
  return hit < 0 ? Infinity : best;
}

const s2l = c => (c < 0.04045 ? c*0.0773993808 : Math.pow(c*0.9478672986 + 0.0521327014, 2.4));
// average linear albedo of a material (its colour x its texture's mean colour)
function albedo_of(mat) {
  const c = new THREE.Color(1, 1, 1);
  if (mat.color) c.copy(mat.color);
  const img = mat.map && mat.map.image;
  if (img && img.getContext) {
    const d = img.getContext('2d').getImageData(0, 0, img.width, img.height).data;
    let r = 0, g = 0, b = 0;
    const n = d.length/4;
    for (let i = 0; i < d.length; i += 4) {
      r += s2l(d[i]/255); g += s2l(d[i + 1]/255); b += s2l(d[i + 2]/255);
    }
    c.r *= r/n; c.g *= g/n; c.b *= b/n;
  }
  return c;
}

// ---------------------------------------------------------------- the bake
// meshes: static meshes (non-indexed geometry; any transform). opts:
//   sun_dir (to the sun), sun_E, sky { y, cx, cz, r, L: [r,g,b] } -- the shaft's opening as a
//   disc at height y, radiance L; rays: per triangle per bounce; bounces;
//   occluders: extra meshes that block light but receive nothing (the lid); albedo 0
export function bake_gi(meshes, opts, progress) {
  const rng = make_rng(opts.seed || 3);
  const L = opts.sun_dir.clone().normalize();
  const all = [];
  const recs = [];
  const add = (m, receive) => {
    m.updateMatrixWorld(true);
    const g = m.geometry.index ? m.geometry.toNonIndexed() : m.geometry;     // occluders may be indexed
    const p = g.attributes.position;
    const tris = p.count/3;
    const a = receive ? albedo_of(m.material) : new THREE.Color(0, 0, 0);
    const base = all.length/9;
    const v = new THREE.Vector3();
    for (let i = 0; i < p.count; i++) { v.fromBufferAttribute(p, i).applyMatrix4(m.matrixWorld); all.push(v.x, v.y, v.z); }
    recs.push({ m, base, tris, a, receive });
  };
  for (const m of meshes) add(m, true);
  for (const m of opts.occluders || []) add(m, false);
  const P = new Float32Array(all);
  const N = P.length/9;
  // the stored bake is valid only for exactly this geometry and these settings
  let sum = 0;
  for (let i = 0; i < P.length; i += 7) sum = (sum + P[i]*(1 + (i % 13)))%1e6;
  const key = [N, sum.toFixed(3), opts.rays, opts.bounces, opts.seed, JSON.stringify(opts.beam || 0), JSON.stringify(opts.sky), opts.sun_E.join(','),
    JSON.stringify(opts.grid || 0), opts.denoise || 0, 'v2'].join('|');
  const cache = opts.cache && opts.cache.key === key ? opts.cache : null;
  const B = cache ? null : build_bvh(P);
  // per ORIGINAL triangle: normal, centre, area, albedo, receive
  const nrm = new Float32Array(N*3), cen = new Float32Array(N*3), area = new Float32Array(N), alb = new Float32Array(N*3);
  const recv = new Uint8Array(N);
  for (const r of recs) for (let t = 0; t < r.tris; t++) {
    const i = r.base + t, o = i*9;
    const e1x = P[o + 3] - P[o], e1y = P[o + 4] - P[o + 1], e1z = P[o + 5] - P[o + 2];
    const e2x = P[o + 6] - P[o], e2y = P[o + 7] - P[o + 1], e2z = P[o + 8] - P[o + 2];
    let nx = e1y*e2z - e1z*e2y, ny = e1z*e2x - e1x*e2z, nz = e1x*e2y - e1y*e2x;
    const l = Math.hypot(nx, ny, nz) || 1;
    area[i] = l/2;
    nrm[i*3] = nx/l; nrm[i*3 + 1] = ny/l; nrm[i*3 + 2] = nz/l;
    cen[i*3] = (P[o] + P[o + 3] + P[o + 6])/3; cen[i*3 + 1] = (P[o + 1] + P[o + 4] + P[o + 7])/3; cen[i*3 + 2] = (P[o + 2] + P[o + 5] + P[o + 8])/3;
    alb[i*3] = r.a.r; alb[i*3 + 1] = r.a.g; alb[i*3 + 2] = r.a.b;
    recv[i] = r.receive ? 1 : 0;
  }
  // BVH order -> original index
  const orig = B ? B.idx : null;
  const Ed = new Float32Array(N*3);              // direct irradiance per triangle (both sides)
  const sun_E = opts.sun_E;
  const hit = { tri: -1, u: 0, v: 0 };
  const shadow = (x, y, z) => intersect(B, x, y, z, L.x, L.y, L.z, 200, null, true) === Infinity;
  for (let i = 0; i < N && !cache; i++) {
    if (!recv[i]) continue;
    const nx = nrm[i*3], ny = nrm[i*3 + 1], nz = nrm[i*3 + 2];
    const d = nx*L.x + ny*L.y + nz*L.z;
    if (d <= 0) continue;
    const x = cen[i*3] + nx*0.02, y = cen[i*3 + 1] + ny*0.02, z = cen[i*3 + 2] + nz*0.02;
    if (!shadow(x, y, z)) continue;
    Ed[i*3] = sun_E[0]*d; Ed[i*3 + 1] = sun_E[1]*d; Ed[i*3 + 2] = sun_E[2]*d;
  }
  // every receiving triangle's winding must point its normal at the open side (cave.js orients
  // them: walls inward, floor up, rocks outward); the gather shoots from that side
  const side = new Int8Array(N).fill(1);
  const sky = opts.sky;
  const Ei = new Float32Array(N*3), Enext = new Float32Array(N*3);
  const K = opts.rays || 32;
  const bounces = opts.bounces || 2;
  const tangent = (nx, ny, nz) => {
    const ax = Math.abs(nx) < 0.9 ? 1 : 0, ay = ax ? 0 : 1;
    let tx = ay*nz - 0*ny, ty = 0*nx - ax*nz, tz = ax*ny - ay*nx;
    const l = Math.hypot(tx, ty, tz) || 1;
    return [tx/l, ty/l, tz/l];
  };
  // the column of light is dusty air: seen along a ray it glows with radiance proportional to
  // the chord through it (beam.L per metre, the same law render.js's shaft pass draws), and
  // what it scatters lights the rock around it
  const beam = opts.beam;
  const ba = opts.sun_dir.clone().normalize();
  function beam_chord(x, y, z, dx, dy, dz, tmax) {
    if (!beam) return 0;
    const wx = x - beam.x, wy = y, wz = z - beam.z;
    const wa = wx*ba.x + wy*ba.y + wz*ba.z, da = dx*ba.x + dy*ba.y + dz*ba.z;
    const px = wx - ba.x*wa, py = wy - ba.y*wa, pz = wz - ba.z*wa;
    const qx = dx - ba.x*da, qy = dy - ba.y*da, qz = dz - ba.z*da;
    const A = qx*qx + qy*qy + qz*qz, Bq = px*qx + py*qy + pz*qz, C = px*px + py*py + pz*pz - beam.r*beam.r;
    if (A < 1e-9) return C < 0 ? Math.min(tmax, beam.h) : 0;
    const disc = Bq*Bq - A*C;
    if (disc <= 0) return 0;
    const sq = Math.sqrt(disc);
    const t0 = Math.max(0, (-Bq - sq)/A), t1 = Math.min(tmax, (-Bq + sq)/A);
    return t1 > t0 ? t1 - t0 : 0;
  }
  function gather(x, y, z, nx, ny, nz, out, rays) {
    const [tx, ty, tz] = tangent(nx, ny, nz);
    const bx = ny*tz - nz*ty, by = nz*tx - nx*tz, bz = nx*ty - ny*tx;
    let r = 0, g = 0, b = 0;
    for (let k = 0; k < rays; k++) {
      // cosine-weighted hemisphere (stratified in phi)
      const u1 = rng.next(), u2 = (k + rng.next())/rays;
      const rr = Math.sqrt(u1), phi = 6.2831853*u2;
      const lx = rr*Math.cos(phi), ly = rr*Math.sin(phi), lz = Math.sqrt(Math.max(0, 1 - u1));
      const dx = tx*lx + bx*ly + nx*lz, dy = ty*lx + by*ly + ny*lz, dz = tz*lx + bz*ly + nz*lz;
      const t = intersect(B, x, y, z, dx, dy, dz, 300, hit);
      if (beam) {
        const ch = beam_chord(x, y, z, dx, dy, dz, t === Infinity ? 60 : t);
        if (ch > 0) { r += Math.PI*beam.L[0]*ch; g += Math.PI*beam.L[1]*ch; b += Math.PI*beam.L[2]*ch; }
      }
      if (t === Infinity) {
        // escaped: the sky, if it went out through the shaft's opening
        if (dy > 0.05) {
          const s = (sky.y - y)/dy;
          const px = x + dx*s - sky.cx, pz = z + dz*s - sky.cz;
          if (s > 0 && px*px + pz*pz < sky.r*sky.r) { r += Math.PI*sky.L[0]; g += Math.PI*sky.L[1]; b += Math.PI*sky.L[2]; }
        }
        continue;
      }
      const j = orig[hit.tri];
      if (!recv[j]) continue;
      // radiance of the hit = albedo x (direct + indirect) / pi; E += pi*L/K per sample
      r += alb[j*3]*(Ed[j*3] + Ei[j*3]);
      g += alb[j*3 + 1]*(Ed[j*3 + 1] + Ei[j*3 + 1]);
      b += alb[j*3 + 2]*(Ed[j*3 + 2] + Ei[j*3 + 2]);
    }
    out[0] = r/rays; out[1] = g/rays; out[2] = b/rays;
  }
  const tmp = [0, 0, 0];
  for (let bounce = 0; bounce < (cache ? 0 : bounces); bounce++) {
    for (let i = 0; i < N; i++) {
      if (!recv[i]) continue;
      const s = side[i];
      const nx = nrm[i*3]*s, ny = nrm[i*3 + 1]*s, nz = nrm[i*3 + 2]*s;
      gather(cen[i*3] + nx*0.02, cen[i*3 + 1] + ny*0.02, cen[i*3 + 2] + nz*0.02, nx, ny, nz, tmp, K);
      Enext[i*3] = tmp[0]; Enext[i*3 + 1] = tmp[1]; Enext[i*3 + 2] = tmp[2];
      if (progress && (i & 4095) === 0) progress(bounce, i/N);
    }
    Ei.set(Enext);
  }
  if (cache) Ei.set(cache.Ei);
  else if (opts.denoise) {
    // bounce light is smooth: average each triangle with its neighbours within `denoise` metres,
    // weighted by area, by how alike the normals are, and by distance (removes Monte Carlo speckle)
    const Rd = opts.denoise, cell = Rd;
    const grid = new Map();
    const ck = (x, y, z) => `${Math.floor(x/cell)},${Math.floor(y/cell)},${Math.floor(z/cell)}`;
    for (let i = 0; i < N; i++) {
      if (!recv[i]) continue;
      const k = ck(cen[i*3], cen[i*3 + 1], cen[i*3 + 2]);
      let a = grid.get(k); if (!a) { a = []; grid.set(k, a); } a.push(i);
    }
    const out = new Float32Array(N*3);
    for (let i = 0; i < N; i++) {
      if (!recv[i]) continue;
      const x = cen[i*3], y = cen[i*3 + 1], z = cen[i*3 + 2];
      const gx = Math.floor(x/cell), gy = Math.floor(y/cell), gz = Math.floor(z/cell);
      let wr = 0, wg = 0, wb = 0, W = 0;
      for (let dz = -1; dz <= 1; dz++) for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const a = grid.get(`${gx + dx},${gy + dy},${gz + dz}`);
        if (!a) continue;
        for (const j of a) {
          const ddx = cen[j*3] - x, ddy = cen[j*3 + 1] - y, ddz = cen[j*3 + 2] - z;
          const d2 = ddx*ddx + ddy*ddy + ddz*ddz;
          if (d2 > Rd*Rd) continue;
          const nd = nrm[i*3]*nrm[j*3] + nrm[i*3 + 1]*nrm[j*3 + 1] + nrm[i*3 + 2]*nrm[j*3 + 2];
          if (nd <= 0.2) continue;
          const w = area[j]*nd*nd*Math.exp(-2.5*d2/(Rd*Rd));
          wr += Ei[j*3]*w; wg += Ei[j*3 + 1]*w; wb += Ei[j*3 + 2]*w; W += w;
        }
      }
      if (W > 0) { out[i*3] = wr/W; out[i*3 + 1] = wg/W; out[i*3 + 2] = wb/W; }
    }
    Ei.set(out);
  }

  // per-vertex values: area-weighted average of the triangles sharing the vertex position,
  // weighted also by how alike their normals are (facets keep a little of their own value)
  const pkey = (x, y, z) => `${Math.round(x*200)},${Math.round(y*200)},${Math.round(z*200)}`;
  const acc = new Map();
  for (const r of recs) {
    if (!r.receive) continue;
    for (let t = 0; t < r.tris; t++) {
      const i = r.base + t, o = i*9;
      for (let k = 0; k < 3; k++) {
        const kk = pkey(P[o + k*3], P[o + k*3 + 1], P[o + k*3 + 2]);
        let a = acc.get(kk);
        if (!a) { a = []; acc.set(kk, a); }
        a.push(i);
      }
    }
  }
  for (const r of recs) {
    if (!r.receive) continue;
    const gi = new Float32Array(r.tris*9);
    for (let t = 0; t < r.tris; t++) {
      const i = r.base + t, o = i*9;
      const s = side[i];
      const nx = nrm[i*3]*s, ny = nrm[i*3 + 1]*s, nz = nrm[i*3 + 2]*s;
      for (let k = 0; k < 3; k++) {
        const list = acc.get(pkey(P[o + k*3], P[o + k*3 + 1], P[o + k*3 + 2]));
        let wr = 0, wg = 0, wb = 0, W = 0;
        for (const j of list) {
          const sj = side[j];
          const dt = nx*nrm[j*3]*sj + ny*nrm[j*3 + 1]*sj + nz*nrm[j*3 + 2]*sj;
          const w = area[j]*Math.max(0.05, dt) + (j === i ? area[j] : 0);
          wr += Ei[j*3]*w; wg += Ei[j*3 + 1]*w; wb += Ei[j*3 + 2]*w; W += w;
        }
        gi[t*9 + k*3] = wr/W; gi[t*9 + k*3 + 1] = wg/W; gi[t*9 + k*3 + 2] = wb/W;
      }
    }
    r.m.geometry.setAttribute('gi', new THREE.BufferAttribute(gi, 3));
  }

  // probe grid for moving things: irradiance on an up- and a down-facing surface
  const G = opts.grid;
  let probes = null, probe_data = null;
  if (G) {
    const [nx_, ny_, nz_] = G.n;
    const up = new Float32Array(nx_*ny_*nz_*4), dn = new Float32Array(nx_*ny_*nz_*4);
    for (let k = 0; k < nz_; k++) for (let j = 0; j < ny_; j++) for (let i = 0; i < nx_; i++) {
      const x = G.min[0] + (G.max[0] - G.min[0])*i/(nx_ - 1);
      const y = G.min[1] + (G.max[1] - G.min[1])*j/(ny_ - 1);
      const z = G.min[2] + (G.max[2] - G.min[2])*k/(nz_ - 1);
      const o = ((k*ny_ + j)*nx_ + i)*4;
      if (cache) continue;
      gather(x, y, z, 0, 1, 0, tmp, G.rays || 48);
      up[o] = tmp[0]; up[o + 1] = tmp[1]; up[o + 2] = tmp[2]; up[o + 3] = 1;
      gather(x, y, z, 0, -1, 0, tmp, G.rays || 48);
      dn[o] = tmp[0]; dn[o + 1] = tmp[1]; dn[o + 2] = tmp[2]; dn[o + 3] = 1;
    }
    if (cache) { up.set(cache.up); dn.set(cache.dn); }
    probe_data = { up, dn };
    const tex = (data) => {
      const t = new THREE.Data3DTexture(data, nx_, ny_, nz_);
      t.format = THREE.RGBAFormat; t.type = THREE.FloatType;
      t.minFilter = t.magFilter = THREE.LinearFilter;
      t.wrapS = t.wrapT = t.wrapR = THREE.ClampToEdgeWrapping;
      t.needsUpdate = true;
      return t;
    };
    probes = { up: tex(up), down: tex(dn), min: new THREE.Vector3(...G.min), max: new THREE.Vector3(...G.max) };
  }
  return { tris: N, probes, cached: !!cache, data: { key, Ei, up: probe_data && probe_data.up, dn: probe_data && probe_data.dn } };
}

// ---------------------------------------------------------------- shader hooks
// static receivers: add the baked indirect irradiance (attribute gi) to a Lambert/Standard material
export function gi_static(mat, U) {
  const prev = mat.onBeforeCompile;
  mat.onBeforeCompile = (sh, r) => {
    if (prev) prev(sh, r);
    sh.uniforms.uGIScale = U.uGIScale;
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nattribute vec3 gi;\nvarying vec3 vGI;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\n  vGI = gi;');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vGI;\nuniform float uGIScale;')
      .replace('#include <lights_fragment_end>', '#include <lights_fragment_end>\n  reflectedLight.indirectDiffuse += vGI*uGIScale*BRDF_Lambert(diffuseColor.rgb);');
  };
  mat.customProgramCacheKey = () => 'gi_static';
  return mat;
}

// moving receivers: sample the probe grid at the fragment's world position
export const GI_DYN_DECL = /* glsl */`
uniform highp sampler3D uGIUp, uGIDown;
uniform vec3 uGIMin, uGIMax;
uniform float uGIScale;
varying vec3 vGIW;
vec3 gi_dyn(vec3 nW){
  vec3 q = clamp((vGIW - uGIMin)/(uGIMax - uGIMin), 0.0, 1.0);
  vec3 u = texture(uGIUp, q).rgb, d = texture(uGIDown, q).rgb;
  float k = nW.y*0.5 + 0.5;
  return mix(d, u, k)*uGIScale;
}`;
export function gi_dynamic(mat, U) {
  const prev = mat.onBeforeCompile;
  mat.onBeforeCompile = (sh, r) => {
    if (prev) prev(sh, r);
    Object.assign(sh.uniforms, { uGIUp: U.uGIUp, uGIDown: U.uGIDown, uGIMin: U.uGIMin, uGIMax: U.uGIMax, uGIScale: U.uGIScale });
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vGIW;')
      .replace('#include <project_vertex>', '#include <project_vertex>\n  {\n    vec4 gw = vec4(transformed, 1.0);\n    #ifdef USE_INSTANCING\n      gw = instanceMatrix*gw;\n    #endif\n    vGIW = (modelMatrix*gw).xyz;\n  }');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', '#include <common>\n' + GI_DYN_DECL)
      .replace('#include <lights_fragment_end>', '#include <lights_fragment_end>\n  {\n    vec3 nW = normalize((vec4(normal, 0.0)*viewMatrix).xyz);\n    reflectedLight.indirectDiffuse += gi_dyn(nW)*BRDF_Lambert(diffuseColor.rgb);\n  }');
  };
  const key = mat.customProgramCacheKey ? mat.customProgramCacheKey.bind(mat) : () => '';
  mat.customProgramCacheKey = () => key() + '|gi_dyn';
  return mat;
}

export function gi_uniforms() {
  const black = new THREE.Data3DTexture(new Float32Array(4), 1, 1, 1);
  black.type = THREE.FloatType; black.needsUpdate = true;
  return {
    uGIScale: { value: 1 }, uGIUp: { value: black }, uGIDown: { value: black },
    uGIMin: { value: new THREE.Vector3(-1, -1, -1) }, uGIMax: { value: new THREE.Vector3(1, 1, 1) },
  };
}

// ---------------------------------------------------------------- storing a bake
const f16 = new Float32Array(1), u32 = new Uint32Array(f16.buffer);
function to_half(v) {
  f16[0] = v; const x = u32[0];
  const sign = (x >>> 16) & 0x8000; let e = ((x >>> 23) & 0xff) - 127 + 15; let m = (x >>> 13) & 0x3ff;
  if (e <= 0) return sign; if (e >= 31) return sign | 0x7bff;
  return sign | (e << 10) | m;
}
function from_half(h) {
  const s = (h & 0x8000) ? -1 : 1, e = (h >>> 10) & 0x1f, m = h & 0x3ff;
  if (e === 0) return s*m*5.960464477539063e-8;
  return s*(1 + m/1024)*Math.pow(2, e - 15);
}
function b64(u8) { let s = ''; for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000)); return btoa(s); }
function unb64(str) { const s = atob(str); const u8 = new Uint8Array(s.length); for (let i = 0; i < s.length; i++) u8[i] = s.charCodeAt(i); return u8; }
const pack = f => { const h = new Uint16Array(f.length); for (let i = 0; i < f.length; i++) h[i] = to_half(f[i]); return b64(new Uint8Array(h.buffer)); };
const unpack = str => { const u8 = unb64(str); const h = new Uint16Array(u8.buffer, u8.byteOffset, u8.length/2); const f = new Float32Array(h.length); for (let i = 0; i < h.length; i++) f[i] = from_half(h[i]); return f; };
export function export_gi(data) { return { key: data.key, Ei: pack(data.Ei), up: pack(data.up), dn: pack(data.dn) }; }
export function import_gi(j) { return j && j.key ? { key: j.key, Ei: unpack(j.Ei), up: unpack(j.up), dn: unpack(j.dn) } : null; }
