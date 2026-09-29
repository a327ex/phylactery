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
// the burn (round 31, owner: "a different burning texture ... irregularities to it overall, it
// should look burned, worn, etc. The same kind of irregularities you added to the hand"): the
// shell warped by the heat, a grainy, pitted surface; blisters risen and a few burst; charred
// crackle over part of it (irregular, not round 30's even scales everywhere); a few long fissures;
// a burn front at the eaten rim, ash going to brown going to black (colour, below).
function char(x, y) {
  const warp = (fbm3(x*9 + 1.7, y*9, 3.3, 57, 3) - 0.5)*0.007;
  const grain = (fbm3(x*260, y*260, 0.5, 43, 3) - 0.5)*0.0008 + (fbm3(x*70, y*70, 0.9, 44, 2) - 0.5)*0.0012;
  const pc = cells2(x/0.004 + 0.3, y/0.004, 59);
  const pit = pc.id > 0.82 ? sstep(0.35, 0.05, pc.d1)*0.0005 : 0;
  // blisters (lacquer lifting off in the heat): some whole, a few burst to a shallow crater
  const bc = cells2(x/0.013 - 7.3, y/0.013 + 2.2, 49);
  let blister = 0, burst = 0;
  if (bc.id > 0.5) {
    const r = bc.d1/(0.22 + 0.25*bc.id);
    if (bc.id > 0.9) { burst = r < 0.8 ? 1 : 0; blister = 0.0005*sstep(1.0, 0.75, r) - 0.0007*sstep(0.8, 0.2, r); }
    else blister = 0.0011*Math.pow(sstep(1.0, 0.0, r), 0.7);
  }
  // charred crackle in patches: cells bent out of true by the noise, deep cracks
  const qx = x + (fbm3(x*40, y*40, 2.9, 71, 2) - 0.5)*0.006, qy = y + (fbm3(x*40, y*40, 6.1, 72, 2) - 0.5)*0.006;
  const cc = cells2(qx/0.0075, qy/0.0065, 41);
  const patch = sstep(0.5, 0.6, fbm3(x*16, y*16, 4.1, 45, 3));
  const crack = sstep(0.0009, 0.00015, cc.edge*0.007)*patch;
  const dome = sstep(0, 0.0022, cc.edge*0.007)*patch;
  // long fissures where the noise lets them run
  const fc = cells2(x/0.034 + 5.1, y/0.028 - 3.3, 61);
  const fissure = sstep(0.0011, 0.0002, fc.edge*0.03)*sstep(0.55, 0.66, fbm3(x*14, y*14, 7.7, 63, 2));
  return { disp: warp + grain - pit + blister + dome*0.0003 - crack*0.0008 - fissure*0.0009, pit: pit > 0 ? 1 : 0,
    blister: Math.max(0, blister)/0.0011, burst, crack, dome, fissure, id: bc.id };
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
  const front = f + ch.disp*(s > 0 ? 0.5 : 1) - (s > 0 ? GROOVE*Math.min(1, s*3) : 0);
  const back = f + (fbm3(x*9 + 1.7, y*9, 3.3, 57, 3) - 0.5)*0.007 - T;
  let d = Math.max(z - front, back - z);
  d = smax(d, o, 0.0016);
  d = Math.max(d, b.hole);
  return d;
}

let CACHE = null;
function geometry() {
  if (CACHE) return CACHE;
  const g = largest_piece(mesh_sdf(field, [-0.1, -0.09, -0.075, 0.1, 0.118, 0.022], 0.0007));
  // colour, roughness
  const P = g.attributes.position, n = P.count;
  const col = new Float32Array(n*3), mr = new Float32Array(n*2);
  for (let i = 0; i < n; i++) {
    const x = P.getX(i), y = P.getY(i), z = P.getZ(i);
    const f = face(x, y), s = slit(x, y), ch = char(x, y), b = burned(x, y);
    const front = z > f + (fbm3(x*9 + 1.7, y*9, 3.3, 57, 3) - 0.5)*0.007 - T*0.85;
    const rim = sstep(-0.006, -0.0005, outline(x, y) + b.eat) + sstep(-0.004, 0.0, b.hole);
    let r, gg, bb, rough;
    const soot = fbm3(x*45, y*20, 1.9, 67, 3);
    // how far in from where the fire ate the rim (0 at the edge): the burn front
    const edge = -(outline(x, y) + b.eat), front_d = Math.min(edge, -b.hole + 0.0065*0.3);
    const ashy = sstep(0.006, 0.0, front_d), brown = sstep(0.02, 0.004, front_d);
    if (front && s > 0.05) {
      // the slits kept their white, stained brown with soot, dirtier at their edges
      const w = sstep(0.05, 0.6, s)*(0.7 + 0.3*sstep(0.62, 0.4, soot));
      r = 0.05 + 0.68*w; gg = 0.042 + 0.62*w; bb = 0.036 + 0.55*w; rough = 0.65;
    } else if (front) {
      // char: black, velvety; a faint grey sheen on crackle tops and blisters; cracks and
      // craters dead black; scorched brown and then ash toward the eaten rim; soot streaks
      const t = fbm3(x*60, y*60, 2.2, 55, 3);
      const v = 0.0045 + 0.005*t + 0.004*ch.dome + 0.003*ch.blister*(1 - ch.burst) - 0.003*Math.max(ch.crack, ch.fissure, ch.burst, ch.pit);
      r = v*1.15; gg = v; bb = v*0.9;
      r += (0.045 - r)*brown*0.8; gg += (0.026 - gg)*brown*0.8; bb += (0.014 - bb)*brown*0.8;
      const streak = sstep(0.62, 0.74, soot)*0.5;
      r *= 1 - streak*0.5; gg *= 1 - streak*0.5; bb *= 1 - streak*0.5;
      rough = 0.8 - 0.25*ch.dome - 0.35*ch.blister*(1 - ch.burst) + 0.15*ch.crack;
    } else {
      r = 0.008; gg = 0.0065; bb = 0.0055; rough = 0.9;
    }
    r += (0.085 - r)*ashy*0.85; gg += (0.078 - gg)*ashy*0.85; bb += (0.072 - bb)*ashy*0.85; rough += (0.95 - rough)*ashy;
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
