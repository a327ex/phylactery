// skeleton.js -- a realistic human skeleton, sculpted (round 3; owner: "the lich model itself
// should be way more realistic"; target: Astra's lich 07, reference/astra-r02/lich/07.png).
//
// Every bone is built in the frame of the joint it hangs from (see RIG below), so the lich can
// be posed by rotating joints. Rounded bones (skull, jaw, pelvis, vertebrae, scapulae, sternum,
// long bones, carpals, tarsals) are signed distance fields meshed by sdf.js; the thin flat ones
// (ribs, costal cartilage, clavicles) are swept tubes with a flattened section.
//
// Units: metres. Frame: +y up, +z forward (the way the lich faces), s = +1 / -1 for the two
// sides (x). A 1.8 m adult.
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { sphere, ellipsoid, cone, capsule, rbox, chain, smin, smax, sub, mesh_sdf, sweep } from 'game/sdf.js';

const cyl = (x, y, z, cx, cy, cz, r, hh, k) => {
  const dx = Math.hypot(x - cx, z - cz) - r + k, dy = Math.abs(y - cy) - hh + k;
  return Math.min(Math.max(dx, dy), 0) + Math.hypot(Math.max(dx, 0), Math.max(dy, 0)) - k;
};
const lerp = (a, b, t) => a + (b - a)*t;

// ------------------------------------------------------------------ the rig (joint offsets)
// parent-relative positions of every joint; the skeleton hangs from them
export const RIG = {
  spine: [0, 0.10, -0.062],        // from the pelvis (hip-joint line) to the top of the sacrum
  chest: [0, 0.18, 0.0],           // from the spine node to T12
  neck: [0, 0.285, 0.004],         // from the chest node to C7
  head: [0, 0.118, 0.014],         // from the neck node to the atlas
  jaw: [0, 0.004, 0.008],          // from the head node to the jaw hinge
  shoulder: [0.172, 0.248, -0.006],  // from the chest node (x times s)
  elbow: [0, -0.305, 0],
  wrist: [0, -0.262, 0.004],
  hip: [0.088, 0, 0],              // from the pelvis (x times s)
  knee: [-0.03, -0.44, 0.004],     // the femur angles in: knees closer than hips (x times s)
  ankle: [0, -0.405, -0.004],
};

