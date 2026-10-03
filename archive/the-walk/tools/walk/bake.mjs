// bake.mjs -- the walk's bounce light, baked once: web/src/gi.js's method (every triangle
// gathers over its hemisphere against a BVH of everything; three bounces; a denoise; per-vertex
// values; probe grids for things that move) with what the walk adds to the final room's light:
// several openings to the sky (one per shaft, each with its dusty column), and surfaces that
// glow (lava, fungi, the glow-worms' ceiling, the burning point under the lens). A ray that hits
// a glowing surface gathers its radiance. Direct sunlight is not baked (the real light and its
// shadow map draw it); everything else is.
import { make_rng } from './lib.mjs';

function build_bvh(P) {
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
  const nb = [], nc = [];
  const LEAF = 4;
  const C = [cx, cy, cz];
  // iterative build (deep trees overflow the JS stack)
  const stack = [[0, N, -1, 0]];
  while (stack.length) {
    const [first, count, parent, side] = stack.pop();
    const ni = nc.length/2;
    if (parent >= 0 && side === 1) nc[parent*2] = ni;
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
    if (count <= LEAF) { nc[ni*2] = first; nc[ni*2 + 1] = count; continue; }
    const ex = c1x - c0x, ey = c1y - c0y, ez = c1z - c0z;
    const ax = ex >= ey && ex >= ez ? 0 : ey >= ez ? 1 : 2;
    const mid = ax === 0 ? (c0x + c1x)/2 : ax === 1 ? (c0y + c1y)/2 : (c0z + c1z)/2;
    const A = C[ax];
    let i = first, j = first + count - 1;
    while (i <= j) { if (A[idx[i]] < mid) i++; else { const t = idx[i]; idx[i] = idx[j]; idx[j] = t; j--; } }
    let nl = i - first;
    if (nl === 0 || nl === count) nl = count >> 1;
    nc[ni*2 + 1] = 0;
    // right first on the stack so the left child is built next (it is ni + 1)
    stack.push([first + nl, count - nl, ni, 1]);
    stack.push([first, nl, ni, 0]);
  }
  const T = new Float32Array(P.length);
  for (let i = 0; i < N; i++) T.set(P.subarray(idx[i]*9, idx[i]*9 + 9), i*9);
  return { T, idx, box: new Float32Array(nb), node: new Int32Array(nc), N };
}

const EPS = 1e-7;
const STACK = new Int32Array(256);
export function intersect(B, ox, oy, oz, dx, dy, dz, tmax, out, any = false) {
  const { T, box, node } = B;
  const ix = 1/dx, iy = 1/dy, iz = 1/dz;
  const stack = STACK;
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
      stack[sp++] = node[n*2];
      stack[sp++] = n + 1;
    }
  }
  if (out) { out.tri = hit; out.u = hu; out.v = hv; }
  return hit < 0 ? Infinity : best;
}

export function make_bvh(soups) {
  let n = 0;
  for (const s of soups) n += s.length;
  const P = new Float32Array(n);
  let o = 0;
  for (const s of soups) { P.set(s, o); o += s.length; }
  return build_bvh(P);
}

