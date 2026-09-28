// beam.js -- PRISMATIC BEAM (round 11, owner: "a beam of prismatic light that is shot from his
// finger and pierces a snake, chaining if more need to be killed").
// Round 13 (owner's references: Diablo 3's Disintegrate for the animation and vibe, and the end
// of the real video of white light through a prism for the look): a channelled beam. White
// light leaves his fingertip and disperses along the way into an ordered band, red on one edge
// to violet on the other (fx.js ribbon style 1: his finger is the prism). Its head shoots out
// to the first snake, burns into it a beat (flares at both ends, sparks, a light riding the
// tip), then goes on to the next: SWEEP (Disintegrate: the beam stays on his finger and its end
// sweeps across to the next snake) or BOUNCE (it goes on from the snake it pierced). After the
// last it thins out and is gone. A pierced snake fills with the light from the wound and
// shatters into prismatic shards.
import * as THREE from 'three';
import { smoothstep } from 'game/util.js';

const SHOOT_V = 45, DWELL = 0.16, MOVE_V = 30, END = 0.22, FILL = 0.22, SHATTER_AT = 0.36;
const W0 = 0.014, W1 = 0.26;                          // metres: at his finger, and dispersed at the far end
export const CHAIN_MODES = ['SWEEP (DISINTEGRATE)', 'BOUNCE (SNAKE TO SNAKE)'];

