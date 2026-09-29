// items.js -- round 28: the six powers as objects. The game before the ending is a walk through
// the cave gathering each power as a physical object, looked at in an inspect view when it is
// taken (inspect.js); in the ending, each power the player removes drops onto the floor around
// the egg (owner, 2026-09-29).
//
// Each item: a builder (ctx) -> THREE.Group, built twice: once lit like everything else in the
// cave (the sun, its shadow, the baked bounce), once for the inspect view's own light. On the
// floor it is a rigid body (body.js) dropped from above its place around the egg.
import * as THREE from 'three';
import { gi_dynamic } from 'game/gi.js';
import { make_rng, smoothstep } from 'game/util.js';
import { create_body, contact_points, box_inertia } from 'game/body.js';
import { build_lens } from 'game/item_lens.js';
import { build_gem } from 'game/item_gem.js';
import { build_orbs } from 'game/item_orbs.js';
import { build_mask } from 'game/item_mask.js';
import { build_hand, HAND_MATS } from 'game/item_hand.js';
import { build_lodestone } from 'game/item_lodestone.js';
import { LAYOUT } from 'game/cave.js';

// in powers.ALL's order (keys 5-0): FIRE, LIFT, ROCK, LEAKAGE, PRISMATIC BEAM, LENS
export const ITEMS = [
  { power: 'FIRE', name: 'A BURNED MASK', build: (ctx) => build_mask(ctx), mass: 0.4, rest: 0.12, fric: 0.6, view: [0.12, 0.35, 0.05], face_up: true },
  { power: 'LIFT AND BURST', name: 'A HAND', build: (ctx, o) => build_hand(ctx, o), mass: 1.5, rest: 0.1, fric: 0.55, view: [-0.1, 0.5, 0.0] },
  { power: 'ROCK', name: 'A LODESTONE', build: (ctx) => build_lodestone(ctx), mass: 1.2, rest: 0.1, fric: 0.7, view: [0.35, 0.45, 0.0] },
  { power: 'LEAKAGE', name: 'THE ORBS', build: (ctx) => build_orbs(ctx), mass: 0.3, rest: 0.35, fric: 0.4, balls: true },
  { power: 'PRISMATIC BEAM', name: 'A PRISMATIC GEM', build: (ctx) => build_gem(ctx.gem ?? ctx), mass: 0.4, rest: 0.12, fric: 0.7, rolling: 3, view: [0.5, 0.4, 0.1] },
  { power: 'LENS', name: 'A LENS', build: (ctx) => build_lens(ctx), mass: 3, rest: 0.15, fric: 0.45, view: [0.85, 0.65, 0.2], fixed_k: 1.8 },
];
export { HAND_MATS };
// how big they lie on the floor (the snakes are dream-sized, 4.4 m, so they read from the room
// camera; the objects as made are the size you'd hold). Round 28: dream-sized (x1.8); round 31
// (owner): "all objects need to be bigger when they fall except the lens": x3, the lens x1.8.
// Z tries the others' size (the lens stays).
export const SIZES = [{ name: 'X3 (LENS X1.8)', k: 3 }, { name: 'X4 (LENS X1.8)', k: 4 }, { name: 'X1.8 (ROUND 30)', k: 1.8 }];

