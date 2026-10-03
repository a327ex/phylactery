// field.mjs -- the cave as a volume. f(x, y, z) < 0 is air: the union of the path's tube (an
// ellipse across it at every sample: half width w at the floor, the ceiling H above), the
// chambers (ellipsoids sitting on their floors), the shafts (columns leaning with the sun up to
// the sky), roughened by 3D noise, with a few biome-specific deformations. The rock surface is
// its zero set, meshed by surface nets on a 0.9 m grid (flat shaded: faceted rock, like the
// final room's lathes). The floor is a height field F(x, z) of its own, meshed where there is air
// above it.
import { CHAMBERS, SHAFTS, SUN_XZ } from './layout.mjs';
import { fbm3, noise3, h3, clamp, smoothstep, lerp, room_ground_y } from './lib.mjs';

export const GRID = { x0: -116, x1: 74, z0: -254, z1: -43, y0: -20, y1: 26, cell: 0.9 };
export const SEAM_Z = -47.3;          // nothing of the walk beyond this (the room's tunnel is there)

function smin(a, b, k) {
  const h = clamp(0.5 + 0.5*(b - a)/k, 0, 1);
  return lerp(b, a, h) - k*h*(1 - h);
}

export function make_field(P) {
  const S = P.S;
  const tmp = [];
  const CH = CHAMBERS.map(c => ({ ...c, cr: Math.cos(-c.rot), sr: Math.sin(-c.rot) }));
  const biome_of_area = a => P.biome_of_area(a);

  // how much a point is "in a chamber" (0..1), and which
  function chamber_q(x, z) {
    let best = Infinity, bc = null;
    for (const c of CH) {
      const dx = x - c.c[0], dz = z - c.c[1];
      const px = dx*c.cr - dz*c.sr, pz = dx*c.sr + dz*c.cr;
      const q = Math.sqrt((px/c.r[0])**2 + (pz/c.r[1])**2);
      if (q < best) { best = q; bc = c; }
    }
    return { q: best, c: bc };
  }

  // the floor height
  const pools = [];
  function floor_y(x, z) {
    let y = P.path_h(x, z);
    y += (fbm3(x*0.23, 0, z*0.23, 191) - 0.5)*0.42 + (noise3(x*0.9, 5.3, z*0.9, 193) - 0.5)*0.12;
    const n = P.nearest(x, z, 30);
    const area = n ? n.p.area : 0;
    const bio = biome_of_area(area);
    if (bio === 'sandstone') {
      // low ripples in the sand, across the way the wind never blew
      y += Math.sin(x*2.3 + z*0.9 + fbm3(x*0.3, 1, z*0.3, 7)*4)*0.025;
    }
    if (bio === 'warped') y += (fbm3(x*0.4, 2, z*0.4, 211) - 0.5)*0.25;
    for (const pl of pools) {
      const dx = (x - pl.c[0])/pl.r[0], dz = (z - pl.c[1])/pl.r[1];
      const q = Math.sqrt(dx*dx + dz*dz);
      y -= pl.depth*(1 - smoothstep(0.55, 1.15, q));
    }
    // the seam: exactly the room's floor where the walk meets its tunnel
    y = lerp(y, room_ground_y(x, z), smoothstep(-53, -48.5, z));
    return y;
  }

  function field(x, y, z) {
    // the path's tube (its width and height swelling and pinching along the way), and inside it
    // the lane: a narrower tube he can always float through, which the roughness never closes
    let f = 40, lane = 40;
    for (const k of P.near(x, z, 8, tmp)) {
      if (k & 1) continue;                                 // every second sample (0.5 m apart)
      const p = S[k];
      const dx = x - p.x, dz = z - p.z;
      const d = Math.sqrt(dx*dx + dz*dz);
      const sw = 1 + 0.55*(noise3(p.s*0.11, 1.5, 0.5, 701) - 0.5), sh = 1 + 0.6*(noise3(p.s*0.09, 4.5, 2.5, 703) - 0.5);
      const w = p.w*sw, H = p.H*sh;
      if (d > w*1.6 + 2.5) continue;
      const dy = y - p.h;
      const ny = dy > 0 ? dy/H : dy/1.4;
      const nd = d/w;
      const e = (Math.sqrt(nd*nd + ny*ny) - 1)*Math.min(w, 2.5);
      if (e < f) f = e;
      const ly = (y - p.h - 1.15)/1.55, ld = d/1.45;
      const el = (Math.sqrt(ld*ld + ly*ly) - 1)*1.45;
      if (el < lane) lane = el;
    }
    // chambers
    let cham = 0;
    for (const c of CH) {
      const dx = x - c.c[0], dz = z - c.c[1];
      const px = dx*c.cr - dz*c.sr, pz = dx*c.sr + dz*c.cr;
      const qh2 = (px/c.r[0])**2 + (pz/c.r[1])**2;
      if (qh2 > 2.6) continue;
      const dy = y - c.h;
      const ny = dy > 0 ? dy/c.H : dy/1.6;
      const e = (Math.sqrt(qh2 + ny*ny) - 1)*Math.min(c.r[0], c.r[1])*0.75;
      f = smin(f, e, 1.6);
      cham = Math.max(cham, smoothstep(1.35, 0.85, Math.sqrt(qh2)));
    }
    // shafts up to the sky
    let shaft = 0;
    for (const sh of SHAFTS) {
      const h0 = sh.h0;
      if (y < h0 + 1.0) continue;
      const ax = sh.at[0] + SUN_XZ[0]*(y - h0), az = sh.at[1] + SUN_XZ[1]*(y - h0);
      const d = Math.hypot(x - ax, z - az);
      if (d > sh.r*3 + 3) continue;
      // wider where it opens into the chamber, uneven up its length
      const r = sh.r*(1 + 0.9*smoothstep(sh.ceil + 2, sh.ceil - 2, y)) + (noise3(x*0.7, y*0.25, z*0.7, 301) - 0.5)*Math.min(0.5, sh.r*0.35);
      const e = d - r;
      f = smin(f, e, 0.8);
      shaft = Math.max(shaft, smoothstep(sh.r*2 + 2, sh.r, d)*smoothstep(sh.ceil - 3, sh.ceil + 1, y));
    }
    if (f > 6) return Math.min(f, lane);
    // roughness: big lumps and smaller knuckles; less in the passages (they must stay open),
    // little up the shafts (they must stay open to the sky)
    const n = P.nearest(x, z, 20);
    const area = n ? n.p.area : 0;
    const bio = biome_of_area(area);
    let amp = lerp(1.15, 1.5, cham)*(1 - 0.8*shaft);
    let wx = x, wy = y, wz = z;
    if (bio === 'warped') {
      // the leakage bent it: the noise is read through a swirl
      const s = 3.0;
      wx += (fbm3(x*0.11, y*0.11, z*0.11, 401) - 0.5)*s*2;
      wy += (fbm3(x*0.11, y*0.11, z*0.11, 403) - 0.5)*s*2;
      wz += (fbm3(x*0.11, y*0.11, z*0.11, 405) - 0.5)*s*2;
      amp *= 1.25;
    }
    f += amp*(fbm3(wx*0.16, wy*0.16, wz*0.16, 11) - 0.5)*2.4 + amp*0.35*(noise3(wx*0.7, wy*0.7, wz*0.7, 13) - 0.5)*2;
    if (bio === 'sandstone') {
      // strata: ledges where softer bands weathered back
      const b = y*1.15 + (fbm3(x*0.08, 0, z*0.08, 501) - 0.5)*1.6;
      const fr = b - Math.floor(b);
      f += (smoothstep(0.0, 0.25, fr) - smoothstep(0.55, 1.0, fr))*0.32*(1 - shaft);
    }
    if (bio === 'basalt') {
      // columnar jointing: shallow vertical flutes on the walls
      const c = cells2(x*0.6, z*0.6, 601);
      f += smoothstep(0.0, 0.12, c[1] - c[0])*0.22 - 0.11;
    }
    return Math.min(f, lane);
  }

  // shafts' floor and ceiling heights (for their shape)
  for (const sh of SHAFTS) {
    sh.h0 = floor_y(sh.at[0], sh.at[1]);
    const cq = chamber_q(sh.at[0], sh.at[1]);
    if (cq.q < 0.9) sh.ceil = cq.c.h + cq.c.H*0.9*Math.sqrt(Math.max(0.05, 1 - cq.q*cq.q));
    else { const n = P.nearest(sh.at[0], sh.at[1], 20); sh.ceil = n.p.h + n.p.H*0.9; }
  }

  return { field, floor_y, chamber_q, pools };
}

