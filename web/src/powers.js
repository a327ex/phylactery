// powers.js -- the lich's six powers and what decides when they act (round 11).
//
// Owner, 2026-09-28: fire, lift and burst, wind, leakage, prismatic beam, lens. "The player
// starts with all abilities and the cooldowns of abilities are such that snakes always almost
// reach the egg but never do, regardless of where the lich is in the cave. As attacks are
// removed by the player, the remaining attacks increase in frequency to make sure that snakes
// don't reach." Fire, lift, rock (wind until round 23) and beam are cast with a hand pointing at the target; the lens
// is a floating object; leakage happens by itself.
//
// How that is kept:
// - A snake becomes a target only when its head comes within ENGAGE of the egg (so they always
//   get close), wherever the lich is: no power has a range limit, except leakage, which is
//   about what is near him.
// - He casts one gestured power at a time: head turns to the spot, the arm rises and points,
//   the power goes off a beat after both are on it (round 19), he holds a moment, lowers. Among the powers that
//   are ready he uses the one he has used least recently, so all of them show.
// - With fewer powers, each one left grows by power = 6 / (powers left): cooldowns divide by
//   it, and what one cast takes multiplies (fire lights several, lift raises several, rock
//   blows several away, the beam chains through many, several lenses form, leakage reaches
//   further and works faster).
// - A snake that gets within URGENT of the egg with nothing on it forces a cast now (cooldown
//   ignored, a quicker aim), whichever power is left. With no powers left, they reach the egg.
// - Round 20 (owner: "When you have N attacks active they should keep the snakes away but be used
//   roughly equally"; with the beam and the lens the lens took 31 casts of 31, because it forms
//   at 6 m, in parallel, before the gestured powers engage at 3.4 m): one rotation for every
//   power that acts (all but leakage, which is always on): a power goes only when no other power
//   that is ready, or nearly (under SOON s of cooldown left), has been used fewer times since
//   the set of powers last changed. Something about to reach the egg skips the rotation.
import * as THREE from 'three';
import { create_lift } from 'game/lift.js';
import { create_rock } from 'game/rock.js';
import { create_beam } from 'game/beam.js';
import { create_lens } from 'game/lens.js';
import { create_leak } from 'game/leak.js';

export const ENGAGE = 3.4, URGENT = 2.6, LENS_ENGAGE = 6.0;             // the lens takes ~1.5 s from forming to cutting
const ON_T = 0.08, HOLD = 0.45, LOWER = 0.3;
// round 19 (owner: "He should point, wait a beat, then attack, currently he's attacking before he
// finishes pointing"; it went off with the arm still swinging up at ~3 rad/s): it goes off only
// once his head is on the spot and his arm has arrived (its swing below ARRIVE rad/s), after a
// beat of stillness; at most AIM_MAX after the aim starts. Something about to reach the egg: a
// looser arrival and a shorter beat.
// Round 20 (owner): the beat 0.15 s ("a tad too long"); fire's own 0.05 s ("that one should be quick").
const ARRIVE = 0.7, BEAT = 0.15, AIM_MAX = 1.2, QUICK_ARRIVE = 1.6, QUICK_BEAT = 0.08, QUICK_MAX = 0.45;
const SOON = 1.5;
// round 20: with a snake waiting, he goes from one gesture to the next without lowering his arm,
// after holding this long (the hand, shared by the gestured powers, was the bottleneck: with
// five powers the lens made up for it and was used twice as much)
const HOLD_CHAIN = 0.2;
// round 22 (owner: "he tries to orient his body such that what he points at [is] in a 180 degree
// angle in front of him ... his body should orient itself such that it doesn't break, or he
// should drop a previous target, maybe? I don't know"): O picks which. Either way a new gesture
// prefers a snake in front of him; one behind him he only turns for when nothing in front will
// do, or it is about to reach the egg.
export const FACINGS = ['TURNS TO KEEP IT IN FRONT', 'LETS GO OF IT'];
const FRONT = Math.PI/2;            // behind = past his shoulders' line
const ARM_UP = 1.66, FIRE_IN = 1.4; // his arm rises only once it is within 95 deg, and it goes off within 80