export function create_items(ctx) {
  const { R, cave, fx, warp, env_world, nav, lich, mover, get_L, glance } = ctx;
  const rng = make_rng(71);
  // round 31 (owner): the hand's default is the material that isn't metal (BONE)
  const opts = { size: 0, hand_mat: HAND_MATS.indexOf('BONE') };
  const kf = (w) => w.it.fixed_k ?? SIZES[opts.size].k;
  const S = LAYOUT.sun_dir, sxz = new THREE.Vector2(S.x/S.y, S.z/S.y);
  const sun = { dir: S.clone(), col: new THREE.Vector3(1, 0.9, 0.72).multiplyScalar(22) };
  const egg = { x: LAYOUT.egg.x, z: LAYOUT.egg.z, r: 0.42, top: cave.ground_y(0, 0) + 0.8 };
  // on the floor the gem's light is the shaft's opening, a few degrees across seen from below
  const world_ctx = { lit: m => gi_dynamic(m, cave.GU), env: env_world, env_i: 0, sun, glint_pow: 420, rim: 0.15 };
  const floor = (x, z) => cave.ground_y(x, z);
  // how much of the shaft's sun reaches a point (the pool, soft-edged)
  const in_sun = p => 1 - smoothstep(1.55, 2.05, Math.hypot(p.x - sxz.x*p.y, p.z - sxz.y*p.y));
  // dust knocked up where something lands: lit by the sun in the pool, dark out of it
  function dust(p, v) {
    const gy = floor(p.x, p.z), n = Math.min(7, Math.round(v*3));
    const k = 0.06 + 0.5*in_sun(p);
    for (let j = 0; j < n; j++) {
      const a = rng.float(0, 6.28);
      fx.puff({ x: p.x + Math.cos(a)*0.08, y: gy + 0.03, z: p.z + Math.sin(a)*0.08, vx: Math.cos(a)*rng.float(0.2, 0.6)*v*0.35, vy: rng.float(0.08, 0.3), vz: Math.sin(a)*rng.float(0.2, 0.6)*v*0.35,
        drag: 2.4, life: rng.float(0.5, 0.9), s0: 0.05, s1: 0.14, r: 0.9*k, g: 0.72*k, b: 0.5*k, a: 0.2 });
    }
  }

  // one world instance per item that has a model
  const W = ITEMS.map((it, i) => {
    if (!it.build) return null;
    const make = () => {
      const g = it.build(world_ctx, opts);
      g.traverse(o => { if (o.isMesh) { o.castShadow = !o.userData.no_shadow; o.receiveShadow = true; } });
      return g;
    };
    const w = { it, i, g: make(), make, body: null, state: 'away', t: 0, scale: 1 };
    // how far it reaches from its middle, as made (its footprint on the floor, scaled)
    const bs = new THREE.Box3().setFromObject(w.g).getSize(new THREE.Vector3());
    w.r0 = it.balls ? 0.14 : Math.max(bs.x, bs.y, bs.z)*0.5;
    w.g.visible = false;
    R.world_scene.add(w.g);
    return w;
  });

  function make_body(w) {
    w.g.updateMatrixWorld(true);
    const P = [];
    w.g.traverse(o => { if (o.isMesh && !o.isInstancedMesh && !o.userData.no_contact) { const g = o.geometry, p = g.attributes.position; o.updateMatrix(); const m = new THREE.Matrix4().compose(o.position, o.quaternion, o.scale); const step = Math.max(1, Math.floor(p.count/6000)); for (let k = 0; k < p.count; k += step) P.push(new THREE.Vector3().fromBufferAttribute(p, k).applyMatrix4(m)); } });
    const pg = new THREE.BufferGeometry().setFromPoints(P);
    const k = kf(w);
    for (const q of P) q.multiplyScalar(k);
    const pts = contact_points(pg.setFromPoints(P), 64);
    const bb = new THREE.Box3().setFromPoints(P), sz = bb.getSize(new THREE.Vector3());
    const b = create_body({ points: pts, mass: w.it.mass, inertia: box_inertia(w.it.mass, sz.x, sz.y, sz.z), restitution: w.it.rest, friction: w.it.fric, rolling: w.it.rolling ?? 0.8, floor, egg });
    b.on_hit = (v) => dust(b.x, v);
    return b;
  }

  // ---------------------------------------------------------------- where it goes
  // Round 31 (owner: "the objects should all fall around the lich not the egg, as though he
  // discarded them"): each leaves his nearer hand, growing to its size as it flies, and lands on
  // clear floor beside him: never rock (they meet only the floor's height field), never the egg,
  // never another object lying there, never out of the room camera's frame; to one side of him
  // and a little ahead, the next one to the other side.
  const lying_r = (w) => kf(w)*w.r0*0.9;
  let side = 1;
  function spot(w, r) {
    const L = get_L(), yaw = mover.yaw;
    const fwd = new THREE.Vector2(Math.sin(yaw), Math.cos(yaw));
    side = -side;
    const base = Math.atan2(fwd.y, fwd.x) + side*(Math.PI*0.42);
    let best = null, bs = Infinity;
    for (let da = 0; da <= 170; da += 10) for (const sg of da ? [1, -1] : [1]) for (let d = 0.55 + r; d <= 1.9 + r; d += 0.15) {
      const a = base + sg*side*da*Math.PI/180;
      const x = L.x + Math.cos(a)*d, z = L.z + Math.sin(a)*d;
      let bad = 0;
      for (let dz = -r; dz <= r; dz += 0.1) for (let dx = -r; dx <= r; dx += 0.1) {
        if (dx*dx + dz*dz > r*r) continue;
        const px = x + dx, pz = z + dz;
        if (nav.is_blocked(px, pz) || nav.rock_top(px, pz) > floor(px, pz) + 0.02) bad++;
      }
      if (Math.hypot(x - egg.x, z - egg.z) < egg.r + r + 0.1) bad += 50;
      for (const o of W) if (o && o !== w && (o.state === 'lying' || o.state === 'falling' || o.state === 'forming')) {
        const ox = o.bodies ? o.land.x : o.g.position.x, oz = o.bodies ? o.land.y : o.g.position.z;
        if (Math.hypot(x - ox, z - oz) < r + lying_r(o) + 0.08) bad += 50;
      }
      const score = bad*10 + da*0.01 + Math.abs(d - ((w.it.balls ? 0.7 : 0.95) + r))*0.8;
      if (score < bs) { bs = score; best = new THREE.Vector2(x, z); }
    }
    return best;
  }
  // his hand nearer to where it goes (0 = his right, 1 = his left)
  const tmp = new THREE.Vector3();
  function from_hand(to) {
    const a = lich.fingertip(0, new THREE.Vector3()), b = lich.fingertip(1, new THREE.Vector3());
    const k = a.distanceToSquared(tmp.set(to.x, a.y, to.y)) < b.distanceToSquared(tmp.set(to.x, b.y, to.y)) ? 0 : 1;
    return { k, p: k === 0 ? a : b };
  }
  // a throw from p that comes down at (x, z) at height y after t seconds
  const toss = (p, x, y, z, t) => new THREE.Vector3((x - p.x)/t, (y - p.y + 0.5*9.81*t*t)/t, (z - p.z)/t);

  // orbs: each its own ball, tossed as a loose handful
  function drop_balls(w, to, from) {
    const k = kf(w);
    w.land = to.clone();
    w.bodies = w.g.userData.orbs.map((m, j) => {
      const r = m.userData.r*k;
      const b = create_body({ sphere: r, mass: w.it.mass, inertia: new THREE.Vector3(1, 1, 1).multiplyScalar(0.4*w.it.mass*r*r), restitution: 0.22, friction: w.it.fric, rolling: 2.5, rr: 0.26, floor, egg });
      const a = j*2.4, spread = 0.06*k;
      b.x.copy(from).add(new THREE.Vector3(rng.spread(0.05), j*0.03, rng.spread(0.05)));
      const tx = to.x + Math.cos(a)*spread, tz = to.y + Math.sin(a)*spread;
      b.v.copy(toss(b.x, tx, floor(tx, tz) + r, tz, 0.72 + j*0.04));     // lobbed, so they don't roll away
      b.on_hit = (v) => { if (v > 1.2) dust(b.x, v*0.5); };
      return b;
    });
    w.body = w.bodies[0];
  }
  // balls knock each other apart (and never sink into one another)
  function collide_balls(w) {
    const B = w.bodies, O = w.g.userData.orbs, k = kf(w);
    for (let i = 0; i < B.length; i++) for (let j = i + 1; j < B.length; j++) {
      const a = B[i], b = B[j], d = a.x.distanceTo(b.x), min = (O[i].userData.r + O[j].userData.r)*k;
      if (d >= min || d < 1e-6) continue;
      const n = new THREE.Vector3().subVectors(b.x, a.x).multiplyScalar(1/d);
      a.x.addScaledVector(n, -(min - d)*0.5); b.x.addScaledVector(n, (min - d)*0.5);
      const vn = new THREE.Vector3().subVectors(b.v, a.v).dot(n);
      if (vn < 0) { const j2 = -(1 + 0.4)*vn*0.5; a.v.addScaledVector(n, -j2); b.v.addScaledVector(n, j2); a.wake(); b.wake(); }
    }
  }

  // he lets it go: it leaves his hand in a breath of warped air, his arm flicks, he glances where
  // it goes, and it grows to its size as it flies there
  function drop(i) {
    const w = W[i];
    if (!w) return false;
    const r = lying_r(w);
    const to = spot(w, r);
    const h = from_hand(to);
    const from = h.p.clone().add(new THREE.Vector3(to.x - h.p.x, 0, to.y - h.p.z).normalize().multiplyScalar(0.12));
    lich.kick(h.k, 0.45);
    if (glance) glance(new THREE.Vector3(to.x, floor(to.x, to.y), to.y));
    for (let k = 0; k < 5; k++) warp.puff({ x: from.x + rng.spread(0.06), y: from.y + rng.spread(0.06), z: from.z + rng.spread(0.06), vx: rng.spread(0.3), vy: rng.spread(0.2), vz: rng.spread(0.3), drag: 2.5, life: rng.float(0.3, 0.45), s0: 0.1, s1: 0.3, amp: 3.2, spin: rng.spread(4) });
    if (w.it.balls) {
      drop_balls(w, to, from);
      w.state = 'forming'; w.t = 0; w.g.visible = true;
      w.g.position.set(0, 0, 0); w.g.quaternion.identity(); w.g.scale.setScalar(1);
      return true;
    }
    w.body = make_body(w);
    w.land = to.clone();
    w.body.x.copy(from);
    const T = 0.5 + 0.12*Math.hypot(to.x - from.x, to.y - from.z);
    w.body.v.copy(toss(from, to.x, floor(to.x, to.y) + r*0.7, to.y, T));
    if (w.it.face_up) {
      // the mask comes down face up, tipping a little, so it lies showing its slits (face down
      // its black back read as a hole in the floor)
      w.body.q.setFromEuler(new THREE.Euler(-Math.PI/2 + rng.spread(0.35), rng.float(0, 6.28), rng.spread(0.35), 'YXZ'));
      w.body.w.set(rng.spread(1), rng.spread(1.5), rng.spread(1));
    } else {
      w.body.q.setFromEuler(new THREE.Euler(rng.spread(1.2), rng.float(0, 6.28), rng.spread(1.2)));
      w.body.w.set(rng.spread(3), rng.spread(2), rng.spread(3));
    }
    w.state = 'forming'; w.t = 0;
    w.g.visible = true;
    return true;
  }
  // (testing only: the power restored) it rises out of sight into warped air
  function take(i) {
    const w = W[i];
    if (!w || w.state === 'away') return;
    w.state = 'leaving'; w.t = 0;
    if (w.body) w.body.asleep = true;
    if (w.bodies) for (const b of w.bodies) b.asleep = true;
    for (let k = 0; k < 5; k++) warp.puff({ x: w.g.position.x + rng.spread(0.12), y: w.g.position.y + 0.1, z: w.g.position.z + rng.spread(0.12), vy: 0.6, drag: 1.5, life: 0.5, s0: 0.15, s1: 0.4, amp: 3, spin: rng.spread(3) });
  }

  function update_balls(w, dt) {
    const O = w.g.userData.orbs, k = kf(w);
    if (w.state === 'forming') { w.scale = smoothstep(0, 0.3, w.t); for (const b of w.bodies) b.step(dt); collide_balls(w); if (w.t > 0.3) w.state = 'falling'; }
    else if (w.state === 'falling') { for (const b of w.bodies) b.step(dt); collide_balls(w); if (w.bodies.every(b => b.asleep)) w.state = 'lying'; }
    else if (w.state === 'leaving') { for (const b of w.bodies) b.x.y += dt*0.9*smoothstep(0, 0.3, w.t); w.scale = 1 - smoothstep(0.1, 0.45, w.t); if (w.t > 0.45) { w.state = 'away'; w.g.visible = false; } }
    O.forEach((m, j) => {
      const b = w.bodies[j];
      m.position.copy(b.x); m.quaternion.copy(b.q);
      m.scale.setScalar(Math.max(1e-4, m.userData.r*k*w.scale));
      m.userData.mat.userData.U.uLit.value = in_sun(b.x);
    });
  }

  function update(t, dt) {
    for (const w of W) {
      if (!w || w.state === 'away') continue;
      w.t += dt;
      if (w.it.balls) { update_balls(w, dt); continue; }
      if (w.state === 'forming') {
        w.scale = 0.08 + 0.92*smoothstep(0, 0.3, w.t);
        w.body.step(dt);
        if (w.t > 0.3) w.state = 'falling';
      } else if (w.state === 'falling') {
        w.body.step(dt);
        if (w.body.asleep) w.state = 'lying';
      } else if (w.state === 'leaving') {
        w.g.position.y += dt*0.9*smoothstep(0, 0.3, w.t);
        w.scale = 1 - smoothstep(0.1, 0.45, w.t);
        w.g.scale.setScalar(Math.max(1e-3, w.scale)*kf(w));
        if (w.t > 0.45) { w.state = 'away'; w.g.visible = false; }
        continue;
      }
      w.g.position.copy(w.body.x);
      w.g.quaternion.copy(w.body.q);
      w.g.scale.setScalar(Math.max(1e-3, w.scale)*kf(w));
    }
    // the gem sees the sun only in the pool
    const gw = W[4];
    if (gw && gw.g.visible) for (const m of gw.g.userData.mats) m.userData.U.uLit.value = in_sun(gw.g.position);
  }

  // swap the hand's metal (M): rebuild that world instance in place
  function set_hand_mat(c) {
    opts.hand_mat = ((c % HAND_MATS.length) + HAND_MATS.length) % HAND_MATS.length;
    rebuild(1);
    return HAND_MATS[opts.hand_mat];
  }
  function rebuild(i) {
    const w = W[i];
    const vis = w.g.visible, pos = w.g.position.clone(), q = w.g.quaternion.clone();
    R.world_scene.remove(w.g);
    w.g = w.make(); w.g.visible = vis; w.g.position.copy(pos); w.g.quaternion.copy(q);
    R.world_scene.add(w.g);
    if (w.state !== 'away') { const old = w.body; w.body = make_body(w); w.body.x.copy(old.x); w.body.q.copy(old.q); w.body.x.y += 0.05; w.state = 'falling'; }
  }

  // Z: the others' size; what lies on the floor is let go again at it
  function set_size(i) {
    opts.size = ((i % SIZES.length) + SIZES.length) % SIZES.length;
    const lying = W.filter(w => w && w.state !== 'away');
    for (const w of lying) { w.state = 'away'; w.g.visible = false; }
    for (const w of lying) { drop(w.i); for (let n = 0; n < 40; n++) update(0, 1/60); }
    return SIZES[opts.size].name;
  }

  return {
    W, opts, drop, take, update, set_hand_mat, set_size,
    state: () => W.map(w => w && (w.bodies ? { state: w.state, balls: w.bodies.map(b => [+b.x.x.toFixed(2), +b.x.y.toFixed(3), +b.x.z.toFixed(2), b.asleep ? 1 : 0]) }
      : { state: w.state, x: +w.g.position.x.toFixed(2), y: +w.g.position.y.toFixed(3), z: +w.g.position.z.toFixed(2), asleep: !!(w.body && w.body.asleep) })),
  };
}
