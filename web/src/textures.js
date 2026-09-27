// textures.js -- every texture is generated here (canvas), no files.
//
// TEXEL DENSITY RULE (Sun Court, retro-shooter/STYLE.md): world surfaces use 32 texels per metre,
// world-space UVs (cave.js projects every face onto its dominant axis), NearestMipmapNearest.
// Tones are quantized into a few flat steps so surfaces read as painted pixels, never noise.
//
// Palette: the It Follows egg cover (/artifacts, it-follows-3.jpg) -- near-black cool rock,
// brown-grey slabs whose edges catch warm bronze, a cream-yellow pool of light, a pale egg,
// dark bronze snakes.
import * as THREE from 'three';

export const TEXELS_PER_METER = 32;

export function finish(canvas, { srgb = true, repeat = true, mips = true } = {}) {
  const t = new THREE.CanvasTexture(canvas);
  t.magFilter = THREE.NearestFilter;
  t.minFilter = mips ? THREE.NearestMipmapNearestFilter : THREE.NearestFilter;
  t.generateMipmaps = mips;
  t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
  if (repeat) t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.anisotropy = 1;
  t.needsUpdate = true;
  return t;
}

function painter(w, h) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  const g = c.getContext('2d');
  const img = g.createImageData(w, h);
  const d = img.data;
  const cl = v => (v < 0 ? 0 : v > 255 ? 255 : v | 0);
  return {
    w, h,
    set(x, y, rgb) {
      x = ((x % w) + w) % w; y = ((y % h) + h) % h;
      const i = (y*w + x)*4;
      d[i] = cl(rgb[0]); d[i + 1] = cl(rgb[1]); d[i + 2] = cl(rgb[2]); d[i + 3] = 255;
    },
    get(x, y) {
      x = ((x % w) + w) % w; y = ((y % h) + h) % h;
      const i = (y*w + x)*4;
      return [d[i], d[i + 1], d[i + 2]];
    },
    done(opts) { g.putImageData(img, 0, 0); return finish(c, opts); },
  };
}

const mix = (a, b, t) => [a[0] + (b[0] - a[0])*t, a[1] + (b[1] - a[1])*t, a[2] + (b[2] - a[2])*t];
const mul = (a, k) => [a[0]*k, a[1]*k, a[2]*k];

function lattice_hash(ix, iy, seed) {
  let h = Math.imul(ix | 0, 374761393) ^ Math.imul(iy | 0, 668265263) ^ Math.imul(seed | 0, 1442695041);
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0)/4294967296;
}
function vnoise(x, y, px, py, seed) {
  const ix = Math.floor(x), iy = Math.floor(y), fx = x - ix, fy = y - iy;
  const u = fx*fx*(3 - 2*fx), v = fy*fy*(3 - 2*fy);
  const m = (a, p) => ((a % p) + p) % p;
  const a = lattice_hash(m(ix, px), m(iy, py), seed), b = lattice_hash(m(ix + 1, px), m(iy, py), seed);
  const c = lattice_hash(m(ix, px), m(iy + 1, py), seed), d = lattice_hash(m(ix + 1, px), m(iy + 1, py), seed);
  return (a + (b - a)*u) + ((c + (d - c)*u) - (a + (b - a)*u))*v;
}
// tileable fbm over a w x h texture; cells = lattice cells across the width at octave 0
function fbm(x, y, w, h, cells, seed, oct = 3) {
  let s = 0, amp = 1, tot = 0, f = 1;
  for (let o = 0; o < oct; o++) {
    const cx = cells*f, cy = Math.max(1, Math.round(cells*f*h/w));
    s += amp*vnoise(x/w*cx, y/h*cy, cx, cy, seed + o*101);
    tot += amp; amp *= 0.5; f *= 2;
  }
  return s/tot;
}
// tileable cellular (nearest point) noise: returns [d1, d2, cell id]
function cells2(x, y, w, h, n, seed) {
  const gx = x/w*n, gy = y/h*n;
  const ix = Math.floor(gx), iy = Math.floor(gy);
  let d1 = 9, d2 = 9, id = 0;
  for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) {
    const cx = ix + i, cy = iy + j;
    const wx = ((cx % n) + n) % n, wy = ((cy % n) + n) % n;
    const px = cx + lattice_hash(wx, wy, seed), py = cy + lattice_hash(wx, wy, seed + 7);
    const d = Math.hypot(gx - px, gy - py);
    if (d < d1) { d2 = d1; d1 = d; id = lattice_hash(wx, wy, seed + 13); } else if (d < d2) d2 = d;
  }
  return [d1, d2, id];
}

