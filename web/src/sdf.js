// sdf.js -- sculpting with signed distance fields, and meshing them (naive surface nets).
//
// A shape is a function (x, y, z) -> signed distance (negative inside). mesh_sdf() samples it
// on a grid over a box and builds an indexed mesh: one vertex per cell the surface crosses, at
// the mean of that cell's edge crossings, one quad per crossed edge. Normals come from the
// field's gradient, so the surface is smooth whatever the voxel size.
import * as THREE from 'three';

// ---------------------------------------------------------------- primitives (return distance)
export const sphere = (x, y, z, cx, cy, cz, r) => Math.hypot(x - cx, y - cy, z - cz) - r;

export function ellipsoid(x, y, z, cx, cy, cz, rx, ry, rz) {
  const px = (x - cx)/rx, py = (y - cy)/ry, pz = (z - cz)/rz;
  const k0 = Math.hypot(px, py, pz);
  const k1 = Math.hypot(px/rx, py/ry, pz/rz);
  return k1 < 1e-9 ? -Math.min(rx, ry, rz) : k0*(k0 - 1)/k1;
}

// capsule between a and b with radius ra at a and rb at b (a "round cone" when they differ)
export function cone(x, y, z, ax, ay, az, bx, by, bz, ra, rb) {
  const px = x - ax, py = y - ay, pz = z - az;
  const dx = bx - ax, dy = by - ay, dz = bz - az;
  const L2 = dx*dx + dy*dy + dz*dz;
  let t = L2 > 0 ? (px*dx + py*dy + pz*dz)/L2 : 0;
  t = t < 0 ? 0 : t > 1 ? 1 : t;
  const qx = px - dx*t, qy = py - dy*t, qz = pz - dz*t;
  return Math.hypot(qx, qy, qz) - (ra + (rb - ra)*t);
}
export const capsule = (x, y, z, ax, ay, az, bx, by, bz, r) => cone(x, y, z, ax, ay, az, bx, by, bz, r, r);

export function rbox(x, y, z, cx, cy, cz, hx, hy, hz, r) {
  const qx = Math.abs(x - cx) - hx + r, qy = Math.abs(y - cy) - hy + r, qz = Math.abs(z - cz) - hz + r;
  const ox = Math.max(qx, 0), oy = Math.max(qy, 0), oz = Math.max(qz, 0);
  return Math.hypot(ox, oy, oz) + Math.min(Math.max(qx, qy, qz), 0) - r;
}

// a chain of round cones through points [[x,y,z,r], ...] (smooth-unioned with k)
export function chain(x, y, z, P, k = 0) {
  let d = Infinity;
  for (let i = 0; i < P.length - 1; i++) {
    const a = P[i], b = P[i + 1];
    const e = cone(x, y, z, a[0], a[1], a[2], b[0], b[1], b[2], a[3], b[3]);
    d = k > 0 ? smin(d, e, k) : Math.min(d, e);
  }
  return d;
}

// ---------------------------------------------------------------- combinators
export function smin(a, b, k) {
  if (!isFinite(a)) return b;
  const h = Math.max(k - Math.abs(a - b), 0)/k;
  return Math.min(a, b) - h*h*k*0.25;
}
export function smax(a, b, k) { return -smin(-a, -b, k); }
export const sub = (a, b, k = 0) => (k > 0 ? smax(a, -b, k) : Math.max(a, -b));

