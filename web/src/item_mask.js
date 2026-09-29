// item_mask.js -- round 29: the FIRE power's object (owner: "a burned mask instead,
// specifically the a327ex, so black with white eyes/mouth, as though it had been burned"). The
// a327ex avatar is Shun's mask (Shin Sekai Yori): a smooth white full-face mask, a round brow over
// a short lower face narrowing to a pointed chin, no features but a faint ridge of a nose, two
// long slits for eyes and a short one for the mouth.
//
// Burned: the face charred black into blistered scales split by cracks (charred wood's
// alligator pattern), the rim eaten ragged and grey with ash where it burned through, one hole
// burned right through the cheek; the slits sit a little below the face and kept their white.
// Sculpted as a thin shell (distance field, meshed by surface nets) with its colour, roughness
// and cracks read from the same functions.
import * as THREE from 'three';
import { mesh_sdf, smax, largest_piece } from 'game/sdf.js';
import { cells2, fbm3, sstep, vertex_mr } from 'game/shape_noise.js';

const T = 0.0055;                 // shell thickness, m
const GROOVE = 0.0026;            // how far the slits sit below the face

// Round 30 (owner: "the proportions are off compared to the source"). Measured on the avatar,
// in units of E = the span from one eye's outer end to the other's: each eye 0.34 E long with a
// 0.34 E gap between them; the mouth 0.47 E below the eyes and 0.24 E long; the chin's point
// 0.77 E below the eyes; the face 1.37 E wide at the eyes, 1.26 E a little below them, 1.02 E at
// a third of E down, 0.81 E at the mouth, then straight jaw lines to the point. (Round 29 had the
// mouth 0.84 E and the chin 1.18 E down, the eyes 0.21 E apart: a long face.) E = 13.8 cm here.
const EY = 0.022;                 // the eyes' line
const JAW = [[0, 0.093], [0.0245, 0.0855], [0.042, 0.0695], [0.06, 0.059], [0.068, 0.0555], [0.085, 0.0365], [0.098, 0.017], [0.106, 0.0]];
function jaw(dy) {
  // Catmull-Rom through the measured half-widths (dy below the eyes)
  if (dy <= 0) return JAW[0][1];
  if (dy >= JAW[JAW.length - 1][0]) return 0;
  let i = 0;
  while (JAW[i + 1][0] < dy) i++;
  const p0 = JAW[Math.max(0, i - 1)][1], p1 = JAW[i][1], p2 = JAW[i + 1][1], p3 = JAW[Math.min(JAW.length - 1, i + 2)][1];
  const t = (dy - JAW[i][0])/(JAW[i + 1][0] - JAW[i][0]);
  return 0.5*((2*p1) + (-p0 + p2)*t + (2*p0 - 5*p1 + 4*p2 - p3)*t*t + (-p0 + 3*p1 - 3*p2 + p3)*t*t*t);
}
// the outline (2D, <0 inside): a round brow over the eyes, the measured jaw below them
function outline(x, y) {
  if (y >= EY) return (Math.hypot(x/0.093, (y - EY)/0.09) - 1)*0.09;
  const dy = EY - y;
  if (dy > 0.106) return Math.hypot(x, dy - 0.106);
  return (Math.abs(x) - jaw(dy))*0.85;
}
// the face, before the fire: its height toward the viewer at (x, y)
function face(x, y) {
  const v = y - 0.01;
  let z = -(x*x)/(2*0.105) - (v*v)/(2*0.3);
  z += 0.008*Math.exp(-((x/0.0105)**2))*sstep(EY + 0.012, EY - 0.01, y)*sstep(EY - 0.046, EY - 0.03, y);   // the nose's ridge
  z -= 0.0035*Math.exp(-(((Math.abs(x) - 0.046)/0.026)**2 + ((y - EY)/0.018)**2));                         // the eyes sit a little in
  z += 0.0026*Math.exp(-(((Math.abs(x) - 0.048)/0.028)**2 + ((y - EY + 0.036)/0.024)**2));                 // cheeks
  z += 0.0016*Math.exp(-((x/0.026)**2 + ((y - EY + 0.064)/0.013)**2));                                      // the mouth's rise
  return z;
}
// the slits (2D): > 0 inside, its value the depth fraction there. Bars of even thickness with
// rounded ends, like the avatar's (round 30's first pass tapered them to points)
function bar(x, y, cx, cy, hl, t) {
  const dx = Math.max(Math.abs(x - cx) - (hl - t), 0), dy = y - cy;
  return (t - Math.hypot(dx, dy))/t;
}
function slit(x, y) {
  let best = -1;
  for (const s of [-1, 1]) best = Math.max(best, bar(x, y, s*0.046, EY, 0.0235, 0.0041));
  return Math.max(best, bar(x, y, 0, EY - 0.065, 0.0168, 0.0029));
}
// the char: matte black with a rough grain, crazed with fine cracks in patches (not all over:
// round 29's first pass, all scales, read as reptile skin), a few blisters risen from the heat
function char(x, y) {
  const S = 0.0058;
  const c = cells2(x/(S*1.2) + 3.1, y/S - 1.7, 41);
  const patch = sstep(0.46, 0.6, fbm3(x*22, y*22, 4.1, 45, 3));
  const crack = sstep(0.0008, 0.00015, c.edge*S)*patch;
  const dome = sstep(0, 0.0022, c.edge*S)*patch;
  const b = cells2(x/0.019 - 7.3, y/0.019 + 2.2, 49);
  const blister = b.id > 0.72 ? sstep(0.34, 0.0, b.d1) : 0;
  const grain = fbm3(x*420, y*420, 0.5, 43, 2) - 0.5;
  return { disp: dome*0.00025 - crack*0.0007 + blister*0.0013 + grain*0.0003, crack, dome, blister, id: c.id, patch };
}
// where the fire ate the rim, and the hole through the cheek (2D, > 0 = burned away); ragged
// but shallow (round 30: up to ~7 mm, so the outline stays the source's)
function burned(x, y) {
  const n = fbm3(x*38, y*38, 1.3, 47, 3);
  let eat = (n - 0.45)*0.014;
  eat += 0.006*Math.exp(-(((x + 0.06)/0.03)**2 + ((y - EY + 0.07)/0.03)**2));   // a bite out of the lower left jaw
  const hole = 0.0065 + 0.0035*(fbm3(x*90, y*90, 2.1, 53, 2) - 0.5)*2 - Math.hypot(x - 0.058, y - EY + 0.04);
  return { eat: Math.max(eat, 0), hole };
}