export const PAL = {
  rock_hi: [118, 102, 82], rock: [84, 74, 62], rock_mid: [66, 58, 50], rock_lo: [48, 43, 39], rock_deep: [34, 31, 30],
  bronze: [150, 112, 66],
  floor_hi: [132, 112, 84], floor: [96, 82, 64], floor_lo: [70, 60, 50], floor_deep: [50, 44, 38],
  egg_hi: [246, 238, 216], egg: [232, 220, 192], egg_lo: [206, 192, 162], egg_spot: [150, 128, 100],
  bone: [236, 228, 212],
  scale_hi: [104, 84, 56], scale: [62, 50, 36], scale_lo: [38, 31, 24], scale_belly: [120, 100, 70],
};

// Rock: broad chipped facets (cellular patches), each a flat tone, a pale chip edge where two
// patches meet on the lit side -- the cover's palette-knife slabs, at 32 texels/m.
export function rock(seed = 11, S = 64) {
  const P = painter(S, S);
  const tones = [PAL.rock_deep, PAL.rock_lo, PAL.rock_mid, PAL.rock, PAL.rock_hi];
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const [d1, d2, id] = cells2(x + 0.5, y + 0.5, S, S, 5, seed);
    const n = fbm(x, y, S, S, 4, seed + 3, 2);
    let k = Math.floor(id*3.2 + n*1.6);               // 0..4 flat tone per patch
    k = Math.max(0, Math.min(4, k));
    let c = tones[k];
    const edge = d2 - d1;
    if (edge < 0.07) c = tones[Math.max(0, k - 2)];    // dark crack between facets
    else if (edge < 0.13 && ((x + y) & 1) === 0 && id > 0.55) c = mix(tones[Math.min(4, k + 1)], PAL.bronze, 0.25);
    P.set(x, y, c);
  }
  return P.done();
}

// Floor: packed grit and flat stones, darker, one or two tones per stone, gritty speckle.
export function floor(seed = 21, S = 64) {
  const P = painter(S, S);
  const tones = [PAL.floor_deep, PAL.floor_lo, PAL.floor, PAL.floor_hi];
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const [d1, d2, id] = cells2(x + 0.5, y + 0.5, S, S, 8, seed);
    const n = fbm(x, y, S, S, 6, seed + 5, 3);
    let k = Math.floor(n*2.4 + id*1.4);
    k = Math.max(0, Math.min(3, k));
    let c = tones[k];
    if (d2 - d1 < 0.08) c = PAL.floor_deep;
    const grit = lattice_hash(x, y, seed + 99);
    if (grit > 0.93) c = tones[Math.min(3, k + 1)];
    else if (grit < 0.06) c = PAL.floor_deep;
    P.set(x, y, c);
  }
  return P.done();
}

// Egg shell: pale cream, a few sparse brown speckles, slightly cooler toward one pole.
export function egg_shell(seed = 31, S = 64) {
  const P = painter(S, S);
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const n = fbm(x, y, S, S, 4, seed, 2);
    let c = n > 0.62 ? PAL.egg_hi : n < 0.4 ? PAL.egg_lo : PAL.egg;
    const h = lattice_hash(x, y, seed + 17);
    if (h > 0.985) c = PAL.egg_spot;
    else if (h > 0.97) c = mix(PAL.egg_lo, PAL.egg_spot, 0.4);
    P.set(x, y, c);
  }
  return P.done({ repeat: true });
}

// Snake: overlapping diamond scales along the body (u = around, v = along), a paler belly band,
// dark seams. The texture wraps around one body segment.
export function scales(seed = 41, W = 32, H = 16) {
  const P = painter(W, H);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const u = x/W, v = y/H;
    const sx = (x + (Math.floor(y/4) % 2)*2) % 4, sy = y % 4;
    const dia = Math.abs(sx - 1.5) + Math.abs(sy - 1.5);
    let c = dia < 1.2 ? PAL.scale_hi : dia < 2.2 ? PAL.scale : PAL.scale_lo;
    const belly = Math.abs(u - 0.75) < 0.12;
    if (belly) c = (y % 3 === 0) ? PAL.scale_lo : PAL.scale_belly;
    if (lattice_hash(x, y, seed) > 0.9 && !belly) c = mul(c, 0.8);
    P.set(x, y, c);
  }
  return P.done();
}