// ------------------------------------------------------------------ bone fields
function skull(x, y, z) {
  // proportions from the foramen magnum (origin): orbits ~4 cm above it and ~8 cm in front,
  // the vertex ~14 cm up, the occiput ~10 cm behind
  let d = ellipsoid(x, y, z, 0, 0.072, -0.016, 0.067, 0.07, 0.097);                      // cranium
  d = smin(d, ellipsoid(x, y, z, 0, 0.078, 0.03, 0.056, 0.052, 0.06), 0.018);             // forehead
  d = smin(d, ellipsoid(x, y, z, 0, -0.008, 0.064, 0.037, 0.036, 0.036), 0.014);        // maxilla, taller
  for (const s of [-1, 1]) {
    d = smin(d, ellipsoid(x, y, z, s*0.05, 0.018, 0.064, 0.02, 0.016, 0.019), 0.009);   // cheekbone
    d = smin(d, capsule(x, y, z, s*0.055, 0.018, 0.058, s*0.064, 0.022, 0.0, 0.006), 0.007);  // arch
    d = smin(d, ellipsoid(x, y, z, s*0.056, -0.012, -0.024, 0.011, 0.016, 0.013), 0.009); // mastoid
  }
  d = smin(d, capsule(x, y, z, -0.045, 0.058, 0.08, 0.045, 0.058, 0.08, 0.0095), 0.012);  // brow ridge
  for (const s of [-1, 1]) {
    d = smax(d, -ellipsoid(x, y, z, s*0.032, 0.037, 0.094, 0.0165, 0.0155, 0.03), 0.004);  // orbit: smaller, deep
    d = smax(d, -ellipsoid(x, y, z, s*0.073, 0.045, 0.018, 0.011, 0.02, 0.026), 0.009);  // temple
  }
  d = smax(d, -ellipsoid(x, y, z, 0, 0.004, 0.099, 0.0095, 0.018, 0.02), 0.003);       // nasal opening
  d = smax(d, -ellipsoid(x, y, z, 0, -0.045, -0.03, 0.05, 0.03, 0.05), 0.012);         // skull base
  for (let i = 0; i < 12; i++) {                                                        // upper teeth
    const a = lerp(-1.25, 1.25, i/11);
    const tx = Math.sin(a)*0.033, tz = 0.052 + Math.cos(a)*0.035;
    d = smin(d, capsule(x, y, z, tx, -0.03, tz, tx, -0.043, tz, 0.0042 - Math.abs(a)*0.0006), 0.002);
  }
  return d;
}
function mandible(x, y, z) {
  // jaw-hinge frame: condyles at the origin's sides, the chin ~7.5 cm down-forward
  const P = [];
  for (let i = 0; i <= 10; i++) {
    const a = lerp(-1.5, 1.5, i/10);
    P.push([Math.sin(a)*0.046, -0.072 + Math.abs(Math.sin(a))*0.01, 0.018 + Math.cos(a)*0.05, 0.0088]);
  }
  let d = chain(x, y, z, P, 0.006);
  for (const s of [-1, 1]) {
    d = smin(d, cone(x, y, z, s*0.046, -0.066, 0.004, s*0.05, -0.004, -0.004, 0.011, 0.008), 0.008);   // ramus
    d = smin(d, sphere(x, y, z, s*0.05, -0.002, -0.005, 0.0075), 0.004);                 // condyle
    d = smin(d, cone(x, y, z, s*0.049, -0.03, 0.004, s*0.046, 0.002, 0.016, 0.006, 0.003), 0.005);   // coronoid
  }
  d = smin(d, ellipsoid(x, y, z, 0, -0.08, 0.064, 0.014, 0.012, 0.009), 0.008);           // chin
  for (let i = 0; i < 12; i++) {                                                         // lower teeth
    const a = lerp(-1.2, 1.2, i/11);
    const tx = Math.sin(a)*0.039, tz = 0.018 + Math.cos(a)*0.044;
    d = smin(d, capsule(x, y, z, tx, -0.061, tz, tx, -0.049, tz, 0.0042), 0.002);
  }
  return d;
}
// a vertebra at height yc, depth zc: body, pedicles, spinous and transverse processes
function vertebra(x, y, z, yc, zc, R, hh, spL, spDrop, trL) {
  let d = cyl(x, y, z, 0, yc, zc + R*0.1, R, hh, hh*0.6);
  d = smin(d, capsule(x, y, z, -R*0.5, yc + hh*0.3, zc - R*0.8, R*0.5, yc + hh*0.3, zc - R*0.8, R*0.28), R*0.3);
  d = smin(d, cone(x, y, z, 0, yc + hh*0.3, zc - R*0.9, 0, yc - spDrop, zc - R - spL, R*0.32, R*0.2), R*0.25);
  for (const s of [-1, 1]) d = smin(d, cone(x, y, z, s*R*0.5, yc + hh*0.4, zc - R*0.8, s*(R*0.5 + trL), yc + hh*0.5, zc - R*0.95, R*0.25, R*0.16), R*0.2);
  return d;
}
function pelvis(x, y, z) {
  let d = Infinity;
  for (const s of [-1, 1]) {
    // iliac blade: a thin broad fan facing out and forward, thick at its crest
    const cx = s*0.088, cy = 0.085, cz = -0.012;
    const a = s*0.55, ca = Math.cos(a), sa = Math.sin(a);
    const lx = (x - cx)*ca - (z - cz)*sa, lz = (x - cx)*sa + (z - cz)*ca, ly = y - cy;
    // bent so its edges curl medially: the iliac fossa is a bowl, the gluteal side convex
    let blade = ellipsoid(lx + 3.2*(lz*lz + (ly - 0.01)*(ly - 0.01)), ly, lz, 0, 0, 0, 0.0075, 0.07, 0.078);
    blade = smax(blade, -(ly + 0.045), 0.01);
    d = smin(d, blade, 0.01);
    const crest = [];
    for (let i = 0; i <= 8; i++) {
      const t = lerp(-1.25, 1.25, i/8);
      const px = Math.sin(t)*0.077, py = Math.cos(t)*0.064;
      // the crest traced in the blade's plane, back in pelvis space
      const bend = -3.2*(px*px + (py - 0.014)*(py - 0.014));      // follow the blade's curl
      crest.push([cx + bend*ca + px*sa, cy + py - 0.004, cz - bend*sa + px*ca, 0.0075]);
    }
    d = smin(d, chain(x, y, z, crest, 0.006), 0.008);
    // body of the ilium down to the socket, the socket, the ischium and its tuberosity
    d = smin(d, cone(x, y, z, s*0.084, 0.05, -0.012, s*0.08, 0.004, -0.002, 0.021, 0.024), 0.014);
    const sock = sphere(x, y, z, s*0.078, 0, 0, 0.029);
    d = smin(d, sock, 0.012);
    d = smax(d, -sphere(x, y, z, s*0.093, 0, 0, 0.025), 0.004);                      // acetabulum
    d = smin(d, cone(x, y, z, s*0.072, -0.02, -0.012, s*0.058, -0.085, -0.03, 0.017, 0.014), 0.01);
    // the pelvic ring: arcuate line to the pubis, pubic rami, the obturator loop
    d = smin(d, chain(x, y, z, [[s*0.035, 0.07, -0.062, 0.011], [s*0.062, 0.04, -0.03, 0.01], [s*0.066, 0.008, 0.022, 0.011], [s*0.036, -0.018, 0.058, 0.011], [s*0.012, -0.03, 0.066, 0.012]], 0.006), 0.008);
    d = smin(d, chain(x, y, z, [[s*0.012, -0.056, 0.058, 0.009], [s*0.034, -0.078, 0.028, 0.008], [s*0.056, -0.088, -0.018, 0.011]], 0.005), 0.006);
    d = smin(d, capsule(x, y, z, s*0.012, -0.03, 0.066, s*0.012, -0.058, 0.058, 0.01), 0.006);
  }
  // sacrum: a curved wedge between the blades at the back, and the coccyx
  const sac = [];
  for (let i = 0; i <= 5; i++) { const t = i/5; sac.push([0, lerp(0.1, -0.02, t), -0.066 - Math.sin(t*2.6)*0.016 + t*0.01, lerp(0.034, 0.012, t)]); }
  let sd = chain(x, y, z, sac, 0.01);
  sd = smax(sd, Math.abs(z + 0.07 + (y - 0.04)*0.25) - 0.022, 0.008);          // flatten front-to-back
  d = smin(d, sd, 0.012);
  d = smin(d, chain(x, y, z, [[0, -0.02, -0.06, 0.009], [0, -0.042, -0.05, 0.006], [0, -0.056, -0.038, 0.004]], 0.003), 0.004);
  return d;
}
// long bones, each hanging from its joint (local y down)
function humerus(x, y, z, s) {
  let d = sphere(x, y, z, -s*0.006, -0.012, -0.006, 0.024);
  d = smin(d, sphere(x, y, z, s*0.012, -0.018, 0.004, 0.016), 0.01);                   // tubercles
  d = smin(d, chain(x, y, z, [[0, -0.03, 0, 0.014], [s*0.004, -0.1, 0.002, 0.012], [s*0.002, -0.2, 0, 0.010], [0, -0.27, 0, 0.011]], 0.01), 0.012);
  d = smin(d, ellipsoid(x, y, z, 0, -0.288, -0.002, 0.031, 0.012, 0.014), 0.01);          // epicondyles
  d = smin(d, sphere(x, y, z, -s*0.01, -0.298, 0.006, 0.011), 0.006);
  d = smin(d, sphere(x, y, z, s*0.012, -0.297, 0.006, 0.01), 0.006);
  return d;
}
function forearm(x, y, z, s) {
  // ulna (inner, with the olecranon hooked up behind the elbow) and radius (outer)
  let d = cone(x, y, z, -s*0.009, 0.014, -0.012, -s*0.01, -0.03, -0.004, 0.012, 0.011);
  d = smin(d, chain(x, y, z, [[-s*0.01, -0.03, -0.004, 0.0105], [-s*0.011, -0.14, -0.002, 0.008], [-s*0.012, -0.245, 0, 0.0065]], 0.006), 0.008);
  d = smin(d, sphere(x, y, z, -s*0.012, -0.25, 0.0, 0.0085), 0.004);
  let r = cyl(x, y, z, s*0.012, -0.012, 0.004, 0.01, 0.006, 0.003);
  r = smin(r, chain(x, y, z, [[s*0.012, -0.016, 0.004, 0.007], [s*0.016, -0.13, 0.006, 0.0075], [s*0.016, -0.235, 0.006, 0.011], [s*0.012, -0.252, 0.006, 0.013]], 0.006), 0.006);
  return Math.min(d, r);
}
function femur(x, y, z, s) {
  let d = sphere(x, y, z, 0, 0, 0, 0.025);                                             // head
  d = smin(d, cone(x, y, z, 0, 0, 0, s*0.038, -0.036, -0.002, 0.016, 0.018), 0.01);     // neck
  d = smin(d, sphere(x, y, z, s*0.046, -0.028, -0.008, 0.019), 0.012);                   // greater trochanter
  d = smin(d, sphere(x, y, z, s*0.012, -0.065, -0.012, 0.01), 0.008);                    // lesser
  d = smin(d, chain(x, y, z, [[s*0.036, -0.05, -0.002, 0.016], [s*0.022, -0.16, 0.008, 0.0145], [s*0.004, -0.3, 0.008, 0.0145], [-s*0.022, -0.405, 0.0, 0.019]], 0.012), 0.014);
  for (const k of [-1, 1]) d = smin(d, ellipsoid(x, y, z, -s*0.03 + k*0.021, -0.425, -0.006, 0.019, 0.021, 0.028), 0.012);
  return d;
}
function shin(x, y, z, s) {
  let d = ellipsoid(x, y, z, 0, -0.016, -0.002, 0.037, 0.016, 0.03);                    // plateau
  d = smin(d, sphere(x, y, z, 0, -0.05, 0.022, 0.011), 0.01);                            // tuberosity
  d = smin(d, chain(x, y, z, [[0, -0.035, 0.004, 0.019], [0, -0.14, 0.008, 0.0135], [-s*0.002, -0.3, 0.004, 0.012], [-s*0.004, -0.38, 0, 0.016]], 0.012), 0.014);
  d = smin(d, sphere(x, y, z, -s*0.016, -0.397, 0.001, 0.0115), 0.008);                  // medial malleolus
  let f = chain(x, y, z, [[s*0.03, -0.035, -0.012, 0.01], [s*0.03, -0.2, -0.01, 0.0065], [s*0.028, -0.38, -0.008, 0.008]], 0.004);
  f = smin(f, sphere(x, y, z, s*0.029, -0.405, -0.006, 0.011), 0.006);                   // lateral malleolus
  return Math.min(d, f);
}
function patella(x, y, z) { return ellipsoid(x, y, z, 0, 0.018, 0.036, 0.021, 0.025, 0.011); }
function foot(x, y, z, s) {
  let d = ellipsoid(x, y, z, 0, -0.016, 0.0, 0.02, 0.016, 0.022);                        // talus
  d = smin(d, ellipsoid(x, y, z, s*0.004, -0.038, -0.038, 0.017, 0.022, 0.034), 0.012);  // calcaneus
  d = smin(d, ellipsoid(x, y, z, -s*0.004, -0.032, 0.03, 0.028, 0.014, 0.02), 0.01);     // tarsals
  const toes = [[-s*0.022, 1.0], [-s*0.006, 0.82], [s*0.008, 0.78], [s*0.02, 0.72], [s*0.031, 0.64]];
  for (let i = 0; i < 5; i++) {
    const [tx, L] = toes[i], r = i === 0 ? 0.009 : 0.0058;
    const bx = tx*0.8, bz = 0.045;
    const mz = bz + 0.072*L, tz = mz + (i === 0 ? 0.052 : 0.045)*L;
    d = smin(d, chain(x, y, z, [[bx, -0.036, bz, r*1.1], [tx, -0.05, mz, r], [tx, -0.055, mz + 0.01, r*0.95], [tx, -0.056, tz, r*0.75]], 0.004), 0.006);
  }
  return d;
}
function carpals(x, y, z, s) {
  let d = Infinity;
  for (let i = 0; i < 4; i++) for (let row = 0; row < 2; row++) {
    const zz = lerp(0.016, -0.018, i/3), yy = -0.008 - row*0.013;
    d = smin(d, sphere(x, y, z, 0, yy, zz, 0.0082 - row*0.0006), 0.006);
  }
  return d;
}
// fingers: z offsets across the hanging hand (palm toward the body), index at the front
const FINGERS = [
  { z: 0.018, meta: 0.064, ph: [0.04, 0.024, 0.018] },
  { z: 0.005, meta: 0.062, ph: [0.044, 0.027, 0.019] },
  { z: -0.008, meta: 0.058, ph: [0.041, 0.026, 0.018] },
  { z: -0.02, meta: 0.052, ph: [0.033, 0.019, 0.016] },
];

