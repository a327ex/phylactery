// mask_v2.mjs -- round 47 (owner, 2026-10-05: "The mask, I want the fire burn effect to be like the one
// on the baby mask. Hole and scratches should still be there but also made more realistic"; the baby =
// round 46's photo 07, the Hiroshima ceramic child: one side of the face blackened with soot, the
// other clean, a soft ragged boundary between).
//
// The avatar's mask (item_mask.js: the measured outline, the face, the slits, the claw lines from his
// drawing, the hole through the left eye, the blood) as what it would be if it were glazed porcelain,
// and what fire and violence do to that: nothing chars or warps or melts; soot settles on the side the
// fire was, black and matte, thickest low and in every hollow, thinning in a ragged soft edge across
// the face, with tongues where it climbed and specks beyond; the glaze elsewhere stays white and a
// little glossy. The hole is a break, not a melt: an angular outline of straight fractures, shell-
// shaped chips flaked off its front edge down to the matte body, hairline cracks running out, the
// back spalled off wider. The claws cut through the glaze: grooves with chipped, scalloped edges
// (brittle: no raised lips), matte floors with fine scratches along them, through where deepest.
import * as THREE from 'three';
import { mesh_sdf, smax, largest_piece } from 'game/sdf.js';
import { fbm3, sstep, rand } from 'game/shape_noise.js';

const T = 0.0055, GROOVE = 0.0026, EY = 0.022;
const JAW = [[0, 0.093], [0.0245, 0.0855], [0.042, 0.0695], [0.06, 0.059], [0.068, 0.0555], [0.085, 0.0365], [0.098, 0.017], [0.106, 0.0]];
function jaw(dy) {
  if (dy <= 0) return JAW[0][1];
  if (dy >= JAW[JAW.length - 1][0]) return 0;
  let i = 0;
  while (JAW[i + 1][0] < dy) i++;
  const p0 = JAW[Math.max(0, i - 1)][1], p1 = JAW[i][1], p2 = JAW[i + 1][1], p3 = JAW[Math.min(JAW.length - 1, i + 2)][1];
  const t = (dy - JAW[i][0])/(JAW[i + 1][0] - JAW[i][0]);
  return 0.5*((2*p1) + (-p0 + p2)*t + (2*p0 - 5*p1 + 4*p2 - p3)*t*t + (-p0 + 3*p1 - 3*p2 + p3)*t*t*t);
}
function outline(x, y) {
  if (y >= EY) return (Math.hypot(x/0.093, (y - EY)/0.09) - 1)*0.09;
  const dy = EY - y;
  if (dy > 0.106) return Math.hypot(x, dy - 0.106);
  return (Math.abs(x) - jaw(dy))*0.85;
}
function face(x, y) {
  const v = y - 0.01;
  let z = -(x*x)/(2*0.105) - (v*v)/(2*0.3);
  z += 0.008*Math.exp(-((x/0.0105)**2))*sstep(EY + 0.012, EY - 0.01, y)*sstep(EY - 0.046, EY - 0.03, y);
  z -= 0.0035*Math.exp(-(((Math.abs(x) - 0.046)/0.026)**2 + ((y - EY)/0.018)**2));
  z += 0.0026*Math.exp(-(((Math.abs(x) - 0.048)/0.028)**2 + ((y - EY + 0.036)/0.024)**2));
  z += 0.0016*Math.exp(-((x/0.026)**2 + ((y - EY + 0.064)/0.013)**2));
  return z;
}
function bar(x, y, cx, cy, hl, t) { const dx = Math.max(Math.abs(x - cx) - (hl - t), 0), dy = y - cy; return (t - Math.hypot(dx, dy))/t; }
function slit(x, y) {
  let best = -1;
  for (const s of [-1, 1]) best = Math.max(best, bar(x, y, s*0.046, EY, 0.0235, 0.0041));
  return Math.max(best, bar(x, y, 0, EY - 0.065, 0.0168, 0.0029));
}
const dseg = (x, y, ax, ay, bx, by) => {
  const dx = bx - ax, dy = by - ay, L2 = dx*dx + dy*dy;
  const u = Math.max(0, Math.min(1, ((x - ax)*dx + (y - ay)*dy)/L2));
  return [Math.hypot(x - ax - dx*u, y - ay - dy*u), u];
};

