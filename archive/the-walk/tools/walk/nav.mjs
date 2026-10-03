// nav.mjs -- where the lich can float in the walk (port/nav.lua's grid, for the whole walk and the
// final room's tunnel): a 0.25 m grid; a cell is blocked where rock rises more than 0.6 m above
// its floor below head height, or where there is no room for him (rock within 2 m above the
// floor); lower rock lifts his float. The pool's water is a floor he floats over. Stored as
// little-endian blobs the Lua side samples in place:
//   lift  (f32) the floor he hovers over (the highest floor within 0.35 m)
//   dist  (f32) distance to the nearest blocking cell, minus half a cell (negative: blocked)
//   rock  (f32) the top of the rock that blocks a cell (1e9 for walls), -1e30 where clear
//   s     (f32) how far along the walk the cell is (its nearest path sample; the tunnel continues it)
//   area  (u8)  which area the cell belongs to (8: the final room's tunnel)
import { GRID, SEAM_Z } from './field.mjs';
import { room_ground_y } from './lib.mjs';

export const NAV = { x0: GRID.x0, x1: GRID.x1, z0: GRID.z0, z1: -4, cell: 0.25, block_h: 0.6, head: 2.2 };
const TUNNEL_HALF = 1.9;

function dt1(f, n, d, v, z) {
  let k = 0;
  v[0] = 0; z[0] = -Infinity; z[1] = Infinity;
  for (let q = 1; q < n; q++) {
    let s = ((f[q] + q*q) - (f[v[k]] + v[k]*v[k]))/(2*q - 2*v[k]);
    while (s <= z[k]) { k--; s = ((f[q] + q*q) - (f[v[k]] + v[k]*v[k]))/(2*q - 2*v[k]); }
    k++; v[k] = q; z[k] = s; z[k + 1] = Infinity;
  }
  k = 0;
  for (let q = 0; q < n; q++) { while (z[k + 1] < q) k++; const dq = q - v[k]; d[q] = dq*dq + f[v[k]]; }
}

