// geo.mjs -- primitive shapes as triangle soups (arrays of x, y, z; 9 numbers a triangle), wound
// outward: convex blocks (three.js ConvexGeometry, as cave.js makes its rocks), prisms and cones
// along any axis (basalt columns, crystals, stalactites), tubes along a spine (twisted pillars,
// stems), caps (squashed hemispheres), a torus (the stone ring).
import * as THREE from 'three';
import { ConvexGeometry } from 'three/addons/geometries/ConvexGeometry.js';

// an orthonormal frame round a direction
export function frame(dx, dy, dz) {
  const l = Math.hypot(dx, dy, dz) || 1;
  dx /= l; dy /= l; dz /= l;
  let ax = Math.abs(dy) < 0.9 ? 0 : 1, ay = Math.abs(dy) < 0.9 ? 1 : 0, az = 0;
  // u = a x d
  let ux = ay*dz - az*dy, uy = az*dx - ax*dz, uz = ax*dy - ay*dx;
  const ul = Math.hypot(ux, uy, uz); ux /= ul; uy /= ul; uz /= ul;
  const vx = dy*uz - dz*uy, vy = dz*ux - dx*uz, vz = dx*uy - dy*ux;
  return { d: [dx, dy, dz], u: [ux, uy, uz], v: [vx, vy, vz] };
}

// wind every triangle of a soup so its normal points away from `inside(x, y, z)`'s answer:
// a centre point, or a function giving the inside point for a triangle
export function orient_out(T, cx, cy, cz) {
  for (let i = 0; i < T.length; i += 9) {
    const ax = T[i], ay = T[i + 1], az = T[i + 2], bx = T[i + 3], by = T[i + 4], bz = T[i + 5], qx = T[i + 6], qy = T[i + 7], qz = T[i + 8];
    const nx = (by - ay)*(qz - az) - (bz - az)*(qy - ay), ny = (bz - az)*(qx - ax) - (bx - ax)*(qz - az), nz = (bx - ax)*(qy - ay) - (by - ay)*(qx - ax);
    const mx = (ax + bx + qx)/3 - cx, my = (ay + by + qy)/3 - cy, mz = (az + bz + qz)/3 - cz;
    if (nx*mx + ny*my + nz*mz < 0) { T[i + 3] = qx; T[i + 4] = qy; T[i + 5] = qz; T[i + 6] = bx; T[i + 7] = by; T[i + 8] = bz; }
  }
  return T;
}

// a convex hull of points (rng-scattered in a box, a few pinned near its corners: big planar
// fracture faces), placed at c, turned by quaternion q
export function block(rng, w, h, d, { corners = 0.55, n = 12, c = [0, 0, 0], q = null } = {}) {
  const pts = [];
  for (let i = 0; i < n; i++) pts.push(new THREE.Vector3(rng.spread(w/2), rng.spread(h/2), rng.spread(d/2)));
  for (const sx of [-1, 1]) for (const sy of [-1, 1]) for (const sz of [-1, 1]) {
    if (rng.chance(corners)) pts.push(new THREE.Vector3(sx*w/2*rng.float(0.7, 1), sy*h/2*rng.float(0.7, 1), sz*d/2*rng.float(0.7, 1)));
  }
  return hull(pts, c, q);
}
export function hull(pts, c = [0, 0, 0], q = null) {
  let g = new ConvexGeometry(pts);
  if (g.index) g = g.toNonIndexed();
  const m = new THREE.Matrix4().compose(new THREE.Vector3(c[0], c[1], c[2]), q || new THREE.Quaternion(), new THREE.Vector3(1, 1, 1));
  g.applyMatrix4(m);
  const T = Array.from(g.attributes.position.array);
  return orient_out(T, c[0], c[1], c[2]);
}
export const quat_euler = (x, y, z, order = 'YXZ') => new THREE.Quaternion().setFromEuler(new THREE.Euler(x, y, z, order));

