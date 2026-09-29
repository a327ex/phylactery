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
import { cells2, fbm3, sstep, rand, vertex_mr } from 'game/shape_noise.js';

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
// the claws (round 33: along the two lines the owner drew): two long gouges from high on the brow
// at the viewer's left, down across that eye's slit, bending toward the mouth, spreading apart as
// they go; shallow where the claw went in, deepest past the middle, tapering out; the material
// shoved up in a lip along each edge
const CLAW_LINES = [
  { pts: [[-0.0409, EY + 0.0463], [-0.0357, EY + 0.0041], [-0.0175, EY - 0.0468]], w: 0.0024 },
  { pts: [[-0.0293, EY + 0.062], [-0.0252, EY + 0.0179], [-0.0142, EY - 0.0152], [0.0106, EY - 0.0744]], w: 0.0027 },
];
// each line sampled densely along a Catmull-Rom curve through its points: [x, y, t along it]
const CLAW_PATHS = CLAW_LINES.map(({ pts, w }) => {
  const P = pts, out = [], n = 48;
  const at = (i) => P[Math.max(0, Math.min(P.length - 1, i))];
  for (let k = 0; k <= n; k++) {
    const u = k/n*(P.length - 1), i = Math.min(P.length - 2, Math.floor(u)), f = u - i;
    const p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2);
    const c = (j) => 0.5*((2*p1[j]) + (-p0[j] + p2[j])*f + (2*p0[j] - 5*p1[j] + 4*p2[j] - p3[j])*f*f + (-p0[j] + 3*p1[j] - 3*p2[j] + p3[j])*f*f*f);
    out.push([c(0), c(1), k/n]);
  }
  return { pts: out, w };
});
function claws(x, y) {
  let depth = 0, lip = 0, inside = 0;
  for (const { pts, w: w0 } of CLAW_PATHS) {
    // nearest point on the curve: distance across, and how far along
    let best = 1e9, tt = 0;
    for (let k = 0; k < pts.length - 1; k++) {
      const [ax, ay, at] = pts[k], [bx, by, bt] = pts[k + 1];
      const dx = bx - ax, dy = by - ay, L2 = dx*dx + dy*dy;
      const u = Math.max(0, Math.min(1, ((x - ax)*dx + (y - ay)*dy)/L2));
      const d = Math.hypot(x - ax - dx*u, y - ay - dy*u);
      if (d < best) { best = d; tt = at + (bt - at)*u; }
    }
    if (best > 0.008) continue;
    const taper = Math.pow(Math.sin(Math.PI*Math.min(1, tt*1.2)), 0.6)*(tt > 0.82 ? sstep(1.0, 0.82, tt) : 1);
    const w = w0*(0.55 + 0.45*taper);
    if (best < w) { const q = 1 - (best/w)*(best/w); depth = Math.max(depth, 0.0028*taper*q); inside = Math.max(inside, taper*q); }
    lip = Math.max(lip, 0.00034*taper*Math.exp(-(((best - w*1.35)/(w*0.45))**2)));
  }
  return { depth, lip, inside };
}
// the pierce: the wearer's left eye (the viewer's right), where the owner drew it: an irregular
// hole, wider than tall, taking most of that eye's slit; around it the face crushed in; cracks
// running out from it
const HOLE = [0.038, EY + 0.001], HRX = 0.0235, HRY = 0.0175;
function pierce(x, y) {
  const dx = (x - HOLE[0])/HRX, dy = (y - HOLE[1])/HRY, re = Math.hypot(dx, dy), th = Math.atan2(dy, dx);
  const Re = 1 + 0.2*(fbm3(Math.cos(th)*1.8 + 3.1, Math.sin(th)*1.8, 0.7, 91, 3) - 0.5)*2 + 0.07*(fbm3(Math.cos(th)*7, Math.sin(th)*7, 1.9, 93, 2) - 0.5)*2;
  const k = (HRX + HRY)*0.5;                                  // to metres, roughly
  const r = re*k, R = Re*k;
  const crush = sstep(R + 0.009, R, r);
  let crack = 0;
  const RAYS = [[0.35, 0.03], [1.25, 0.016], [2.2, 0.024], [3.05, 0.012], [3.9, 0.02], [4.9, 0.034], [5.7, 0.014]];
  const tw = Math.atan2(y - HOLE[1], x - HOLE[0]);
  for (const [a0, len] of RAYS) {
    const a = a0 + 0.12*Math.sin(r*420 + a0*5);
    const dd = Math.abs(Math.atan2(Math.sin(tw - a), Math.cos(tw - a)))*Math.hypot(x - HOLE[0], y - HOLE[1]);
    const u = (r - R)/len;
    if (u > 0 && u < 1) crack = Math.max(crack, sstep(0.0007*(1 - u) + 0.0002, 0.0, dd));
  }
  return { r, R, crush, crack, in_hole: r < R };
}
// the blood (round 33: burned, not red; one run, the rest a spray from the violence of it): one run
// down the cheek from the hole's lower edge, a coat round the rim, and a spray flung out from the
// break: drops, most small, stretched along the way they flew, thicker near the hole
const SPRAY = (() => {
  const R = rand(4242), out = [];
  for (let i = 0; i < 150; i++) {
    const a = R.f(0, 6.283) + 0.35*Math.sin(i*1.7), far = Math.pow(R.next(), 1.8);
    const d = 0.004 + far*0.055;
    const size = (0.0022 - 0.0016*far)*R.f(0.35, 1.0);
    const ex = HOLE[0] + Math.cos(a)*(HRX + d), ey = HOLE[1] + Math.sin(a)*(HRY + d*0.85);
    out.push([ex, ey, Math.cos(a), Math.sin(a), size, 1 + far*2.6 + R.f(0, 0.8)]);
  }
  return out;
})();
function blood(x, y, p) {
  let m = 0, rim = 0;
  if (p.r < p.R + 0.0035) { m = sstep(p.R + 0.0035, p.R + 0.0008, p.r)*0.85; rim = sstep(p.R + 0.001, p.R + 0.003, p.r); }
  // the one run
  {
    const y0 = HOLE[1] - HRY*0.9, len = 0.064, v = (y0 - y)/len;
    if (v >= -0.05 && v <= 1.12) {
      const cx = HOLE[0] - 0.004 + 0.0008*Math.sin(y*230) + 0.0004*Math.sin(y*690);
      const w = 0.0024*(1 - 0.5*Math.min(1, Math.max(0, v)));
      const a = v <= 1 ? Math.abs(x - cx)/w : 9, bq = Math.hypot(x - cx, (y - (y0 - len))*0.8)/(w*1.4), q = Math.min(a, bq);
      if (q < 1) { m = 1; rim = sstep(0.55, 0.95, q); }
    }
  }
  // the spray
  if (m < 1) for (const [ex, ey, ux, uy, sz, el] of SPRAY) {
    const dx = x - ex, dy = y - ey;
    if (Math.abs(dx) > sz*el*1.6 || Math.abs(dy) > sz*el*1.6) continue;
    const along = dx*ux + dy*uy, across = -dx*uy + dy*ux;
    // a drop with a tail pointing on the way it flew
    const q = Math.hypot(along/(sz*(along > 0 ? el : 1)), across/sz);
    if (q < 1) { m = 1; rim = Math.max(rim, sstep(0.5, 0.95, q)); break; }
  }
  return { m, rim };
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
  front += -cl.depth + cl.lip - 0.0019*p.crush - 0.0006*p.crack + 0.00035*bl.m*(1 - 0.5*bl.rim);
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
      if (bl.m > 0) {
        // blood that burned (round 33: not red): a crust of dark maroon-brown, rust at its thin
        // edges, a little glossy, standing off the dead black of the char
        const k = bl.m*(0.85 + 0.15*t);
        const cr = 0.028 + 0.02*bl.rim, cg = 0.0085 + 0.011*bl.rim, cb = 0.0055 + 0.005*bl.rim;
        r += (cr - r)*k; gg += (cg - gg)*k; bb += (cb - bb)*k; rough += (0.4 + 0.25*bl.rim - rough)*k;
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
