// textures.mjs -- the walk's textures, painted the way web/src/textures.js paints the final room's:
// 64x64 tiles at 32 texels per metre on world-space UVs (2 m a tile), flat tones in a few steps
// so surfaces read as painted pixels, never noise. One rock and one floor texture per biome, plus
// the formations' own (bone, crystal, fungus, lava crust, glass). Rows are written bottom-up, as
// the three.js build's exporter wrote the room's (GL receives them that way).
import { h3 } from './lib.mjs';

const S = 64;
const cl = v => (v < 0 ? 0 : v > 255 ? 255 : v | 0);
function painter(w = S, h = S) {
  const d = new Uint8Array(w*h*4);
  return {
    w, h, d,
    set(x, y, rgb) { x = ((x % w) + w) % w; y = ((y % h) + h) % h; const i = (y*w + x)*4; d[i] = cl(rgb[0]); d[i + 1] = cl(rgb[1]); d[i + 2] = cl(rgb[2]); d[i + 3] = 255; },
    // rows bottom-up, as GL takes them
    bytes() { const out = new Uint8Array(d.length); for (let y = 0; y < h; y++) out.set(d.subarray(y*w*4, (y + 1)*w*4), (h - 1 - y)*w*4); return out; },
  };
}
const mix = (a, b, t) => [a[0] + (b[0] - a[0])*t, a[1] + (b[1] - a[1])*t, a[2] + (b[2] - a[2])*t];
const mul = (a, k) => [a[0]*k, a[1]*k, a[2]*k];
const lh = (ix, iy, seed) => h3(ix, iy, 0, seed);
function vnoise(x, y, px, py, seed) {
  const ix = Math.floor(x), iy = Math.floor(y), fx = x - ix, fy = y - iy;
  const u = fx*fx*(3 - 2*fx), v = fy*fy*(3 - 2*fy);
  const m = (a, p) => ((a % p) + p) % p;
  const a = lh(m(ix, px), m(iy, py), seed), b = lh(m(ix + 1, px), m(iy, py), seed);
  const c = lh(m(ix, px), m(iy + 1, py), seed), d = lh(m(ix + 1, px), m(iy + 1, py), seed);
  return (a + (b - a)*u) + ((c + (d - c)*u) - (a + (b - a)*u))*v;
}
// tileable fbm; cx, cy = lattice cells across at octave 0 (may differ: stretched noise)
function fbm(x, y, cx, cy, seed, oct = 3) {
  let s = 0, amp = 1, tot = 0, f = 1;
  for (let o = 0; o < oct; o++) {
    const gx = Math.max(1, Math.round(cx*f)), gy = Math.max(1, Math.round(cy*f));
    s += amp*vnoise(x/S*gx, y/S*gy, gx, gy, seed + o*101);
    tot += amp; amp *= 0.5; f *= 2;
  }
  return s/tot;
}
// tileable cellular noise: [d1, d2, id]
function cells2(x, y, n, seed, ny = n) {
  const gx = x/S*n, gy = y/S*ny;
  const ix = Math.floor(gx), iy = Math.floor(gy);
  let d1 = 9, d2 = 9, id = 0;
  for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) {
    const cx = ix + i, cy = iy + j;
    const wx = ((cx % n) + n) % n, wy = ((cy % ny) + ny) % ny;
    const px = cx + lh(wx, wy, seed), py = cy + lh(wx, wy, seed + 7);
    const d = Math.hypot(gx - px, gy - py);
    if (d < d1) { d2 = d1; d1 = d; id = lh(wx, wy, seed + 13); } else if (d < d2) d2 = d;
  }
  return [d1, d2, id];
}

// the final room's palette (web/src/textures.js PAL) and its rock/floor painters, as they are
const PAL = {
  rock_hi: [168, 150, 126], rock: [136, 121, 103], rock_mid: [114, 102, 89], rock_lo: [90, 81, 72], rock_deep: [64, 58, 53],
  bronze: [186, 146, 96],
  floor_hi: [164, 142, 110], floor: [132, 114, 90], floor_lo: [104, 90, 74], floor_deep: [76, 67, 57],
};
// facets: cellular patches, each a flat tone; dark cracks between them; a pale chip edge
function facets(tones, { seed, cells = 5, crack = 0.07, chip = 0.13, chip_col = null, chip_k = 0.25, spread = 3.2, nk = 1.6, cy = cells, soft = false } = {}) {
  const P = painter();
  const n = tones.length - 1;
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const [d1, d2, id] = cells2(x + 0.5, y + 0.5, cells, seed, cy);
    const nn = fbm(x, y, 4, 4, seed + 3, 2);
    let k = Math.max(0, Math.min(n, Math.floor(id*spread + nn*nk)));
    let c = tones[k];
    const edge = d2 - d1;
    if (edge < crack) c = tones[Math.max(0, k - (soft ? 1 : 2))];
    else if (edge < chip && ((x + y) & 1) === 0 && id > 0.55) c = chip_col ? mix(tones[Math.min(n, k + 1)], chip_col, chip_k) : tones[Math.min(n, k + 1)];
    P.set(x, y, c);
  }
  return P;
}
function grit(tones, deep, { seed, cells = 8, nk = 2.4, ik = 1.4, hi = 0.93, lo = 0.06, crack = 0.08 } = {}) {
  const P = painter();
  const n = tones.length - 1;
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const [d1, d2, id] = cells2(x + 0.5, y + 0.5, cells, seed);
    const nn = fbm(x, y, 6, 6, seed + 5, 3);
    let k = Math.max(0, Math.min(n, Math.floor(nn*nk + id*ik)));
    let c = tones[k];
    if (d2 - d1 < crack) c = deep;
    const g = lh(x, y, seed + 99);
    if (g > hi) c = tones[Math.min(n, k + 1)];
    else if (g < lo) c = deep;
    P.set(x, y, c);
  }
  return P;
}

