// item_mask.js -- the FIRE power's object (owner, round 29: "a burned mask instead, specifically
// the a327ex, so black with white eyes/mouth, as though it had been burned"). The a327ex avatar is
// Shun's mask (Shin Sekai Yori): a smooth white full-face mask, a round brow over a short lower
// face narrowing to a pointed chin, no features but a faint ridge of a nose, two long slits for
// eyes and a short one for the mouth. Round 30 matched its proportions to the avatar.
//
// Round 32 (owner): its history, captured and aged by time. First a big monster clawed it across
// its middle: three long gouges, curving together, raised lips along their edges. Then a flying
// thing that pierces drove through its left eye (the wearer's left, the viewer's right): an
// irregular round hole, the face crushed in around it, cracks running out from it, the back
// spalled off; blood ran from it down the cheek. Then the wearer burned, and the mask with them:
// black, the soot laid in tongues where the flames licked up it, heat blisters, the rim eaten
// ragged to ash, the blood cooked to a crust. Then time: dust in every hollow, the high points
// rubbed smooth, the blood dulled. (Round 31's charred crackle, "dragon skin", is gone.)
// Sculpted as a thin shell (distance field, meshed by surface nets); colour and roughness are
// read from the same functions.
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
// the claws: three gouges down the middle of the face, from the brow to the chin, slanting a
// little and curving together (through the mouth); each shallow where the claw went in, deepest
// past its middle, tapering out; the material shoved up in a lip along each edge
const CLAW = { a: [-0.017, EY + 0.08], b: [0.014, EY - 0.112], bow: -0.007, off: [-0.0125, 0, 0.0128], span: [[0.06, 0.82], [0.0, 0.93], [0.12, 0.88]], w: [0.0017, 0.0021, 0.0018] };
function claws(x, y) {
  const ax = CLAW.a[0], ay = CLAW.a[1], dx = CLAW.b[0] - ax, dy = CLAW.b[1] - ay, L = Math.hypot(dx, dy);
  const ux = dx/L, uy = dy/L, nx = -uy, ny = ux;
  const t = ((x - ax)*ux + (y - ay)*uy)/L;
  const across0 = (x - ax)*nx + (y - ay)*ny - CLAW.bow*Math.sin(Math.PI*Math.min(1, Math.max(0, t)));
  let depth = 0, lip = 0, inside = 0;
  for (let k = 0; k < 3; k++) {
    const [t0, t1] = CLAW.span[k];
    if (t < t0 || t > t1) continue;
    const u = (t - t0)/(t1 - t0);
    const taper = Math.pow(Math.sin(Math.PI*Math.min(1, u*1.25)), 0.6)*(u > 0.8 ? sstep(1.0, 0.8, u) : 1);
    const w = CLAW.w[k]*(0.55 + 0.45*taper);
    const a = Math.abs(across0 - CLAW.off[k]*(1 - 0.18*t));      // they converge a little toward the end
    if (a < w) { const q = 1 - (a/w)*(a/w); depth = Math.max(depth, 0.0024*taper*q); inside = Math.max(inside, taper*q); }
    lip = Math.max(lip, 0.00032*taper*Math.exp(-(((a - w*1.35)/(w*0.45))**2)));
  }
  return { depth, lip, inside };
}
// the pierce: the wearer's left eye, an irregular round hole; around it the face crushed in; five
// cracks running out from it
const HOLE = [0.047, EY + 0.0008];
function pierce(x, y) {
  const dx = x - HOLE[0], dy = y - HOLE[1], r = Math.hypot(dx, dy), th = Math.atan2(dy, dx);
  const R = 0.0118 + 0.0022*(fbm3(Math.cos(th)*2.2 + 3.1, Math.sin(th)*2.2, 0.7, 91, 3) - 0.5)*2 + 0.0007*(fbm3(Math.cos(th)*9, Math.sin(th)*9, 1.9, 93, 2) - 0.5)*2;
  const crush = sstep(R + 0.0085, R, r);
  let crack = 0;
  const RAYS = [[0.35, 0.026], [1.4, 0.014], [2.45, 0.021], [3.6, 0.011], [4.9, 0.03]];
  for (const [a0, len] of RAYS) {
    const a = a0 + 0.12*Math.sin(r*420 + a0*5);
    let dd = Math.abs(Math.atan2(Math.sin(th - a), Math.cos(th - a)))*r;
    const u = (r - R)/len;
    if (u > 0 && u < 1) crack = Math.max(crack, sstep(0.0007*(1 - u) + 0.0002, 0.0, dd));
  }
  return { r, R, crush, crack, in_hole: r < R };
}
// the blood: runs down from the hole's lower edge (four, of different lengths), a smear round it
const DRIPS = [[-0.0065, 0.044, 0.0016], [0.0005, 0.078, 0.0022], [0.0072, 0.03, 0.0014]];
function blood(x, y, p) {
  let m = 0;
  if (p.r < p.R + 0.0045 && y < HOLE[1] + 0.003) m = sstep(p.R + 0.0045, p.R + 0.001, p.r)*0.9;
  for (const [ox, len, w0] of DRIPS) {
    const y0 = HOLE[1] - 0.009, v = (y0 - y)/len;             // 0 at its start, 1 at its end
    if (v < -0.1 || v > 1.15) continue;
    const cx = HOLE[0] + ox + 0.0007*Math.sin(y*230 + ox*900) + 0.0004*Math.sin(y*690 + ox*300);
    const w = w0*(1 - 0.55*Math.min(1, Math.max(0, v)));
    const bulb = Math.hypot(x - cx, (y - (y0 - len))*0.8) < w*1.35 ? 1 : 0;
    m = Math.max(m, (Math.abs(x - cx) < w && v >= 0 && v <= 1 ? 1 : 0), bulb);
  }
  return m;
}
// the burn: the shell warped by the heat; blisters where the surface lifted; a grain; soot in
// tongues where the flames licked up it (colour only, below)
function burn(x, y) {
  const warp = (fbm3(x*9 + 1.7, y*9, 3.3, 57, 3) - 0.5)*0.007;
  const grain = (fbm3(x*260, y*260, 0.5, 43, 3) - 0.5)*0.0007 + (fbm3(x*70, y*70, 0.9, 44, 2) - 0.5)*0.001;
  const bc = cells2(x/0.012 - 7.3, y/0.012 + 2.2, 49);
  const blister = bc.id > 0.74 ? 0.0008*Math.pow(sstep(0.4 + 0.2*bc.id, 0.0, bc.d1), 0.7) : 0;
  return { warp, grain, blister: blister/0.0008, disp: warp + grain + blister };
}
// soot tongues: stretched noise, the flames came from below and licked up
function flames(x, y) {
  const q = (fbm3(x*9, y*9, 5.1, 95, 2) - 0.5)*2.2;
  const n = fbm3(x*34 + q, y*7.5 - q*0.4, 2.7, 97, 3);
  return sstep(0.44, 0.58, n + (EY - y)*1.6);
}