// ---------------------------------------------------------------- meshing
// f: the field; box: [x0, y0, z0, x1, y1, z1]; h: voxel size. Returns a BufferGeometry (indexed)
export function mesh_sdf(f, box, h) {
  const pad = 2*h;
  const x0 = box[0] - pad, y0 = box[1] - pad, z0 = box[2] - pad;
  const nx = Math.ceil((box[3] + pad - x0)/h) + 1, ny = Math.ceil((box[4] + pad - y0)/h) + 1, nz = Math.ceil((box[5] + pad - z0)/h) + 1;
  const F = new Float32Array(nx*ny*nz);
  const I = (i, j, k) => (k*ny + j)*nx + i;
  // narrow band: sample a lattice 4x coarser first; a fine point is evaluated only when the
  // nearest coarse sample is close to the surface (the fields here are only roughly metric, so
  // the band is generous); elsewhere the coarse value stands in (its sign is all that matters)
  const Q = 4, cq = Q*h, band = cq*2.2;
  const mx = Math.ceil((nx - 1)/Q) + 1, my = Math.ceil((ny - 1)/Q) + 1, mz = Math.ceil((nz - 1)/Q) + 1;
  const Cs = new Float32Array(mx*my*mz);
  for (let k = 0; k < mz; k++) for (let j = 0; j < my; j++) for (let i = 0; i < mx; i++) Cs[(k*my + j)*mx + i] = f(x0 + i*cq, y0 + j*cq, z0 + k*cq);
  for (let k = 0; k < nz; k++) for (let j = 0; j < ny; j++) for (let i = 0; i < nx; i++) {
    const c = Cs[(Math.min(mz - 1, Math.round(k/Q))*my + Math.min(my - 1, Math.round(j/Q)))*mx + Math.min(mx - 1, Math.round(i/Q))];
    F[I(i, j, k)] = Math.abs(c) > band ? c : f(x0 + i*h, y0 + j*h, z0 + k*h);
  }
  const vid = new Int32Array((nx - 1)*(ny - 1)*(nz - 1)).fill(-1);
  const C = (i, j, k) => (k*(ny - 1) + j)*(nx - 1) + i;
  const pos = [];
  const EDGES = [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]];
  const corner = new Float32Array(8);
  for (let k = 0; k < nz - 1; k++) for (let j = 0; j < ny - 1; j++) for (let i = 0; i < nx - 1; i++) {
    let mask = 0;
    for (let c = 0; c < 8; c++) {
      const v = F[I(i + (c & 1), j + ((c >> 1) & 1), k + ((c >> 2) & 1))];
      corner[c] = v;
      if (v < 0) mask |= 1 << c;
    }
    if (mask === 0 || mask === 255) continue;
    let sx = 0, sy = 0, sz = 0, n = 0;
    for (const [a, b] of EDGES) {
      const va = corner[a], vb = corner[b];
      if ((va < 0) === (vb < 0)) continue;
      const t = va/(va - vb);
      sx += (a & 1) + (((b & 1) - (a & 1))*t);
      sy += ((a >> 1) & 1) + ((((b >> 1) & 1) - ((a >> 1) & 1))*t);
      sz += ((a >> 2) & 1) + ((((b >> 2) & 1) - ((a >> 2) & 1))*t);
      n++;
    }
    vid[C(i, j, k)] = pos.length/3;
    pos.push(x0 + (i + sx/n)*h, y0 + (j + sy/n)*h, z0 + (k + sz/n)*h);
  }
  const idx = [];
  const quad = (a, b, c, d, flip) => {
    if (a < 0 || b < 0 || c < 0 || d < 0) return;
    if (flip) idx.push(a, c, b, a, d, c); else idx.push(a, b, c, a, c, d);
  };
  for (let k = 1; k < nz - 1; k++) for (let j = 1; j < ny - 1; j++) for (let i = 1; i < nx - 1; i++) {
    const v0 = F[I(i, j, k)] < 0;
    // x edge (i,j,k)-(i+1,j,k): cells around it share j-1..j, k-1..k
    if (i < nx - 1 && v0 !== (F[I(i + 1, j, k)] < 0)) quad(vid[C(i, j - 1, k - 1)], vid[C(i, j, k - 1)], vid[C(i, j, k)], vid[C(i, j - 1, k)], !v0);
    if (j < ny - 1 && v0 !== (F[I(i, j + 1, k)] < 0)) quad(vid[C(i - 1, j, k - 1)], vid[C(i - 1, j, k)], vid[C(i, j, k)], vid[C(i, j, k - 1)], !v0);
    if (k < nz - 1 && v0 !== (F[I(i, j, k + 1)] < 0)) quad(vid[C(i - 1, j - 1, k)], vid[C(i, j - 1, k)], vid[C(i, j, k)], vid[C(i - 1, j, k)], !v0);
  }
  const g = new THREE.BufferGeometry();
  const P = new Float32Array(pos);
  g.setAttribute('position', new THREE.BufferAttribute(P, 3));
  g.setIndex(idx);
  // normals from the field's gradient
  const N = new Float32Array(P.length), e = h*0.5;
  for (let v = 0; v < P.length; v += 3) {
    const x = P[v], y = P[v + 1], z = P[v + 2];
    let gx = f(x + e, y, z) - f(x - e, y, z), gy = f(x, y + e, z) - f(x, y - e, z), gz = f(x, y, z + e) - f(x, y, z - e);
    const l = Math.hypot(gx, gy, gz) || 1;
    N[v] = gx/l; N[v + 1] = gy/l; N[v + 2] = gz/l;
  }
  g.setAttribute('normal', new THREE.BufferAttribute(N, 3));
  return g;
}

