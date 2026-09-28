// beam.js -- PRISMATIC BEAM (round 11, owner: "a beam of prismatic light that is shot from his
// finger and pierces a snake, chaining if more need to be killed").
// Round 13 (owner's references: Diablo 3's Disintegrate for the animation and vibe): a channelled
// beam. Its head shoots out to the first snake, burns into it a beat, then goes on to the next.
// After the last it thins out and is gone. A pierced snake fills with the light from the wound
// and shatters into prismatic shards. Round 19 (owner: "He should also not change targets while
// the beam is live. If he needs to kill multiple targets quickly, the beam should bounce
// instead"): it only BOUNCES, from the snake it pierced on to the next; his finger stays on the
// first (round 13's SWEEP, the end swept across to the next snake with his hand, is gone).
// Round 18 (owner: "just like the lens beam, except prismatic instead of red"; the round 13
// prism light "is wrong, it should be more like a rainbow sort of thing, inspired by the
// skeleton himself"; thinner; "come out of the lich's finger exactly"; "the lich's hand + arm
// should have some force thrown back on them"):
//   - the lens beam's build (fx.js ribbon style 4): white-hot core, a sheath in the colours of
//     his bones (K: held in the room like the field on his bones (round 18 verdict) / streaming
//     out along it / a full rainbow), noise eating the edges, flicker, a pop wider as it starts and as it bites,
//     sparks shed along it, a white-hot point where it burns; 6.5 cm (the lens beam: 16-22 cm)
//   - it leaves the index fingertip at the finger's own thickness, read after he is posed (it
//     was a tick behind his hand), the finger laid along it (lich.js), and always along the
//     finger: it is drawn as a curve from the finger's direction onto the snake, straight while
//     the finger points at it, whipping when the recoil throws the hand up; the white ball that sat
//     on his fingertip is gone: the tip glows at its own size, and the beam's light, in its
//     colours, falls on his hand and arm, which turn prismatic in it like the rest of him
//   - recoil (lich.kick / lich.press; HEAVY, round 18 verdict): firing throws his arm up and
//     back, its first bite a smaller kick (the later ones are away from him), the pressure holds it braced and trembling while it channels, and it springs back
//     when the beam lets go
//   - no flash discs or rings where it hits (the lens's round 16 ruling): a spit of sparks
import * as THREE from 'three';
import { smoothstep } from 'game/util.js';
import { spectrum } from 'game/fx.js';

const SHOOT_V = 45, DWELL = 0.16, END = 0.22, FILL = 0.22, SHATTER_AT = 0.36;
const W0 = 0.012, W1 = 0.065;                         // metres: the fingertip's thickness, and the beam
const PIECES = 10;                                    // a beam leaving his finger is a curve in this many straight pieces
export const BEAM_LOOKS = ['HIS COLOURS, STREAMING', 'HIS COLOURS, HELD', 'FULL RAINBOW, STREAMING'];

// his bones' colours on the CPU (fx.js opal(), gem.js): for the lights and the sparks
const opal = (h, full, out) => {
  const c = spectrum(h).map(v => v*v*(3 - 2*v)), g = full ? 0 : 0.16;
  for (let i = 0; i < 3; i++) c[i] = c[i]*(1 - g) + 0.5*g;
  const m = Math.max((c[0] + c[1] + c[2])/3, 0.2);
  out[0] = c[0]/m; out[1] = c[1]/m; out[2] = c[2]/m;
  return out;
};