// ------------------------------------------------------------------ ribs (swept)
// chest-node frame. Rib k (0 = first) hangs from thoracic vertebra T(k+1).
const T_Y = k => 0.268 - k*0.0223;                           // thoracic vertebra heights (T1 top)
const T_Z = y => -0.026*Math.sin(Math.PI*y/0.29);            // the thoracic curve (kyphosis)
const RIB = {
  halfw: [0.058, 0.082, 0.098, 0.11, 0.12, 0.127, 0.131, 0.132, 0.128, 0.12, 0.104, 0.086],
  depth: [0.118, 0.148, 0.168, 0.182, 0.192, 0.196, 0.196, 0.188, 0.172, 0.148, 0.098, 0.066],
  drop: [0.028, 0.048, 0.066, 0.082, 0.092, 0.098, 0.102, 0.102, 0.098, 0.088, 0.06, 0.04],
  end: [0.84, 0.86, 0.86, 0.86, 0.85, 0.84, 0.83, 0.79, 0.75, 0.71, 0.55, 0.47],
};
const STERNUM = { top: [0, 0.228, 0.118], bot: [0, 0.07, 0.186] };
const sternum_at = t => [0, lerp(STERNUM.top[1], STERNUM.bot[1], t), lerp(STERNUM.top[2], STERNUM.bot[2], t)];

