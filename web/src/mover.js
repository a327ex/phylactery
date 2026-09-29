// mover.js -- the lich's body through the room (round 5). He floats: he eases into motion,
// drifts a little out of it, turns to face where he is sent, rides up over stones and rubble,
// and is stopped by rock, the egg, and the edge of what the room camera sees (nav.js).
// Each tick hands lich.pose() the pelvis' real acceleration and velocity in his own frame,
// which is what swings his parts.
import * as THREE from 'three';
import { clamp } from 'game/util.js';

export const MOVE = {
  speed: 2.6,            // m/s; the snakes crawl at 1.0-1.35
  acc: 7.0, tau_acc: 0.3,   // pushing: at most 7 m/s^2, closing the gap to the wanted velocity in ~0.3 s
  dec: 5.0, tau_dec: 0.38,  // letting go: a softer stop, he drifts ~0.6 m
  jerk: 11,              // how fast the push itself changes (1/s): no instant jolts
  radius: 0.34,          // his body, for rock
  turn_f: 0.8, turn_z: 0.85, turn_amax: 22, turn_vmax: 5.5,   // facing spring (Hz, damping, limits)
  turn_f_point: 2.0, turn_amax_point: 45, turn_vmax_point: 8,   // round 22: quicker while he turns to keep what he points at in front
  bob: 0.05,             // the breathing float, metres
};

const wrap = a => Math.atan2(Math.sin(a), Math.cos(a));

export function create_mover(nav, lich, start, yaw0) {
  const p = start.clone();                     // the pelvis, world
  const v = new THREE.Vector3();               // horizontal velocity (y unused)
  const push = new THREE.Vector2();            // the applied horizontal acceleration
  let vy = 0, yaw = yaw0, yaw_v = 0, yaw_a = 0, want_yaw = yaw0;
  // round 22 (owner: he should not point at something behind him; what he points at stays in the
  // half in front, "open like on a cross" at most): while `face` is on, he faces as near to where
  // he is sent as he can with face.yaw (the way to what he points at) within face.half of his
  // facing; still, he turns toward it just enough. He floats, so he can go one way facing another.
  const face = { on: false, yaw: 0, half: 1.31 };
  const prev_p = p.clone(), prev_vel = new THREE.Vector3(), vel = new THREE.Vector3(), acc = new THREE.Vector3();
  const motion = { a: [0, 0, 0], v: [0, 0, 0], push: [0, 0], yaw_a: 0, yaw_v: 0, look: 0 };
  const height_at = (t) => nav.floor(p.x, p.z) + lich.hover_h + MOVE.bob*Math.sin(t*1.1) + 0.015*Math.sin(t*0.63 + 1.0);
  p.y = height_at(0);
  prev_p.copy(p);

  function tick(t, dt, want) {
    const wl = Math.hypot(want.x, want.z);
    const pushing = wl > 0.01;
    // steer toward the wanted velocity with a bounded push, harder when sent than when let go
    const tau = pushing ? MOVE.tau_acc : MOVE.tau_dec, amax = pushing ? MOVE.acc : MOVE.dec;
    let cx = (want.x - v.x)/tau, cz = (want.z - v.z)/tau;
    const cl = Math.hypot(cx, cz);
    if (cl > amax) { cx *= amax/cl; cz *= amax/cl; }
    const k = 1 - Math.exp(-MOVE.jerk*dt);
    push.x += (cx - push.x)*k; push.y += (cz - push.y)*k;
    v.x += push.x*dt; v.z += push.y*dt;
    if (!pushing && Math.hypot(v.x, v.z) < 0.02 && Math.hypot(push.x, push.y) < 0.05) { v.x = v.z = 0; push.set(0, 0); }
    p.x += v.x*dt; p.z += v.z*dt;
    if (nav.resolve(p, v, MOVE.radius)) {
      // against rock: the push along the wall survives, the push into it doesn't
      const s = Math.hypot(v.x, v.z), ps = Math.hypot(push.x, push.y);
      if (s > 1e-4 && ps > 1e-4) { const along = (push.x*v.x + push.y*v.z)/s; push.set(v.x/s*along, v.z/s*along); }
    }
    // height: a soft spring to the floor under his legs, plus the bob
    const wv = 6.2832*1.0;
    vy += (wv*wv*(height_at(t) - p.y) - 2*0.65*wv*vy)*dt;
    p.y += vy*dt;
    // facing: a spring toward where he is sent
    if (pushing) want_yaw = Math.atan2(want.x, want.z);
    if (face.on) { const rel = wrap(face.yaw - want_yaw); if (Math.abs(rel) > face.half) want_yaw = wrap(face.yaw - Math.sign(rel)*face.half); }
    const wy = 6.2832*(face.on ? MOVE.turn_f_point : MOVE.turn_f);
    const tam = face.on ? MOVE.turn_amax_point : MOVE.turn_amax, tvm = face.on ? MOVE.turn_vmax_point : MOVE.turn_vmax;
    yaw_a = clamp(wy*wy*wrap(want_yaw - yaw) - 2*MOVE.turn_z*wy*yaw_v, -tam, tam);
    yaw_v = clamp(yaw_v + yaw_a*dt, -tvm, tvm);
    yaw = wrap(yaw + yaw_v*dt);
    // what the body felt this tick, in his frame (x = his left, z = forward)
    vel.subVectors(p, prev_p).divideScalar(dt);
    acc.subVectors(vel, prev_vel).divideScalar(dt);
    if (acc.length() > 20) acc.setLength(20);
    prev_p.copy(p); prev_vel.copy(vel);
    const sy = Math.sin(yaw), cy = Math.cos(yaw);
    motion.a[0] = acc.x*cy - acc.z*sy; motion.a[1] = acc.y; motion.a[2] = acc.x*sy + acc.z*cy;
    motion.v[0] = vel.x*cy - vel.z*sy; motion.v[1] = vel.y; motion.v[2] = vel.x*sy + vel.z*cy;
    // the push: where he is sent minus how he moves, in his frame, as a fraction of full speed
    let qx = ((want.x - vel.x)*cy - (want.z - vel.z)*sy)/MOVE.speed, qz = ((want.x - vel.x)*sy + (want.z - vel.z)*cy)/MOVE.speed;
    const ql = Math.hypot(qx, qz);
    if (ql > 1) { qx /= ql; qz /= ql; }
    motion.push[0] = qx; motion.push[1] = qz;
    motion.yaw_a = yaw_a; motion.yaw_v = yaw_v;
    motion.look = pushing ? wrap(want_yaw - yaw) : 0;
    lich.root.position.copy(p);
    lich.root.rotation.y = yaw;
  }

  return {
    p, v, motion, tick, face,
    get yaw() { return yaw; },
    get speed() { return Math.hypot(v.x, v.z); },
    place(x, z, y_ = yaw) {
      p.x = x; p.z = z; v.set(0, 0, 0); push.set(0, 0); yaw = want_yaw = y_; yaw_v = 0;
      p.y = height_at(0); vy = 0; prev_p.copy(p); prev_vel.set(0, 0, 0);
      lich.root.position.copy(p); lich.root.rotation.y = yaw;
    },
  };
}
