// item_hand.js -- the LIFT AND BURST power's object (owner, round 28: the Hand of Sabazios "looks
// cool", but "the model doesn't need to be that hand specifically though, just pinky + the other
// finger curled, index and the other pointing forward, thumb outwards"). A votive hand: a right
// hand raised palm out in that gesture, on the cuff it stands on, cast in bronze gone green (the
// patina, the bronze worn through at a few high points), without the Sabazios hand's symbols.
// M: BRONZE (default) / BONE.
//
// Round 30 (owner: "more realistic and aesthetic, the current one is too square on the upper
// side (inverse of the palm) and the fingers have an unnatural thickness to them"): built from
// the bones out. The back of the hand is the four metacarpals blended under one skin (an arch
// across, the knuckles a ridge at the top, narrowing to the wrist), not a box; the palm is its
// pads (the ball of the thumb, the heel, the pads under the fingers) with its creases; fingers
// are flatter than deep, a real finger's width (~1.8 cm at the base), fuller at the joints and a
// little narrower between them, with pads and nails at their tips; the cast surface finer.
import * as THREE from 'three';
import { mesh_sdf, smin, cone, ellipsoid } from 'game/sdf.js';
import { fbm3, cells3, sstep, vertex_mr } from 'game/shape_noise.js';

export const HAND_MATS = ['BRONZE', 'BONE'];

// ---------------------------------------------------------------- the pose (m; palm faces +z,
// fingers +y, the thumb toward -x: a right hand seen from its palm)
const V = (x, y, z) => new THREE.Vector3(x, y, z);

// a finger: joints along it, each segment turned by its flex toward the palm (+z); per joint a
// half-width (across) and half-depth (palm to back); each segment knows its own frame
function finger(base, lens, W, D, spread, flex) {
  const pts = [base.clone()], seg = [];
  let th = 0;
  for (let i = 0; i < lens.length; i++) {
    th += flex[i];
    const d = V(Math.sin(spread)*Math.cos(th), Math.cos(spread)*Math.cos(th), Math.sin(th)).normalize();
    const n = V(-Math.sin(spread)*Math.sin(th), -Math.cos(spread)*Math.sin(th), Math.cos(th)).normalize();   // toward the palm side
    const s = new THREE.Vector3().crossVectors(d, n).normalize();
    pts.push(pts[i].clone().addScaledVector(d, lens[i]));
    seg.push({ d, n, s });
  }
  return { pts, W, D, seg };
}
const FINGERS = [
  // index, middle: raised (a little natural curve); ring, pinky: curled into the palm
  finger(V(-0.029, 0.093, -0.002), [0.04, 0.024, 0.019], [0.0092, 0.0085, 0.0077, 0.0064], [0.0079, 0.0071, 0.0063, 0.0052], -0.07, [0.05, 0.08, 0.06]),
  finger(V(-0.008, 0.098, -0.002), [0.045, 0.028, 0.02], [0.0095, 0.0088, 0.0079, 0.0066], [0.0082, 0.0074, 0.0065, 0.0054], 0.02, [0.04, 0.07, 0.06]),
  finger(V(0.013, 0.094, -0.002), [0.042, 0.026, 0.019], [0.009, 0.0083, 0.0075, 0.0063], [0.0077, 0.007, 0.0062, 0.0051], 0.09, [1.3, 1.62, 1.12]),
  finger(V(0.032, 0.085, -0.003), [0.033, 0.019, 0.018], [0.0079, 0.0073, 0.0066, 0.0056], [0.0068, 0.0062, 0.0056, 0.0046], 0.17, [1.22, 1.66, 1.08]),
];
// the thumb: from the wrist's side out and up; its metacarpal is part of it
const THUMB = (() => {
  const p0 = V(-0.017, 0.012, 0.003);
  const dirs = [V(-0.75, 0.55, 0.36), V(-0.5, 0.82, 0.25), V(-0.3, 0.94, 0.15)].map(v => v.normalize());
  const L = [0.042, 0.03, 0.026];
  const pts = [p0], seg = [];
  for (let i = 0; i < 3; i++) {
    pts.push(pts[i].clone().addScaledVector(dirs[i], L[i]));
    // the thumb's pad faces across the palm (+x, +z)
    const n = V(0.55, 0.0, 0.85).addScaledVector(dirs[i], -V(0.55, 0, 0.85).dot(dirs[i])).normalize();
    seg.push({ d: dirs[i], n, s: new THREE.Vector3().crossVectors(dirs[i], n).normalize() });
  }
  return { pts, W: [0.0128, 0.0109, 0.0099, 0.0083], D: [0.0115, 0.0096, 0.0086, 0.0071], seg };
})();
// the metacarpals: from the wrist to each knuckle; the middle two sit further back, so the back
// of the hand arches across
const META = [
  [V(-0.011, 0.012, -0.005), V(-0.029, 0.092, -0.004)],
  [V(-0.002, 0.014, -0.008), V(-0.008, 0.097, -0.007)],
  [V(0.008, 0.013, -0.0075), V(0.013, 0.093, -0.0065)],
  [V(0.017, 0.011, -0.005), V(0.032, 0.084, -0.004)],
];

