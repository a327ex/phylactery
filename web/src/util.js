// util.js -- seeded rng, math helpers, springs, and the collision / raycast geometry that
// player, enemy and weapon all share. Pure functions over plain numbers; no three.js here.
//
// COLLIDER FORMAT (what room.js exports as room.colliders):
//   { x0, y0, z0, x1, y1, z1 }                  solid axis-aligned box, x0<x1 etc (use box())
//   { ..., ramp: '+x'|'-x'|'+z'|'-z' }           wedge inside that box whose top rises from y0 at
//                                                 the low edge to y1 at the edge named by `ramp`
//                                                 (use ramp()); walkable, blocks from the sides
//   optional flags: no_ray (bullets pass), no_walk (bodies pass), no_floor (never chosen as a
//                   spawn/teleport floor or nav surface: lids, clip ceilings), color (hex, used for
//                   impact debris), tag (any string)
// Bodies (player, enemy) are vertical capsules: feet at y, radius r, height h.

export const DT = 1 / 60;
export const DEG = Math.PI / 180;

// ---------------------------------------------------------------- rng
function splitmix(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x9e3779b9) >>> 0;
    let z = s;
    z = Math.imul(z ^ (z >>> 16), 0x85ebca6b);
    z = Math.imul(z ^ (z >>> 13), 0xc2b2ae35);
    return (z ^ (z >>> 16)) >>> 0;
  };
}

export function hash_str(str) {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < str.length; i++) h = Math.imul(h ^ str.charCodeAt(i), 16777619);
  return h >>> 0;
}

// sfc32 seeded through splitmix32. rng.next() in [0,1).
export function make_rng(seed = 1) {
  const sm = splitmix(seed);
  let a = sm(), b = sm(), c = sm(), d = sm();
  const next = () => {
    a >>>= 0; b >>>= 0; c >>>= 0; d >>>= 0;
    let t = (a + b) | 0;
    a = b ^ (b >>> 9);
    b = (c + (c << 3)) | 0;
    c = (c << 21) | (c >>> 11);
    d = (d + 1) | 0;
    t = (t + d) | 0;
    c = (c + t) | 0;
    return (t >>> 0) / 4294967296;
  };
  for (let i = 0; i < 12; i++) next();
  const rng = {
    seed,
    next,
    float: (lo = 0, hi = 1) => lo + (hi - lo)*next(),
    int: (lo, hi) => lo + Math.floor(next()*(hi - lo + 1)),     // inclusive
    chance: p => next() < p,
    sign: () => (next() < 0.5 ? -1 : 1),
    pick: arr => arr[Math.floor(next()*arr.length)],
    spread: s => (next()*2 - 1)*s,                                // symmetric in [-s, s]
    // a new independent stream derived from this seed + a tag
    fork: tag => make_rng((seed ^ hash_str(String(tag))) >>> 0),
  };
  return rng;
}

// ---------------------------------------------------------------- math
// the port to Anchor (2026-09-30): every material carries a stable name (the Anchor build's do too)
export const named = (m, name) => { m.name = name; return m; };
export const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
export const lerp = (a, b, t) => a + (b - a)*t;
export const inv_lerp = (a, b, x) => (x - a)/(b - a);
export const remap = (x, a, b, c, d) => c + (d - c)*clamp((x - a)/(b - a), 0, 1);
export const smoothstep = (a, b, x) => { const t = clamp((x - a)/(b - a), 0, 1); return t*t*(3 - 2*t); };
export const approach = (x, target, step) => (x < target ? Math.min(x + step, target) : Math.max(x - step, target));
// frame-rate independent exponential smoothing: rate = 1/time-constant
export const damp = (a, b, rate, dt) => lerp(a, b, 1 - Math.exp(-rate*dt));
export const ease_out_cubic = t => 1 - Math.pow(1 - t, 3);
export const ease_in_cubic = t => t*t*t;
export const ease_out_back = (t, k = 1.7) => 1 + (k + 1)*Math.pow(t - 1, 3) + k*Math.pow(t - 1, 2);
export const wrap_deg = a => { a = (a + 180) % 360; if (a < 0) a += 360; return a - 180; };
export const len2 = (x, z) => Math.sqrt(x*x + z*z);
export const len3 = (x, y, z) => Math.sqrt(x*x + y*y + z*z);

// compass heading convention used by the whole game and the GAME API:
// yaw 0 looks at -z, yaw 90 looks at +x. pitch > 0 looks up.
export const yaw_to = (x0, z0, x1, z1) => Math.atan2(x1 - x0, -(z1 - z0))/DEG;
export const forward_of = (yaw_deg, pitch_deg = 0) => {
  const y = yaw_deg*DEG, p = pitch_deg*DEG, cp = Math.cos(p);
  return [Math.sin(y)*cp, Math.sin(p), -Math.cos(y)*cp];
};

