// shape_noise.js -- round 29: noise for sculpting the objects (value noise, fbm, cellular
// cracks), deterministic by seed. Everything here runs once at build time, on the CPU.

function h3(ix, iy, iz, seed) {
  let h = Math.imul(ix | 0, 374761393) ^ Math.imul(iy | 0, 668265263) ^ Math.imul(iz | 0, 2147483647) ^ Math.imul(seed | 0, 1442695041);
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0)/4294967296;
}
export const hash3 = h3;

export function noise3(x, y, z, seed = 0) {
  const ix = Math.floor(x), iy = Math.floor(y), iz = Math.floor(z);
  const fx = x - ix, fy = y - iy, fz = z - iz;
  const u = fx*fx*(3 - 2*fx), v = fy*fy*(3 - 2*fy), w = fz*fz*(3 - 2*fz);
  const L = (a, b, t) => a + (b - a)*t;
  const c = (dx, dy, dz) => h3(ix + dx, iy + dy, iz + dz, seed);
  return L(L(L(c(0, 0, 0), c(1, 0, 0), u), L(c(0, 1, 0), c(1, 1, 0), u), v),
           L(L(c(0, 0, 1), c(1, 0, 1), u), L(c(0, 1, 1), c(1, 1, 1), u), v), w);
}

// fractal sum, 0..1 around 0.5
export function fbm3(x, y, z, seed = 0, oct = 4) {
  let s = 0, a = 1, t = 0, f = 1;
  for (let o = 0; o < oct; o++) { s += a*noise3(x*f, y*f, z*f, seed + o*31); t += a; a *= 0.5; f *= 2.03; }
  return s/t;
}

// 2D cells (jittered grid, cell size 1): the distance to the nearest cell's point (d1), to the
// second (d2), the edge distance ~ (d2 - d1)/2, and the nearest cell's id (0..1)
export function cells2(x, y, seed = 0) {
  const ix = Math.floor(x), iy = Math.floor(y);
  let d1 = 9, d2 = 9, id = 0;
  for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) {
    const cx = ix + i, cy = iy + j;
    const px = cx + 0.15 + 0.7*h3(cx, cy, 0, seed), py = cy + 0.15 + 0.7*h3(cx, cy, 1, seed);
    const d = Math.hypot(x - px, y - py);
    if (d < d1) { d2 = d1; d1 = d; id = h3(cx, cy, 2, seed); } else if (d < d2) d2 = d;
  }
  return { d1, d2, edge: (d2 - d1)*0.5, id };
}

// 3D cells, same idea (for a crack network on a curved solid)
export function cells3(x, y, z, seed = 0) {
  const ix = Math.floor(x), iy = Math.floor(y), iz = Math.floor(z);
  let d1 = 9, d2 = 9, id = 0;
  for (let k = -1; k <= 1; k++) for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) {
    const cx = ix + i, cy = iy + j, cz = iz + k;
    const px = cx + 0.1 + 0.8*h3(cx, cy, cz, seed), py = cy + 0.1 + 0.8*h3(cx, cy, cz, seed + 1), pz = cz + 0.1 + 0.8*h3(cx, cy, cz, seed + 2);
    const d = Math.hypot(x - px, y - py, z - pz);
    if (d < d1) { d2 = d1; d1 = d; id = h3(cx, cy, cz, seed + 3); } else if (d < d2) d2 = d;
  }
  return { d1, d2, edge: (d2 - d1)*0.5, id };
}

export const sstep = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a)/(b - a))); return t*t*(3 - 2*t); };

// a seeded random stream
export function rand(seed) {
  let s = seed >>> 0 || 1;
  const next = () => { s = (Math.imul(s ^ (s >>> 15), 2246822519) + 0x9e3779b9) >>> 0; s = (s ^ (s >>> 13)) >>> 0; return s/4294967296; };
  return { next, f: (a, b) => a + (b - a)*next(), s: (k) => (next()*2 - 1)*k };
}

// per-vertex colour, metalness and roughness on a standard material: attribute aMR (x = metal,
// y = rough) replaces the material's factors (vertex colours give the albedo)
export function vertex_mr(mat) {
  const prev = mat.onBeforeCompile;
  mat.onBeforeCompile = (sh, r) => {
    if (prev) prev(sh, r);
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nattribute vec2 aMR;\nvarying vec2 vMR;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\n  vMR = aMR;');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', '#include <common>\nvarying vec2 vMR;')
      .replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\n  roughnessFactor = vMR.y;')
      .replace('#include <metalnessmap_fragment>', '#include <metalnessmap_fragment>\n  metalnessFactor = vMR.x;');
  };
  const key = mat.customProgramCacheKey ? mat.customProgramCacheKey.bind(mat) : () => '';
  mat.customProgramCacheKey = () => key() + '|vmr';
  return mat;
}