// distance to an elliptical capsule segment (half-widths across / deep, blended along it)
function oval_seg(x, y, z, a, b, sg, w0, w1, d0, d1) {
  const px = x - a.x, py = y - a.y, pz = z - a.z;
  const L = a.distanceTo(b);
  const t = (px*sg.d.x + py*sg.d.y + pz*sg.d.z)/L;
  const tc = t < 0 ? 0 : t > 1 ? 1 : t;
  const ax = px - sg.d.x*tc*L, ay = py - sg.d.y*tc*L, az = pz - sg.d.z*tc*L;
  const u = ax*sg.s.x + ay*sg.s.y + az*sg.s.z, v = ax*sg.n.x + ay*sg.n.y + az*sg.n.z;
  const w = w0 + (w1 - w0)*tc, d = d0 + (d1 - d0)*tc, mr = Math.min(w, d);
  // rounded (ellipsoidal) ends, so segments meeting at a joint join smoothly without a blend
  const along = t < 0 ? -t*L : t > 1 ? (t - 1)*L : 0;
  return (Math.hypot(u/w, v/d, along/mr) - 1)*mr;
}
function digit(x, y, z, f) {
  let dd = Infinity;
  // one smooth tapering finger through its joints (round 30's first pass, knuckle knobs and a
  // waist in each bone, read as a jointed stick)
  // (a blend between segments swells a ring at every joint: they are simply joined)
  for (let i = 0; i < f.seg.length; i++) dd = Math.min(dd, oval_seg(x, y, z, f.pts[i], f.pts[i + 1], f.seg[i], f.W[i], f.W[i + 1], f.D[i], f.D[i + 1]));
  // the fingertip's pad (fuller on the palm side) and a nail on the back
  const tip = f.pts[f.pts.length - 1], sg = f.seg[f.seg.length - 1], w = f.W[f.W.length - 1];
  const pad = tip.clone().addScaledVector(sg.d, -w*0.9).addScaledVector(sg.n, w*0.28);
  dd = smin(dd, Math.hypot(x - pad.x, y - pad.y, z - pad.z) - w*0.84, 0.004);
  const nc = tip.clone().addScaledVector(sg.d, -w*1.25).addScaledVector(sg.n, -f.D[f.D.length - 1]*0.72);
  const nx = x - nc.x, ny = y - nc.y, nz = z - nc.z;
  const nu = nx*sg.s.x + ny*sg.s.y + nz*sg.s.z, nv = nx*sg.n.x + ny*sg.n.y + nz*sg.n.z, nw = nx*sg.d.x + ny*sg.d.y + nz*sg.d.z;
  const nail = Math.hypot(nu/(w*0.7), (nv + 0.0004)/(w*0.22), nw/(w*1.05)) - 1;
  dd = smin(dd, nail*w*0.22, 0.0008);
  return dd;
}

function body(x, y, z) {
  // the back: the metacarpals under one skin
  let d = Infinity;
  for (const [a, b] of META) d = smin(d, cone(x, y, z, a.x, a.y, a.z, b.x, b.y, b.z, 0.0078, 0.0088), 0.016);
  // the knuckles' ridge: the metacarpals' heads
  for (const [, b] of META) d = smin(d, Math.hypot(x - b.x, y - b.y + 0.002, z - b.z + 0.0015) - 0.0098, 0.006);
  // the palm's pads: the ball of the thumb, the heel of the hand, the pad under the fingers
  d = smin(d, ellipsoid(x, y, z, 0.003, 0.052, 0.003, 0.036, 0.043, 0.0115), 0.012);
  d = smin(d, ellipsoid(x, y, z, -0.021, 0.028, 0.008, 0.017, 0.026, 0.0135), 0.012);
  d = smin(d, ellipsoid(x, y, z, 0.026, 0.034, 0.005, 0.013, 0.03, 0.0105), 0.012);
  d = smin(d, ellipsoid(x, y, z, 0.002, 0.087, 0.006, 0.036, 0.009, 0.008), 0.008);
  // fingers, thumb
  for (const f of FINGERS) d = smin(d, digit(x, y, z, f), 0.0075);
  d = smin(d, digit(x, y, z, THUMB), 0.011);
  // the palm's creases (shallow grooves on its face)
  if (z > 0 && y > 0.02 && y < 0.1) {
    const crease = (px, py, qx, qy, depth) => {
      const dx = qx - px, dy = qy - py, L2 = dx*dx + dy*dy;
      const t = Math.max(0, Math.min(1, ((x - px)*dx + (y - py)*dy)/L2));
      return depth*sstep(0.0016, 0.0, Math.hypot(x - px - dx*t, y - py - dy*t))*Math.sin(Math.PI*t);
    };
    d += crease(-0.03, 0.066, 0.035, 0.078, 0.0009) + crease(-0.033, 0.058, 0.02, 0.05, 0.0008) + crease(-0.012, 0.018, -0.028, 0.07, 0.0007);
  }
  // the wrist (wider than deep), rounding down into the cuff
  const wx = Math.hypot((x - 0.001)/1.42, (z + 0.001)) - 0.0195, wy = Math.max(y - 0.018, -0.03 - y);
  d = smin(d, Math.min(Math.max(wx, wy), 0) + Math.hypot(Math.max(wx, 0), Math.max(wy, 0)), 0.014);
  // the cuff it stands on: a smooth sleeve flaring to a rounded foot, grown out of the wrist
  const cr = Math.hypot((x - 0.001)/1.12, z + 0.001);
  const t = Math.min(1, Math.max(0, (-0.024 - y)/0.05));
  const R = 0.026 + 0.01*t*t;
  let cuff = Math.max(cr - R, y + 0.024, -0.075 - y);
  cuff = smin(cuff, Math.hypot(cr - 0.035, y + 0.072) - 0.0042, 0.004);    // the foot's rim
  d = smin(d, cuff, 0.012);
  return d;
}
// cast, and worn by time: a fine pitting and a faint unevenness (finer than round 29's lumps)
function field(x, y, z) {
  const d = body(x, y, z);
  if (d > 0.01) return d;
  const pit = cells3(x*300, y*300, z*300, 61);
  return d + (fbm3(x*140, y*140, z*140, 63, 3) - 0.5)*0.0005 + sstep(0.2, 0.04, pit.d1)*0.00028;
}