// where the fire ate the rim (2D, > 0 = burned away); ragged but shallow (round 30: up to ~7 mm,
// so the outline stays the source's)
function burned(x, y) {
  const n = fbm3(x*38, y*38, 1.3, 47, 3);
  let eat = (n - 0.45)*0.014;
  eat += 0.006*Math.exp(-(((x + 0.06)/0.03)**2 + ((y - EY + 0.07)/0.03)**2));   // a bite out of the lower left jaw
  return Math.max(eat, 0);
}

const WARP = (x, y) => (fbm3(x*9 + 1.7, y*9, 3.3, 57, 3) - 0.5)*0.007;
function field(x, y, z) {
  const o = outline(x, y) + burned(x, y);
  if (o > 0.012) return o;
  const f = face(x, y);
  const s = slit(x, y), bu = burn(x, y), cl = claws(x, y), p = pierce(x, y);
  const bl = blood(x, y, p);
  let front = f + bu.disp*(s > 0 ? 0.5 : 1) - (s > 0 ? GROOVE*Math.min(1, s*3) : 0);
  front += -cl.depth + cl.lip - 0.0019*p.crush - 0.0006*p.crack + 0.00022*bl;
  // the back: the same warped shell; spalled off round the hole's exit
  const back = f + bu.warp - T + 0.0022*sstep(p.R + 0.011, p.R, p.r);
  let d = Math.max(z - front, back - z);
  d = smax(d, o, 0.0016);
  d = Math.max(d, p.R - p.r);                                 // the hole, straight through
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
    const f = face(x, y), s = slit(x, y), bu = burn(x, y), cl = claws(x, y), p = pierce(x, y);
    const bl = blood(x, y, p), fl = flames(x, y);
    const front = z > f + bu.warp - T*0.85;
    // the hole's wall (the shell's section) and its spalled back
    const wall = sstep(p.R + 0.0012, p.R, p.r);
    const eat = burned(x, y), edge = -(outline(x, y) + eat);
    const ashy = sstep(0.006, 0.0, edge), brown = sstep(0.02, 0.004, edge);
    const soot = fbm3(x*45, y*20, 1.9, 67, 3), t = fbm3(x*60, y*60, 2.2, 55, 3);
    let r, gg, bb, rough;
    if (front && s > 0.05 && wall < 0.5) {
      // the slits kept their white, stained brown with soot, dirtier at their edges
      const w = sstep(0.05, 0.6, s)*(0.7 + 0.3*sstep(0.62, 0.4, soot));
      r = 0.05 + 0.68*w; gg = 0.042 + 0.62*w; bb = 0.036 + 0.55*w; rough = 0.65;
    } else if (front) {
      // char: black, the flames' tongues deepest; between them a scorched umber; blisters a
      // little glossy; toward the eaten rim scorched brown, then ash
      const v = 0.0035 + 0.004*t + 0.003*bu.blister;
      r = v*1.2; gg = v; bb = v*0.85;
      const gap = 1 - fl;
      r += (0.015 - r)*gap*0.7; gg += (0.0085 - gg)*gap*0.7; bb += (0.005 - bb)*gap*0.7;
      r += (0.045 - r)*brown*0.8; gg += (0.026 - gg)*brown*0.8; bb += (0.014 - bb)*brown*0.8;
      rough = 0.82 - 0.3*bu.blister;
    } else {
      r = 0.008; gg = 0.0065; bb = 0.0055; rough = 0.9;
    }
    if (front) {
      // the gouges: the claw cut through the lacquer to the pale core, then the fire browned it
      // and time filled it with dust; the lips glossy black
      const g0 = cl.inside;
      r += (0.07 - r)*g0; gg += (0.055 - gg)*g0; bb += (0.042 - bb)*g0; rough += (0.93 - rough)*g0;
      const lp = Math.min(1, cl.lip/0.00032);
      rough -= 0.25*lp;
      // crushed round the hole: broken into grey-brown grit, the cracks dark with dust at their lips
      r += (0.05 - r)*p.crush*0.7; gg += (0.043 - gg)*p.crush*0.7; bb += (0.036 - bb)*p.crush*0.7;
      r *= 1 - 0.6*p.crack; gg *= 1 - 0.6*p.crack; bb *= 1 - 0.6*p.crack;
      // the blood: dried, then cooked by the fire: a near-black red crust, glossier where thick
      if (bl > 0) {
        // old blood, cooked: a dark reddish-brown crust, duller at the thin ends
        const k = bl*(0.8 + 0.2*t);
        r += (0.05 - r)*k; gg += (0.009 - gg)*k; bb += (0.0065 - bb)*k; rough += (0.6 - rough)*k;
      }
    }
    // the hole's wall: the core, charred through
    r += (0.03 - r)*wall; gg += (0.022 - gg)*wall; bb += (0.016 - bb)*wall;
    // time: dust settled in the hollows (gouges, cracks, the crush), the high points rubbed smooth
    const hollow = front ? Math.min(1, cl.depth/0.0012 + p.crack + p.crush*0.5) : 0;
    const dust = hollow*0.5*(0.6 + 0.4*t);
    r += (0.085 - r)*dust; gg += (0.08 - gg)*dust; bb += (0.074 - bb)*dust;
    const worn = front ? sstep(0.004, 0.008, f - (-(x*x)/(2*0.105) - ((y - 0.01)**2)/(2*0.3))) : 0;
    rough -= 0.3*worn;
    // the burn front's ash at the eaten rim
    r += (0.085 - r)*ashy*0.85; gg += (0.078 - gg)*ashy*0.85; bb += (0.072 - bb)*ashy*0.85; rough += (0.95 - rough)*ashy;
    col[i*3] = r; col[i*3 + 1] = gg; col[i*3 + 2] = bb;
    mr[i*2] = 0; mr[i*2 + 1] = Math.min(1, Math.max(0.2, rough));
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