export function make_textures() {
  const T = {};
  // ---- brown: the final room's own rock and floor (the waking chamber, the approach)
  T.brown_rock = facets([PAL.rock_deep, PAL.rock_lo, PAL.rock_mid, PAL.rock, PAL.rock_hi], { seed: 11, chip_col: PAL.bronze });
  T.brown_floor = grit([PAL.floor_deep, PAL.floor_lo, PAL.floor, PAL.floor_hi], PAL.floor_deep, { seed: 21 });

  // ---- basalt: blue-black, the columns' joints as dark vertical seams; ash underfoot
  {
    const tones = [[34, 34, 40], [46, 46, 54], [58, 57, 64], [72, 70, 76], [90, 86, 88]];
    const P = facets(tones, { seed: 111, cells: 4, cy: 7, crack: 0.05, chip: 0.09, chip_col: [150, 96, 70], chip_k: 0.15, spread: 3.0, nk: 1.4, soft: true });
    // joints: a dark seam every ~0.4 m, a little crooked
    for (let x0 = 0; x0 < S; x0 += 13) for (let y = 0; y < S; y++) {
      const x = x0 + Math.round((vnoise(0.5, y/16, 1, 4, 117 + x0) - 0.5)*3);
      P.set(x, y, tones[0]);
    }
    T.basalt_rock = P;
    T.basalt_floor = grit([[46, 44, 44], [72, 69, 66], [96, 92, 87], [118, 113, 106]], [30, 29, 30], { seed: 121, cells: 9, nk: 2.6, ik: 1.0, hi: 0.95, lo: 0.1 });
    T.lava_crust = grit([[30, 22, 20], [52, 34, 26], [80, 46, 30]], [20, 16, 16], { seed: 131, cells: 10, nk: 2.0, ik: 1.0 });
  }

  // ---- limestone: pale cream-grey, streaked downward where water ran; rimstone floor; bone
  {
    const tones = [[112, 106, 96], [138, 131, 118], [160, 152, 137], [180, 172, 156], [198, 190, 174]];
    const P = painter();
    for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
      const [d1, d2, id] = cells2(x + 0.5, y + 0.5, 4, 211, 3);
      const streak = fbm(x, y, 10, 1, 213, 2);                    // stretched along v: vertical drips
      let k = Math.max(0, Math.min(4, Math.floor(id*2.2 + streak*2.6)));
      let c = tones[k];
      if (d2 - d1 < 0.05) c = tones[Math.max(0, k - 2)];
      if (lh(x, y, 215) > 0.96) c = tones[Math.min(4, k + 1)];
      P.set(x, y, c);
    }
    T.limestone_rock = P;
    const F = painter();
    for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
      const [d1, d2] = cells2(x + 0.5, y + 0.5, 5, 221);
      const nn = fbm(x, y, 6, 6, 223, 3);
      let c = nn > 0.6 ? tones[4] : nn > 0.42 ? tones[3] : tones[2];
      const e = d2 - d1;
      if (e < 0.05) c = tones[1];                                  // rimstone lips
      else if (e < 0.09) c = tones[4];
      if (lh(x, y, 225) < 0.04) c = tones[1];
      F.set(x, y, c);
    }
    T.limestone_floor = F;
    const B = painter();
    for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
      const nn = fbm(x, y, 8, 8, 231, 2);
      let c = nn > 0.6 ? [230, 222, 204] : nn > 0.4 ? [212, 202, 182] : [190, 178, 156];
      if (lh(x, y, 233) > 0.97) c = [140, 126, 104];
      B.set(x, y, c);
    }
    T.bone = B;
  }

  // ---- iron: rust and ochre, dark hematite; red dust underfoot
  {
    const tones = [[78, 52, 46], [96, 60, 46], [112, 68, 48], [128, 78, 52], [146, 94, 60]];
    T.iron_rock = facets(tones, { seed: 311, cells: 7, crack: 0.05, chip: 0.09, chip_col: [186, 140, 92], chip_k: 0.2, spread: 2.6, nk: 1.6, soft: true });
    T.iron_floor = grit([[62, 40, 34], [86, 56, 44], [106, 70, 52], [128, 86, 62]], [44, 30, 28], { seed: 321 });
    T.lodestone_dark = grit([[40, 38, 42], [56, 52, 56], [70, 64, 66]], [28, 26, 30], { seed: 331, cells: 7 });
  }

  // ---- warped: slick green-grey rock, darker veins swirling, pale lichen; black mud
  {
    const tones = [[46, 54, 50], [60, 70, 63], [76, 86, 76], [94, 104, 90], [118, 126, 104]];
    const P = painter();
    for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
      const wx = x + (fbm(x, y, 3, 3, 401, 2) - 0.5)*30, wy = y + (fbm(x, y, 3, 3, 403, 2) - 0.5)*30;
      const b = fbm(wx, wy, 4, 4, 405, 3);
      let k = Math.max(0, Math.min(4, Math.floor(b*5.2 - 0.6)));
      let c = tones[k];
      const v = Math.abs(Math.sin(b*28));
      if (v < 0.12) c = tones[0];
      if (lh(x, y, 407) > 0.975) c = [168, 170, 140];
      P.set(x, y, c);
    }
    T.warped_rock = P;
    T.warped_floor = grit([[34, 38, 34], [48, 54, 46], [62, 68, 56], [78, 84, 68]], [24, 28, 26], { seed: 421 });
    T.fungus = grit([[176, 186, 170], [200, 208, 190], [222, 228, 210]], [140, 150, 136], { seed: 431, cells: 6, nk: 1.6, ik: 1.0 });
    T.water = grit([[8, 12, 14], [12, 16, 18], [16, 22, 24]], [6, 8, 10], { seed: 441, cells: 4, nk: 1.2, ik: 0.6 });
  }

  // ---- crystal: cool grey host rock veined white; grey grit with shards; the crystals
  {
    const tones = [[78, 82, 92], [98, 102, 112], [118, 122, 132], [138, 142, 152], [160, 164, 174]];
    const P = facets(tones, { seed: 511, cells: 5, crack: 0.045, chip: 0.08, chip_col: [220, 226, 236], chip_k: 0.3, spread: 3.0, nk: 1.6, soft: true });
    // quartz veins: thin white lines along a second cell pattern's edges
    for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
      const [d1, d2] = cells2(x + 0.5, y + 0.5, 3, 513);
      if (d2 - d1 < 0.025) P.set(x, y, [196, 202, 214]);
    }
    T.crystal_rock = P;
    T.crystal_floor = grit([[70, 74, 82], [92, 96, 104], [112, 116, 124], [132, 136, 144]], [52, 56, 64], { seed: 521, hi: 0.9 });
    const C = painter();
    for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
      const streak = fbm(x, y, 12, 1, 531, 2);
      let c = streak > 0.62 ? [178, 192, 210] : streak > 0.45 ? [150, 168, 192] : [126, 146, 176];
      if (lh(x, y, 533) > 0.985) c = [220, 230, 242];
      C.set(x, y, c);
    }
    T.crystal = C;
  }

  // ---- sandstone: strata in bands (v = height on walls), pitted; pale sand underfoot; the glass
  {
    const bands = [[176, 128, 84], [204, 168, 120], [188, 120, 92], [214, 186, 140], [160, 114, 78], [196, 150, 100]];
    const P = painter();
    for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
      const b = y/S*6 + (fbm(x, y, 4, 2, 611, 2) - 0.5)*0.9;
      const bi = ((Math.floor(b) % 6) + 6) % 6;
      let c = bands[bi];
      const fr = b - Math.floor(b);
      if (fr < 0.1) c = mul(c, 0.78);                                // a softer seam between beds
      const [d1, d2, id] = cells2(x + 0.5, y + 0.5, 7, 613);
      if (d2 - d1 < 0.06) c = mul(c, 0.85);
      else if (id > 0.8) c = mul(c, 1.07);
      if (lh(x, y, 615) < 0.03) c = mul(c, 0.7);
      P.set(x, y, c);
    }
    T.sand_rock = P;
    const F = painter();
    for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
      const r = Math.sin((x*0.35 + y*0.9) + fbm(x, y, 3, 3, 621, 2)*6);
      const nn = fbm(x, y, 6, 6, 623, 2);
      let c = r > 0.75 ? [222, 196, 152] : nn > 0.55 ? [208, 180, 136] : [192, 164, 122];
      if (lh(x, y, 625) < 0.05) c = [168, 140, 104];
      F.set(x, y, c);
    }
    T.sand_floor = F;
    T.glass = grit([[14, 12, 12], [24, 20, 18], [40, 34, 30]], [8, 8, 8], { seed: 631, cells: 6, hi: 0.97 });
  }
  const out = {};
  for (const k in T) out[k] = T[k].bytes();
  return out;
}

export const BIOMES = {
  brown: { rock: 'brown_rock', floor: 'brown_floor' },
  basalt: { rock: 'basalt_rock', floor: 'basalt_floor' },
  limestone: { rock: 'limestone_rock', floor: 'limestone_floor' },
  iron: { rock: 'iron_rock', floor: 'iron_floor' },
  warped: { rock: 'warped_rock', floor: 'warped_floor' },
  crystal: { rock: 'crystal_rock', floor: 'crystal_floor' },
  sandstone: { rock: 'sand_rock', floor: 'sand_floor' },
};
