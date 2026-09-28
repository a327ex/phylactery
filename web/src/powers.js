// powers.js -- the lich's six powers and what decides when they act (round 11).
//
// Owner, 2026-09-28: fire, lift and burst, wind, leakage, prismatic beam, lens. "The player
// starts with all abilities and the cooldowns of abilities are such that snakes always almost
// reach the egg but never do, regardless of where the lich is in the cave. As attacks are
// removed by the player, the remaining attacks increase in frequency to make sure that snakes
// don't reach." Fire, lift, wind and beam are cast with a hand pointing at the target; the lens
// is a floating object; leakage happens by itself.
//
// How that is kept:
// - A snake becomes a target only when its head comes within ENGAGE of the egg (so they always
//   get close), wherever the lich is: no power has a range limit, except leakage, which is
//   about what is near him.
// - He casts one gestured power at a time: head turns to the spot, the arm rises and points,
//   the power goes off when both are on it, he holds a moment, lowers. Among the powers that
//   are ready he uses the one he has used least recently, so all of them show.
// - With fewer powers, each one left grows by power = 6 / (powers left): cooldowns divide by
//   it, and what one cast takes multiplies (fire lights several, lift raises several, wind
//   blows several away, the beam chains through many, several lenses form, leakage reaches
//   further and works faster).
// - A snake that gets within URGENT of the egg with nothing on it forces a cast now (cooldown
//   ignored, a quicker aim), whichever power is left. With no powers left, they reach the egg.
import * as THREE from 'three';
import { create_lift } from 'game/lift.js';
import { create_wind } from 'game/wind.js';
import { create_beam } from 'game/beam.js';
import { create_lens } from 'game/lens.js';
import { create_leak } from 'game/leak.js';

export const ENGAGE = 3.4, URGENT = 2.6, LENS_ENGAGE = 6.0;             // the lens takes ~1.5 s from forming to cutting
const AIM_MIN = 0.3, AIM_MAX = 0.55, QUICK_MIN = 0.12, QUICK_MAX = 0.28, ON_T = 0.08, HOLD = 0.45, LOWER = 0.3;