// 2D cellular noise (untiled): [d1, d2, id]
export function cells2(x, y, seed) {
  const ix = Math.floor(x), iy = Math.floor(y);
  let d1 = 9, d2 = 9, id = 0;
  for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) {
    const cx = ix + i, cy = iy + j;
    const px = cx + h3(cx, cy, 0, seed), py = cy + h3(cx, cy, 0, seed + 7);
    const d = Math.hypot(x - px, y - py);
    if (d < d1) { d2 = d1; d1 = d; id = h3(cx, cy, 0, seed + 13); } else if (d < d2) d2 = d;
  }
  return [d1, d2, id];
}

// ---------------------------------------------------------------- surface nets
// samples f on GRID, returns a triangle soup (Float32Array, 9 per triangle) with every triangle
// wound so its normal points into the air
export function mesh_volume(field, G = GRID, near_fn = null, log = () => {}) {
  const c = G.cell;
  const nx = Math.round((G.x1 - G.x0)/c) + 1, ny = Math.round((G.y1 - G.y0)/c) + 1, nz = Math.round((G.z1 - G.z0)/c) + 1;
  const F = new Float32Array(nx*ny*nz);
  const idx = (i, j, k) => (k*ny + j)*nx + i;
  const t0 = Date.now();
  let evals = 0;
  for (let k = 0; k < nz; k++) {
    const z = G.z0 + k*c;
    for (let i = 0; i < nx; i++) {
      const x = G.x0 + i*c;
      const near = near_fn ? near_fn(x, z) : true;
      for (let j = 0; j < ny; j++) {
        if (!near) { F[idx(i, j, k)] = 8; continue; }
        F[idx(i, j, k)] = field(x, G.y0 + j*c, z); evals++;
      }
    }
    if (k % 40 === 0) log(`  volume ${k}/${nz} (${evals} evals, ${((Date.now() - t0)/1000).toFixed(1)} s)`);
  }
  // the box's faces are rock, except its top (the shafts open to the sky)
  for (let k = 0; k < nz; k++) for (let j = 0; j < ny; j++) { F[idx(0, j, k)] = Math.max(F[idx(0, j, k)], 1); F[idx(nx - 1, j, k)] = Math.max(F[idx(nx - 1, j, k)], 1); }
  for (let k = 0; k < nz; k++) for (let i = 0; i < nx; i++) F[idx(i, 0, k)] = Math.max(F[idx(i, 0, k)], 1);
  for (let j = 0; j < ny; j++) for (let i = 0; i < nx; i++) { F[idx(i, j, 0)] = Math.max(F[idx(i, j, 0)], 1); F[idx(i, j, nz - 1)] = Math.max(F[idx(i, j, nz - 1)], 1); }

  // one vertex per cell the surface crosses
  const vid = new Int32Array((nx - 1)*(ny - 1)*(nz - 1)).fill(-1);
  const cidx = (i, j, k) => (k*(ny - 1) + j)*(nx - 1) + i;
  const V = [];
  const corner = [[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0], [0, 0, 1], [1, 0, 1], [0, 1, 1], [1, 1, 1]];
  const edges = [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]];
  const fv = new Float64Array(8);
  for (let k = 0; k < nz - 1; k++) for (let j = 0; j < ny - 1; j++) for (let i = 0; i < nx - 1; i++) {
    let mask = 0;
    for (let q = 0; q < 8; q++) {
      const cc = corner[q];
      fv[q] = F[idx(i + cc[0], j + cc[1], k + cc[2])];
      if (fv[q] < 0) mask |= 1 << q;
    }
    if (mask === 0 || mask === 255) continue;
    let sx = 0, sy = 0, sz = 0, n = 0;
    for (const [a, b] of edges) {
      const fa = fv[a], fb = fv[b];
      if ((fa < 0) === (fb < 0)) continue;
      const t = fa/(fa - fb);
      const A = corner[a], Bc = corner[b];
      sx += A[0] + (Bc[0] - A[0])*t; sy += A[1] + (Bc[1] - A[1])*t; sz += A[2] + (Bc[2] - A[2])*t; n++;
    }
    vid[cidx(i, j, k)] = V.length/3;
    V.push(G.x0 + (i + sx/n)*c, G.y0 + (j + sy/n)*c, G.z0 + (k + sz/n)*c);
  }
  // a quad round every crossed grid edge
  const T = [];
  const quad = (a, b, cc, d, nxw, nyw, nzw) => {
    if (a < 0 || b < 0 || cc < 0 || d < 0) return;
    const P = [a, b, cc, d].map(v => [V[v*3], V[v*3 + 1], V[v*3 + 2]]);
    // split along the shorter diagonal
    const d02 = (P[0][0] - P[2][0])**2 + (P[0][1] - P[2][1])**2 + (P[0][2] - P[2][2])**2;
    const d13 = (P[1][0] - P[3][0])**2 + (P[1][1] - P[3][1])**2 + (P[1][2] - P[3][2])**2;
    const tris = d02 <= d13 ? [[0, 1, 2], [0, 2, 3]] : [[0, 1, 3], [1, 2, 3]];
    for (const t of tris) {
      const p0 = P[t[0]], p1 = P[t[1]], p2 = P[t[2]];
      const ux = p1[0] - p0[0], uy = p1[1] - p0[1], uz = p1[2] - p0[2];
      const vx = p2[0] - p0[0], vy = p2[1] - p0[1], vz = p2[2] - p0[2];
      const cx = uy*vz - uz*vy, cy = uz*vx - ux*vz, cz = ux*vy - uy*vx;
      if (cx*cx + cy*cy + cz*cz < 1e-10) continue;
      if (cx*nxw + cy*nyw + cz*nzw >= 0) T.push(...p0, ...p1, ...p2);
      else T.push(...p0, ...p2, ...p1);
    }
  };
  for (let k = 1; k < nz - 1; k++) for (let j = 1; j < ny - 1; j++) for (let i = 0; i < nx - 1; i++) {
    const f0 = F[idx(i, j, k)], f1 = F[idx(i + 1, j, k)];
    if ((f0 < 0) === (f1 < 0)) continue;
    const s = f0 < 0 ? -1 : 1;                    // air at the low end: the normal points -x
    quad(vid[cidx(i, j - 1, k - 1)], vid[cidx(i, j, k - 1)], vid[cidx(i, j, k)], vid[cidx(i, j - 1, k)], s, 0, 0);
  }
  for (let k = 1; k < nz - 1; k++) for (let j = 0; j < ny - 1; j++) for (let i = 1; i < nx - 1; i++) {
    const f0 = F[idx(i, j, k)], f1 = F[idx(i, j + 1, k)];
    if ((f0 < 0) === (f1 < 0)) continue;
    const s = f0 < 0 ? -1 : 1;
    quad(vid[cidx(i - 1, j, k - 1)], vid[cidx(i, j, k - 1)], vid[cidx(i, j, k)], vid[cidx(i - 1, j, k)], 0, s, 0);
  }
  for (let k = 0; k < nz - 1; k++) for (let j = 1; j < ny - 1; j++) for (let i = 1; i < nx - 1; i++) {
    const f0 = F[idx(i, j, k)], f1 = F[idx(i, j, k + 1)];
    if ((f0 < 0) === (f1 < 0)) continue;
    const s = f0 < 0 ? -1 : 1;
    quad(vid[cidx(i - 1, j - 1, k)], vid[cidx(i, j - 1, k)], vid[cidx(i, j, k)], vid[cidx(i - 1, j, k)], 0, 0, s);
  }
  log(`  surface: ${V.length/3} vertices, ${T.length/9} triangles (${((Date.now() - t0)/1000).toFixed(1)} s)`);
  return { tris: new Float32Array(T), F, dims: [nx, ny, nz] };
}