// ---------------------------------------------------------------- swept tubes
// A tube along a polyline of points [[x,y,z], ...] with an elliptical section (w across the
// curve's `up` side, t across the other), radii scaled per point by prof(s) (s = 0..1).
// `up` is a fixed direction the section's wide axis aligns to (a rib's flat side faces it).
export function sweep(pts, w, t, prof, up, sides = 8) {
  const n = pts.length;
  const P = pts.map(p => new THREE.Vector3(p[0], p[1], p[2]));
  const pos = [], nor = [], idx = [];
  const U = new THREE.Vector3(...up).normalize();
  for (let i = 0; i < n; i++) {
    const T = new THREE.Vector3().subVectors(P[Math.min(n - 1, i + 1)], P[Math.max(0, i - 1)]).normalize();
    const B = new THREE.Vector3().crossVectors(T, U).normalize();
    const Nn = new THREE.Vector3().crossVectors(B, T).normalize();
    const s = i/(n - 1), k = prof(s);
    for (let j = 0; j < sides; j++) {
      const a = j/sides*Math.PI*2;
      const ca = Math.cos(a), sa = Math.sin(a);
      const ox = Nn.x*ca*w*k + B.x*sa*t*k, oy = Nn.y*ca*w*k + B.y*sa*t*k, oz = Nn.z*ca*w*k + B.z*sa*t*k;
      pos.push(P[i].x + ox, P[i].y + oy, P[i].z + oz);
      const nx = Nn.x*ca/w + B.x*sa/t, ny = Nn.y*ca/w + B.y*sa/t, nz = Nn.z*ca/w + B.z*sa/t;
      const l = Math.hypot(nx, ny, nz) || 1;
      nor.push(nx/l, ny/l, nz/l);
    }
  }
  for (let i = 0; i < n - 1; i++) for (let j = 0; j < sides; j++) {
    const a = i*sides + j, b = i*sides + (j + 1)%sides, c = (i + 1)*sides + (j + 1)%sides, d = (i + 1)*sides + j;
    idx.push(a, b, c, a, c, d);
  }
  // caps
  for (const end of [0, n - 1]) {
    const c = pos.length/3;
    const p = P[end], T = new THREE.Vector3().subVectors(P[end === 0 ? 1 : n - 1], P[end === 0 ? 0 : n - 2]).normalize();
    pos.push(p.x, p.y, p.z); nor.push(end === 0 ? -T.x : T.x, end === 0 ? -T.y : T.y, end === 0 ? -T.z : T.z);
    for (let j = 0; j < sides; j++) {
      const a = end*sides + j, b = end*sides + (j + 1)%sides;
      if (end === 0) idx.push(c, b, a); else idx.push(c, a, b);
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  g.setIndex(idx);
  return g;
}
