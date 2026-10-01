// coil.js -- the ending (round 36; owner, 2026-09-29): "As a snake reaches the egg, it coils
// around it. The more snakes reach, the more they cover of the egg's surface as they rotate
// around it, and then eventually you win when they cover it entirely."
//
// The egg's geometry (its surface and normals, from the same formula cave.js builds it with),
// where each arriving snake coils, and how much of the egg is covered. Plain numbers, no three.js,
// so node can test it (tools/coil_test.mjs).
//
// A snake is 4.4 m and the egg 0.8 m tall: laid in tight rows, one snake covers ~45% of the shell
// and two finish it. So by default (KNOT) each snake wraps ~2 turns around its own tilted axis, a
// band round the egg's middle at a tilt nobody has taken yet, crossing over the ones already
// there; it takes ~6-8 to hide the egg, which grows into a ball of snakes. STACKED is the tight
// rows, from the bottom up, for comparison. Once coiled, each band turns about its own axis (the
// body slides along itself, like a barber's pole), so the ball churns.

export const COIL_MODES = ['KNOT: EACH AT ITS OWN TILT, OVER THE OTHERS', 'STACKED: TIGHT ROWS FROM THE BOTTOM UP'];

const EGG_S = 0.8;                  // cave.js: the egg is 0.8 m tall, its shell centred 0.4 m up
export const OFF = 0.056;           // a full-width body's centre above the shell (its flat belly)
const SPACING = 0.152;              // between neighbouring turns: a body width, a little overlapped
const MAX_TILT = 1.1;               // a band's axis at most ~63 deg off vertical (under ~50 no band reaches the top; past it they sink under the egg)
const E_VIS = -0.9;                 // below this elevation the shell is in the mound: not counted

const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const norm = v => { const l = Math.hypot(v[0], v[1], v[2]) || 1; return [v[0]/l, v[1]/l, v[2]/l]; };
const dot = (a, b) => a[0]*b[0] + a[1]*b[1] + a[2]*b[2];
const cross = (a, b) => [a[1]*b[2] - a[2]*b[1], a[2]*b[0] - a[0]*b[2], a[0]*b[1] - a[1]*b[0]];

// the shell's profile (cave.js: a sphere of 0.5 scaled 0.78 x taper sideways, x0.8 overall), as
// a table by elevation seen from the centre: point (h, y) and outward normal (nh, ny)
const PROF = [];
{
  const taper = qy => 1 - 0.14*clamp(qy/0.5, 0, 1) + 0.03*clamp(-qy/0.5, 0, 1);
  const P = qy => [Math.sqrt(Math.max(0, 0.25 - qy*qy))*0.78*taper(qy)*EGG_S, qy*EGG_S];
  const NT = 720;
  for (let i = 0; i <= NT; i++) {
    const qy = -0.5 + i/NT;
    const [h, y] = P(qy);
    const a = P(Math.max(-0.5, qy - 1e-4)), b = P(Math.min(0.5, qy + 1e-4));
    const th = b[0] - a[0], ty = b[1] - a[1];
    const l = Math.hypot(ty, th) || 1;
    PROF.push({ e: Math.atan2(y, h), h, y, nh: ty/l, ny: -th/l });
  }
}
function profile(e) {
  let lo = 0, hi = PROF.length - 1;
  if (e <= PROF[0].e) return PROF[0];
  if (e >= PROF[hi].e) return PROF[hi];
  while (hi - lo > 1) { const m = (lo + hi) >> 1; if (PROF[m].e < e) lo = m; else hi = m; }
  const A = PROF[lo], B = PROF[hi], f = (e - A.e)/((B.e - A.e) || 1);
  return { h: A.h + (B.h - A.h)*f, y: A.y + (B.y - A.y)*f, nh: A.nh + (B.nh - A.nh)*f, ny: A.ny + (B.ny - A.ny)*f };
}