export function create_beam(ctx) {
  const { R, snakes, fx, rng, lich } = ctx;
  const N = snakes.RINGS;
  const light = new THREE.PointLight(0xf4f0ff, 0, 5, 2);
  R.world_scene.add(light);
  let mode = 0, ch = null;
  const TIP = new THREE.Vector3(), V = new THREE.Vector3();

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

  // the flare where it burns in: a white flash, spectral sparks, a ring of light on the floor
  function impact(p, big) {
    fx.mote({ x: p.x, y: p.y, z: p.z, life: 0.1, s0: big ? 0.5 : 0.3, s1: 0.2, r: 4, g: 4, b: 4.2, fin: 0.01 });
    for (let k = 0; k < (big ? 18 : 6); k++) fx.mote({ x: p.x, y: p.y, z: p.z, vx: rng.spread(2.4), vy: rng.float(0.3, 2.2), vz: rng.spread(2.4), grav: 4, drag: 1.2,
      life: rng.float(0.25, 0.5), s0: 0.035, s1: 0.012, r: 3, g: 3, b: 3.2, hue: rng.next(), hr: 1 });
    if (big) for (let k = 0; k < 20; k++) {
      const a = k/20*6.283;
      fx.mote({ x: p.x, y: p.y - 0.03, z: p.z, vx: Math.cos(a)*1.6, vy: 0, vz: Math.sin(a)*1.6, drag: 3, life: 0.35, s0: 0.03, s1: 0.015, r: 2, g: 2, b: 2.2, hue: k/20, fin: 0.02 });
    }
  }

  function new_seg(from) {
    return fx.ribbon(from, from, { held: true, style: 1, w: 1.5, w0: W0, w1: W1, c: [1, 1, 1], a: 1 });
  }

  function update(t, dt) {
    if (!ch) { light.intensity = 0; return; }
    ch.t += dt;
    lich.fingertip(ch.arm, TIP);
    const cur = ch.targets[ch.i];
    // the point on the current snake it goes to (the snake is held still by the pierce)
    const goal = cur ? cur.s.spine[cur.ring] : ch.head;
    if (ch.phase === 'shoot' || ch.phase === 'move') {
      const d = V.subVectors(goal, ch.head).length(), step = (ch.phase === 'shoot' ? SHOOT_V : MOVE_V)*dt;
      if (d <= step) ch.head.copy(goal); else ch.head.addScaledVector(V, step/d);
      // SWEEP: whatever else it crosses on the way burns too
      if (ch.phase === 'move') for (const s of snakes.S) {
        if (!snakes.free(s) || ch.targets.some(q => q.s === s)) continue;
        for (let j = 4; j < N; j += 6) if (s.spine[j].distanceTo(ch.head) < 0.14) { snakes.take(s, pierce_fx(s, j)); impact(s.spine[j], false); break; }
      }
      if (d <= step) {
        // it burns in
        if (!cur.s.fx || cur.s.fx.placeholder) cur.s.fx = pierce_fx(cur.s, cur.ring);
        impact(goal, true);
        ch.phase = 'dwell'; ch.pt = 0;
      }
    } else if (ch.phase === 'dwell') {
      ch.pt += dt;
      if (ch.pt >= DWELL) {
        ch.i++;
        if (ch.i >= ch.targets.length) { ch.phase = 'end'; ch.pt = 0; }
        else {
          ch.phase = mode === 0 ? 'move' : 'shoot';
          if (mode === 1) { ch.segs.push(new_seg(ch.head)); }
        }
      }
    } else if (ch.phase === 'end') {
      ch.pt += dt;
    }
    // draw: SWEEP = one segment from his finger to the head; BOUNCE = finger to the first hit,
    // then hit to hit, the newest one ending at the head
    const k_end = ch.phase === 'end' ? 1 - smoothstep(0, END, ch.pt) : 1;
    const k_on = smoothstep(0, 0.06, ch.t);
    const flick = 1 + 0.14*Math.sin(t*63) + 0.08*Math.sin(t*91 + 1);
    ch.segs.forEach((b, j) => {
      if (mode === 0 || j === 0) b.p0.copy(TIP);
      if (mode === 1 && j > 0) b.p0.copy(ch.targets[j - 1].s.spine[ch.targets[j - 1].ring]);
      const last = j === ch.segs.length - 1;
      if (last) b.p1.copy(ch.head);
      else b.p1.copy(ch.targets[j].s.spine[ch.targets[j].ring]);
      const w = k_on*k_end*flick;
      b.w0 = W0*w; b.w1 = W1*w; b.a = k_end;
    });
    // flares: a hot point at his fingertip, and at the head, spitting spectral sparks
    const fl = 0.8 + 0.2*Math.sin(t*47);
    fx.mote({ x: TIP.x, y: TIP.y, z: TIP.z, life: 0.05, s0: 0.1*fl*k_end, s1: 0.08, r: 4, g: 4, b: 4.2, fin: 0.01 });
    fx.mote({ x: ch.head.x, y: ch.head.y, z: ch.head.z, life: 0.05, s0: 0.2*fl*k_end, s1: 0.15, r: 3, g: 3, b: 3.2, fin: 0.01 });
    if (k_end > 0.5 && rng.next() < 0.7) fx.mote({ x: ch.head.x, y: ch.head.y, z: ch.head.z, vx: rng.spread(1.6), vy: rng.float(0.3, 1.8), vz: rng.spread(1.6), grav: 4, drag: 1,
      life: rng.float(0.2, 0.45), s0: 0.03, s1: 0.01, r: 2.6, g: 2.6, b: 2.8, hue: rng.next(), hr: 1 });
    if (k_end > 0.5 && rng.next() < 0.4) fx.mote({ x: TIP.x, y: TIP.y, z: TIP.z, vx: rng.spread(0.5), vy: rng.float(0, 0.6), vz: rng.spread(0.5), drag: 2,
      life: rng.float(0.2, 0.4), s0: 0.02, s1: 0.008, r: 2.4, g: 2.4, b: 2.6, hue: rng.next(), hr: 1 });
    light.position.copy(ch.head); light.position.y += 0.2;
    light.intensity = 1.6*k_end*k_on*fl;
    if (ch.phase === 'end' && ch.pt >= END) {
      for (const b of ch.segs) fx.release(b);
      ch = null; light.intensity = 0;
    }
  }

  return {
    name: 'BEAM', gesture: true,
    cooldown: 5.5,
    // the first target, then as many more as the chain can take
    capacity: p => 1 + Math.round((p - 1)*1.3),
    aim_ring: () => Math.round(N*0.3),
    get mode() { return mode; },
    set mode(m) { mode = ((m % CHAIN_MODES.length) + CHAIN_MODES.length) % CHAIN_MODES.length; },
    // targets[0] is where he points; the rest in the order it reaches them (each time the nearest)
    cast(targets, from, ring, arm = 1) {
      if (ch) { for (const b of ch.segs) fx.release(b); }
      const rest = targets.slice(1), order = [targets[0]];
      while (rest.length) {
        const p = order[order.length - 1].spine[20];
        rest.sort((a, b) => a.spine[20].distanceTo(p) - b.spine[20].distanceTo(p));
        order.push(rest.shift());
      }
      // they stop where they are while the beam comes for them
      for (const s of order) if (snakes.free(s)) snakes.take(s, { placeholder: true, tick() { } });
      lich.fingertip(arm, TIP);
      ch = { t: 0, arm, i: 0, phase: 'shoot', pt: 0, head: TIP.clone(),
        targets: order.map((s, k) => ({ s, ring: k === 0 ? ring : hit_ring() })), segs: [] };
      ch.segs.push(new_seg(TIP));
    },
    update,
    // take on more while it channels (a snake about to reach the egg): they join the end of the chain
    extend(more) {
      if (!ch) return;
      for (const s of more) {
        if (!snakes.free(s) || ch.targets.some(q => q.s === s)) continue;
        snakes.take(s, { placeholder: true, tick() { } });
        ch.targets.push({ s, ring: hit_ring() });
        if (ch.phase === 'end') { ch.phase = mode === 0 ? 'move' : 'shoot'; ch.pt = 0; if (mode === 1) ch.segs.push(new_seg(ch.head)); }
      }
    },
    // while it channels, his hand follows the head of the beam
    busy: () => !!ch,
    aim_point: () => (ch ? ch.head : null),
  };
}
