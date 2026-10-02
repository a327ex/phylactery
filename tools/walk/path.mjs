// path.mjs -- the walk's centre line: a Catmull-Rom spline through layout.NODES, sampled every
// STEP metres by arc length (s), each sample carrying the floor height, half width, ceiling and
// area its nodes give it; a spatial hash answers "which samples are near (x, z)".
import { NODES, AREAS } from './layout.mjs';
import { room_ground_y, lerp } from './lib.mjs';

export const STEP = 0.25;

function catmull(p0, p1, p2, p3, t) {
  const t2 = t*t, t3 = t2*t;
  return 0.5*((2*p1) + (-p0 + p2)*t + (2*p0 - 5*p1 + 4*p2 - p3)*t2 + (-p0 + 3*p1 - 3*p2 + p3)*t3);
}

export function build_path() {
  const N = NODES.map(n => ({ x: n[0], z: n[1], h: n[2] == null ? room_ground_y(n[0], n[1]) : n[2], w: n[3], H: n[4], area: n[5] }));
  // dense polyline first (fine parameter steps), then resample by arc length
  const dense = [];
  for (let i = 0; i < N.length - 1; i++) {
    const p0 = N[Math.max(0, i - 1)], p1 = N[i], p2 = N[i + 1], p3 = N[Math.min(N.length - 1, i + 2)];
    const K = 80;
    for (let k = 0; k < K; k++) {
      const t = k/K;
      dense.push({
        x: catmull(p0.x, p1.x, p2.x, p3.x, t), z: catmull(p0.z, p1.z, p2.z, p3.z, t),
        h: lerp(p1.h, p2.h, t*t*(3 - 2*t)), w: lerp(p1.w, p2.w, t), H: lerp(p1.H, p2.H, t),
        area: p1.area === p2.area ? p1.area : (t < 0.5 ? p1.area : p2.area), node: i + t,
      });
    }
  }
  const last = N[N.length - 1];
  dense.push({ x: last.x, z: last.z, h: last.h, w: last.w, H: last.H, area: last.area, node: N.length - 1 });
  // arc length
  let acc = 0;
  dense[0].s = 0;
  for (let i = 1; i < dense.length; i++) { acc += Math.hypot(dense[i].x - dense[i - 1].x, dense[i].z - dense[i - 1].z); dense[i].s = acc; }
  const total = acc;
  const S = [];
  let j = 0;
  for (let s = 0; s <= total + 1e-6; s += STEP) {
    while (j < dense.length - 2 && dense[j + 1].s < s) j++;
    const a = dense[j], b = dense[j + 1];
    const t = b.s > a.s ? (s - a.s)/(b.s - a.s) : 0;
    S.push({ s, x: lerp(a.x, b.x, t), z: lerp(a.z, b.z, t), h: lerp(a.h, b.h, t), w: lerp(a.w, b.w, t), H: lerp(a.H, b.H, t),
      area: t < 0.5 ? a.area : b.area, node: lerp(a.node, b.node, t) });
  }
  // tangents
  for (let i = 0; i < S.length; i++) {
    const a = S[Math.max(0, i - 2)], b = S[Math.min(S.length - 1, i + 2)];
    const l = Math.hypot(b.x - a.x, b.z - a.z) || 1;
    S[i].tx = (b.x - a.x)/l; S[i].tz = (b.z - a.z)/l;
  }
  // spatial hash
  const B = 4;
  const hash = new Map();
  const key = (i, j) => i*100003 + j;
  for (let i = 0; i < S.length; i++) {
    const k = key(Math.floor(S[i].x/B), Math.floor(S[i].z/B));
    let a = hash.get(k); if (!a) { a = []; hash.set(k, a); } a.push(i);
  }
  function near(x, z, R, out) {
    out.length = 0;
    const i0 = Math.floor((x - R)/B), i1 = Math.floor((x + R)/B), j0 = Math.floor((z - R)/B), j1 = Math.floor((z + R)/B);
    for (let i = i0; i <= i1; i++) for (let jj = j0; jj <= j1; jj++) {
      const a = hash.get(key(i, jj));
      if (a) for (const k of a) out.push(k);
    }
    return out;
  }
  const tmp = [];
  // nearest sample (index) and its horizontal distance
  function nearest(x, z, R = 24) {
    let best = -1, bd = Infinity;
    for (const k of near(x, z, R, tmp)) { const d = (S[k].x - x)**2 + (S[k].z - z)**2; if (d < bd) { bd = d; best = k; } }
    return best < 0 ? null : { i: best, d: Math.sqrt(bd), p: S[best] };
  }
  // the floor height the path gives (x, z): a Gaussian-weighted mean of nearby samples' h,
  // continuous where the nearest sample jumps (inside chambers, round bends)
  function path_h(x, z) {
    let W = 0, A = 0;
    for (const k of near(x, z, 9, tmp)) {
      const d2 = (S[k].x - x)**2 + (S[k].z - z)**2;
      if (d2 > 81) continue;
      const w = Math.exp(-d2/9);
      W += w; A += w*S[k].h;
    }
    if (W < 1e-9) { const n = nearest(x, z, 60); return n ? n.p.h : 0; }
    return A/W;
  }
  const areas_s = AREAS.map(() => ({ s0: Infinity, s1: -Infinity }));
  for (const p of S) { const a = areas_s[p.area]; a.s0 = Math.min(a.s0, p.s); a.s1 = Math.max(a.s1, p.s); }
  return { S, total, near, nearest, path_h, areas_s, nodes: N };
}
