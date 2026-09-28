// wind.js -- WIND (round 11, owner: "pushes snakes away"): he points; a gust hits the snake and
// throws it away from the egg (always straight out from the egg, so no gust can ever blow one
// into it), the body skidding and tumbling a little off the floor, dust streaming with it. It
// doesn't kill: the snake lands, turns, and comes back. With fewer powers left one gust takes
// several.
import * as THREE from 'three';
import { smoothstep } from 'game/util.js';

const PUSH_T = 1.0;

export function create_wind(ctx) {
  const { snakes, fx, cave, rng, egg } = ctx;
  const N = snakes.RINGS;

  function push_fx(s) {
    // straight out from the egg, through the snake's head
    const out = new THREE.Vector2(s.x - egg.x, s.z - egg.z);
    if (out.lengthSq() < 1e-4) out.set(1, 0);
    out.normalize();
    const r0 = Math.hypot(s.x - egg.x, s.z - egg.z);
    const D = Math.max(1.5, Math.min(rng.float(4.5, 6.0), 13 - r0));
    const side = rng.sign(), ph = rng.float(0, 6.28);
    let moved = 0;
    const f = {
      t: 0,
      sag: 0,
      lift(i) { return 0.28*Math.sin(Math.PI*Math.min(1, f.t/PUSH_T))*(0.6 + 0.4*Math.sin(i*0.12 + ph)); },
      shift(i, out_) {
        // the body swings as it tumbles
        const w = Math.sin(Math.PI*Math.min(1, f.t/PUSH_T))*Math.sin(i*0.18 + f.t*9 + ph)*0.1*side;
        out_[0] += -out.y*w; out_[2] += out.x*w;
      },
      tick(dt) {
        f.t += dt;
        const u = Math.min(1, f.t/PUSH_T);
        const d = D*(1 - Math.pow(1 - u, 3));
        const step = d - moved; moved = d;
        // the whole body goes with it
        s.x += out.x*step; s.z += out.y*step;
        for (const q of s.trail) { q[0] += out.x*step; q[1] += out.y*step; }
        f.sag = Math.sin(Math.PI*u)*0.8;
        // dust where it scrapes the floor
        if (rng.next() < 0.5*(1 - u)) {
          const p = s.spine[rng.int(0, N - 1)];
          fx.puff({ x: p.x, y: cave.ground_y(p.x, p.z) + 0.05, z: p.z, vx: out.x*rng.float(0.8, 2.0), vy: rng.float(0.1, 0.5), vz: out.y*rng.float(0.8, 2.0),
            drag: 1.8, life: rng.float(0.8, 1.5), s0: 0.12, s1: 0.5, r: 0.09, g: 0.08, b: 0.06, a: 0.45 });
        }
        if (f.t >= PUSH_T) {
          // dazed: it faces somewhere else for a moment before it turns back
          s.dir = Math.atan2(out.y, out.x) + rng.spread(1.2);
          return 'free';
        }
      },
    };
    return f;
  }

  // the gust itself: pale streaks racing from his hand to the snake, and a blast of air bursting
  // out from its body (lit air: it has to read in the dark from the room camera)
  function gust(from, s) {
    const c = s.spine[20];
    const out = new THREE.Vector2(c.x - egg.x, c.z - egg.z).normalize();
    const dx = c.x - from.x, dz = c.z - from.z, l = Math.hypot(dx, dz) || 1;
    for (let k = 0; k < 44; k++) {
      const u = rng.next();
      const x = from.x + dx*u, y = from.y + (c.y + 0.3 - from.y)*u, z = from.z + dz*u;
      fx.mote({ x: x + rng.spread(0.25), y: y + rng.spread(0.2), z: z + rng.spread(0.25), vx: dx/l*rng.float(6, 11), vy: rng.spread(0.3), vz: dz/l*rng.float(6, 11),
        drag: 1.5, life: rng.float(0.25, 0.45), s0: 0.06, s1: 0.03, r: 0.75, g: 0.72, b: 0.62, a: 0.7, fin: 0.05 });
    }
    // the blast: a ring of air bursting outward from the body, mostly away from the egg
    for (let k = 0; k < 40; k++) {
      const p = s.spine[rng.int(0, N - 1)], a = rng.float(0, 6.28);
      const vx = Math.cos(a)*rng.float(1.5, 3) + out.x*rng.float(3, 6), vz = Math.sin(a)*rng.float(1.5, 3) + out.y*rng.float(3, 6);
      fx.mote({ x: p.x, y: p.y + 0.08, z: p.z, vx, vy: rng.float(0.2, 1.0), vz, drag: 2.0,
        life: rng.float(0.35, 0.7), s0: 0.07, s1: 0.03, r: 0.8, g: 0.76, b: 0.66, a: 0.6, fin: 0.03 });
    }
    for (let k = 0; k < 22; k++) {
      const p = s.spine[rng.int(0, N - 1)];
      fx.puff({ x: p.x + rng.spread(0.3), y: p.y + rng.float(0, 0.4), z: p.z + rng.spread(0.3), vx: out.x*rng.float(2, 4.5), vy: rng.float(0, 0.6), vz: out.y*rng.float(2, 4.5),
        drag: 1.4, life: rng.float(0.7, 1.2), s0: 0.15, s1: 0.7, r: 0.1, g: 0.09, b: 0.07, a: 0.45 });
    }
  }

  return {
    name: 'WIND', gesture: true,
    cooldown: 5.0,
    capacity: p => Math.ceil(p/1.5),
    aim_ring: () => 20,
    cast(targets, from) { for (const s of targets) { gust(from, s); snakes.take(s, push_fx(s)); } },
    update() { },
  };
}