// a prism of n sides from base point b along direction dir, length L, radius r0 at the base and
// r1 at the top; tip > 0 adds a pyramid of that height (crystals, stalactite points); jitter
// roughens the side vertices; twist turns the top ring
export function prism(b, dir, L, r0, r1, { n = 6, tip = 0, jitter = 0, rng = null, rot = 0, cap0 = true, rings = 1, wobble = null } = {}) {
  const F = frame(dir[0], dir[1], dir[2]);
  const R = [];
  for (let k = 0; k <= rings; k++) {
    const t = k/rings;
    const r = r0 + (r1 - r0)*t;
    const ring = [];
    const off = wobble ? wobble(t) : [0, 0];
    for (let i = 0; i < n; i++) {
      const a = rot + i/n*Math.PI*2;
      const jr = jitter && rng ? 1 + rng.spread(jitter) : 1;
      const cu = Math.cos(a)*r*jr + off[0], cv = Math.sin(a)*r*jr + off[1];
      ring.push([b[0] + F.d[0]*L*t + F.u[0]*cu + F.v[0]*cv, b[1] + F.d[1]*L*t + F.u[1]*cu + F.v[1]*cv, b[2] + F.d[2]*L*t + F.u[2]*cu + F.v[2]*cv]);
    }
    R.push(ring);
  }
  const T = [];
  const tri = (a, bb, c) => T.push(a[0], a[1], a[2], bb[0], bb[1], bb[2], c[0], c[1], c[2]);
  for (let k = 0; k < rings; k++) for (let i = 0; i < n; i++) {
    const a = R[k][i], bb = R[k][(i + 1)%n], c = R[k + 1][(i + 1)%n], d = R[k + 1][i];
    tri(a, bb, c); tri(a, c, d);
  }
  const top = R[rings];
  if (tip > 0 || r1 > 0.001) {
    const ct = [b[0] + F.d[0]*(L + tip), b[1] + F.d[1]*(L + tip), b[2] + F.d[2]*(L + tip)];
    for (let i = 0; i < n; i++) tri(top[i], top[(i + 1)%n], ct);
  }
  if (cap0) for (let i = 0; i < n; i++) tri(R[0][(i + 1)%n], R[0][i], b);
  // wind outward: from the centroid's foot on the axis, nudged toward the prism's middle (side
  // faces see a radial vector, end caps an axial one)
  for (let i = 0; i < T.length; i += 9) {
    const mx = (T[i] + T[i + 3] + T[i + 6])/3, my = (T[i + 1] + T[i + 4] + T[i + 7])/3, mz = (T[i + 2] + T[i + 5] + T[i + 8])/3;
    let t = (mx - b[0])*F.d[0] + (my - b[1])*F.d[1] + (mz - b[2])*F.d[2];
    t += t < L*0.5 ? 0.01 : -0.01;
    const sub = [T[i], T[i + 1], T[i + 2], T[i + 3], T[i + 4], T[i + 5], T[i + 6], T[i + 7], T[i + 8]];
    orient_out(sub, b[0] + F.d[0]*t, b[1] + F.d[1]*t, b[2] + F.d[2]*t);
    for (let q = 0; q < 9; q++) T[i + q] = sub[q];
  }
  return T;
}

// a squashed hemisphere (a cap): centre c (its flat base), radius r, height hgt, facing up
export function cap(c, r, hgt, { seg = 10, rings = 4, jitter = 0, rng = null, under = 0.25 } = {}) {
  const P = [];
  for (let k = 0; k <= rings; k++) {
    const ph = k/rings*Math.PI/2;
    const row = [];
    for (let i = 0; i < seg; i++) {
      const a = i/seg*Math.PI*2;
      const jr = jitter && rng && k < rings ? 1 + rng.spread(jitter) : 1;
      const rr = Math.cos(ph)*r*jr;
      row.push([c[0] + Math.cos(a)*rr, c[1] + Math.sin(ph)*hgt, c[2] + Math.sin(a)*rr]);
    }
    P.push(row);
  }
  const T = [];
  const tri = (a, b, q) => T.push(a[0], a[1], a[2], b[0], b[1], b[2], q[0], q[1], q[2]);
  for (let k = 0; k < rings; k++) for (let i = 0; i < seg; i++) {
    const a = P[k][i], b = P[k][(i + 1)%seg], q = P[k + 1][(i + 1)%seg], d = P[k + 1][i];
    if (k === rings - 1) tri(a, b, q); else { tri(a, b, q); tri(a, q, d); }
  }
  // the gills underneath: a shallow cone inward
  const uc = [c[0], c[1] - hgt*under, c[2]];
  for (let i = 0; i < seg; i++) tri(P[0][(i + 1)%seg], P[0][i], uc);
  return orient_out(T, c[0], c[1] + hgt*0.3, c[2]);
}