export function build_nav({ P, F, recs, log }) {
  const { x0, x1, z0, z1, cell, block_h, head } = NAV;
  const nx = Math.round((x1 - x0)/cell), nz = Math.round((z1 - z0)/cell);
  const NN = nx*nz;
  const cx = i => x0 + (i + 0.5)*cell, cz = j => z0 + (j + 0.5)*cell;
  const floor = new Float32Array(NN), top = new Float32Array(NN).fill(-1e9), blocked = new Uint8Array(NN);
  const sv = new Float32Array(NN), area = new Uint8Array(NN);
  const last = P.S[P.S.length - 1];
  const water = F.pools[0];
  // floors, headroom, the stretch each cell is on
  for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) {
    const k = j*nx + i, x = cx(i), z = cz(j);
    if (z > SEAM_Z) {
      // the final room's tunnel: its own floor; walls by a fixed half width
      floor[k] = room_ground_y(x, z);
      blocked[k] = Math.abs(x) < TUNNEL_HALF ? 0 : 1;
      sv[k] = last.s + (z - last.z); area[k] = 8;
      continue;
    }
    const n = P.nearest(x, z, 18);
    if (!n) { blocked[k] = 1; floor[k] = 0; sv[k] = 0; area[k] = 255; continue; }
    sv[k] = n.p.s; area[k] = n.p.area;
    let fy = F.floor_y(x, z);
    if (water && fy < water.level) {
      const dx = (x - water.c[0])/water.r[0], dz = (z - water.c[1])/water.r[1];
      if (dx*dx + dz*dz < 2.5) fy = water.level;
    }
    floor[k] = fy;
    if (!(F.field(x, fy + 0.45, z) < 0 && F.field(x, fy + 1.3, z) < 0 && F.field(x, fy + 2.0, z) < 0)) blocked[k] = 1;
  }
  log(`nav: ${nx}x${nz} cells, floors (${blocked.reduce((s, b) => s + (b ? 0 : 1), 0)} open before rock)`);
  // rock: every triangle's height at the cell centres it covers, below head height only
  // (ceilings and what hangs high stay out of it); the water is left out (a floor, above)
  const mark = (i, j, y) => {
    if (i < 0 || j < 0 || i >= nx || j >= nz) return;
    const k = j*nx + i;
    if (y > floor[k] + head) return;
    if (y > top[k]) top[k] = y;
  };
  for (const r of recs) {
    if (!r.receive || r.mat === 'water' || r.mat === undefined) continue;
    if (r.key === 'extra') continue;                       // the floating stones: he passes under them
    const p = r.T;
    for (let t = 0; t < p.length; t += 9) {
      const ax = p[t], ay = p[t + 1], az = p[t + 2], bx = p[t + 3], by = p[t + 4], bz = p[t + 5], qx = p[t + 6], qy = p[t + 7], qz = p[t + 8];
      const det = (bz - qz)*(ax - qx) + (qx - bx)*(az - qz);
      if (Math.abs(det) < 1e-9) continue;
      const i0 = Math.max(0, Math.floor((Math.min(ax, bx, qx) - x0)/cell)), i1 = Math.min(nx - 1, Math.floor((Math.max(ax, bx, qx) - x0)/cell));
      const j0 = Math.max(0, Math.floor((Math.min(az, bz, qz) - z0)/cell)), j1 = Math.min(nz - 1, Math.floor((Math.max(az, bz, qz) - z0)/cell));
      for (let j = j0; j <= j1; j++) for (let i = i0; i <= i1; i++) {
        const x = cx(i), z = cz(j);
        const l1 = ((bz - qz)*(x - qx) + (qx - bx)*(z - qz))/det;
        const l2 = ((qz - az)*(x - qx) + (ax - qx)*(z - qz))/det;
        const l3 = 1 - l1 - l2;
        if (l1 < -1e-4 || l2 < -1e-4 || l3 < -1e-4) continue;
        mark(i, j, l1*ay + l2*by + l3*qy);
      }
    }
  }
  const flo = new Float32Array(NN), rock = new Float32Array(NN).fill(-1e30);
  for (let k = 0; k < NN; k++) {
    const h = top[k] - floor[k];
    if (h > block_h) { blocked[k] = 1; rock[k] = top[k]; }
    else if (blocked[k]) rock[k] = 1e9;
    flo[k] = Math.max(floor[k], (h > 0 && h <= block_h) ? top[k] : floor[k]);
  }
  // lift: the highest open floor within 0.35 m
  const lift = new Float32Array(NN);
  const LR = Math.ceil(0.35/cell);
  for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) {
    let m = flo[j*nx + i];
    for (let dj = -LR; dj <= LR; dj++) for (let di = -LR; di <= LR; di++) {
      if (di*di + dj*dj > LR*LR) continue;
      const ii = i + di, jj = j + dj;
      if (ii < 0 || jj < 0 || ii >= nx || jj >= nz || blocked[jj*nx + ii]) continue;
      if (flo[jj*nx + ii] > m) m = flo[jj*nx + ii];
    }
    lift[j*nx + i] = m;
  }
  // distance to the nearest blocking cell (outside the grid blocks), capped
  const MAXD = 1.6;
  const R = Math.ceil(MAXD/cell);
  const W = nx + 2*R, H = nz + 2*R;
  const g = new Float64Array(W*H);
  for (let jj = 0; jj < H; jj++) for (let ii = 0; ii < W; ii++) {
    const i = ii - R, j = jj - R;
    const b = (i < 0 || j < 0 || i >= nx || j >= nz) || blocked[j*nx + i] === 1;
    g[jj*W + ii] = b ? 0 : 1e20;
  }
  const f = new Float64Array(Math.max(W, H)), d = new Float64Array(Math.max(W, H)), v = new Int32Array(Math.max(W, H) + 1), zz = new Float64Array(Math.max(W, H) + 2);
  for (let jj = 0; jj < H; jj++) { for (let ii = 0; ii < W; ii++) f[ii] = g[jj*W + ii]; dt1(f, W, d, v, zz); for (let ii = 0; ii < W; ii++) g[jj*W + ii] = d[ii]; }
  for (let ii = 0; ii < W; ii++) { for (let jj = 0; jj < H; jj++) f[jj] = g[jj*W + ii]; dt1(f, H, d, v, zz); for (let jj = 0; jj < H; jj++) g[jj*W + ii] = d[jj]; }
  const dist = new Float32Array(NN);
  for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) {
    const k = j*nx + i;
    dist[k] = blocked[k] ? -cell*0.5 : Math.sqrt(Math.min(MAXD*MAXD, g[(j + R)*W + (i + R)]*cell*cell)) - cell*0.5;
  }
  let open = 0;
  for (let k = 0; k < NN; k++) if (!blocked[k]) open++;
  log(`nav: ${open} open cells (${(open*cell*cell).toFixed(0)} m2)`);
  const api = {
    meta: { x0, z0, nx, nz, cell, maxd: MAXD },
    blobs: { lift, dist, rock, s: sv, area },
    blocked, floor: flo, lift, nx, nz,
    at: (x, z) => { const i = Math.floor((x - x0)/cell), j = Math.floor((z - z0)/cell); return (i < 0 || j < 0 || i >= nx || j >= nz) ? -1 : j*nx + i; },
    open: (x, z) => { const k = api.at(x, z); return k >= 0 && !blocked[k] && dist[k] > 0.34; },
    s_at: (x, z) => { const k = api.at(x, z); return k >= 0 ? sv[k] : -1; },
  };
  return api;
}
