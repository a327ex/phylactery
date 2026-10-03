// lib.mjs -- small shared helpers for the walk builder: the cave's value noise (the same bits as
// web/src/cave.js, so the walk's floor meets the final room's tunnel floor exactly), a seeded rng
// (util.js make_rng's shape), and vector helpers.

export const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
export const lerp = (a, b, t) => a + (b - a)*t;
export const smoothstep = (a, b, x) => { const t = clamp((x - a)/(b - a), 0, 1); return t*t*(3 - 2*t); };

export function h3(ix, iy, iz, seed) {
  let h = Math.imul(ix | 0, 374761393) ^ Math.imul(iy | 0, 668265263) ^ Math.imul(iz | 0, 2147483647) ^ Math.imul(seed | 0, 1442695041);
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0)/4294967296;
}
export function noise3(x, y, z, seed = 0) {
  const ix = Math.floor(x), iy = Math.floor(y), iz = Math.floor(z);
  const fx = x - ix, fy = y - iy, fz = z - iz;
  const u = fx*fx*(3 - 2*fx), v = fy*fy*(3 - 2*fy), w = fz*fz*(3 - 2*fz);
  const L = (a, b, t) => a + (b - a)*t;
  const c = (dx, dy, dz) => h3(ix + dx, iy + dy, iz + dz, seed);
  return L(L(L(c(0, 0, 0), c(1, 0, 0), u), L(c(0, 1, 0), c(1, 1, 0), u), v),
           L(L(c(0, 0, 1), c(1, 0, 1), u), L(c(0, 1, 1), c(1, 1, 1), u), v), w);
}
export const fbm3 = (x, y, z, seed, oct = 3) => {
  let s = 0, a = 1, t = 0, f = 1;
  for (let o = 0; o < oct; o++) { s += a*noise3(x*f, y*f, z*f, seed + o*31); t += a; a *= 0.5; f *= 2.03; }
  return s/t;
};

// the final room's floor (cave.js ground_y), for the seam where the walk meets its tunnel
export function room_ground_y(x, z) {
  const r2 = x*x + z*z, r = Math.sqrt(r2);
  let y = (fbm3(x*0.21, 0, z*0.21, 91) - 0.5)*0.7 + (noise3(x*0.9, 7.1, z*0.9, 93) - 0.5)*0.14;
  const rid = 1 - Math.abs(fbm3(x*0.13, 3.3, z*0.13, 97, 2)*2 - 1);
  y += Math.pow(rid, 6)*0.55*smoothstep(3.5, 7, r);
  y += 0.3*Math.exp(-r2/4.0);
  y += smoothstep(12.5, 17.5, r)*1.4;
  return y;
}

// util.js make_rng: mulberry32 with float / int / spread / chance helpers
export function make_rng(seed) {
  let a = seed >>> 0;
  const next = () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0)/4294967296;
  };
  return {
    next,
    float: (lo, hi) => lo + (hi - lo)*next(),
    int: (lo, hi) => lo + Math.floor(next()*(hi - lo + 1)),
    spread: (r) => (next()*2 - 1)*r,
    chance: (p) => next() < p,
    pick: (arr) => arr[Math.floor(next()*arr.length)],
  };
}

export const v3 = (x = 0, y = 0, z = 0) => ({ x, y, z });
export const len2 = (x, z) => Math.sqrt(x*x + z*z);