// ---------------------------------------------------------------- the claws (his drawing's lines)
const CLAW_LINES = [
  { pts: [[-0.0409, EY + 0.0463], [-0.0357, EY + 0.0041], [-0.0175, EY - 0.0468]], w: 0.0021 },
  { pts: [[-0.0293, EY + 0.062], [-0.0252, EY + 0.0179], [-0.0142, EY - 0.0152], [0.0106, EY - 0.0744]], w: 0.0024 },
];
const CLAW_PATHS = CLAW_LINES.map(({ pts, w }, li) => {
  const P = pts, out = [], n = 64;
  const at = (i) => P[Math.max(0, Math.min(P.length - 1, i))];
  for (let k = 0; k <= n; k++) {
    const u = k/n*(P.length - 1), i = Math.min(P.length - 2, Math.floor(u)), f = u - i;
    const p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2);
    const c = (j) => 0.5*((2*p1[j]) + (-p0[j] + p2[j])*f + (2*p0[j] - 5*p1[j] + 4*p2[j] - p3[j])*f*f + (-p0[j] + 3*p1[j] - 3*p2[j] + p3[j])*f*f*f);
    out.push([c(0), c(1), k/n]);
  }
  // chips along each edge: where the glaze flaked off beside the groove (brittle: bites, not lips)
  const R = rand(700 + li*31), chips = [];
  for (let s of [-1, 1]) for (let i = 0; i < 9; i++) chips.push({ side: s, t: R.f(0.06, 0.94), len: R.f(0.012, 0.03), bite: R.f(0.5, 1.3) });
  return { pts: out, w, chips };
});
const GASH_THROUGH = [[0.38, 0.55], [0.3, 0.58]];
function claws(x, y) {
  let depth = 0, inside = 0, wall = 0, slot = -1, chip = 0, stria = 0;
  CLAW_PATHS.forEach(({ pts, w: w0, chips }, li) => {
    let best = 1e9, tt = 0, side = 1, dir = [1, 0];
    for (let k = 0; k < pts.length - 1; k++) {
      const [ax, ay, at] = pts[k], [bx, by, bt] = pts[k + 1];
      const [d, u] = dseg(x, y, ax, ay, bx, by);
      if (d < best) { best = d; tt = at + (bt - at)*u; side = (bx - ax)*(y - ay) - (by - ay)*(x - ax) >= 0 ? 1 : -1; dir = [bx - ax, by - ay]; }
    }
    if (best > 0.012) return;
    const taper = Math.pow(Math.sin(Math.PI*Math.min(1, tt*1.12)), 0.45)*(tt > 0.86 ? sstep(1.0, 0.86, tt) : 1);
    // the groove's own width, a little uneven (the claw skipped and dug)
    const w = w0*(0.45 + 0.55*taper)*(1 + (fbm3(tt*22, li*3.1, 0.4, 801, 2) - 0.5)*0.35);
    // the edge on this side: scalloped by chips (each a shell-shaped bite with a sharp outer rim)
    let we = w;
    for (const c of chips) {
      if (c.side !== side) continue;
      const q = (tt - c.t)/(c.len/0.11);
      if (Math.abs(q) < 1) we = Math.max(we, w*(1 + c.bite*Math.sqrt(1 - q*q)*taper));
    }
    if (best < we) {
      if (best < w) {
        // the groove: steep walls, a rough flat floor
        const a = best/w;
        const q = Math.pow(1 - Math.pow(a, 2.4), 0.55);
        depth = Math.max(depth, 0.0036*taper*q);
        inside = Math.max(inside, taper*q);
        wall = Math.max(wall, taper*sstep(0.45, 0.9, a));
        // scratches along it (the claw's own ridges), across its floor
        const across = (x - pts[0][0])*(-dir[1]) + (y - pts[0][1])*dir[0];
        stria = Math.max(stria, taper*(0.5 + 0.5*Math.sin(across/Math.hypot(dir[0], dir[1])*2*Math.PI/0.00055 + fbm3(tt*40, li, 0.2, 803, 2)*4)));
      } else {
        // a chip scar: shallow, concave, down to the body; its outer rim sharp
        const a = (best - w)/(we - w);
        chip = Math.max(chip, 1 - a*a);
        depth = Math.max(depth, 0.00075*(1 - a*a)*taper);
      }
    }
    const [t0, t1] = GASH_THROUGH[li];
    if (tt > t0 && tt < t1) {
      const k = Math.sin(Math.PI*(tt - t0)/(t1 - t0));
      slot = Math.max(slot, w*0.32*Math.pow(k, 0.6)*(1 + 0.4*(fbm3(tt*60, 0.5, li, 105, 2) - 0.5)) - best);
    }
  });
  return { depth, inside, wall, slot, chip, stria };
}

