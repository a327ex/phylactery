// nav.js -- where the lich can float (round 5). A 0.2 m grid over the chamber, rasterized from
// the rock meshes: a cell whose rock rises more than BLOCK_H above the ground blocks him; lower
// rock (stones, rubble) only lifts his float so his toes pass over it. Anything else the caller
// marks (the egg, what the room camera can't see) blocks too. The distance to the nearest
// blocking cell pushes him out and lets him slide along an edge.
export function build_nav({ geo, ground_y, x0 = -16, x1 = 16, z0 = -16, z1 = 16, cell = 0.2, block_h = 0.6 }) {
  const nx = Math.round((x1 - x0)/cell), nz = Math.round((z1 - z0)/cell), N = nx*nz;
  const top = new Float32Array(N).fill(-1e9);
  const gy = new Float32Array(N);
  const cx = i => x0 + (i + 0.5)*cell, cz = j => z0 + (j + 0.5)*cell;
  for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) gy[j*nx + i] = ground_y(cx(i), cz(j));

  // rock tops: every triangle's surface over the cell centres it covers, and its corners
  const p = geo.attributes.position.array;
  const mark = (x, z, y) => {
    const i = Math.floor((x - x0)/cell), j = Math.floor((z - z0)/cell);
    if (i >= 0 && j >= 0 && i < nx && j < nz && y > top[j*nx + i]) top[j*nx + i] = y;
  };
  for (let t = 0; t < p.length; t += 9) {
    const ax = p[t], ay = p[t + 1], az = p[t + 2], bx = p[t + 3], by = p[t + 4], bz = p[t + 5], qx = p[t + 6], qy = p[t + 7], qz = p[t + 8];
    mark(ax, az, ay); mark(bx, bz, by); mark(qx, qz, qy);
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
      const y = l1*ay + l2*by + l3*qy;
      if (y > top[j*nx + i]) top[j*nx + i] = y;
    }
  }
  const blocked = new Uint8Array(N);
  const floor = new Float32Array(N);
  for (let k = 0; k < N; k++) {
    const h = top[k] - gy[k];
    if (h > block_h) blocked[k] = 1;
    floor[k] = Math.max(gy[k], h > 0 && h <= block_h ? top[k] : gy[k]);
  }
  const rock = blocked.slice();                   // rock alone (block() adds the rest to `blocked`)

  // what the float clears: the highest floor under his legs (a disc around the pelvis)
  const lift = new Float32Array(N);
  const LR = Math.ceil(0.35/cell);
  for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) {
    let m = floor[j*nx + i];
    for (let dj = -LR; dj <= LR; dj++) for (let di = -LR; di <= LR; di++) {
      if (di*di + dj*dj > LR*LR) continue;
      const ii = i + di, jj = j + dj;
      if (ii < 0 || jj < 0 || ii >= nx || jj >= nz || blocked[jj*nx + ii]) continue;
      m = Math.max(m, floor[jj*nx + ii]);
    }
    lift[j*nx + i] = m;
  }

  // bilinear read of a cell field at a world point
  const sample = (F, x, z) => {
    const fx = (x - x0)/cell - 0.5, fz = (z - z0)/cell - 0.5;
    let i = Math.floor(fx), j = Math.floor(fz);
    const u = fx - i, v = fz - j;
    const at = (a, b) => F[Math.min(nz - 1, Math.max(0, b))*nx + Math.min(nx - 1, Math.max(0, a))];
    return (at(i, j)*(1 - u) + at(i + 1, j)*u)*(1 - v) + (at(i, j + 1)*(1 - u) + at(i + 1, j + 1)*u)*v;
  };

  let dist = null;
  const MAXD = 1.6;
  const nav = {
    nx, nz, cell, x0, z0, blocked,
    // block every cell whose centre `fn(x, z)` says so; call finish() after the last one
    block(fn) { for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) if (fn(cx(i), cz(j))) blocked[j*nx + i] = 1; },
    finish() {
      // distance from each cell centre to the edge of the nearest blocking cell (brute force in a window)
      dist = new Float32Array(N);
      const R = Math.ceil(MAXD/cell);
      for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) {
        if (blocked[j*nx + i]) { dist[j*nx + i] = -cell*0.5; continue; }
        let best = MAXD*MAXD;
        for (let dj = -R; dj <= R; dj++) for (let di = -R; di <= R; di++) {
          const ii = i + di, jj = j + dj;
          const out = ii < 0 || jj < 0 || ii >= nx || jj >= nz;
          if (!out && !blocked[jj*nx + ii]) continue;
          const d2 = (di*di + dj*dj)*cell*cell;
          if (d2 < best) best = d2;
        }
        dist[j*nx + i] = Math.sqrt(best) - cell*0.5;
      }
      return nav;
    },
    floor: (x, z) => sample(lift, x, z),
    dist: (x, z) => sample(dist, x, z),
    // rock at a point, and how high it rises there (for cameras to stop short of it)
    rock_at(x, z) {
      const i = Math.floor((x - x0)/cell), j = Math.floor((z - z0)/cell);
      if (i < 0 || j < 0 || i >= nx || j >= nz) return Infinity;
      return rock[j*nx + i] ? top[j*nx + i] : -Infinity;
    },
    is_blocked(x, z) {
      const i = Math.floor((x - x0)/cell), j = Math.floor((z - z0)/cell);
      return i < 0 || j < 0 || i >= nx || j >= nz || blocked[j*nx + i] === 1;
    },
    // push a body of radius r at (p.x, p.z) out of blocking cells; slide v along the edge.
    // Returns true on contact.
    resolve(pos, vel, r) {
      let hit = false;
      for (let it = 0; it < 3; it++) {
        const d = sample(dist, pos.x, pos.z);
        if (d >= r) break;
        const e = cell*0.5;
        let gx = sample(dist, pos.x + e, pos.z) - sample(dist, pos.x - e, pos.z);
        let gz = sample(dist, pos.x, pos.z + e) - sample(dist, pos.x, pos.z - e);
        const gl = Math.hypot(gx, gz);
        if (gl < 1e-6) break;
        gx /= gl; gz /= gl;
        pos.x += gx*(r - d); pos.z += gz*(r - d);
        const into = vel.x*gx + vel.z*gz;
        if (into < 0) { vel.x -= gx*into; vel.z -= gz*into; }
        hit = true;
      }
      return hit;
    },
  };
  return nav;
}