// damped spring (semi-implicit Euler, stable at 60 Hz for freq up to ~40 rad/s)
// s = {x, v}; omega = angular frequency (rad/s), zeta = damping ratio (1 = critical)
export function spring(s, target, omega, zeta, dt) {
  const a = -2*zeta*omega*s.v - omega*omega*(s.x - target);
  s.v += a*dt;
  s.x += s.v*dt;
  return s.x;
}
export const make_spring = (x = 0) => ({ x, v: 0 });

// smooth 1D value noise in [-1, 1], deterministic
export function noise1(x, seed = 0) {
  const i = Math.floor(x), f = x - i;
  const h = n => {
    let v = Math.imul((n + seed*7919) | 0, 0x27d4eb2d);
    v ^= v >>> 15; v = Math.imul(v, 0x85ebca6b); v ^= v >>> 13;
    return ((v >>> 0)/4294967296)*2 - 1;
  };
  const u = f*f*(3 - 2*f);
  return lerp(h(i), h(i + 1), u);
}

// ---------------------------------------------------------------- colliders
export function box(x0, y0, z0, x1, y1, z1, extra) {
  const c = {
    x0: Math.min(x0, x1), y0: Math.min(y0, y1), z0: Math.min(z0, z1),
    x1: Math.max(x0, x1), y1: Math.max(y0, y1), z1: Math.max(z0, z1),
  };
  return extra ? Object.assign(c, extra) : c;
}

// wedge: rises from y0 at the low edge to y1 at the side named by dir
export function ramp(x0, y0, z0, x1, y1, z1, dir, extra) {
  const c = box(x0, y0, z0, x1, y1, z1, extra);
  c.ramp = dir;
  c.H = c.y1 - c.y0;
  c.gx = 0; c.gz = 0; c.ax = 0; c.az = 0;
  if (dir === '+x') { c.gx = 1/(c.x1 - c.x0); c.ax = c.x0; }
  else if (dir === '-x') { c.gx = -1/(c.x1 - c.x0); c.ax = c.x1; }
  else if (dir === '+z') { c.gz = 1/(c.z1 - c.z0); c.az = c.z0; }
  else if (dir === '-z') { c.gz = -1/(c.z1 - c.z0); c.az = c.z1; }
  else throw new Error('ramp dir must be +x -x +z -z');
  return c;
}

// top surface height of a collider at (x, z) (clamped into its footprint)
export function surface_y(c, x, z) {
  if (!c.ramp) return c.y1;
  const px = clamp(x, c.x0, c.x1), pz = clamp(z, c.z0, c.z1);
  const u = clamp(c.gx*(px - c.ax) + c.gz*(pz - c.az), 0, 1);
  return c.y0 + c.H*u;
}

// does a circle (x, z, r) overlap the collider's footprint (strictly)?
export function circle_hits(c, x, z, r) {
  const px = clamp(x, c.x0, c.x1), pz = clamp(z, c.z0, c.z1);
  const dx = x - px, dz = z - pz;
  return dx*dx + dz*dz < r*r;
}

export function point_inside(c, x, y, z) {
  if (x <= c.x0 || x >= c.x1 || z <= c.z0 || z >= c.z1 || y <= c.y0) return false;
  return y < surface_y(c, x, z);
}

// highest walkable surface under a circle, not above max_y. -Infinity when nothing.
export function ground_at(cols, x, z, r, max_y = Infinity) {
  let g = -Infinity;
  for (const c of cols) {
    if (c.no_walk || !circle_hits(c, x, z, r)) continue;
    const top = surface_y(c, x, z);
    if (top <= max_y && top > g) g = top;
  }
  return g;
}

// floor under a point for teleports / spawns: the highest surface with headroom h above it
export function resolve_floor_y(cols, x, z, h = 1.8, r = 0.05) {
  const tops = [];
  for (const c of cols) if (!c.no_walk && !c.no_floor && circle_hits(c, x, z, r)) tops.push(surface_y(c, x, z));
  tops.sort((a, b) => b - a);
  for (const top of tops) {
    let clear = true;
    for (const c of cols) {
      if (c.no_walk || !circle_hits(c, x, z, r)) continue;
      if (c.y0 < top + h - 0.01 && surface_y(c, x, z) > top + 0.01) { clear = false; break; }
    }
    if (clear) return top;
  }
  return tops.length ? tops[tops.length - 1] : 0;
}

function headroom_ok(cols, x, z, r, y_new, h, y_now) {
  for (const c of cols) {
    if (c.no_walk) continue;
    if (c.y0 < y_new + h && c.y0 >= y_now + h - 0.02 && circle_hits(c, x, z, r - 0.01)) return false;
  }
  return true;
}