// ---------------------------------------------------------------- the hole: a break
const HOLE = [0.038, EY + 0.001], HRX = 0.0225, HRY = 0.0172;
const POLY = (() => {
  // straight fractures between nine corners, in the hole's own ellipse units
  const R = rand(9191), out = [];
  const n = 9;
  for (let k = 0; k < n; k++) {
    const a = (k + R.f(-0.32, 0.32))/n*2*Math.PI;
    const r = R.f(0.78, 1.18);
    out.push([Math.cos(a)*r, Math.sin(a)*r]);
  }
  return out;
})();
function poly_sd(u, v) {
  // signed distance to the polygon (ellipse units; < 0 inside)
  let d = 1e9, inside = false;
  for (let i = 0, j = POLY.length - 1; i < POLY.length; j = i++) {
    const [xi, yi] = POLY[i], [xj, yj] = POLY[j];
    d = Math.min(d, dseg(u, v, xj, yj, xi, yi)[0]);
    if ((yi > v) !== (yj > v) && u < (xj - xi)*(v - yi)/(yj - yi) + xi) inside = !inside;
  }
  return inside ? -d : d;
}
const CHIPS = (() => {
  // shell-shaped flakes off the front round the break: a corner of the outline, out along its way
  const R = rand(9292), out = [];
  for (let k = 0; k < 7; k++) {
    const a = R.f(0, 2*Math.PI);
    out.push({ a, len: R.f(0.35, 0.8), wid: R.f(0.25, 0.5) });
  }
  return out;
})();
const CRACKS = (() => {
  // hairlines from the break out across the glaze: each a zigzag, a few forking
  const R = rand(9393), out = [];
  const add = (x, y, a, len, seg) => {
    const pts = [[x, y]];
    let cx = x, cy = y, ca = a;
    const n = Math.max(2, Math.round(len/seg));
    for (let i = 0; i < n; i++) { ca += R.f(-0.45, 0.45); cx += Math.cos(ca)*seg; cy += Math.sin(ca)*seg; pts.push([cx, cy]); }
    out.push(pts);
    return pts;
  };
  for (let k = 0; k < 7; k++) {
    const a = k/7*2*Math.PI + R.f(-0.3, 0.3);
    const x0 = HOLE[0] + Math.cos(a)*HRX*1.05, y0 = HOLE[1] + Math.sin(a)*HRY*1.05;
    const pts = add(x0, y0, a, R.f(0.012, 0.04), 0.003);
    if (R.next() < 0.5) { const m = pts[Math.floor(pts.length/2)]; add(m[0], m[1], a + R.f(-0.9, 0.9), R.f(0.006, 0.016), 0.0025); }
  }
  // one ring crack partly round it
  const ring = [];
  for (let i = 0; i <= 14; i++) { const a = 0.4 + i/14*2.6; ring.push([HOLE[0] + Math.cos(a)*HRX*1.75, HOLE[1] + Math.sin(a)*HRY*1.75 + (R.next() - 0.5)*0.001]); }
  out.push(ring);
  return out;
})();
function pierce(x, y) {
  const u = (x - HOLE[0])/HRX, v = (y - HOLE[1])/HRY;
  const sd = poly_sd(u, v) + (fbm3(u*9, v*9, 0.4, 905, 2) - 0.5)*0.07;
  const k = (HRX + HRY)*0.5;
  const r_out = sd*k;                         // metres outside the break (< 0 inside)
  let chip = 0;
  for (const c of CHIPS) {
    const ex = Math.cos(c.a), ey = Math.sin(c.a);
    const along = u*ex + v*ey - 0.95, across = -u*ey + v*ex;
    if (along < -0.2 || along > c.len) continue;
    const q = Math.hypot(Math.max(0, along)/c.len, across/c.wid);
    if (q < 1) chip = Math.max(chip, 1 - q*q);
  }
  let crack = 0;
  if (r_out > -0.002 && r_out < 0.05) for (const pts of CRACKS) {
    for (let i = 0; i < pts.length - 1; i++) {
      const [d, uu] = dseg(x, y, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1]);
      const tw = 0.00028*(1 - 0.5*(i + uu)/pts.length);
      if (d < tw*2.5) crack = Math.max(crack, sstep(tw*2.5, tw*0.4, d));
    }
  }
  return { sd, r_out, chip, crack, in_hole: sd < 0 };
}

