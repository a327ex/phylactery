// beam.js -- PRISMATIC BEAM (round 11, owner: "a beam of prismatic light that is shot from his
// finger and pierces a snake, chaining if more need to be killed"): a white core with coloured
// fringes (light split like a prism's) from his fingertip to the first snake, then jumping from
// snake to snake. A pierced snake fills with that light from the wound outward and shatters
// into prismatic shards. With fewer powers left the beam chains through many more.
import * as THREE from 'three';
import { smoothstep } from 'game/util.js';

const HOP = 0.05, FILL = 0.3, SHATTER_AT = 0.42;

export function create_beam(ctx) {
  const { snakes, fx, rng } = ctx;
  const N = snakes.RINGS;
  const pending = [];                      // hops still to be drawn: { at (time), from, s, ring }
  let clock = 0;

  // one segment of the beam: a white core and a red and a blue fringe either side
  function draw(a, b) {
    fx.ribbon(a, b, { c: [5.0, 5.0, 5.0], w: 2.2, life: 0.3 });
    fx.ribbon(a, b, { c: [2.2, 0.35, 0.3], w: 1.6, off: 1.3, life: 0.3 });
    fx.ribbon(a, b, { c: [0.3, 0.5, 2.6], w: 1.6, off: -1.3, life: 0.3 });
    fx.ribbon(a, b, { c: [0.9, 0.9, 1.0], w: 7, life: 0.22, a: 0.35, hue: rng.next() });
  }

  function pierce_fx(s, hit) {
    const f = {
      t: 0, sag: 0,
      // the light runs out from the wound along the body
      glow(i) { const reach = smoothstep(0, FILL, f.t)*N; const d = Math.abs(i - hit); return d < reach ? 1 - 0.4*smoothstep(reach*0.7, reach, d) : 0; },
      shift(i, out) { const k = Math.max(0, 1 - Math.abs(i - hit)/6)*Math.sin(f.t*60)*0.01; out[1] += k; },
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
      const i = rng.int(0, N - 1), p = s.spine[i];
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

  function hit_point(s) { return rng.int(Math.round(N*0.1), Math.round(N*0.6)); }

  return {
    name: 'BEAM', gesture: true,
    cooldown: 5.5,
    // the first target, then as many more as the chain can take
    capacity: p => 1 + Math.round((p - 1)*1.3),
    aim_ring: () => Math.round(N*0.3),
    // targets[0] is where he points; the chain goes on to the nearest next each time
    cast(targets, from) {
      let prev = from.clone(), rest = targets.slice(), cur = rest.shift(), k = 0;
      while (cur) {
        const ring = k === 0 ? Math.round(N*0.3) : hit_point(cur);
        pending.push({ at: clock + k*HOP, from: prev.clone(), s: cur, ring });
        prev = cur.spine[ring].clone();
        // chain to the nearest of the rest
        rest.sort((a, b) => a.spine[20].distanceTo(prev) - b.spine[20].distanceTo(prev));
        cur = rest.shift(); k++;
      }
      // claim them now so nothing else takes them while the chain travels
      for (const q of pending) if (!q.s.fx) snakes.take(q.s, { held: true, t: 0, tick() { } });
    },
    update(t, dt) {
      clock += dt;
      for (let i = pending.length - 1; i >= 0; i--) {
        const q = pending[i];
        if (clock < q.at) continue;
        pending.splice(i, 1);
        const p = q.s.spine[q.ring].clone();
        draw(q.from, p);
        // the hit: a small burst of light at the wound
        for (let k = 0; k < 10; k++) fx.mote({ x: p.x, y: p.y, z: p.z, vx: rng.spread(1.4), vy: rng.float(0, 1.4), vz: rng.spread(1.4), drag: 2,
          life: rng.float(0.2, 0.4), s0: 0.04, s1: 0.01, r: 3, g: 3, b: 3.2, hue: rng.next() });
        q.s.fx = pierce_fx(q.s, q.ring);
      }
    },
  };
}