function rib_points(k, s) {
  const y0 = T_Y(k), z0 = T_Z(y0);
  const hw = RIB.halfw[k], dp = RIB.depth[k], dr = RIB.drop[k];
  const pts = [[s*0.024, y0, z0 - 0.012]];
  const back = 0.035;                                         // the rib's angle, behind the spine
  const N = 18;
  for (let i = 0; i <= N; i++) {
    const th = lerp(0.16, RIB.end[k]*Math.PI, i/N);
    const x = s*hw*Math.sin(th)*(1 - 0.08*Math.sin(th*2));
    const z = z0 - back + (dp*0.5 + back)*(1 - Math.cos(th)) - 0.01;
    const y = y0 - dr*(1 - Math.cos(th))/2;
    pts.push([x, y, z]);
  }
  return pts;
}
function cartilage_points(k, s, rib_end) {
  // ribs 1-7 reach the sternum; 8-10 join the cartilage above; 11-12 float
  if (k >= 10) return null;
  const e = rib_end;
  let tgt;
  if (k < 7) tgt = sternum_at([0.02, 0.1, 0.25, 0.4, 0.55, 0.7, 0.82][k]);
  else tgt = [s*(0.06 - (k - 7)*0.004), T_Y(6) - RIB.drop[6] - 0.012 - (k - 7)*0.018, 0.17 - (k - 7)*0.012];
  const tx = k < 7 ? s*0.016 : tgt[0];
  const pts = [];
  for (let i = 0; i <= 8; i++) {
    const t = i/8;
    // bend upward toward the sternum (the costal margin), more for the lower ribs
    const lift = Math.sin(t*Math.PI*0.5)*(k > 4 ? 0.025 + (k - 4)*0.006 : 0.004);
    pts.push([lerp(e[0], tx, t), lerp(e[1], tgt[1], t) + lift*(1 - t)*0.8, lerp(e[2], tgt[2], t)]);
  }
  return pts;
}