export function create_beam(ctx) {
  const { R, snakes, fx, rng, lich } = ctx;
  const N = snakes.RINGS;
  const light = new THREE.PointLight(0xffffff, 0, 5, 2);        // where it burns
  const hand = new THREE.PointLight(0xffffff, 0, 1.8, 2);       // on his hand and arm
  R.world_scene.add(light); R.world_scene.add(hand);
  let look = 1, ch = null, clock = 0;                            // round 18 verdict: HIS COLOURS, HELD
  const TIP = new THREE.Vector3(), FD = new THREE.Vector3(), V = new THREE.Vector3(), P = new THREE.Vector3(), C3 = [1, 1, 1];

  // the hue the ribbon shows at a point (fx.js style 4), for what shares its light
  const hue_at = (p, x) => {
    const field0 = (TIP.x*0.45 + TIP.y*0.9 + TIP.z*0.3)*0.55 - clock*0.04;
    return look === 1 ? (p.x*0.45 + p.y*0.9 + p.z*0.3)*0.55 - clock*0.04 : field0 - (x - clock*2.4)*0.3;
  };
  const tint = (p, x) => opal(hue_at(p, x), look === 2, C3);
  // a spark in the beam's colour where it is (hue given straight: the pool's rainbow tint is
  // weaker than the ribbon's, so the colour is put into r g b and the tint left off)
  const spark = (p, x, o) => {
    const c = tint(p, x);
    return fx.mote(Object.assign({ x: p.x, y: p.y, z: p.z, r: 0.5 + 2.2*c[0], g: 0.5 + 2.2*c[1], b: 0.5 + 2.2*c[2] }, o));
  };

  function pierce_fx(s, hit) {
    const f = {
      t: 0, sag: 0,
      // the light runs out from the wound along the body
      glow(i) { const reach = smoothstep(0, FILL, f.t)*N; const d = Math.abs(i - hit); return d < reach ? 1 - 0.4*smoothstep(reach*0.7, reach, d) : 0; },
      shift(i, out) { const k = Math.max(0, 1 - Math.abs(i - hit)/6)*Math.sin(f.t*60)*0.012; out[1] += k; },
      hide: false,
      tick(dt) {
        f.t += dt;
        f.sag = smoothstep(0, SHATTER_AT, f.t)*0.6;
        if (f.t >= SHATTER_AT && !f.hide) { shatter(s); f.hide = true; }
        if (f.t >= SHATTER_AT + 0.05) return 'done';
      },
    };
    return f;
  }
  function shatter(s) {
    for (let k = 0; k < 46; k++) {
      const p = s.spine[rng.int(0, N - 1)];
      fx.shard({ x: p.x + rng.spread(0.05), y: p.y + rng.spread(0.04), z: p.z + rng.spread(0.05),
        vx: rng.spread(1.8), vy: rng.float(0.4, 2.6), vz: rng.spread(1.8), grav: 3.5, drag: 0.8,
        life: rng.float(0.6, 1.2), s0: rng.float(0.05, 0.09), s1: 0.02, r: 2.4, g: 2.4, b: 2.6, hue: rng.next(), hr: 0.8, fin: 0.02 });
    }
    for (let k = 0; k < 30; k++) {
      const p = s.spine[rng.int(0, N - 1)];
      fx.mote({ x: p.x, y: p.y, z: p.z, vx: rng.spread(0.5), vy: rng.float(0.2, 0.9), vz: rng.spread(0.5), drag: 1.0,
        life: rng.float(0.8, 1.6), s0: 0.035, s1: 0.01, r: 1.6, g: 1.6, b: 1.8, hue: rng.next(), hr: 0.5 });
    }
  }
  // where it goes in: a point on the front half of the body
  const hit_ring = () => rng.int(Math.round(N*0.12), Math.round(N*0.55));

  // where it bites: a white-hot point and a spit of sparks in its colours, no discs or rings
  function bite(p, big) {
    fx.mote({ x: p.x, y: p.y, z: p.z, life: 0.08, s0: big ? 0.16 : 0.1, s1: 0.06, r: 5, g: 5, b: 5, fin: 0.01 });
    const x = ch ? ch.head.distanceTo(TIP) : 0;
    for (let k = 0; k < (big ? 14 : 6); k++) spark(p, x + rng.spread(0.6), { vx: rng.spread(1.8), vy: rng.float(0.8, 2.8), vz: rng.spread(1.8), grav: 8, drag: 0.5,
      life: rng.float(0.3, 0.6), s0: 0.03, s1: 0.012, fin: 0.01 });
    if (ch) { ch.pop = 1; if (ch.i === 0) lich.kick(ch.arm, 0.45); }
  }
  // where the beam meets a target: fixed once it has burnt in (the snake then shatters and goes)
  const at = (q) => q.at || q.s.spine[q.ring];

  // a segment of the beam: from his finger (a curve leaving along the finger) or snake to snake
  function new_seg(from) {
    const rb = [];
    for (let k = 0; k < PIECES; k++) rb.push(fx.ribbon(from, from, { held: true, style: 4, hue: look, w: 1.5, w0: W1, w1: W1, c: [1, 1, 1], a: 1 }));
    return { rb, p0: from.clone(), p1: from.clone(), len: 0 };
  }
  const release = (sg) => { for (const b of sg.rb) fx.release(b); };
  const Q0 = new THREE.Vector3(), Q1 = new THREE.Vector3(), CT = new THREE.Vector3();
  const bez = (sg, u, out) => {
    const a = (1 - u)*(1 - u), b = 2*u*(1 - u), c = u*u;
    return out.set(sg.p0.x*a + CT.x*b + sg.p1.x*c, sg.p0.y*a + CT.y*b + sg.p1.y*c, sg.p0.z*a + CT.z*b + sg.p1.z*c);
  };
  // lays a segment's pieces: `curved` leaves p0 along FD (the finger) and bends onto p1
  function lay(sg, curved, w0, w1, a, ph0) {
    const len = sg.p0.distanceTo(sg.p1);
    // the bend stays near his finger: it leaves along the finger for a short way (at most
    // 40 cm), then runs straight on (a longer arm bowed it into an arc at close snakes)
    CT.lerpVectors(sg.p0, sg.p1, 0.5);
    if (curved) CT.copy(sg.p0).addScaledVector(FD, Math.min(0.4, 0.15*len));
    let x = 0;
    bez(sg, 0, Q0);
    // pieces crowd toward the finger, where it bends (u^2 spacing)
    sg.rb.forEach((b, k) => {
      const u1 = (k + 1)/PIECES;
      bez(sg, u1*u1, Q1);
      b.p0.copy(Q0); b.p1.copy(Q1); b.x0 = x; b.ph0 = ph0;
      b.w0 = w0; b.w1 = w1; b.a = a; b.hue = look;
      b.pv = k > 0 ? sg.rb[k - 1].p0 : null; b.nx = null;
      if (k > 0) sg.rb[k - 1].nx = b.p1;
      x += Q0.distanceTo(Q1); Q0.copy(Q1);
    });
    sg.len = x;
  }

  function update(t, dt) {
    clock = t;
    if (!ch) { light.intensity = 0; hand.intensity = 0; return; }
    ch.t += dt;
    const cur = ch.targets[ch.i];
    // the point on the current snake it goes to (the snake is held still while the beam comes)
    const goal = cur ? at(cur) : ch.head;
    if (ch.phase === 'shoot') {
      const d = V.subVectors(goal, ch.head).length(), step = SHOOT_V*dt;
      if (d <= step) ch.head.copy(goal); else ch.head.addScaledVector(V, step/d);
      if (d <= step) {
        // it burns in
        cur.at = goal.clone();
        if (!cur.s.fx || cur.s.fx.placeholder) cur.s.fx = pierce_fx(cur.s, cur.ring);
        bite(goal, true);
        ch.phase = 'dwell'; ch.pt = 0;
      }
    } else if (ch.phase === 'dwell') {
      ch.pt += dt;
      if (ch.pt >= DWELL) {
        ch.i++;
        if (ch.i >= ch.targets.length) { ch.phase = 'end'; ch.pt = 0; }
        else { ch.phase = 'shoot'; ch.segs.push(new_seg(ch.head)); }
      }
    } else if (ch.phase === 'end') {
      ch.pt += dt;
    }
    ch.k_end = ch.phase === 'end' ? 1 - smoothstep(0, END, ch.pt) : 1;
    ch.k_on = smoothstep(0, 0.06, ch.t);
    ch.pop = Math.max(0, ch.pop - dt*6);
    // the pressure on his arm while it is on
    lich.press(ch.arm, ch.k_on*ch.k_end);
    // the burning point at the head, like the lens's: a white-hot point, sparks in its colours
    const fl = 0.8 + 0.2*Math.sin(t*47);
    const hx = ch.head.distanceTo(TIP);
    if (ch.k_end > 0.3) {
      fx.mote({ x: ch.head.x, y: ch.head.y, z: ch.head.z, life: 0.05, s0: 0.12*fl*ch.k_end, s1: 0.1, r: 4, g: 4, b: 4, fin: 0.01 });
      const c = tint(ch.head, hx);
      fx.mote({ x: ch.head.x, y: ch.head.y, z: ch.head.z, life: 0.05, s0: 0.26*fl*ch.k_end, s1: 0.22, r: 0.9*c[0], g: 0.9*c[1], b: 0.9*c[2], fin: 0.01 });
      for (let k = 0; k < 2; k++) spark(ch.head, hx + rng.spread(0.5), { vx: rng.spread(2.0), vy: rng.float(0.6, 2.4), vz: rng.spread(2.0), grav: 7, drag: 0.5,
        life: rng.float(0.25, 0.55), s0: 0.028, s1: 0.01 });
    }
    // sparks shed along its length
    for (const sg of ch.segs) {
      if (sg.len < 0.3 || rng.next() > 0.8) continue;
      const b = sg.rb[rng.int(0, PIECES - 1)], e = rng.next();
      P.lerpVectors(b.p0, b.p1, e);
      spark(P, b.x0 + e*b.p0.distanceTo(b.p1), { x: P.x + rng.spread(0.03), z: P.z + rng.spread(0.03), vx: rng.spread(0.6), vy: rng.float(-0.5, 0.4), vz: rng.spread(0.6), grav: 2, drag: 1.5,
        life: rng.float(0.2, 0.4), s0: 0.022, s1: 0.008, a: ch.k_end });
    }
    const c = tint(ch.head, hx);
    light.color.setRGB(0.55 + 0.45*c[0]/2, 0.55 + 0.45*c[1]/2, 0.55 + 0.45*c[2]/2);
    light.position.copy(ch.head); light.position.y += 0.2;
    light.intensity = 1.6*ch.k_end*ch.k_on*fl;
    if (ch.phase === 'end' && ch.pt >= END) {
      for (const sg of ch.segs) release(sg);
      lich.press(ch.arm, 0);
      ch = null; light.intensity = 0; hand.intensity = 0;
    }
  }

  // after he is posed this tick: the beam leaves his fingertip where it is now
  function after_pose(t) {
    if (!ch) return;
    lich.fingertip(ch.arm, TIP);
    lich.finger_dir(ch.arm, FD);
    TIP.addScaledVector(FD, 0.004);                      // the bone's rounded end, not its joint
    const flick = 1 + 0.12*Math.sin(t*57) + 0.07*Math.sin(t*83 + 1);
    const pop = 1 + 0.6*Math.exp(-ch.t*18) + 0.35*ch.pop;
    const ph0 = (TIP.x*0.45 + TIP.y*0.9 + TIP.z*0.3)*0.55 - t*0.04;      // his bones' field where it leaves him
    ch.segs.forEach((sg, j) => {
      const from_finger = j === 0;
      if (from_finger) sg.p0.copy(TIP);
      else sg.p0.copy(at(ch.targets[j - 1]));
      const last = j === ch.segs.length - 1;
      if (last) sg.p1.copy(ch.head);
      else sg.p1.copy(at(ch.targets[j]));
      const w = W1*ch.k_on*ch.k_end*flick*pop;
      lay(sg, from_finger, from_finger ? Math.min(W0, w) : w, w, ch.k_end, ph0);
    });
    // the fingertip glows at its own size; the beam's light falls on his hand and arm
    const c = tint(TIP, 0);
    fx.mote({ x: TIP.x, y: TIP.y, z: TIP.z, life: 0.04, s0: 0.026*ch.k_end*(0.9 + 0.3*ch.pop), s1: 0.024, r: 4, g: 4, b: 4, fin: 0.01 });
    fx.mote({ x: TIP.x, y: TIP.y, z: TIP.z, life: 0.04, s0: 0.038*ch.k_end, s1: 0.034, r: 0.35*c[0], g: 0.35*c[1], b: 0.35*c[2], fin: 0.01 });
    // the light from the beam's first stretch, 15 cm out: his hand gets about the light of the
    // sunlit pool (where his bones turn most prismatic), his forearm less; nearer, the bones
    // washed out to white
    hand.position.copy(TIP).addScaledVector(FD, 0.15);
    hand.color.setRGB(0.4 + 0.6*c[0]/2, 0.4 + 0.6*c[1]/2, 0.4 + 0.6*c[2]/2);
    hand.intensity = 0.05*ch.k_on*ch.k_end*(0.9 + 0.1*flick);
  }

  return {
    name: 'BEAM', gesture: true,
    cooldown: 5.5,
    // the first target, then as many more as the chain can take
    capacity: p => 1 + Math.round((p - 1)*1.3),
    aim_ring: () => Math.round(N*0.3),
    get look() { return look; },
    set look(m) { look = ((m % BEAM_LOOKS.length) + BEAM_LOOKS.length) % BEAM_LOOKS.length; },
    // targets[0] is where he points; the rest in the order it reaches them (each time the nearest)
    cast(targets, from, ring, arm = 1) {
      if (ch) { for (const sg of ch.segs) release(sg); lich.press(ch.arm, 0); }
      const rest = targets.slice(1), order = [targets[0]];
      while (rest.length) {
        const p = order[order.length - 1].spine[20];
        rest.sort((a, b) => a.spine[20].distanceTo(p) - b.spine[20].distanceTo(p));
        order.push(rest.shift());
      }
      // they stop where they are while the beam comes for them
      for (const s of order) if (snakes.free(s)) snakes.take(s, { placeholder: true, tick() { } });
      lich.fingertip(arm, TIP);
      ch = { t: 0, arm, i: 0, phase: 'shoot', pt: 0, head: TIP.clone(), pop: 0, k_on: 0, k_end: 1,
        targets: order.map((s, k) => ({ s, ring: k === 0 ? ring : hit_ring() })), segs: [] };
      ch.segs.push(new_seg(TIP));
      // it fires: the arm is thrown back, the fingertip spits sparks out to the sides
      lich.kick(arm, 1);
      lich.finger_dir(arm, FD);
      for (let k = 0; k < 8; k++) {
        V.set(rng.spread(1), rng.spread(1), rng.spread(1)); V.addScaledVector(FD, -V.dot(FD)).setLength(rng.float(0.6, 1.4)).addScaledVector(FD, rng.float(-0.3, 0.4));
        spark(TIP, 0, { vx: V.x, vy: V.y, vz: V.z, grav: 3, drag: 2.5, life: rng.float(0.15, 0.3), s0: 0.018, s1: 0.006, fin: 0.01 });
      }
    },
    update, after_pose,
    lights: { light, hand },
    chain: () => (ch ? ch.targets.length : 0),         // tests: how many the live beam is taking
    // take on more while it channels (a snake about to reach the egg): they join the end of the chain
    extend(more) {
      if (!ch) return;
      for (const s of more) {
        if (!snakes.free(s) || ch.targets.some(q => q.s === s)) continue;
        snakes.take(s, { placeholder: true, tick() { } });
        ch.targets.push({ s, ring: hit_ring() });
        if (ch.phase === 'end') { ch.phase = 'shoot'; ch.pt = 0; ch.segs.push(new_seg(ch.head)); }
      }
    },
    // while it channels his finger stays on the first snake, where the segment from it goes
    busy: () => !!ch,
    aim_point: () => (ch ? at(ch.targets[0]) : null),
  };
}