// horizontal circle push-out against every collider that is a wall at this height.
// Colliders whose top at the contact point is within step_allow of the feet are left for the
// vertical pass (that is the step-up). Returns true if a wall was touched.
export function push_out(b, cols, step_allow) {
  let touched = false;
  for (let pass = 0; pass < 4; pass++) {
    let moved = false;
    for (const c of cols) {
      if (c.no_walk) continue;
      if (c.y0 >= b.y + b.h - 0.01) continue;                    // entirely above the head
      const px = clamp(b.x, c.x0, c.x1), pz = clamp(b.z, c.z0, c.z1);
      const ddx = b.x - px, ddz = b.z - pz, d2 = ddx*ddx + ddz*ddz;
      if (d2 >= b.r*b.r) continue;
      const top = surface_y(c, px, pz);
      if (top <= b.y + 0.001) continue;                            // below the feet
      if (top <= b.y + step_allow && headroom_ok(cols, b.x, b.z, b.r, top, b.h, b.y)) continue;
      let nx, nz, pen;
      if (d2 > 1e-12) {
        const d = Math.sqrt(d2);
        nx = ddx/d; nz = ddz/d; pen = b.r - d;
      } else {                                                     // centre inside: nearest side
        const l = b.x - c.x0, rr = c.x1 - b.x, bk = b.z - c.z0, f = c.z1 - b.z;
        const m = Math.min(l, rr, bk, f);
        if (m === l) { nx = -1; nz = 0; pen = l + b.r; }
        else if (m === rr) { nx = 1; nz = 0; pen = rr + b.r; }
        else if (m === bk) { nx = 0; nz = -1; pen = bk + b.r; }
        else { nx = 0; nz = 1; pen = f + b.r; }
      }
      b.x += nx*(pen + 1e-5); b.z += nz*(pen + 1e-5);
      const vn = b.vx*nx + b.vz*nz;
      if (vn < 0) { b.vx -= vn*nx; b.vz -= vn*nz; }
      touched = moved = true;
    }
    if (!moved) break;
  }
  return touched;
}

// Kinematic capsule mover shared by player and enemy.
//   b = {x, y, z, vx, vy, vz, r, h, grounded}  (y = feet). Gravity is the caller's job.
//   o = {step, air_step, snap}
// Returns events: {landed: impact speed or 0, step_dy: vertical snap while grounded, wall, ceiling}
export function move_body(b, cols, dt, o) {
  const ev = { landed: 0, step_dy: 0, wall: false, ceiling: false };
  const y_before = b.y, was_grounded = b.grounded;
  const dx = b.vx*dt, dz = b.vz*dt;
  const n = Math.max(1, Math.ceil(Math.hypot(dx, dz)/(b.r*0.45)));
  const allow = was_grounded ? o.step : o.air_step;
  for (let i = 0; i < n; i++) {
    b.x += dx/n; b.z += dz/n;
    if (push_out(b, cols, allow)) ev.wall = true;
  }
  const vy_before = b.vy;
  b.y += b.vy*dt;
  // ceiling: colliders that were above the head before this move
  const rr = b.r - 0.01;
  if (b.vy > 0) {
    let ceil = Infinity;
    for (const c of cols) {
      if (c.no_walk || c.y0 < y_before + b.h - 0.02 || !circle_hits(c, b.x, b.z, rr)) continue;
      if (c.y0 < ceil) ceil = c.y0;
    }
    if (b.y + b.h > ceil) { b.y = ceil - b.h; b.vy = 0; ev.ceiling = true; }
  }
  // ground: highest surface under the circle that is not a ceiling
  let ground = -Infinity;
  for (const c of cols) {
    if (c.no_walk || !circle_hits(c, b.x, b.z, rr)) continue;
    if (c.y0 >= y_before + b.h - 0.02) continue;
    const top = surface_y(c, b.x, b.z);
    if (top <= Math.max(y_before, b.y) + allow + 0.001 && top > ground) ground = top;
  }
  b.grounded = false;
  if (b.vy <= 0) {
    if (b.y <= ground) { b.y = ground; b.vy = 0; b.grounded = true; }
    else if (was_grounded && b.y - ground <= o.snap) { b.y = ground; b.vy = 0; b.grounded = true; }
  } else if (b.y < ground) {
    b.y = ground;
  }
  if (b.grounded && !was_grounded) ev.landed = Math.max(0, -vy_before);
  if (b.grounded && was_grounded) ev.step_dy = b.y - y_before;
  return ev;
}