// recs: [{ T (soup), albedo: [r,g,b] linear, emit: [r,g,b] | null, receive: bool }]
// opts: sun_dir (to the sun), sun_E [r,g,b], skies [{ y, cx, cz, r, L }], beams [{ x, z, y0, r, h, L }],
//   rays, bounces, seed, denoise, grids [{ min, max, n, rays }], log
export function bake(recs, opts) {
  const log = opts.log || (() => {});
  const rng = make_rng(opts.seed || 3);
  const L = opts.sun_dir;
  let total = 0;
  for (const r of recs) total += r.T.length;
  const P = new Float32Array(total);
  let o = 0;
  for (const r of recs) { r.base = o/9; r.tris = r.T.length/9; P.set(r.T, o); o += r.T.length; }
  const N = total/9;
  const t0 = Date.now();
  const B = build_bvh(P);
  log(`  bvh: ${N} triangles (${((Date.now() - t0)/1000).toFixed(1)} s)`);
  const nrm = new Float32Array(N*3), cen = new Float32Array(N*3), area = new Float32Array(N), alb = new Float32Array(N*3), emi = new Float32Array(N*3);
  const recv = new Uint8Array(N);
  for (const r of recs) for (let t = 0; t < r.tris; t++) {
    const i = r.base + t, q = i*9;
    const e1x = P[q + 3] - P[q], e1y = P[q + 4] - P[q + 1], e1z = P[q + 5] - P[q + 2];
    const e2x = P[q + 6] - P[q], e2y = P[q + 7] - P[q + 1], e2z = P[q + 8] - P[q + 2];
    const nx = e1y*e2z - e1z*e2y, ny = e1z*e2x - e1x*e2z, nz = e1x*e2y - e1y*e2x;
    const l = Math.hypot(nx, ny, nz) || 1;
    area[i] = l/2;
    nrm[i*3] = nx/l; nrm[i*3 + 1] = ny/l; nrm[i*3 + 2] = nz/l;
    cen[i*3] = (P[q] + P[q + 3] + P[q + 6])/3; cen[i*3 + 1] = (P[q + 1] + P[q + 4] + P[q + 7])/3; cen[i*3 + 2] = (P[q + 2] + P[q + 5] + P[q + 8])/3;
    if (r.albedo) { alb[i*3] = r.albedo[0]; alb[i*3 + 1] = r.albedo[1]; alb[i*3 + 2] = r.albedo[2]; }
    if (r.emit) { emi[i*3] = r.emit[0]; emi[i*3 + 1] = r.emit[1]; emi[i*3 + 2] = r.emit[2]; }
    recv[i] = r.receive ? 1 : 0;
  }
  const orig = B.idx;
  const Ed = new Float32Array(N*3);
  const sun_E = opts.sun_E;
  for (let i = 0; i < N; i++) {
    if (!recv[i]) continue;
    const nx = nrm[i*3], ny = nrm[i*3 + 1], nz = nrm[i*3 + 2];
    const d = nx*L[0] + ny*L[1] + nz*L[2];
    if (d <= 0) continue;
    const x = cen[i*3] + nx*0.02, y = cen[i*3 + 1] + ny*0.02, z = cen[i*3 + 2] + nz*0.02;
    // (the rock surface is a shell: a face buried in the rock behind it would see the sky)
    if (opts.air && !opts.air(x + nx*0.05, y + ny*0.05, z + nz*0.05)) continue;
    if (intersect(B, x, y, z, L[0], L[1], L[2], 200, null, true) !== Infinity) continue;
    // and the rock itself (the field) along the way: a face poking through the shell sees nothing
    if (opts.air) {
      let blocked = false;
      for (let t = 0.6; t < 45 && !blocked; t += 0.4) if (!opts.air(x + L[0]*t, y + L[1]*t, z + L[2]*t)) blocked = true;
      if (blocked) continue;
    }
    Ed[i*3] = sun_E[0]*d; Ed[i*3 + 1] = sun_E[1]*d; Ed[i*3 + 2] = sun_E[2]*d;
  }
  {
    const lit = {};
    for (const r of recs) { if (!r.receive) continue; let n = 0; for (let t = 0; t < r.tris; t++) if (Ed[(r.base + t)*3] > 0) n++; if (n) lit[r.area + ':' + r.mat] = (lit[r.area + ':' + r.mat] || 0) + n; }
    log(`  direct sun (${((Date.now() - t0)/1000).toFixed(1)} s): sunlit triangles ${JSON.stringify(lit)}`);
    if (opts.debug_sun !== undefined && opts.field) {
      let shown = 0;
      for (const r of recs) {
        if (!r.receive || r.area !== opts.debug_sun || shown > 6) continue;
        for (let t = 0; t < r.tris && shown < 6; t++) {
          const i = r.base + t;
          if (!(Ed[i*3] > 0)) continue;
          const x = cen[i*3], y = cen[i*3 + 1], z = cen[i*3 + 2];
          if (!(opts.field(x + nrm[i*3]*0.15, y + nrm[i*3 + 1]*0.15, z + nrm[i*3 + 2]*0.15) < 0)) continue;
          // walk the ray: where is it in rock (field > 0) without a triangle in the way?
          let inrock = null;
          for (let d = 0.3; d < 60; d += 0.3) { const f = opts.field(x + L[0]*d, y + L[1]*d, z + L[2]*d); if (f > 0.2) { inrock = [d.toFixed(1), (x + L[0]*d).toFixed(1), (y + L[1]*d).toFixed(1), (z + L[2]*d).toFixed(1), f.toFixed(2)]; break; } }
          log(`    sunlit ${r.mat} at ${x.toFixed(1)},${y.toFixed(1)},${z.toFixed(1)} n ${nrm[i*3].toFixed(2)},${nrm[i*3+1].toFixed(2)},${nrm[i*3+2].toFixed(2)}: ray enters rock at ${inrock}`);
          shown++;
        }
      }
    }
  }
  const skies = opts.skies || [], beams = opts.beams || [];
  const ba = L;
  function beam_light(x, y, z, dx, dy, dz, tmax, acc) {
    for (const bm of beams) {
      // the column's axis passes (bm.x, bm.y0, bm.z) along the sun's direction
      const wx = x - bm.x, wy = y - bm.y0, wz = z - bm.z;
      const wa = wx*ba[0] + wy*ba[1] + wz*ba[2], da = dx*ba[0] + dy*ba[1] + dz*ba[2];
      const px = wx - ba[0]*wa, py = wy - ba[1]*wa, pz = wz - ba[2]*wa;
      const qx = dx - ba[0]*da, qy = dy - ba[1]*da, qz = dz - ba[2]*da;
      const A = qx*qx + qy*qy + qz*qz, Bq = px*qx + py*qy + pz*qz, C = px*px + py*py + pz*pz - bm.r*bm.r;
      let ch = 0;
      if (A < 1e-9) ch = C < 0 ? Math.min(tmax, bm.h) : 0;
      else {
        const disc = Bq*Bq - A*C;
        if (disc > 0) {
          const sq = Math.sqrt(disc);
          const a0 = Math.max(0, (-Bq - sq)/A), a1 = Math.min(tmax, (-Bq + sq)/A);
          if (a1 > a0) {
            // only the part of the chord above the floor and below the opening
            const ya = y + dy*a0, yb = y + dy*a1;
            if (Math.max(ya, yb) > bm.y0 && Math.min(ya, yb) < bm.y0 + bm.h) ch = a1 - a0;
          }
        }
      }
      if (ch > 0) { acc[0] += Math.PI*bm.L[0]*ch; acc[1] += Math.PI*bm.L[1]*ch; acc[2] += Math.PI*bm.L[2]*ch; }
    }
  }
  const tangent = (nx, ny, nz) => {
    const ax = Math.abs(nx) < 0.9 ? 1 : 0, ay = ax ? 0 : 1;
    let tx = ay*nz, ty = -ax*nz, tz = ax*ny - ay*nx;
    const l = Math.hypot(tx, ty, tz) || 1;
    return [tx/l, ty/l, tz/l];
  };
  const Ei = new Float32Array(N*3), Enext = new Float32Array(N*3);
  const hit = { tri: -1, u: 0, v: 0 };
  const acc = [0, 0, 0];
  function gather(x, y, z, nx, ny, nz, out, rays) {
    const [tx, ty, tz] = tangent(nx, ny, nz);
    const bx = ny*tz - nz*ty, by = nz*tx - nx*tz, bz = nx*ty - ny*tx;
    acc[0] = 0; acc[1] = 0; acc[2] = 0;
    for (let k = 0; k < rays; k++) {
      const u1 = rng.next(), u2 = (k + rng.next())/rays;
      const rr = Math.sqrt(u1), phi = 6.2831853*u2;
      const lx = rr*Math.cos(phi), ly = rr*Math.sin(phi), lz = Math.sqrt(Math.max(0, 1 - u1));
      const dx = tx*lx + bx*ly + nx*lz, dy = ty*lx + by*ly + ny*lz, dz = tz*lx + bz*ly + nz*lz;
      const t = intersect(B, x, y, z, dx, dy, dz, 300, hit);
      if (beams.length) beam_light(x, y, z, dx, dy, dz, t === Infinity ? 60 : t, acc);
      if (t === Infinity) {
        if (dy > 0.05) for (const sk of skies) {
          const s = (sk.y - y)/dy;
          const px = x + dx*s - sk.cx, pz = z + dz*s - sk.cz;
          if (s > 0 && px*px + pz*pz < sk.r*sk.r) { acc[0] += Math.PI*sk.L[0]; acc[1] += Math.PI*sk.L[1]; acc[2] += Math.PI*sk.L[2]; break; }
        }
        continue;
      }
      const j = orig[hit.tri];
      acc[0] += Math.PI*emi[j*3]; acc[1] += Math.PI*emi[j*3 + 1]; acc[2] += Math.PI*emi[j*3 + 2];
      if (!recv[j]) continue;
      acc[0] += alb[j*3]*(Ed[j*3] + Ei[j*3]);
      acc[1] += alb[j*3 + 1]*(Ed[j*3 + 1] + Ei[j*3 + 1]);
      acc[2] += alb[j*3 + 2]*(Ed[j*3 + 2] + Ei[j*3 + 2]);
    }
    out[0] = acc[0]/rays; out[1] = acc[1]/rays; out[2] = acc[2]/rays;
  }
  const K = opts.rays || 48, bounces = opts.bounces || 3;
  const tmp = [0, 0, 0];
  for (let bounce = 0; bounce < bounces; bounce++) {
    for (let i = 0; i < N; i++) {
      if (!recv[i]) continue;
      const nx = nrm[i*3], ny = nrm[i*3 + 1], nz = nrm[i*3 + 2];
      gather(cen[i*3] + nx*0.02, cen[i*3 + 1] + ny*0.02, cen[i*3 + 2] + nz*0.02, nx, ny, nz, tmp, K);
      Enext[i*3] = tmp[0]; Enext[i*3 + 1] = tmp[1]; Enext[i*3 + 2] = tmp[2];
      if ((i & 32767) === 0) log(`  bounce ${bounce + 1}/${bounces}: ${(100*i/N).toFixed(0)}% (${((Date.now() - t0)/1000).toFixed(0)} s)`);
    }
    Ei.set(Enext);
  }
  // denoise: average with neighbours within Rd, by area, normal likeness and distance
  if (opts.denoise) {
    const Rd = opts.denoise, cell = Rd;
    const grid = new Map();
    const ck = (gx, gy, gz) => (gx + 4096)*67108864 + (gy + 4096)*8192 + (gz + 4096);
    for (let i = 0; i < N; i++) {
      if (!recv[i]) continue;
      const k = ck(Math.floor(cen[i*3]/cell), Math.floor(cen[i*3 + 1]/cell), Math.floor(cen[i*3 + 2]/cell));
      let a = grid.get(k); if (!a) { a = []; grid.set(k, a); } a.push(i);
    }
    const out = new Float32Array(N*3);
    for (let i = 0; i < N; i++) {
      if (!recv[i]) continue;
      const x = cen[i*3], y = cen[i*3 + 1], z = cen[i*3 + 2];
      const gx = Math.floor(x/cell), gy = Math.floor(y/cell), gz = Math.floor(z/cell);
      let wr = 0, wg = 0, wb = 0, W = 0;
      for (let dz = -1; dz <= 1; dz++) for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const a = grid.get(ck(gx + dx, gy + dy, gz + dz));
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
  // per vertex: area-weighted over triangles sharing the position, by normal likeness
  const pk = (x, y, z) => `${Math.round(x*200)},${Math.round(y*200)},${Math.round(z*200)}`;
  const accm = new Map();
  for (const r of recs) {
    if (!r.receive) continue;
    for (let t = 0; t < r.tris; t++) {
      const i = r.base + t, q = i*9;
      for (let k = 0; k < 3; k++) {
        const kk = pk(P[q + k*3], P[q + k*3 + 1], P[q + k*3 + 2]);
        let a = accm.get(kk); if (!a) { a = []; accm.set(kk, a); } a.push(i);
      }
    }
  }
  for (const r of recs) {
    if (!r.receive) continue;
    const gi = new Float32Array(r.tris*9);
    for (let t = 0; t < r.tris; t++) {
      const i = r.base + t, q = i*9;
      const nx = nrm[i*3], ny = nrm[i*3 + 1], nz = nrm[i*3 + 2];
      for (let k = 0; k < 3; k++) {
        const list = accm.get(pk(P[q + k*3], P[q + k*3 + 1], P[q + k*3 + 2]));
        let wr = 0, wg = 0, wb = 0, W = 0;
        for (const j of list) {
          const dt = nx*nrm[j*3] + ny*nrm[j*3 + 1] + nz*nrm[j*3 + 2];
          const w = area[j]*Math.max(0.05, dt) + (j === i ? area[j] : 0);
          wr += Ei[j*3]*w; wg += Ei[j*3 + 1]*w; wb += Ei[j*3 + 2]*w; W += w;
        }
        gi[t*9 + k*3] = wr/W; gi[t*9 + k*3 + 1] = wg/W; gi[t*9 + k*3 + 2] = wb/W;
      }
    }
    r.gi = gi;
  }
  // probe grids for things that move: irradiance on an up- and a down-facing surface
  const grids = [];
  for (const G of opts.grids || []) {
    const [nx_, ny_, nz_] = G.n;
    const up = new Float32Array(nx_*ny_*nz_*4), dn = new Float32Array(nx_*ny_*nz_*4);
    for (let k = 0; k < nz_; k++) for (let j = 0; j < ny_; j++) for (let i = 0; i < nx_; i++) {
      const x = G.min[0] + (G.max[0] - G.min[0])*i/(nx_ - 1);
      const y = G.min[1] + (G.max[1] - G.min[1])*j/(ny_ - 1);
      const z = G.min[2] + (G.max[2] - G.min[2])*k/(nz_ - 1);
      const q = ((k*ny_ + j)*nx_ + i)*4;
      gather(x, y, z, 0, 1, 0, tmp, G.rays || 48);
      up[q] = tmp[0]; up[q + 1] = tmp[1]; up[q + 2] = tmp[2]; up[q + 3] = 1;
      gather(x, y, z, 0, -1, 0, tmp, G.rays || 48);
      dn[q] = tmp[0]; dn[q + 1] = tmp[1]; dn[q + 2] = tmp[2]; dn[q + 3] = 1;
    }
    grids.push({ up, dn });
  }
  log(`  bake done (${((Date.now() - t0)/1000).toFixed(1)} s)`);
  return { N, grids, B };
}