export function create_coil({ centre, ground_y, rng, len }) {
  const C = centre;                                   // [x, y, z]: the shell's centre, world
  // the shell point in direction d from the centre (world), and its outward normal
  function surface(d, out_p, out_n) {
    const hl = Math.hypot(d[0], d[2]);
    const ux = hl > 1e-6 ? d[0]/hl : 1, uz = hl > 1e-6 ? d[2]/hl : 0;
    const p = profile(Math.asin(clamp(d[1], -1, 1)));
    out_p[0] = C[0] + ux*p.h; out_p[1] = C[1] + p.y; out_p[2] = C[2] + uz*p.h;
    const nl = Math.hypot(p.nh, p.ny) || 1;
    out_n[0] = ux*p.nh/nl; out_n[1] = p.ny/nl; out_n[2] = uz*p.nh/nl;
  }
  const TP = [0, 0, 0], TN = [0, 0, 0];
  const lifted = (d, off, out) => { surface(d, TP, TN); out[0] = TP[0] + TN[0]*off; out[1] = TP[1] + TN[1]*off; out[2] = TP[2] + TN[2]*off; return out; };

  // where a snake crawling in from (hx, hz) meets the shell: the direction whose lifted point
  // sits at its body's height on the floor, on its side of the egg
  function base_dir(hx, hz, body_h) {
    let ux = hx - C[0], uz = hz - C[2]; const l = Math.hypot(ux, uz) || 1; ux /= l; uz /= l;
    let best = null, bd = Infinity; const q = [0, 0, 0];
    for (let e = -1.45; e < 0.3; e += 0.01) {
      const d = [ux*Math.cos(e), Math.sin(e), uz*Math.cos(e)];
      lifted(d, OFF, q);
      const want = ground_y(q[0], q[2]) + body_h;
      const err = Math.abs(q[1] - want);
      if (err < bd) { bd = err; best = d; }
    }
    return best;
  }

  // ------------------------------------------------------------------ coverage
  // Samples spread evenly over the directions (a Fibonacci sphere), weighted by the shell area
  // each stands for; the ones in the mound don't count.
  const NS = 900, SMP = [];
  {
    const ga = Math.PI*(3 - Math.sqrt(5));
    for (let i = 0; i < NS; i++) {
      const y = 1 - 2*(i + 0.5)/NS, r = Math.sqrt(1 - y*y), a = i*ga;
      const d = [Math.cos(a)*r, y, Math.sin(a)*r];
      if (Math.asin(y) < E_VIS) continue;
      const p = [0, 0, 0], n = [0, 0, 0];
      surface(d, p, n);
      const rr = Math.hypot(p[0] - C[0], p[1] - C[1], p[2] - C[2]);
      SMP.push({ d, p, w: rr*rr/Math.max(0.3, dot(d, n)) });
    }
  }
  const W_ALL = SMP.reduce((a, s) => a + s.w, 0);
  // what is covered: `bodies` = [{ foot: [[x,y,z]...], rad: [..], on: [bool..] }] (foot = the shell
  // point under each ring); a sample is covered when a body segment passes within its radius
  function coverage(bodies, out_mask) {
    let wc = 0;
    for (let k = 0; k < SMP.length; k++) {
      const s = SMP[k], p = s.p;
      let hit = false;
      for (const b of bodies) {
        const F = b.foot, R = b.rad, O = b.on;
        for (let i = 0; i < F.length - 1 && !hit; i++) {
          if (!O[i] || !O[i + 1]) continue;
          const a = F[i], c = F[i + 1];
          const ex = c[0] - a[0], ey = c[1] - a[1], ez = c[2] - a[2];
          const L2 = ex*ex + ey*ey + ez*ez || 1e-9;
          let t = ((p[0] - a[0])*ex + (p[1] - a[1])*ey + (p[2] - a[2])*ez)/L2; t = clamp(t, 0, 1);
          const dx = a[0] + ex*t - p[0], dy = a[1] + ey*t - p[1], dz = a[2] + ez*t - p[2];
          const r = (R[i] + (R[i + 1] - R[i])*t)*0.95;
          if (dx*dx + dy*dy + dz*dz < r*r) hit = true;
        }
        if (hit) break;
      }
      if (out_mask) out_mask[k] = hit ? 1 : 0;
      if (hit) wc += s.w;
    }
    return wc/W_ALL;
  }

  // ------------------------------------------------------------------ bands
  // A band: `dirs` (unit directions from the centre, tail end first, at rotation 0), `arc`
  // (cumulative arc along the lifted path), the axis it turns about and which way (sigma),
  // `rho` (its mean distance from the axis, for the turning speed), and what it planned to cover.
  const frame = (a) => {
    const t = Math.abs(a[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0];
    const e1 = norm(cross(t, a)), e2 = cross(a, e1);
    return [e1, e2];
  };
  const dir_at = (a, e1, e2, th, ph) => {
    const s = Math.sin(th), c = Math.cos(th), cp = Math.cos(ph), sp = Math.sin(ph);
    return [a[0]*c + (e1[0]*cp + e2[0]*sp)*s, a[1]*c + (e1[1]*cp + e2[1]*sp)*s, a[2]*c + (e1[2]*cp + e2[2]*sp)*s];
  };
  function arcs_of(dirs) {
    const arc = [0], q0 = [0, 0, 0], q1 = [0, 0, 0];
    lifted(dirs[0], OFF, q0);
    for (let i = 1; i < dirs.length; i++) {
      lifted(dirs[i], OFF, q1);
      arc.push(arc[i - 1] + Math.hypot(q1[0] - q0[0], q1[1] - q0[1], q1[2] - q0[2]));
      q0[0] = q1[0]; q0[1] = q1[1]; q0[2] = q1[2];
    }
    return arc;
  }
  const mean_rho = (a, e1, e2) => {
    let s = 0; const q = [0, 0, 0];
    for (let k = 0; k < 24; k++) { lifted(dir_at(a, e1, e2, Math.PI/2, k/24*Math.PI*2), OFF, q); const v = [q[0] - C[0], q[1] - C[1], q[2] - C[2]]; const al = dot(v, a); s += Math.sqrt(Math.max(0, dot(v, v) - al*al)); }
    return s/24;
  };
  // the helix round axis a from theta0 to theta1 through Phi radians of turn, starting at phi0, sigma = +-1
  function helix(a, e1, e2, th0, th1, phi0, sigma, Phi) {
    const n = Math.max(8, Math.ceil(Phi/0.03));
    const dirs = [];
    for (let k = 0; k <= n; k++) { const f = k/n; dirs.push(dir_at(a, e1, e2, th0 + (th1 - th0)*f, phi0 + sigma*Phi*f)); }
    return dirs;
  }
  // KNOT: a band round axis a, ~2 turns, its width set so the turns lie a body apart, exactly the
  // snake's length long; entered from d_b at the nearer edge, turning the way the snake arrives
  function knot_band(a, d_b, heading) {
    const [e1, e2] = frame(a);
    const rho = mean_rho(a, e1, e2);
    const W = SPACING/(rho + 0.02);                 // radians of theta between turns
    let Phi = 4*Math.PI, beta = 0, th0 = 0, th1 = 0, phi0 = 0, sigma = 1, dirs = null, arc = null;
    const tb = Math.acos(clamp(dot(d_b, a), -1, 1));
    const v = [d_b[0] - a[0]*dot(d_b, a), d_b[1] - a[1]*dot(d_b, a), d_b[2] - a[2]*dot(d_b, a)];
    phi0 = Math.atan2(dot(v, e2), dot(v, e1));
    for (let it = 0; it < 6; it++) {
      beta = W*Phi/(4*Math.PI);
      th0 = tb > Math.PI/2 ? Math.PI/2 + beta : Math.PI/2 - beta;
      th1 = tb > Math.PI/2 ? Math.PI/2 - beta : Math.PI/2 + beta;
      dirs = helix(a, e1, e2, th0, th1, phi0, sigma, Phi);
      arc = arcs_of(dirs);
      Phi *= len/arc[arc.length - 1];
    }
    // which way round: the one that carries on from how it arrives (up the stem, or its heading)
    const d0 = dirs[0];
    const tan = s => { const q = dir_at(a, e1, e2, th0, phi0 + s*0.05); return [q[0] - d0[0], q[1] - d0[1], q[2] - d0[2]]; };
    let way = [d0[0] - d_b[0], d0[1] - d_b[1], d0[2] - d_b[2]];
    if (Math.hypot(...way) < 0.08) way = [heading[0], 0, heading[1]];
    sigma = dot(tan(1), way) >= dot(tan(-1), way) ? 1 : -1;
    dirs = helix(a, e1, e2, th0, th1, phi0, sigma, Phi);
    arc = arcs_of(dirs);
    return { axis: a, sigma, rho, dirs, arc, beta, turns: Phi/(2*Math.PI), covers: d => Math.abs(dot(d, a)) < Math.sin(beta*0.92) };
  }

  // STACKED: one tight helix round the vertical from the mound to near the top, cut into
  // snake-length pieces taken in order from the bottom; each piece turned about the vertical so
  // it starts on the arriving snake's side
  const UPA = [0, 1, 0], [UE1, UE2] = frame(UPA);
  const STACK = (() => {
    const rho = 0.36, W = SPACING/(rho + 0.02);
    const TH_BOT = Math.PI/2 - E_VIS + 0.05, TH_TOP = 0.3;
    const Phi = (TH_BOT - TH_TOP)/W*2*Math.PI;
    const dirs = helix(UPA, UE1, UE2, TH_BOT, TH_TOP, 0, 1, Phi);
    const arc = arcs_of(dirs);
    return { dirs, arc, total: arc[arc.length - 1], W };
  })();
  let stack_next = 0;
  function stacked_band(d_b) {
    const k = stack_next;
    const s0 = k*len*0.96;
    if (s0 + len > STACK.total + 0.3) return null;  // the rows are full (the rest go on as KNOT)
    stack_next++;
    const A = STACK.arc;
    let i0 = A.findIndex(x => x >= s0); if (i0 < 0) i0 = A.length - 1;
    let i1 = A.findIndex(x => x >= s0 + len); if (i1 < 0) i1 = A.length - 1;
    const piece = STACK.dirs.slice(i0, i1 + 1);
    // turn it about the vertical so it starts on the snake's side
    const az = d => Math.atan2(d[2], d[0]);
    const r = az(d_b) - az(piece[0]), cr = Math.cos(r), sr = Math.sin(r);
    const dirs = piece.map(d => [d[0]*cr - d[2]*sr, d[1], d[0]*sr + d[2]*cr]);
    const arc = arcs_of(dirs);
    const t0 = Math.acos(clamp(dirs[0][1], -1, 1)), t1 = Math.acos(clamp(dirs[dirs.length - 1][1], -1, 1));
    return { axis: UPA, sigma: 1, rho: 0.3, dirs, arc, stacked: k, covers: d => { const t = Math.acos(clamp(d[1], -1, 1)); return t <= t0 + STACK.W*0.5 && t >= t1 - STACK.W*0.5; } };
  }

  // choosing a KNOT axis: the one whose band covers the most of what nothing covers yet (counting
  // bands already planned for snakes still coiling), a little at random so no two eggs coil alike
  function pick_axis(covered_count) {
    let best = null, bs = -Infinity;
    for (let c = 0; c < 72; c++) {
      // a random axis within MAX_TILT of vertical, either way up (the same band)
      const ct = 1 - rng.next()*(1 - Math.cos(MAX_TILT)), st = Math.sqrt(1 - ct*ct), ph = rng.next()*Math.PI*2;
      const a = [Math.cos(ph)*st, ct, Math.sin(ph)*st];
      const sb = Math.sin(0.36*0.92);
      let sc = 0;
      for (let k = 0; k < SMP.length; k++) {
        if (Math.abs(dot(SMP[k].d, a)) >= sb) continue;
        const n = covered_count[k];
        sc += SMP[k].w*(n === 0 ? 1 : 0.12/n);
      }
      sc *= 1 + 0.08*rng.next();
      if (sc > bs) { bs = sc; best = a; }
    }
    return best;
  }

  // the way from where it meets the shell to where its band starts, over the shell
  function stem(d_b, d_s) {
    const ang = Math.acos(clamp(dot(d_b, d_s), -1, 1));
    const n = Math.max(1, Math.ceil(ang/0.04));
    const out = [];
    for (let k = 0; k <= n; k++) {
      const f = k/n;
      if (ang < 1e-4) { out.push(d_b.slice()); continue; }
      const s = Math.sin(ang), wa = Math.sin((1 - f)*ang)/s, wb = Math.sin(f*ang)/s;
      out.push(norm([d_b[0]*wa + d_s[0]*wb, d_b[1]*wa + d_s[1]*wb, d_b[2]*wa + d_s[2]*wb]));
    }
    return out;
  }

  // plan the coil of a snake meeting the shell at d_b, arriving along `heading` ([x, z]):
  // `planned` = the bands of the snakes already coiling or coiled, `covered` = the samples the
  // coiled bodies actually cover now (a mask), so a new band goes where the egg still shows
  function plan(mode, d_b, heading, planned, covered) {
    let band = mode === 1 ? stacked_band(d_b) : null;
    if (!band) {
      const cnt = new Uint16Array(SMP.length);
      for (let k = 0; k < SMP.length; k++) {
        if (covered && covered[k]) cnt[k]++;
        for (const b of planned) if (b.covers(SMP[k].d)) cnt[k]++;
      }
      band = knot_band(pick_axis(cnt), d_b, heading);
    }
    const st = stem(d_b, band.dirs[0]);
    return { band, stem: st, stem_arc: arcs_of(st) };
  }

  return { C, surface, lifted, base_dir, plan, coverage, samples: SMP, stack: STACK, reset() { stack_next = 0; },
    get stack_used() { return stack_next; } };
}