// ---------------------------------------------------------------- raycasts
// ray vs one collider; returns {t, nx, ny, nz} of the entry point or null (origin inside = miss)
export function ray_collider(c, ox, oy, oz, dx, dy, dz, max_t) {
  let tmin = -Infinity, tmax = Infinity, nx = 0, ny = 0, nz = 0;
  // slabs
  const slab = (o, d, lo, hi, ax) => {
    if (Math.abs(d) < 1e-12) return o > lo && o < hi;
    let t1 = (lo - o)/d, t2 = (hi - o)/d, s = -1;
    if (t1 > t2) { const tmp = t1; t1 = t2; t2 = tmp; s = 1; }
    if (t1 > tmin) { tmin = t1; nx = ny = nz = 0; if (ax === 0) nx = s; else if (ax === 1) ny = s; else nz = s; }
    if (t2 < tmax) tmax = t2;
    return tmin <= tmax;
  };
  if (!slab(ox, dx, c.x0, c.x1, 0) || !slab(oy, dy, c.y0, c.y1, 1) || !slab(oz, dz, c.z0, c.z1, 2)) return null;
  if (c.ramp) {
    // inside: y - y0 - H*u(x,z) <= 0, u = gx*(x-ax) + gz*(z-az)
    const gxw = -c.H*c.gx, gzw = -c.H*c.gz;
    const f0 = oy - c.y0 + gxw*(ox - c.ax) + gzw*(oz - c.az);
    const fd = dy + gxw*dx + gzw*dz;
    if (Math.abs(fd) < 1e-12) { if (f0 > 0) return null; }
    else {
      const ts = -f0/fd;
      if (fd < 0) {
        if (ts > tmin) { tmin = ts; const l = Math.hypot(gxw, 1, gzw); nx = gxw/l; ny = 1/l; nz = gzw/l; }
      } else if (ts < tmax) tmax = ts;
      if (tmin > tmax) return null;
    }
  }
  if (tmax < 0 || tmin < 0 || tmin > max_t) return null;
  return { t: tmin, nx, ny, nz };
}

// nearest hit along a ray against the collider list (dir need not be unit; t is in dir units)
export function raycast(cols, ox, oy, oz, dx, dy, dz, max_t = 1e9) {
  let best = null, bt = max_t;
  for (const c of cols) {
    if (c.no_ray) continue;
    const r = ray_collider(c, ox, oy, oz, dx, dy, dz, bt);
    if (r && r.t < bt) { bt = r.t; best = r; best.c = c; }
  }
  if (best) { best.x = ox + dx*bt; best.y = oy + dy*bt; best.z = oz + dz*bt; }
  return best;
}

// clear line between two points?
export function line_clear(cols, ax, ay, az, bx, by, bz) {
  return !raycast(cols, ax, ay, az, bx - ax, by - ay, bz - az, 1);
}

// ray vs vertical capsule (segment (cx,y0,cz)-(cx,y1,cz), radius r). returns t or Infinity
export function ray_capsule(ox, oy, oz, dx, dy, dz, cx, y0, y1, cz, r) {
  let best = Infinity;
  // cylinder side
  const px = ox - cx, pz = oz - cz;
  const a = dx*dx + dz*dz;
  if (a > 1e-12) {
    const bq = 2*(px*dx + pz*dz), cq = px*px + pz*pz - r*r;
    const disc = bq*bq - 4*a*cq;
    if (disc >= 0) {
      const t = (-bq - Math.sqrt(disc))/(2*a);
      const y = oy + dy*t;
      if (t >= 0 && y >= y0 && y <= y1) best = t;
    }
  }
  // end spheres
  const sph = (sy) => {
    const qx = ox - cx, qy = oy - sy, qz = oz - cz;
    const A = dx*dx + dy*dy + dz*dz, B = 2*(qx*dx + qy*dy + qz*dz), C = qx*qx + qy*qy + qz*qz - r*r;
    const D = B*B - 4*A*C;
    if (D < 0) return;
    const t = (-B - Math.sqrt(D))/(2*A);
    if (t >= 0 && t < best) best = t;
  };
  sph(y0); sph(y1);
  return best;
}

// sphere overlap vs colliders -> the first collider touched, or null
export function sphere_hits(cols, x, y, z, r) {
  for (const c of cols) {
    if (c.no_ray) continue;
    const px = clamp(x, c.x0, c.x1), pz = clamp(z, c.z0, c.z1);
    const top = surface_y(c, px, pz);
    const py = clamp(y, c.y0, top);
    const dx = x - px, dy = y - py, dz = z - pz;
    if (dx*dx + dy*dy + dz*dz < r*r) return c;
  }
  return null;
}

// distance from a point to a vertical segment (for capsule overlap tests)
export function dist_to_vseg(x, y, z, cx, y0, y1, cz) {
  const cy = clamp(y, y0, y1);
  return len3(x - cx, y - cy, z - cz);
}
