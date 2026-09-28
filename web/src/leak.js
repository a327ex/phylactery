// leak.js -- LEAKAGE (round 11, owner: "prismatic effect coming from his head, slowly
// dematerializes snakes near him"; it happens by itself, he never gestures for it).
//
// Faint prismatic motes rise and spread from his skull, and every so often a ring of them runs
// outward: the power seeping out of him. A snake within its reach slows and comes apart from
// the tail forward, shedding prismatic dust at the edge where it is going (snakes.js draws the
// dissolving, from `s.leak`). Out of reach, a half-gone snake slowly comes back together.
// With fewer powers left its reach grows until, alone, it spans from him to past the egg
// wherever he is, and it works faster.
import * as THREE from 'three';

export function create_leak(ctx) {
  const { snakes, fx, lich, rng, egg, get_L } = ctx;
  const N = snakes.RINGS;
  const H = new THREE.Vector3();
  let ring_t = 0, emit = 0;
  let reach = 2.6, rate = 0.22;

  return {
    name: 'LEAKAGE', gesture: false,
    // how far it reaches and how fast it takes them, for a power level p (1 = all six powers)
    scale(p, R_T) {
      const L = get_L();
      const far = Math.hypot(L.x - egg.x, L.z - egg.z) + R_T + 0.8;
      const k = (p - 1)/5;
      reach = 2.6 + k*Math.max(0, far - 2.6);
      rate = 0.22*Math.pow(p, 0.75)*(p >= 6 ? 1.6 : 1);
    },
    get reach() { return reach; },
    update(t, dt, on, urgent) {
      const L = get_L();
      for (const s of snakes.S) {
        if (s.delay > 0 || s.dying >= 0 || s.burn || s.sink >= 0 || s.fx) continue;
        let d = 1e9;
        for (let i = 0; i < N; i += 6) d = Math.min(d, Math.hypot(s.spine[i].x - L.x, s.spine[i].z - L.z));
        if (on && d < reach) {
          // closer to him, faster; a snake about to reach the egg is taken much faster
          const k = 1 - 0.5*d/reach;
          s.leak += rate*k*dt*(urgent && urgent.has(s) ? 4 : 1);
          // prismatic dust from where it is coming apart
          if (rng.next() < 0.5) {
            const u = Math.min(0.999, s.leak*1.12), i = Math.round((1 - u)*(N - 1));
            const p = s.spine[Math.max(0, Math.min(N - 1, i))];
            fx.mote({ x: p.x + rng.spread(0.05), y: p.y + rng.spread(0.03), z: p.z + rng.spread(0.05), vx: rng.spread(0.15), vy: rng.float(0.15, 0.5), vz: rng.spread(0.15), drag: 0.6,
              life: rng.float(0.9, 1.8), s0: 0.05, s1: 0.015, r: 2.0, g: 2.0, b: 2.2, hue: rng.next(), hr: 0.4, fin: 0.1 });
          }
        } else if (s.leak > 0) s.leak = Math.max(0, s.leak - 0.06*dt);
      }
      if (!on) return;
      // from his head: motes rising and spreading, more and further the larger its reach
      lich.head_pos(H);
      const big = 1 + Math.max(0, reach - 2.6)/5;                 // the further it reaches, the more it shows
      emit += dt*(10 + reach*4);
      while (emit >= 1) {
        emit -= 1;
        const a = rng.float(0, 6.28), sp = rng.float(0.25, 0.6)*(0.6 + reach/4);
        fx.mote({ x: H.x + rng.spread(0.06), y: H.y + rng.spread(0.05), z: H.z + rng.spread(0.06), vx: Math.cos(a)*sp, vy: rng.float(-0.05, 0.25), vz: Math.sin(a)*sp, drag: 0.15,
          life: Math.min(9, reach/sp*rng.float(0.6, 1.0)), s0: 0.03*big, s1: 0.014*big, r: 0.9*big, g: 0.9*big, b: 1.0*big, hue: rng.next(), hr: 0.3, fin: 0.12, a: 0.8 });
      }
      // now and then a ring of it runs out across the floor to the edge of its reach
      ring_t -= dt;
      if (ring_t <= 0) {
        ring_t = rng.float(1.6, 2.6);
        const n = 28 + Math.round(reach*3);
        for (let k = 0; k < n; k++) {
          const a = k/n*6.2832 + rng.spread(0.05), sp = reach/2.2;
          fx.mote({ x: H.x, y: H.y - 0.15, z: H.z, vx: Math.cos(a)*sp, vy: -0.55, vz: Math.sin(a)*sp, drag: 0.05, floor: true,
            life: 2.2, s0: 0.04*big, s1: 0.025*big, r: 0.8*big, g: 0.8*big, b: 0.9*big, hue: k/n, hr: 0.2, a: 0.55, fin: 0.05 });
        }
      }
    },
  };
}