let CACHE = null;
function geometry() {
  if (CACHE) return CACHE;
  const g = mesh_sdf(field, [-0.09, -0.085, -0.04, 0.065, 0.2, 0.065], 0.001);
  const P = g.attributes.position, N = g.attributes.normal, n = P.count;
  const cols = [new Float32Array(n*3), new Float32Array(n*3)], mrs = [new Float32Array(n*2), new Float32Array(n*2)];
  for (let i = 0; i < n; i++) {
    const x = P.getX(i), y = P.getY(i), z = P.getZ(i), nx = N.getX(i), ny = N.getY(i), nz = N.getZ(i);
    // how open this point is: a crevice has the hand close by in front of it
    const o1 = Math.min(1, Math.max(0, body(x + nx*0.003, y + ny*0.003, z + nz*0.003)/0.003));
    const o2 = Math.min(1, Math.max(0, body(x + nx*0.01, y + ny*0.01, z + nz*0.01)/0.01));
    const open = o1*0.5 + o2*0.5;
    const nz_ = fbm3(x*90, y*90, z*90, 67, 3);
    // BRONZE: patina over nearly everything, bronze where it is rubbed, dark in the deepest
    const worn = sstep(0.95, 1.0, open)*sstep(0.62, 0.74, nz_)*(y > 0.165 ? 1.0 : 0.45);
    const tone = fbm3(x*40, y*40, z*40, 69, 3);
    let r = 0.11 + 0.09*tone, gg = 0.17 + 0.08*tone, b = 0.14 + 0.05*(1 - tone);
    if (nz_ > 0.64) { r += 0.07; gg += 0.08; b += 0.05; }           // paler powdery crust
    const dark = sstep(0.6, 0.15, open);
    r *= 1 - 0.75*dark; gg *= 1 - 0.7*dark; b *= 1 - 0.72*dark;
    const w = Math.min(1, worn);
    cols[0][i*3] = r + (0.36 - r)*w; cols[0][i*3 + 1] = gg + (0.25 - gg)*w; cols[0][i*3 + 2] = b + (0.13 - b)*w;
    mrs[0][i*2] = 0.9*w; mrs[0][i*2 + 1] = 0.8 - 0.45*w;
    // BONE: pale, yellowed in the hollows
    const bv = 0.62 + 0.14*tone;
    cols[1][i*3] = bv*(1 - 0.55*dark); cols[1][i*3 + 1] = bv*0.93*(1 - 0.6*dark); cols[1][i*3 + 2] = bv*0.8*(1 - 0.65*dark);
    mrs[1][i*2] = 0; mrs[1][i*2 + 1] = 0.55;
  }
  g.userData.cols = cols.map(a => new THREE.BufferAttribute(a, 3));
  g.userData.mrs = mrs.map(a => new THREE.BufferAttribute(a, 2));
  g.setAttribute('color', g.userData.cols[0]);
  g.setAttribute('aMR', g.userData.mrs[0]);
  CACHE = g;
  return g;
}

export function set_hand_material(i) {
  const g = geometry();
  g.setAttribute('color', g.userData.cols[i]);
  g.setAttribute('aMR', g.userData.mrs[i]);
}

export function build_hand(ctx = {}, opts = {}) {
  const lit = ctx.lit || (m => m);
  set_hand_material(opts.hand_mat ?? 0);
  const mat = lit(vertex_mr(new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.8, metalness: 0, envMapIntensity: ctx.env_i ?? 1, side: THREE.DoubleSide })));
  const m = new THREE.Mesh(geometry(), mat);
  m.castShadow = true;
  const g = new THREE.Group();
  g.add(m);
  return g;
}
