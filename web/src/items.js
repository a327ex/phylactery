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
import { build_gem, GEM_CUTS } from 'game/item_gem.js';
import { build_orbs } from 'game/item_orbs.js';
import { LAYOUT } from 'game/cave.js';

// in powers.ALL's order (keys 5-0): FIRE, LIFT, ROCK, LEAKAGE, PRISMATIC BEAM, LENS
export const ITEMS = [
  { power: 'FIRE', name: 'A BURNED DOLL', pending: 'WHICH DOLL: ON THE BOARD' },
  { power: 'LIFT AND BURST', name: '?', pending: 'WHICH OBJECT: ON THE BOARD' },
  { power: 'ROCK', name: '?', pending: 'WHICH OBJECT: ON THE BOARD' },
  { power: 'LEAKAGE', name: 'THE ORBS', build: (ctx) => build_orbs(ctx), mass: 0.3, rest: 0.35, fric: 0.4, balls: true },
  { power: 'PRISMATIC BEAM', name: 'A PRISMATIC GEM', build: (ctx, o) => build_gem(ctx, o.gem_cut), mass: 0.4, rest: 0.2, fric: 0.5, view: [0.5, 0.4, 0.1] },
  { power: 'LENS', name: 'A LENS', build: (ctx) => build_lens(ctx), mass: 3, rest: 0.15, fric: 0.45, view: [0.85, 0.65, 0.2] },
];
export { GEM_CUTS };
// how big they lie on the floor (the snakes are dream-sized, 4.4 m, so they read from the room
// camera; the objects as made are the size you'd hold)
export const SIZES = [{ name: 'AS MADE', k: 1 }, { name: 'DREAM-SIZED (X1.8)', k: 1.8 }];

// where each one lands: a ring around the egg (none straight behind it from the room camera)
const SLOTS = [0, 60, 120, 180, 240, 300].map((deg, i) => {
  const a = (deg + [8, -6, 4, -9, 5, -4][i])*Math.PI/180, r = [1.35, 1.2, 1.45, 1.3, 1.25, 1.4][i];
  return new THREE.Vector2(Math.cos(a)*r, Math.sin(a)*r);
});