// ---------------------------------------------------------------- the blood (round 33-34's, older now)
const SPRAY = (() => {
  const R = rand(4242), out = [];
  for (let i = 0; i < 55; i++) {
    const up = R.next() < 0.12;
    const g = (R.next() + R.next() + R.next() - 1.5)*1.25;
    const a = up ? R.f(0.3, 2.8) : -Math.PI/2 + g;
    const far = Math.pow(R.next(), 1.7);
    const d = 0.004 + far*(up ? 0.022 : 0.05);
    const size = (0.0021 - 0.0014*far)*R.f(0.4, 1.0);
    const ex = HOLE[0] + Math.cos(a)*(HRX + d), ey = HOLE[1] + Math.sin(a)*(HRY + d*0.85);
    let ux = Math.cos(a), uy = Math.sin(a) - 0.9;
    const ul = Math.hypot(ux, uy); ux /= ul; uy /= ul;
    out.push([ex, ey, ux, uy, size, 1 + far*2.2 + R.f(0, 0.8) + (up ? 0 : R.f(0, 1.4))]);
  }
  return out;
})();
function blood(x, y, p) {
  let m = 0, rim = 0;
  if (p.r_out < 0.0035 && p.r_out > 0) { m = sstep(0.0035, 0.0008, p.r_out)*0.85; rim = sstep(0.001, 0.003, p.r_out); }
  {
    const y0 = HOLE[1] - HRY*0.9, len = 0.064, v = (y0 - y)/len;
    if (v >= -0.05 && v <= 1.12) {
      const cx = HOLE[0] - 0.004 + 0.0008*Math.sin(y*230) + 0.0004*Math.sin(y*690);
      const w = 0.0024*(1 - 0.5*Math.min(1, Math.max(0, v)));
      const a = v <= 1 ? Math.abs(x - cx)/w : 9, bq = Math.hypot(x - cx, (y - (y0 - len))*0.8)/(w*1.4), q = Math.min(a, bq);
      if (q < 1) { m = 1; rim = sstep(0.55, 0.95, q); }
    }
  }
  if (m < 1) for (const [ex, ey, ux, uy, sz, el] of SPRAY) {
    const dx = x - ex, dy = y - ey;
    if (Math.abs(dx) > sz*el*1.6 || Math.abs(dy) > sz*el*1.6) continue;
    const along = dx*ux + dy*uy, across = -dx*uy + dy*ux;
    const q = Math.hypot(along/(sz*(along > 0 ? el : 1)), across/sz);
    if (q < 1) { m = 1; rim = Math.max(rim, sstep(0.5, 0.95, q)); break; }
  }
  return { m, rim };
}