// a tube along a spine (array of [x, y, z]) with radius per point; closed at both ends
export function tube(spine, radius, { n = 8, jitter = 0, rng = null, rot = 0 } = {}) {
  const R = [];
  let prev = null;
  for (let k = 0; k < spine.length; k++) {
    const a = spine[Math.max(0, k - 1)], b = spine[Math.min(spine.length - 1, k + 1)];
    let F = frame(b[0] - a[0], b[1] - a[1], b[2] - a[2]);
    if (prev) {
      // parallel transport: keep u as close to the previous u as possible
      const d = F.d, pu = prev.u;
      const dot = pu[0]*d[0] + pu[1]*d[1] + pu[2]*d[2];
      let ux = pu[0] - d[0]*dot, uy = pu[1] - d[1]*dot, uz = pu[2] - d[2]*dot;
      const l = Math.hypot(ux, uy, uz) || 1; ux /= l; uy /= l; uz /= l;
      F = { d, u: [ux, uy, uz], v: [d[1]*uz - d[2]*uy, d[2]*ux - d[0]*uz, d[0]*uy - d[1]*ux] };
    }
    prev = F;
    const r = typeof radius === 'function' ? radius(k/(spine.length - 1), k) : radius[k];
    const ring = [];
    for (let i = 0; i < n; i++) {
      const ang = rot + i/n*Math.PI*2;
      const jr = jitter && rng ? 1 + rng.spread(jitter) : 1;
      const cu = Math.cos(ang)*r*jr, cv = Math.sin(ang)*r*jr;
      const p = spine[k];
      ring.push([p[0] + F.u[0]*cu + F.v[0]*cv, p[1] + F.u[1]*cu + F.v[1]*cv, p[2] + F.u[2]*cu + F.v[2]*cv]);
    }
    R.push(ring);
  }
  const T = [];
  const tri = (a, b, q) => T.push(a[0], a[1], a[2], b[0], b[1], b[2], q[0], q[1], q[2]);
  for (let k = 0; k < R.length - 1; k++) for (let i = 0; i < n; i++) {
    const a = R[k][i], b = R[k][(i + 1)%n], q = R[k + 1][(i + 1)%n], d = R[k + 1][i];
    // wound outward from the spine point
    const sub = [...a, ...b, ...q, ...a, ...q, ...d];
    const c = spine[k];
    const s1 = sub.slice(0, 9), s2 = sub.slice(9);
    orient_out(s1, c[0], c[1], c[2]); orient_out(s2, c[0], c[1], c[2]);
    T.push(...s1, ...s2);
  }
  const s0 = spine[0], s1 = spine[spine.length - 1];
  for (let i = 0; i < n; i++) {
    const e0 = [...R[0][(i + 1)%n], ...R[0][i], ...s0];
    const e1 = [...R[R.length - 1][i], ...R[R.length - 1][(i + 1)%n], ...s1];
    const n0 = spine[1], n1 = spine[spine.length - 2];
    orient_out(e0, n0[0], n0[1], n0[2]); orient_out(e1, n1[0], n1[1], n1[2]);
    T.push(...e0, ...e1);
  }
  return T;
}