function field(x, y, z) {
  const b = burned(x, y);
  const o = outline(x, y) + b.eat;
  if (o > 0.012) return o;
  const f = face(x, y);
  const s = slit(x, y);
  const ch = char(x, y);
  const front = f + ch.disp*(s > 0 ? 0.2 : 1) - (s > 0 ? GROOVE*Math.min(1, s*3) : 0);
  const back = f - T;
  let d = Math.max(z - front, back - z);
  d = smax(d, o, 0.0016);
  d = Math.max(d, b.hole);
  return d;
}

let CACHE = null;
function geometry() {
  if (CACHE) return CACHE;
  const g = largest_piece(mesh_sdf(field, [-0.1, -0.09, -0.07, 0.1, 0.118, 0.02], 0.00085));
  // colour, roughness
  const P = g.attributes.position, n = P.count;
  const col = new Float32Array(n*3), mr = new Float32Array(n*2);
  for (let i = 0; i < n; i++) {
    const x = P.getX(i), y = P.getY(i), z = P.getZ(i);
    const f = face(x, y), s = slit(x, y), ch = char(x, y), b = burned(x, y);
    const front = z > f - T*0.5;
    const rim = sstep(-0.006, -0.0005, outline(x, y) + b.eat) + sstep(-0.004, 0.0, b.hole);
    let r, gg, bb, rough;
    if (front && s > 0.05) {
      // the slits kept their white, sooted toward their edges
      const w = sstep(0.05, 0.6, s);
      r = 0.05 + 0.73*w; gg = 0.048 + 0.71*w; bb = 0.045 + 0.67*w; rough = 0.6;
    } else {
      // char: black, a little uneven; crazed patches catch a faint sheen, cracks dead black,
      // blisters glossier
      const t = fbm3(x*60, y*60, 2.2, 55, 3);
      const v = 0.0035 + 0.005*t + 0.002*ch.dome - 0.003*ch.crack + 0.003*ch.blister;
      r = v; gg = v*0.98; bb = v*0.96;
      if (!front) { r = 0.006; gg = 0.0058; bb = 0.0056; }
      rough = 0.74 - 0.2*ch.dome - 0.35*ch.blister + 0.2*ch.crack + (front ? 0 : 0.15);
    }
    // ash where it burned through
    r += (0.1 - r)*rim; gg += (0.092 - gg)*rim; bb += (0.085 - bb)*rim; rough += (0.95 - rough)*rim;
    col[i*3] = r; col[i*3 + 1] = gg; col[i*3 + 2] = bb;
    mr[i*2] = 0; mr[i*2 + 1] = Math.min(1, rough);
  }
  g.setAttribute('color', new THREE.BufferAttribute(col, 3));
  g.setAttribute('aMR', new THREE.BufferAttribute(mr, 2));
  CACHE = g;
  return g;
}

export function build_mask(ctx = {}) {
  const lit = ctx.lit || (m => m);
  // char is black and nearly matte: a weak specular (a grey sheen read as "not black")
  const mat = lit(vertex_mr(new THREE.MeshPhysicalMaterial({ vertexColors: true, roughness: 0.8, metalness: 0, side: THREE.DoubleSide,
    specularIntensity: 0.3, envMapIntensity: (ctx.env_i ?? 1)*0.4 })));
  const m = new THREE.Mesh(geometry(), mat);
  m.castShadow = true;
  const g = new THREE.Group();
  g.add(m);
  return g;
}