export function create_powers(ctx) {
  const { snakes, fire, lich, mover, egg, get_L, rng } = ctx;
  const N = snakes.RINGS;
  const FIRE = {
    name: 'FIRE', gesture: true, cooldown: 5.0, beat: 0.05,
    capacity: p => Math.ceil(p/2),
    aim_ring: () => Math.round(N*rng.float(0.15, 0.75)),
    cast(targets, from, ring) {
      // the first catches where he points; any others a beat after, one by one
      targets.forEach((s, k) => { if (k === 0) snakes.ignite(s, ring); else later.push({ at: clock + k*0.12, s }); });
    },
    update() { },
  };
  const later = [];
  // round 23 (owner): wind is replaced by the rock throw
  const lift = create_lift(ctx), rock = create_rock(ctx), beam = create_beam(ctx), lens = create_lens(ctx), leak = create_leak(ctx);
  const ALL = [FIRE, lift, rock, leak, beam, lens];
  const on = new Map(ALL.map(a => [a, true]));
  const next = new Map(ALL.map(a => [a, 1.0])), last = new Map(ALL.map((a, i) => [a, -10 + i]));
  let clock = 0, power = 1;
  // tests: how many times each power was used, and how many snakes each took (leakage: dissolved)
  const uses = new Map(ALL.map(a => [a, 0])), took = new Map(ALL.map(a => [a, 0]));
  // the rotation: uses since the set of powers last changed
  const fair = new Map(ALL.map(a => [a, 0]));
  const count = (a, n) => { uses.set(a, uses.get(a) + 1); took.set(a, took.get(a) + n); fair.set(a, fair.get(a) + 1); };
  const reset_fair = () => { for (const a of ALL) fair.set(a, 0); };
  let quick_lens = 0;                 // tests: lenses fired at once, for something about to reach the egg
  lens.use_claims(s => unclaimed(s), s => claim(s, 'LENS', 2.0));
  const G = { phase: 'idle', ab: null, targets: [], t: 0, on_t: 0, arm: 1, ring: 0, primary: null, quick: false, w: 0, pw: 0, point: new THREE.Vector3(), must_turn: false };
  let facing = 0, drops = 0, test_old = false;       // test_old: round 21's facing, to compare against
  // where something is from his facing (radians, 0 = straight ahead), and whether it is behind him
  const rel_yaw = (c) => { const L = get_L(); const a = Math.atan2(c.x - L.x, c.z - L.z) - mover.yaw; return Math.atan2(Math.sin(a), Math.cos(a)); };
  const behind = (c) => Math.abs(rel_yaw(c)) > FRONT;
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
    G.phase = 'aim'; G.ab = ab; G.targets = targets; G.t = 0; G.on_t = 0; G.still = 0; G.quick = quick;
    G.primary = targets[0]; G.ring = ab.aim_ring();
    G.point.copy(G.primary.spine[G.ring]);
    G.arm = pick_arm(G.point);
    // letting go of what goes behind him (O): not of one he had to turn for
    G.must_turn = behind(G.point);
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
    lift.update(dt);
    // whose turn: the fewest uses among the powers that are ready or nearly
    const acting = actives.filter(a => a !== leak);
    let low = Infinity;
    for (const a of acting) if (next.get(a) < SOON && (a !== lens || lens.free_lenses() > 0)) low = Math.min(low, fair.get(a));
    const turn = a => fair.get(a) <= low;

    // --- the gestured powers, one at a time
    // the next gesture, if there is something to take and a power whose turn it is
    const try_gesture = () => {
      // round 23: a power can take them from further out than ENGAGE (the rock needs its flight time)
      const far = Math.max(ENGAGE, ...gestured.map(a => a.engage || ENGAGE));
      const th_all = threats(far);
      if (!(th_all.length || urgent.size) || !gestured.length) return false;
      const quick = urgent.size > 0;
      const has = a => quick || th_all.some(s => d_egg(s) < (a.engage || ENGAGE));
      let ready = gestured.filter(a => next.get(a) <= 0 && (quick || turn(a)) && has(a));
      if (!ready.length && quick) {
        // something is about to reach the egg: whichever power is soonest goes now
        const a = gestured.reduce((x, y) => (next.get(x) <= next.get(y) ? x : y));
        next.set(a, 0); ready = [a];
      }
      if (!ready.length) return false;
      // the least used, then the least recently used
      const ab = ready.reduce((x, y) => (fair.get(x) < fair.get(y) || (fair.get(x) === fair.get(y) && last.get(x) <= last.get(y)) ? x : y));
      const th = th_all.filter(s => d_egg(s) < (ab.engage || ENGAGE));
      const first = quick ? [...urgent].sort((a, b) => d_egg(a) - d_egg(b)) : [];
      // in front of him first (the list is already nearest the egg first)
      const ahead = th.filter(s => !urgent.has(s)).map(s => [s, !test_old && behind(s.spine[Math.round(N*0.3)]) ? 1 : 0]).sort((a, b) => a[1] - b[1]).map(q => q[0]);
      // letting go (O): one behind him only if it is about to reach the egg
      const pick = [...first, ...(facing === 1 ? ahead.filter(s => !behind(s.spine[Math.round(N*0.3)])) : ahead)];
      if (!pick.length) return false;
      start_gesture(ab, pick.slice(0, Math.max(1, ab.capacity(power))), quick);
      return true;
    };
    if (G.phase === 'idle') {
      try_gesture();
    } else if (G.phase === 'aim') {
      G.t += dt;
      const s = G.primary;
      if (!on.get(G.ab) || !snakes.free(s) || (facing === 1 && !G.must_turn && behind(s.spine[G.ring]))) {
        if (on.get(G.ab) && snakes.free(s)) drops++;
        // it's gone (another power took it), or the power was taken from him: let go, try again
        for (const q of G.targets) q.claim = null;
        G.phase = 'lower'; G.t = 0;
      } else {
        G.point.copy(s.spine[G.ring]);
        const [gy] = gaze_to(G.point);
        const S = lich.springs, reach = Math.max(-1.45, Math.min(1.45, gy));
        G.on_t = Math.abs(reach - (S.hy.x + S.cy.x)) < 0.12 ? G.on_t + dt : 0;
        // (round 22: and with it in front of him: one behind him he turns to before his arm comes up)
        const arrived = G.pw >= 1 && G.on_t >= ON_T && lich.arm_speed(G.arm) < (G.quick ? QUICK_ARRIVE : ARRIVE) && (test_old || Math.abs(rel_yaw(G.point)) < FIRE_IN);
        G.still = arrived ? G.still + dt : 0;
        const beat = Math.min(G.ab.beat ?? BEAT, G.quick ? QUICK_BEAT : 9);
        if (G.still >= beat || G.t >= (G.quick ? QUICK_MAX : AIM_MAX)) {
          const targets = G.targets.filter(q => snakes.free(q));
          lich.fingertip(G.arm, TIP);
          G.ab.cast(targets, TIP, G.ring, G.arm, G.quick);
          count(G.ab, targets.length);
          next.set(G.ab, G.ab.cooldown/power); last.set(G.ab, clock);
          G.phase = 'hold'; G.t = 0;
        }
      }
    } else if (G.phase === 'hold') {
      G.t += dt;
      // a channelled power (the beam; the lift, round 20) keeps his hand up, following it, until it ends
      let channel = G.ab.busy && G.ab.busy();
      if (channel) { G.t = 0; const p = G.ab.aim_point(); if (p) G.point.copy(p); }
      // letting go (O): what he holds has gone behind him (he was moved away from it): the beam
      // ends, the lift goes on without his hand
      if (facing === 1 && !G.must_turn && behind(G.point)) {
        if (channel && G.ab.let_go) G.ab.let_go();
        drops++; G.phase = 'lower'; G.t = 0; channel = false;
      }
      // something about to reach the egg: a channel takes it on; any other hold gives way at once
      if (urgent.size) {
        if (channel && G.ab.extend) G.ab.extend([...urgent], G.arm);
        else if (!channel) { G.phase = 'idle'; G.t = 0; G.ab = null; }
      }
      // the next one waiting: straight on to it, the arm never lowered
      if (G.phase === 'hold' && !channel && G.t >= HOLD_CHAIN && try_gesture()) { }
      else if (G.phase === 'hold' && G.t >= HOLD) { G.phase = 'lower'; G.t = 0; }
    } else if (G.phase === 'lower') {
      G.t += dt;
      // lowering his arm gives way at once to the next gesture, or to something about to reach the egg
      if (try_gesture()) { }
      else if (G.t >= LOWER || urgent.size) { G.phase = 'idle'; G.t = 0; G.ab = null; }
    }
    // head and hand
    if (G.phase === 'aim') {
      G.w = Math.min(1, G.w + dt/0.12);
      // his head turns to it at once; his arm waits until his body has brought it round in front
      if (test_old || Math.abs(rel_yaw(G.point)) < ARM_UP) G.pw = Math.min(1, G.pw + dt/(G.quick ? 0.12 : 0.22));
      else G.pw = Math.max(0, G.pw - dt/0.2);
    }
    else if (G.phase === 'hold') {
      G.w = 1;
      // swung round faster than he can turn: his arm dips until his body brings it back in front
      if (test_old || Math.abs(rel_yaw(G.point)) < ARM_UP) G.pw = Math.min(1, G.pw + dt/0.15);
      else G.pw = Math.max(0.2, G.pw - dt/0.15);
    }
    else { G.w = Math.max(0, G.w - dt/LOWER); G.pw = Math.max(0, G.pw - dt/LOWER); }
    // turning to keep it in front: while he points (TURNS), or for one he had to turn for (LETS GO)
    const pointing = G.phase === 'aim' || G.phase === 'hold';
    mover.face.on = !test_old && pointing && (facing === 0 || G.must_turn);
    if (mover.face.on) { const L = get_L(); mover.face.yaw = Math.atan2(G.point.x - L.x, G.point.z - L.z); }
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
      // something about to reach the egg that his hand can't take now (he has no gestured power,
      // or he is already aiming at another; a hold or a lowering gives way to it, a channel
      // takes it on): a lens that fires at once
      const busy_hand = G.phase === 'aim';
      const rush = (lone || busy_hand) && [...urgent].filter(s => !(s.claim && s.claim_until > clock && /QUICK/.test(s.claim)) && !(busy_hand && G.targets.includes(s)));
      if (rush && rush.length) {
        const targets = rush.slice(0, lens.free_lenses());
        for (const s of targets) claim(s, 'LENS-QUICK', 1.2);
        lens.cast(targets, true);
        if (targets.length) { count(lens, targets.length); quick_lens++; }
      } else if (next.get(lens) <= 0 && turn(lens)) {
        const th = threats(LENS_ENGAGE);
        const n = Math.min(lens.capacity(power), lens.free_lenses(), th.length);
        if (n > 0) {
          const targets = th.slice(0, n);
          for (const s of targets) claim(s, 'LENS', 2.6);
          const at = lens.cast(targets);
          count(lens, targets.length);
          if (at.length) { LOOK.p.copy(at[0]); LOOK.t = 0; }
          next.set(lens, lens.cooldown/power); last.set(lens, clock);
        }
      }
    }
    // --- the rock (round 25: no gesture; his mind alone): its turn in the rotation, like the lens;
    // and for something about to reach the egg that nothing else is taking, a quick one
    if (on.get(rock)) {
      const busy_hand = G.phase === 'aim';
      const rush = (!gestured.length || busy_hand) && [...urgent].filter(s => !(s.claim && s.claim_until > clock && /QUICK/.test(s.claim)) && !(busy_hand && G.targets.includes(s)));
      if (rush && rush.length && rock.free_rocks() > 0) {
        const targets = rush.slice(0, Math.min(2, rock.free_rocks()));
        for (const s of targets) claim(s, 'ROCK-QUICK', 1.2);
        rock.cast(targets, null, 0, 1, true);
        count(rock, targets.length);
      } else if (next.get(rock) <= 0 && turn(rock) && rock.free_rocks() > 0) {
        const th = threats(rock.engage);
        const n = Math.min(rock.capacity(power), rock.free_rocks(), th.length);
        if (n > 0) {
          const targets = th.slice(0, n);
          for (const s of targets) claim(s, 'ROCK', 2.6);
          rock.cast(targets);
          count(rock, targets.length);
          next.set(rock, rock.cooldown/power); last.set(rock, clock);
          // he glances at it as it rises
          const p = rock.hold_at(); if (p && G.w < 0.05) { LOOK.p.copy(p); LOOK.t = 0; }
        }
      }
    }
    // --- leakage: always, if he has it; when it is all he has, it takes the urgent ones fast
    leak.update(t, dt, on.get(leak), gestured.length || on.get(lens) || on.get(rock) ? null : urgent);
    beam.update(t, dt);
    rock.update(t, dt);
    lens.update(t, dt);
  }

  return {
    ALL, tick, beam, lens, rock,
    // after he is posed each tick: what leaves his hand follows it (round 18: the beam was a tick behind)
    after_pose(t) { beam.after_pose(t); },
    get power() { return power; },
    is_on: a => on.get(a),
    toggle(i) { const a = ALL[i]; if (a) { on.set(a, !on.get(a)); reset_fair(); } return a && on.get(a); },
    set(i, v) { const a = ALL[i]; if (a && on.get(a) !== !!v) { on.set(a, !!v); reset_fair(); } },
    state: () => ({ phase: G.phase, ab: G.ab && G.ab.name, t: +G.t.toFixed(2), power: +power.toFixed(2), on: ALL.filter(a => on.get(a)).map(a => a.name), next: ALL.map(a => +next.get(a).toFixed(2)), leak_reach: +leak.reach.toFixed(1),
      uses: Object.fromEntries(ALL.map(a => [a.name, a === leak ? snakes.dissolved : uses.get(a)])), took: Object.fromEntries(ALL.map(a => [a.name, a === leak ? snakes.dissolved : took.get(a)])) }),
    get quick_lens() { return quick_lens; },
    get facing() { return facing; },
    set facing(i) { facing = ((i % FACINGS.length) + FACINGS.length) % FACINGS.length; },
    get drops() { return drops; },
    set test_old(v) { test_old = !!v; },
    // tests: how far off his facing what he points at is (degrees), while he points
    // (only while his arm is up, and not for something almost under him, where the way to it is noise)
    point_off: () => { const L = get_L(); return (G.phase === 'aim' || G.phase === 'hold') && G.pw > 0.5 && Math.hypot(G.point.x - L.x, G.point.z - L.z) > 1 ? Math.abs(rel_yaw(G.point))*57.3 : null; },
    reset_uses() { for (const a of ALL) { uses.set(a, 0); took.set(a, 0); } },
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