// ---------------------------------------------------------------- the soot (the baby's)
// the fire was below and to the wearer's left: soot over that side of the face (the viewer's right,
// round the break) and along the bottom, an edge across it ragged at two scales and soft; tongues
// where it climbed past the edge; specks beyond; thick in every hollow, thin and grey where it is
// only a film (patches the colour of smoke, as on the child's cheek)
export function soot(x, y) {
  // the edge's line bent at large scale (a fire licks, it does not rule lines), then ragged at three
  const wx = x + (fbm3(x*7, y*7, 0.3, 809, 2) - 0.5)*0.06, wy = y + (fbm3(x*7 + 3.1, y*7, 0.6, 810, 2) - 0.5)*0.04;
  const b = wx*0.9 - (wy - EY)*0.42 + 0.006
    + (fbm3(x*120, y*120, 1.1, 811, 2) - 0.5)*0.012 + (fbm3(x*48, y*48, 1.7, 812, 3) - 0.5)*0.03 + (fbm3(x*16, y*16, 2.3, 813, 2) - 0.5)*0.05;
  let s = sstep(-0.02, 0.014, b);
  // blotches past the edge (where smoke curled onto the clean side)
  s = Math.max(s, sstep(0.6, 0.7, fbm3(x*22, y*22, 6.2, 814, 3))*sstep(-0.07, -0.005, b)*0.85);
  // tongues: streaks rising from the edge on the clean side (stretched upward)
  const q = (fbm3(x*12, y*12, 4.4, 815, 2) - 0.5)*1.6;
  const tn = fbm3(x*48 + q, y*7 - q*0.3, 5.1, 817, 3);
  s = Math.max(s, sstep(0.6, 0.72, tn)*sstep(-0.05, -0.002, b)*sstep(0.1, -0.03, y - EY)*0.9);
  // the bottom edge of the face, all along
  s = Math.max(s, sstep(EY - 0.06, EY - 0.1, y)*0.8*sstep(-0.06, 0.0, b + 0.03));
  // specks beyond the edge
  const sp = fbm3(x*260, y*260, 0.7, 819, 2);
  if (b > -0.05 && b < 0) s = Math.max(s, sstep(0.72, 0.78, sp)*0.8);
  // how thick: mottled at two scales (thin smoke-grey patches show through, as on the child's cheek)
  const dens = Math.min(1, Math.max(0, 0.25 + 0.55*fbm3(x*26, y*26, 3.3, 821, 3) + 0.4*(fbm3(x*7, y*7, 8.8, 823, 2) - 0.5)*2 + 0.65*sstep(0.0, 0.035, b)));
  return { s, dens };
}

// ---------------------------------------------------------------- the shape
function field(x, y, z) {
  const o = outline(x, y);
  if (o > 0.012) return o;
  const f = face(x, y);
  const s = slit(x, y), cl = claws(x, y), p = pierce(x, y);
  const bl = blood(x, y, p);
  let front = f - (s > 0 ? GROOVE*Math.min(1, s*3) : 0);
  front += -cl.depth - 0.0009*p.chip - 0.00022*p.crack + 0.00025*bl.m*(1 - 0.5*bl.rim);
  // the back: the shell; spalled off wide round the break's exit (a cone of loss)
  const back = f - T + 0.0026*sstep(0.016, 0.0, p.r_out);
  let d = Math.max(z - front, back - z);
  d = smax(d, o, 0.0012);
  d = Math.max(d, -p.r_out);                                 // the break, straight through
  d = Math.max(d, cl.slot);                                   // the gashes, through where deepest
  return d;
}

