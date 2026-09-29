// item_hand.js -- round 29: the LIFT AND BURST power's object (owner: the Hand of Sabazios "looks
// cool", but "the model doesn't need to be that hand specifically though, just pinky + the other
// finger curled, index and the other pointing forward, thumb outwards"). A votive hand: a right
// hand raised palm out in that gesture, on the cuff it stands on, cast in bronze gone green (the
// reference's patina, the bronze worn through where hands would rub it: knuckles, fingertips,
// the thumb), without the Sabazios hand's symbols. M: BRONZE (default) / BONE.
import * as THREE from 'three';
import { mesh_sdf, smin, cone, ellipsoid, rbox } from 'game/sdf.js';
import { fbm3, cells3, sstep, vertex_mr } from 'game/shape_noise.js';

export const HAND_MATS = ['BRONZE', 'BONE'];

// ---------------------------------------------------------------- the pose (m; palm faces +z,
// fingers +y, the thumb toward -x: a right hand seen from its palm)
const V = (x, y, z) => new THREE.Vector3(x, y, z);
function finger(base, lens, radii, spread, flex) {
  // joints along the finger: each segment turns by its flex (toward the palm, +z) from the last
  const pts = [base.clone()], rad = radii.slice();
  let th = 0;
  for (let i = 0; i < 3; i++) {
    th += flex[i];
    const d = V(Math.sin(spread)*Math.cos(th), Math.cos(spread)*Math.cos(th), Math.sin(th)).normalize();
    pts.push(pts[i].clone().addScaledVector(d, lens[i]));
  }
  return { pts, rad };
}
const FINGERS = [
  // index, middle: pointing up (a little natural curve); ring, pinky: curled into the palm
  finger(V(-0.028, 0.096, 0.0), [0.04, 0.024, 0.02], [0.0112, 0.0102, 0.0092, 0.0075], -0.07, [0.04, 0.07, 0.05]),
  finger(V(-0.007, 0.1, 0.0), [0.044, 0.027, 0.021], [0.0116, 0.0106, 0.0095, 0.0077], 0.02, [0.03, 0.06, 0.05]),
  finger(V(0.014, 0.097, 0.0), [0.041, 0.026, 0.02], [0.0108, 0.0099, 0.0089, 0.0073], 0.08, [1.3, 1.65, 1.15]),
  finger(V(0.033, 0.09, -0.001), [0.032, 0.02, 0.018], [0.0098, 0.009, 0.0081, 0.0067], 0.16, [1.25, 1.7, 1.1]),
];
// the thumb: out to the side and up
const THUMB = (() => {
  const p0 = V(-0.02, 0.022, 0.005);
  const d = [V(-0.8, 0.52, 0.3), V(-0.55, 0.8, 0.2), V(-0.3, 0.95, 0.12)].map(v => v.normalize());
  const L = [0.042, 0.03, 0.026];
  const pts = [p0];
  for (let i = 0; i < 3; i++) pts.push(pts[i].clone().addScaledVector(d[i], L[i]));
  return { pts, rad: [0.0175, 0.0135, 0.0118, 0.0088] };
})();

function chain_d(x, y, z, f, k) {
  let d = Infinity;
  const P = f.pts, Rr = f.rad;
  for (let i = 0; i < P.length - 1; i++) {
    const a = P[i], b = P[i + 1];
    d = smin(d, cone(x, y, z, a.x, a.y, a.z, b.x, b.y, b.z, Rr[i], Rr[i + 1]), k);
  }
  // knuckles a little fuller than the bones between them
  for (let i = 1; i < P.length - 1; i++) d = smin(d, Math.hypot(x - P[i].x, y - P[i].y, z - P[i].z) - Rr[i]*1.07, 0.003);
  return d;
}