// ------------------------------------------------------------------ build all meshes
// Returns { node_name: [geometries...] } in each node's own frame, plus the finger segments.
export function build_skeleton_geometry(res = 1, grow = 0.0032) {
  // owner, round 3: "the lich is almost invisible ... he should be a bit more solid". At the room
  // camera a real bone is under a pixel wide; every surface is pushed out by `grow` metres.
  const H = h => h*res;
  const GROW = grow;
  const mesh_sdf_g = (f, box, h) => mesh_sdf((x, y, z) => f(x, y, z) - GROW, [box[0] - GROW, box[1] - GROW, box[2] - GROW, box[3] + GROW, box[4] + GROW, box[5] + GROW], h);
  const sweep_g = (pts, w, t, prof, up, sides) => sweep(pts, w + GROW*0.8, t + GROW*0.8, prof, up, sides);
  const G = {};
  const add = (node, g) => { (G[node] = G[node] || []).push(g); };
  // skull and jaw (head / jaw nodes)
  add('head', mesh_sdf_g(skull, [-0.085, -0.06, -0.125, 0.085, 0.155, 0.13], H(0.0028)*0.8));
  add('jaw', mesh_sdf_g(mandible, [-0.065, -0.1, -0.025, 0.065, 0.015, 0.09], H(0.0024)*0.85));
  // spine: lumbar (spine node), thoracic (chest), cervical (neck)
  add('spine', mesh_sdf_g((x, y, z) => {
    let d = Infinity;
    for (let i = 0; i < 5; i++) { const yc = 0.015 + i*0.034; d = Math.min(d, vertebra(x, y, z, yc, 0.014*Math.sin(Math.PI*yc/0.18), 0.021 - i*0.0008, 0.0115, 0.028, 0.004, 0.028)); }
    return d;
  }, [-0.06, -0.01, -0.075, 0.06, 0.2, 0.04], H(0.0024)));
  add('chest', mesh_sdf_g((x, y, z) => {
    let d = Infinity;
    for (let k = 0; k < 12; k++) { const yc = T_Y(k); d = Math.min(d, vertebra(x, y, z, yc, T_Z(yc), 0.0125 + k*0.0006, 0.0085, 0.03, 0.02 - Math.abs(k - 6)*0.001, 0.024)); }
    return d;
  }, [-0.05, -0.03, -0.1, 0.05, 0.29, 0.03], H(0.0022)));
  add('neck', mesh_sdf_g((x, y, z) => {
    let d = Infinity;
    for (let i = 0; i < 7; i++) { const yc = 0.008 + i*0.0165; d = Math.min(d, vertebra(x, y, z, yc, 0.012*Math.sin(Math.PI*yc/0.12), 0.0105 - i*0.0003, 0.006, i === 0 ? 0.03 : 0.014, 0.006, 0.02)); }
    return d;
  }, [-0.045, -0.01, -0.07, 0.045, 0.13, 0.03], H(0.002)));
  // pelvis and sacrum
  add('pelvis', mesh_sdf_g(pelvis, [-0.18, -0.11, -0.12, 0.18, 0.17, 0.09], H(0.0028)*1.15));
  // ribcage: ribs, costal cartilage, sternum, scapulae, clavicles (chest node)
  for (const s of [-1, 1]) for (let k = 0; k < 12; k++) {
    const rp = rib_points(k, s);
    add('chest', sweep_g(rp, 0.0062, 0.0031, t => (t < 0.08 ? 0.75 + t*3 : 1 - Math.max(0, t - 0.7)*0.6), [0, 1, 0], 8));
    const cp = cartilage_points(k, s, rp[rp.length - 1]);
    if (cp) add('chest', sweep_g(cp, 0.0048, 0.0028, () => 1, [0, 1, 0], 6));
  }
  add('chest', mesh_sdf_g((x, y, z) => {
    // sternum: manubrium, body, xiphoid, tilted with the chest
    let d = Infinity;
    const P = [0, 0.08, 0.3, 0.55, 0.8, 0.95, 1.05].map(t => { const p = sternum_at(Math.min(t, 1)); return [p[0], p[1] - (t > 1 ? 0.012 : 0), p[2] + (t > 1 ? 0.005 : 0), t < 0.15 ? 0.022 : t > 1 ? 0.006 : 0.014]; });
    d = chain(x, y, z, P, 0.01);
    d = smax(d, Math.abs((z - lerp(0.118, 0.186, (0.228 - y)/0.158))) - 0.0065, 0.004);   // flatten front-to-back
    // scapulae: thin triangular blades on the back, the spine ridge, the acromion
    for (const s of [-1, 1]) {
      const cx = s*0.095, cy = 0.165, cz = -0.078;
      const a = s*0.42, ca = Math.cos(a), sa = Math.sin(a);
      const lx = (x - cx)*ca + (z - cz)*sa, lz = -(x - cx)*sa + (z - cz)*ca, ly = y - cy;
      let b = ellipsoid(lx, ly, lz, 0, 0, 0, 0.052, 0.072, 0.006);
      b = smax(b, (ly + 0.9*(Math.abs(lx) - 0.01)*s*0) - 0.06, 0.01);
      b = smin(b, chain(lx, ly, lz, [[-0.045, 0.035, -0.004, 0.005], [0.03, 0.05, -0.012, 0.007], [0.065, 0.06, 0.005, 0.009]], 0.004), 0.006);
      d = smin(d, b, 0.004);
      d = smin(d, sphere(x, y, z, s*0.168, 0.248, -0.012, 0.014), 0.012);                  // glenoid rim / acromion
    }
    return d;
  }, [-0.22, 0.03, -0.12, 0.22, 0.29, 0.21], H(0.0026)));
  for (const s of [-1, 1]) {
    const cl = [[s*0.016, 0.232, 0.118], [s*0.06, 0.242, 0.122], [s*0.11, 0.25, 0.09], [s*0.15, 0.256, 0.03], [s*0.166, 0.255, -0.004]];
    const pts = [];
    for (let i = 0; i <= 12; i++) {
      const t = i/12*(cl.length - 1), a = Math.floor(Math.min(t, cl.length - 2)), f = t - a;
      pts.push([0, 1, 2].map(c => lerp(cl[a][c], cl[a + 1][c], f)));
    }
    add('chest', sweep_g(pts, 0.0075, 0.0055, t => 1 + 0.25*Math.abs(t - 0.5)*2, [0, 1, 0], 8));
  }
  // limbs, per side
  for (const s of [-1, 1]) {
    const S = s > 0 ? 'L' : 'R';
    add('upper' + S, mesh_sdf_g((x, y, z) => humerus(x, y, z, s), [-0.045, -0.32, -0.04, 0.045, 0.02, 0.04], H(0.0026)*1.3));
    add('fore' + S, mesh_sdf_g((x, y, z) => forearm(x, y, z, s), [-0.035, -0.27, -0.03, 0.035, 0.03, 0.03], H(0.0022)*1.25));
    add('hand' + S, mesh_sdf_g((x, y, z) => carpals(x, y, z, s), [-0.015, -0.035, -0.03, 0.015, 0.005, 0.03], H(0.0016)));
    add('thigh' + S, mesh_sdf_g((x, y, z) => femur(x, y, z, s), [-0.08, -0.46, -0.05, 0.08, 0.035, 0.05], H(0.003)*1.3));
    add('shin' + S, mesh_sdf_g((x, y, z) => shin(x, y, z, s), [-0.055, -0.42, -0.04, 0.055, 0.005, 0.045], H(0.0027)*1.3));
    add('knee' + S, mesh_sdf_g(patella, [-0.025, -0.01, 0.02, 0.025, 0.045, 0.05], H(0.002)));
    add('foot' + S, mesh_sdf_g((x, y, z) => foot(x, y, z, s), [-0.05, -0.07, -0.08, 0.05, 0.005, 0.17], H(0.0021)));
    // metacarpals (rigid with the hand) and the finger segments (each its own joint)
    add('hand' + S, mesh_sdf_g((x, y, z) => {
      let d = Infinity;
      for (const f of FINGERS) d = Math.min(d, cone(x, y, z, 0, -0.028, f.z*0.8, 0, -0.028 - f.meta, f.z, 0.0058, 0.0052), smin(d, sphere(x, y, z, 0, -0.028 - f.meta, f.z, 0.0064), 0.003));
      // thumb metacarpal, angled out toward the front
      d = Math.min(d, cone(x, y, z, 0, -0.02, 0.022, s*0.012, -0.055, 0.046, 0.0065, 0.0058));
      return d;
    }, [-0.02, -0.1, -0.03, 0.02, -0.01, 0.06], H(0.0016)));
    FINGERS.forEach((f, i) => f.ph.forEach((L, j) => {
      const r = (0.0052 - j*0.0009)*(i === 3 ? 0.85 : 1);
      add(`finger${S}${i}_${j}`, mesh_sdf_g((x, y, z) => smin(cone(x, y, z, 0, 0, 0, 0, -L, 0, r, r*0.82), sphere(x, y, z, 0, -L, 0, r*0.95), 0.002), [-0.009, -L - 0.008, -0.009, 0.009, 0.008, 0.009], H(0.0014)));
    }));
    [0.034, 0.026].forEach((L, j) => {
      const r = 0.006 - j*0.001;
      add(`thumb${S}_${j}`, mesh_sdf_g((x, y, z) => smin(cone(x, y, z, 0, 0, 0, 0, -L, 0, r, r*0.85), sphere(x, y, z, 0, -L, 0, r), 0.002), [-0.01, -L - 0.008, -0.01, 0.01, 0.008, 0.01], H(0.0014)));
    });
  }
  // merge each node's pieces
  const out = {};
  for (const k in G) {
    const gs = G[k].map(g => { const n = g.index ? g : g; if (!n.attributes.uv) n.setAttribute('uv', new THREE.Float32BufferAttribute(new Float32Array(n.attributes.position.count*2), 2)); return n; });
    out[k] = gs.length === 1 ? gs[0] : mergeGeometries(gs, false);
  }
  return out;
}
export { FINGERS };