export function create_items(ctx) {
  const { R, cave, fx, warp, env_world } = ctx;
  const rng = make_rng(71);
  const opts = { gem_cut: 0, size: 0 };
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
    w.g.visible = false;
    R.world_scene.add(w.g);
    return w;
  });

  function make_body(w) {
    w.g.updateMatrixWorld(true);
    const P = [];
    w.g.traverse(o => { if (o.isMesh) { const g = o.geometry, p = g.attributes.position; o.updateMatrix(); const m = new THREE.Matrix4().compose(o.position, o.quaternion, o.scale); for (let k = 0; k < p.count; k += 1) P.push(new THREE.Vector3().fromBufferAttribute(p, k).applyMatrix4(m)); } });
    const pg = new THREE.BufferGeometry().setFromPoints(P);
    const k = SIZES[opts.size].k;
    for (const q of P) q.multiplyScalar(k);
    const pts = contact_points(pg.setFromPoints(P), 64);
    const bb = new THREE.Box3().setFromPoints(P), sz = bb.getSize(new THREE.Vector3());
    const b = create_body({ points: pts, mass: w.it.mass, inertia: box_inertia(w.it.mass, sz.x, sz.y, sz.z), restitution: w.it.rest, friction: w.it.fric, rolling: 0.8, floor, egg });
    b.on_hit = (v) => dust(b.x, v);
    return b;
  }

  // orbs: each its own ball, dropped from a little cluster above the place
  function drop_balls(w, x, z) {
    const k = SIZES[opts.size].k;
    w.bodies = w.g.userData.orbs.map((m, j) => {
      const r = m.userData.r*k;
      const b = create_body({ sphere: r, mass: w.it.mass, inertia: new THREE.Vector3(1, 1, 1).multiplyScalar(0.4*w.it.mass*r*r), restitution: w.it.rest, friction: w.it.fric, rolling: 1.6, rr: 0.09, floor, egg });
      const a = j*2.4;
      b.x.set(x + Math.cos(a)*0.12*k, floor(x, z) + 1.1 + j*0.09, z + Math.sin(a)*0.12*k);
      b.v.set(Math.cos(a)*0.15 + rng.spread(0.1), -0.3, Math.sin(a)*0.15 + rng.spread(0.1));
      b.on_hit = (v) => { if (v > 1.2) dust(b.x, v*0.5); };
      return b;
    });
    w.body = w.bodies[0];
  }
  // balls knock each other apart (and never sink into one another)
  function collide_balls(w) {
    const B = w.bodies, O = w.g.userData.orbs, k = SIZES[opts.size].k;
    for (let i = 0; i < B.length; i++) for (let j = i + 1; j < B.length; j++) {
      const a = B[i], b = B[j], d = a.x.distanceTo(b.x), min = (O[i].userData.r + O[j].userData.r)*k;
      if (d >= min || d < 1e-6) continue;
      const n = new THREE.Vector3().subVectors(b.x, a.x).multiplyScalar(1/d);
      a.x.addScaledVector(n, -(min - d)*0.5); b.x.addScaledVector(n, (min - d)*0.5);
      const vn = new THREE.Vector3().subVectors(b.v, a.v).dot(n);
      if (vn < 0) { const j2 = -(1 + 0.4)*vn*0.5; a.v.addScaledVector(n, -j2); b.v.addScaledVector(n, j2); a.wake(); b.wake(); }
    }
  }

  // it condenses out of the air above its place (warped air gathering), then falls
  function drop(i) {
    const w = W[i];
    if (!w) return false;
    const s = SLOTS[i];
    if (w.it.balls) {
      const x = s.x + rng.spread(0.08), z = s.y + rng.spread(0.08);
      drop_balls(w, x, z);
      w.state = 'forming'; w.t = 0; w.g.visible = true;
      w.g.position.set(0, 0, 0); w.g.quaternion.identity(); w.g.scale.setScalar(1);
      for (let k = 0; k < 6; k++) warp.puff({ x: x + rng.spread(0.15), y: floor(x, z) + 1.2 + rng.spread(0.12), z: z + rng.spread(0.15), vx: rng.spread(0.3), vy: rng.spread(0.2), vz: rng.spread(0.3), drag: 2.5, life: rng.float(0.35, 0.55), s0: 0.35, s1: 0.12, amp: 3.2, spin: rng.spread(4) });
      return true;
    }
    w.body = make_body(w);
    const x = s.x + rng.spread(0.12), z = s.y + rng.spread(0.12);
    w.body.x.set(x, floor(x, z) + 1.25, z);
    w.body.q.setFromEuler(new THREE.Euler(rng.spread(1.2), rng.float(0, 6.28), rng.spread(1.2)));
    w.body.v.set(rng.spread(0.3), -0.2, rng.spread(0.3));
    w.body.w.set(rng.spread(3), rng.spread(2), rng.spread(3));
    w.state = 'forming'; w.t = 0;
    w.g.visible = true;
    for (let k = 0; k < 6; k++) warp.puff({ x: x + rng.spread(0.15), y: w.body.x.y + rng.spread(0.12), z: z + rng.spread(0.15), vx: rng.spread(0.3), vy: rng.spread(0.2), vz: rng.spread(0.3), drag: 2.5, life: rng.float(0.35, 0.55), s0: 0.35, s1: 0.12, amp: 3.2, spin: rng.spread(4) });
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
    const O = w.g.userData.orbs, k = SIZES[opts.size].k;
    if (w.state === 'forming') { w.scale = smoothstep(0, 0.22, w.t); if (w.t > 0.18) for (const b of w.bodies) b.step(dt); if (w.t > 0.25) w.state = 'falling'; }
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
        w.scale = smoothstep(0, 0.22, w.t);
        if (w.t > 0.18) { w.body.step(dt); }
        if (w.t > 0.25) w.state = 'falling';
      } else if (w.state === 'falling') {
        w.body.step(dt);
        if (w.body.asleep) w.state = 'lying';
      } else if (w.state === 'leaving') {
        w.g.position.y += dt*0.9*smoothstep(0, 0.3, w.t);
        w.scale = 1 - smoothstep(0.1, 0.45, w.t);
        w.g.scale.setScalar(Math.max(1e-3, w.scale)*SIZES[opts.size].k);
        if (w.t > 0.45) { w.state = 'away'; w.g.visible = false; }
        continue;
      }
      w.g.position.copy(w.body.x);
      w.g.quaternion.copy(w.body.q);
      w.g.scale.setScalar(Math.max(1e-3, w.scale)*SIZES[opts.size].k);
    }
    // the gem sees the sun only in the pool
    const gw = W[4];
    if (gw && gw.g.visible) {
      gw.g.userData.mat.userData.U.uLit.value = in_sun(gw.g.position);
    }
  }

  // swap the gem's cut (C): rebuild its world instance in place
  function set_cut(c) {
    opts.gem_cut = ((c % GEM_CUTS.length) + GEM_CUTS.length) % GEM_CUTS.length;
    const w = W[4];
    const vis = w.g.visible, pos = w.g.position.clone(), q = w.g.quaternion.clone();
    R.world_scene.remove(w.g);
    w.g = w.make(); w.g.visible = vis; w.g.position.copy(pos); w.g.quaternion.copy(q);
    R.world_scene.add(w.g);
    if (w.state !== 'away') { const old = w.body; w.body = make_body(w); w.body.x.copy(old.x); w.body.q.copy(old.q); w.body.x.y += 0.05; w.state = 'falling'; }
    return GEM_CUTS[opts.gem_cut];
  }

  // S: redrop whatever lies on the floor at the other size
  function set_size(i) {
    opts.size = ((i % SIZES.length) + SIZES.length) % SIZES.length;
    for (const w of W) if (w && (w.state === 'lying' || w.state === 'falling')) { if (!w.it.balls) w.g.scale.setScalar(SIZES[opts.size].k); drop(w.i); }
    return SIZES[opts.size].name;
  }

  return {
    W, opts, drop, take, update, set_cut, set_size, SLOTS,
    state: () => W.map(w => w && (w.bodies ? { state: w.state, balls: w.bodies.map(b => [+b.x.x.toFixed(2), +b.x.y.toFixed(3), +b.x.z.toFixed(2), b.asleep ? 1 : 0]) }
      : { state: w.state, x: +w.g.position.x.toFixed(2), y: +w.g.position.y.toFixed(3), z: +w.g.position.z.toFixed(2), asleep: !!(w.body && w.body.asleep) })),
  };
}