function body(x, y, z) {
  // the palm and its pads
  let d = rbox(x, y, z, 0.004, 0.052, 0.0, 0.045, 0.049, 0.014, 0.013);
  d = smin(d, ellipsoid(x, y, z, -0.026, 0.03, 0.008, 0.023, 0.03, 0.016), 0.01);        // the ball of the thumb
  d = smin(d, ellipsoid(x, y, z, 0.033, 0.037, 0.005, 0.016, 0.034, 0.013), 0.01);        // the heel of the hand
  // fingers, thumb
  for (const f of FINGERS) d = smin(d, chain_d(x, y, z, f, 0.004), 0.009);
  d = smin(d, chain_d(x, y, z, THUMB, 0.004), 0.012);
  // the wrist (flatter than round) into the cuff it stands on
  const wx = Math.hypot((x - 0.004)/1.35, z + 0.001) - 0.024, wy = Math.max(y - 0.012, -0.05 - y);
  d = smin(d, Math.min(Math.max(wx, wy), 0) + Math.hypot(Math.max(wx, 0), Math.max(wy, 0)), 0.012);
  // the cuff: a short flared sleeve with a lip at the top and a foot
  const cr = Math.hypot(x - 0.004, z + 0.001);
  const t = Math.min(1, Math.max(0, (-0.045 - y)/0.05));
  const R = 0.04 + 0.01*t*t;
  let cuff = Math.max(cr - R, y - -0.045, -0.097 - y);
  cuff = smin(cuff, Math.hypot(cr - 0.042, y + 0.047) - 0.0055, 0.002);    // the lip
  cuff = Math.min(cuff, Math.max(cr - 0.054, y + 0.09, -0.099 - y));        // the foot
  d = smin(d, cuff, 0.004);
  return d;
}
// cast and corroded: a pitted, lumpy surface
function field(x, y, z) {
  const d = body(x, y, z);
  if (d > 0.01) return d;
  const pit = cells3(x*260, y*260, z*260, 61);
  return d + (fbm3(x*160, y*160, z*160, 63, 3) - 0.5)*0.0012 + sstep(0.22, 0.05, pit.d1)*0.00045;
}

let CACHE = null;
function geometry() {
  if (CACHE) return CACHE;
  const g = mesh_sdf(field, [-0.095, -0.105, -0.045, 0.07, 0.215, 0.075], 0.00115);
  const P = g.attributes.position, N = g.attributes.normal, n = P.count;
  const cols = [new Float32Array(n*3), new Float32Array(n*3)], mrs = [new Float32Array(n*2), new Float32Array(n*2)];
  for (let i = 0; i < n; i++) {
    const x = P.getX(i), y = P.getY(i), z = P.getZ(i), nx = N.getX(i), ny = N.getY(i), nz = N.getZ(i);
    // how open this point is: a crevice has the hand close by in front of it
    const o1 = Math.min(1, Math.max(0, body(x + nx*0.004, y + ny*0.004, z + nz*0.004)/0.004));
    const o2 = Math.min(1, Math.max(0, body(x + nx*0.012, y + ny*0.012, z + nz*0.012)/0.012));
    const open = o1*0.5 + o2*0.5;
    const nz_ = fbm3(x*90, y*90, z*90, 67, 3);
    // BRONZE: patina over nearly everything, bronze where it is rubbed, black in the deepest
    const worn = sstep(0.95, 1.0, open)*sstep(0.55, 0.7, nz_)*(y > 0.12 ? 1.3 : 0.6);
    const tone = fbm3(x*40, y*40, z*40, 69, 3);
    let r = 0.11 + 0.09*tone, gg = 0.17 + 0.08*tone, b = 0.14 + 0.05*(1 - tone);
    if (nz_ > 0.64) { r += 0.07; gg += 0.08; b += 0.05; }           // paler powdery crust
    const dark = sstep(0.6, 0.15, open);
    r *= 1 - 0.75*dark; gg *= 1 - 0.7*dark; b *= 1 - 0.72*dark;
    const w = Math.min(1, worn);
    cols[0][i*3] = r + (0.36 - r)*w; cols[0][i*3 + 1] = gg + (0.25 - gg)*w; cols[0][i*3 + 2] = b + (0.13 - b)*w;
    mrs[0][i*2] = 0.9*w; mrs[0][i*2 + 1] = 0.85 - 0.5*w;
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