let CACHE = null;
export function geometry() {
  if (CACHE) return CACHE;
  const g = largest_piece(mesh_sdf(field, [-0.1, -0.09, -0.075, 0.1, 0.118, 0.022], 0.0007));
  const P = g.attributes.position, n = P.count;
  const col = new Float32Array(n*3), mr = new Float32Array(n*2);
  const GLAZE = [0.70, 0.672, 0.615], BODY = [0.56, 0.54, 0.505], SOOT = [0.0095, 0.008, 0.0072], FILM = [0.105, 0.095, 0.085];
  for (let i = 0; i < n; i++) {
    const x = P.getX(i), y = P.getY(i), z = P.getZ(i);
    const f = face(x, y), sl = slit(x, y), cl = claws(x, y), p = pierce(x, y), bl = blood(x, y, p), so = soot(x, y);
    const front = z > f - T*0.6;
    const wall = sstep(0.0012, 0.0, p.r_out);             // the break's own section
    const t = fbm3(x*70, y*70, 2.2, 55, 3);
    let c = GLAZE.slice(), rough = 0.3 + 0.08*t;
    if (!front) { c = BODY.slice(); rough = 0.88; }
    // unglazed body where the glaze is gone: the break's section, its chips, the grooves and their chips
    const bare = Math.max(wall, front ? Math.max(p.chip, cl.inside, cl.chip*0.9) : 0);
    for (let k = 0; k < 3; k++) c[k] += (BODY[k] - c[k])*bare;
    rough += (0.86 - rough)*bare;
    if (front) {
      // the slits: shadowed in, a little darker
      if (sl > 0.05) { const w = sstep(0.05, 0.7, sl); for (let k = 0; k < 3; k++) c[k] *= 1 - 0.35*w; }
      // the claw's scratches along the groove floors
      if (cl.inside > 0) for (let k = 0; k < 3; k++) c[k] *= 1 - 0.18*cl.stria*cl.inside;
      // hairlines: dark (dirt and soot drawn into them)
      for (let k = 0; k < 3; k++) c[k] *= 1 - 0.78*p.crack;
      // the blood: old, dried, brown-red, glossier where thick
      if (bl.m > 0) {
        const kk = bl.m*(0.85 + 0.15*t);
        const B = [0.045 + 0.03*bl.rim, 0.010 + 0.008*bl.rim, 0.007 + 0.005*bl.rim];
        for (let k = 0; k < 3; k++) c[k] += (B[k] - c[k])*kk;
        rough += (0.42 + 0.25*bl.rim - rough)*kk;
      }
    }
    // the soot over all of it (thickest in the hollows: the slits, the grooves, the break, the chips)
    let s = so.s;
    const hollow = Math.max(front ? Math.min(1, sl*1.5) : 0, cl.inside, p.chip, wall, p.crack);
    s = Math.min(1, s*(1 + 0.6*hollow) + hollow*0.35*so.s);
    if (!front) s *= 0.55;
    const dens = Math.min(1, so.dens + 0.3*hollow);
    const S = [FILM[0] + (SOOT[0] - FILM[0])*dens, FILM[1] + (SOOT[1] - FILM[1])*dens, FILM[2] + (SOOT[2] - FILM[2])*dens];
    for (let k = 0; k < 3; k++) c[k] += (S[k] - c[k])*s;
    rough += (0.95 - rough)*s;
    col[i*3] = c[0]; col[i*3 + 1] = c[1]; col[i*3 + 2] = c[2];
    mr[i*2] = 0; mr[i*2 + 1] = Math.min(1, Math.max(0.2, rough));
  }
  g.setAttribute('color', new THREE.BufferAttribute(col, 3));
  g.setAttribute('aMR', new THREE.BufferAttribute(mr, 2));
  CACHE = g;
  return g;
}