export function create_powers(ctx) {
  const { snakes, fire, lich, mover, egg, get_L, rng } = ctx;
  const N = snakes.RINGS;
  const FIRE = {
    name: 'FIRE', gesture: true, cooldown: 5.0,
    capacity: p => Math.ceil(p/2),
    aim_ring: () => Math.round(N*rng.float(0.15, 0.75)),
    cast(targets, from, ring) {
      // the first catches where he points; any others a beat after, one by one
      targets.forEach((s, k) => { if (k === 0) snakes.ignite(s, ring); else later.push({ at: clock + k*0.12, s }); });
    },
    update() { },
  };
  const later = [];
  const lift = create_lift(ctx), wind = create_wind(ctx), beam = create_beam(ctx), lens = create_lens(ctx), leak = create_leak(ctx);
  const ALL = [FIRE, lift, wind, leak, beam, lens];
  const on = new Map(ALL.map(a => [a, true]));
  const next = new Map(ALL.map(a => [a, 1.0])), last = new Map(ALL.map((a, i) => [a, -10 + i]));
  let clock = 0, power = 1;
  const G = { phase: 'idle', ab: null, targets: [], t: 0, on_t: 0, arm: 1, ring: 0, primary: null, quick: false, w: 0, pw: 0, point: new THREE.Vector3() };
  const TIP = new THREE.Vector3();
  // a lens forms from his mind: when his hands are free he glances up at it while it forms
  const LOOK = { p: new THREE.Vector3(), t: 9 };

  const d_egg = s => Math.hypot(s.x - egg.x, s.z - egg.z);
  const unclaimed = s => snakes.free(s) && !(s.claim && s.claim_until > clock);
  const claim = (s, who, secs) => { s.claim = who; s.claim_until = clock + secs; };
  const threats = (R) => snakes.S.filter(s => unclaimed(s) && d_egg(s) < R).sort((a, b) => d_egg(a) - d_egg(b));

  // where he looks from his facing (yaw) and down (pitch), toward a point
  const gaze_to = (c) => {
    const L = get_L();
    const a = Math.atan2(c.x - L.x, c.z - L.z) - mover.yaw;
    return [Math.atan2(Math.sin(a), Math.cos(a)), Math.atan2(L.y + 0.75 - c.y, Math.max(0.3, Math.hypot(c.x - L.x, c.z - L.z)))];
  };
  // the arm on the target's side (his left arm, the reaching one, when it's ahead)
  const pick_arm = (c) => {
    const L = get_L(), yw = mover.yaw;
    const x = (c.x - L.x)*Math.cos(yw) - (c.z - L.z)*Math.sin(yw);
    const z = (c.x - L.x)*Math.sin(yw) + (c.z - L.z)*Math.cos(yw);
    return x > -0.25*Math.abs(z) ? 1 : 0;
  };

  function start_gesture(ab, targets, quick) {
    for (const s of targets) claim(s, ab.name, 2.0);
    G.phase = 'aim'; G.ab = ab; G.targets = targets; G.t = 0; G.on_t = 0; G.quick = quick;
    G.primary = targets[0]; G.ring = ab.aim_ring();
    G.point.copy(G.primary.spine[G.ring]);
    G.arm = pick_arm(G.point);
  }

  function tick(t, dt) {
    clock += dt;
    const actives = ALL.filter(a => on.get(a));
    power = actives.length ? 6/actives.length : 1;
    leak.scale(power, ENGAGE);
    for (const a of ALL) next.set(a, next.get(a) - dt);
    // fire's second and later catches
    for (let i = later.length - 1; i >= 0; i--) if (clock >= later[i].at) { snakes.ignite(later[i].s); later.splice(i, 1); }

    // about to reach the egg with nothing on it yet (claimed or not: a claim can be too slow)
    const urgent = new Set(snakes.S.filter(s => snakes.free(s) && d_egg(s) < URGENT));
    const gestured = actives.filter(a => a.gesture);

    // --- the gestured powers, one at a time
    if (G.phase === 'idle') {
      const th = threats(ENGAGE);
      if ((th.length || urgent.size) && gestured.length) {
        let ready = gestured.filter(a => next.get(a) <= 0);
        const quick = urgent.size > 0;
        if (!ready.length && quick) {
          // something is about to reach the egg: whichever power is soonest goes now
          const a = gestured.reduce((x, y) => (next.get(x) <= next.get(y) ? x : y));
          next.set(a, 0); ready = [a];
        }
        if (ready.length) {
          const ab = ready.reduce((x, y) => (last.get(x) <= last.get(y) ? x : y));
          const first = quick ? [...urgent].sort((a, b) => d_egg(a) - d_egg(b)) : [];
          const pick = [...first, ...th.filter(s => !urgent.has(s))];
          start_gesture(ab, pick.slice(0, Math.max(1, ab.capacity(power))), quick);
        }
      }
    } else if (G.phase === 'aim') {
      G.t += dt;
      const s = G.primary;
      if (!snakes.free(s)) {
        // it's gone (another power took it): let go, try again
        for (const q of G.targets) q.claim = null;
        G.phase = 'lower'; G.t = 0;
      } else {
        G.point.copy(s.spine[G.ring]);
        const [gy] = gaze_to(G.point);
        const S = lich.springs, reach = Math.max(-1.45, Math.min(1.45, gy));
        G.on_t = Math.abs(reach - (S.hy.x + S.cy.x)) < 0.12 ? G.on_t + dt : 0;
        const mn = G.quick ? QUICK_MIN : AIM_MIN, mx = G.quick ? QUICK_MAX : AIM_MAX;
        if ((G.t >= mn && G.on_t >= ON_T) || G.t >= mx) {
          const targets = G.targets.filter(q => snakes.free(q));
          lich.fingertip(G.arm, TIP);
          G.ab.cast(targets, TIP, G.ring, G.arm);
          next.set(G.ab, G.ab.cooldown/power); last.set(G.ab, clock);
          G.phase = 'hold'; G.t = 0;
        }
      }
    } else if (G.phase === 'hold') {
      G.t += dt;
      // a channelled power (the beam) keeps his hand up, following its head, until it ends
      const channel = G.ab.busy && G.ab.busy();
      if (channel) { G.t = 0; const p = G.ab.aim_point(); if (p) G.point.copy(p); }
      // something about to reach the egg: a channel takes it on; any other hold gives way at once
      if (urgent.size) {
        if (channel && G.ab.extend) G.ab.extend([...urgent]);
        else if (!channel) { G.phase = 'idle'; G.t = 0; G.ab = null; }
      }
      if (G.phase === 'hold' && G.t >= HOLD) { G.phase = 'lower'; G.t = 0; }
    } else if (G.phase === 'lower') {
      G.t += dt;
      // lowering his arm gives way at once to something about to reach the egg
      if (G.t >= LOWER || urgent.size) { G.phase = 'idle'; G.t = 0; G.ab = null; }
    }
    // head and hand
    if (G.phase === 'aim') { G.w = Math.min(1, G.w + dt/0.12); G.pw = Math.min(1, G.pw + dt/(G.quick ? 0.12 : 0.22)); }
    else if (G.phase === 'hold') { G.w = 1; G.pw = 1; }
    else { G.w = Math.max(0, G.w - dt/LOWER); G.pw = Math.max(0, G.pw - dt/LOWER); }
    const m = mover.motion;
    m.gaze_w = G.w;
    if (G.w > 0) [m.gaze, m.gaze_p] = gaze_to(G.point);
    LOOK.t += dt;
    if (G.w < 0.05 && LOOK.t < 1.1) {
      m.gaze_w = 0.85*Math.min(1, LOOK.t/0.15)*(1 - Math.max(0, (LOOK.t - 0.8)/0.3));
      [m.gaze, m.gaze_p] = gaze_to(LOOK.p);
    }
    m.point = G.pw > 0 ? { w: G.pw*G.pw*(3 - 2*G.pw), arm: G.arm, x: G.point.x, y: G.point.y, z: G.point.z } : null;

    // --- the lens: no gesture; it forms when a snake comes close
    if (on.get(lens)) {
      const lone = !gestured.length;
      const rush = lone && [...urgent].filter(s => !(s.claim === 'LENS-QUICK' && s.claim_until > clock));
      if (rush && rush.length) {
        // alone and something is about to reach the egg: a lens that fires at once
        const targets = rush.slice(0, lens.free_lenses());
        for (const s of targets) claim(s, 'LENS-QUICK', 1.2);
        lens.cast(targets, true);
      } else if (next.get(lens) <= 0) {
        const th = threats(LENS_ENGAGE);
        const n = Math.min(lens.capacity(power), lens.free_lenses(), th.length);
        if (n > 0) {
          const targets = th.slice(0, n);
          for (const s of targets) claim(s, 'LENS', 2.6);
          const at = lens.cast(targets);
          if (at.length) { LOOK.p.copy(at[0]); LOOK.t = 0; }
          next.set(lens, lens.cooldown/power); last.set(lens, clock);
        }
      }
    }
    // --- leakage: always, if he has it; when it is all he has, it takes the urgent ones fast
    leak.update(t, dt, on.get(leak), gestured.length || on.get(lens) ? null : urgent);
    beam.update(t, dt);
    lens.update(t, dt);
  }

  return {
    ALL, tick, beam, lens,
    // after he is posed each tick: what leaves his hand follows it (round 18: the beam was a tick behind)
    after_pose(t) { beam.after_pose(t); },
    get power() { return power; },
    is_on: a => on.get(a),
    toggle(i) { const a = ALL[i]; if (a) on.set(a, !on.get(a)); return a && on.get(a); },
    set(i, v) { const a = ALL[i]; if (a) on.set(a, !!v); },
    state: () => ({ phase: G.phase, ab: G.ab && G.ab.name, t: +G.t.toFixed(2), power: +power.toFixed(2), on: ALL.filter(a => on.get(a)).map(a => a.name), next: ALL.map(a => +next.get(a).toFixed(2)), leak_reach: +leak.reach.toFixed(1) }),
    // tests: cast one power now at the snake nearest a point, skipping cooldowns
    force(i, x, z) {
      const a = ALL[i];
      const live = snakes.S.filter(unclaimed).sort((p, q) => Math.hypot(p.x - x, p.z - z) - Math.hypot(q.x - x, q.z - z));
      if (!live.length || !a) return -1;
      if (a === lens) { lens.cast([live[0]]); return snakes.S.indexOf(live[0]); }
      if (a.gesture && G.phase === 'idle') { start_gesture(a, live.slice(0, Math.max(1, a.capacity(power))), false); return snakes.S.indexOf(live[0]); }
      return -1;
    },
  };
}