// a ring (torus) lying level at c: major radius Rm, tube radius rt
export function torus(c, Rm, rt, { seg = 18, sides = 6, jitter = 0, rng = null } = {}) {
  const spine = [];
  for (let i = 0; i <= seg; i++) { const a = i/seg*Math.PI*2; spine.push([c[0] + Math.cos(a)*Rm, c[1], c[2] + Math.sin(a)*Rm]); }
  const T = [];
  const R = [];
  for (let i = 0; i < seg; i++) {
    const a = i/seg*Math.PI*2;
    const ring = [];
    for (let k = 0; k < sides; k++) {
      const b = k/sides*Math.PI*2;
      const jr = jitter && rng ? 1 + rng.spread(jitter) : 1;
      const rr = Rm + Math.cos(b)*rt*jr;
      ring.push([c[0] + Math.cos(a)*rr, c[1] + Math.sin(b)*rt*jr, c[2] + Math.sin(a)*rr]);
    }
    R.push(ring);
  }
  for (let i = 0; i < seg; i++) for (let k = 0; k < sides; k++) {
    const a = R[i][k], b = R[(i + 1)%seg][k], q = R[(i + 1)%seg][(k + 1)%sides], d = R[i][(k + 1)%sides];
    const ang = (i + 0.5)/seg*Math.PI*2;
    const cc = [c[0] + Math.cos(ang)*Rm, c[1], c[2] + Math.sin(ang)*Rm];
    const s1 = [...a, ...b, ...q], s2 = [...a, ...q, ...d];
    orient_out(s1, cc[0], cc[1], cc[2]); orient_out(s2, cc[0], cc[1], cc[2]);
    T.push(...s1, ...s2);
  }
  return T;
}

// flat normals for a soup
export function flat_normals(T) {
  const N = new Float32Array(T.length);
  for (let i = 0; i < T.length; i += 9) {
    const ax = T[i], ay = T[i + 1], az = T[i + 2];
    const ux = T[i + 3] - ax, uy = T[i + 4] - ay, uz = T[i + 5] - az, vx = T[i + 6] - ax, vy = T[i + 7] - ay, vz = T[i + 8] - az;
    let nx = uy*vz - uz*vy, ny = uz*vx - ux*vz, nz = ux*vy - uy*vx;
    const l = Math.hypot(nx, ny, nz) || 1; nx /= l; ny /= l; nz /= l;
    for (let k = 0; k < 3; k++) { N[i + k*3] = nx; N[i + k*3 + 1] = ny; N[i + k*3 + 2] = nz; }
  }
  return N;
}
// smooth normals: averaged over vertices sharing a position
export function smooth_normals(T) {
  const F = flat_normals(T);
  const acc = new Map();
  const key = (i) => `${Math.round(T[i]*1000)},${Math.round(T[i + 1]*1000)},${Math.round(T[i + 2]*1000)}`;
  for (let i = 0; i < T.length; i += 3) {
    const k = key(i); let a = acc.get(k); if (!a) { a = [0, 0, 0]; acc.set(k, a); }
    a[0] += F[i]; a[1] += F[i + 1]; a[2] += F[i + 2];
  }
  const N = new Float32Array(T.length);
  for (let i = 0; i < T.length; i += 3) {
    const a = acc.get(key(i)); const l = Math.hypot(a[0], a[1], a[2]) || 1;
    N[i] = a[0]/l; N[i + 1] = a[1]/l; N[i + 2] = a[2]/l;
  }
  return N;
}
// world-space UVs (cave.js world_uv): each triangle projected on its dominant axis
export function world_uv(T, tile = 2) {
  const UV = new Float32Array(T.length/3*2);
  for (let i = 0; i < T.length; i += 9) {
    const ax = T[i], ay = T[i + 1], az = T[i + 2];
    const ux = T[i + 3] - ax, uy = T[i + 4] - ay, uz = T[i + 5] - az, vx = T[i + 6] - ax, vy = T[i + 7] - ay, vz = T[i + 8] - az;
    // cave.js: nn = (c - b) x (a - b)
    const bx = T[i + 3], by = T[i + 4], bz = T[i + 5];
    const e1x = T[i + 6] - bx, e1y = T[i + 7] - by, e1z = T[i + 8] - bz, e2x = ax - bx, e2y = ay - by, e2z = az - bz;
    const nx = Math.abs(e1y*e2z - e1z*e2y), ny = Math.abs(e1z*e2x - e1x*e2z), nz = Math.abs(e1x*e2y - e1y*e2x);
    void ux; void uy; void uz; void vx; void vy; void vz;
    for (let k = 0; k < 3; k++) {
      const x = T[i + k*3], y = T[i + k*3 + 1], z = T[i + k*3 + 2];
      let u, v;
      if (ny >= nx && ny >= nz) { u = x; v = z; } else if (nx >= nz) { u = z; v = y; } else { u = x; v = y; }
      UV[(i/3 + k)*2] = u/tile; UV[(i/3 + k)*2 + 1] = v/tile;
    }
  }
  return UV;
}
