// lift.js -- LIFT AND BURST (round 11, owner): he points; the snake is lifted off the floor by
// an unseen hand under its middle (head and tail hanging, the body writhing), held a moment,
// swells, and bursts: dark chunks thrown out to fall and bounce, a mist of blood, dust
// kicked up on the floor below. With fewer powers left one gesture lifts several at once.
import * as THREE from 'three';
import { smoothstep } from 'game/util.js';

const RISE = 0.8, HOLD = 0.4, SWELL = 0.14;

export function create_lift(ctx) {
  const { snakes, fx, cave, rng } = ctx;
  const N = snakes.RINGS, mid = Math.round(N*0.45), half = N*0.55;

  function lift_fx(s) {
    const H = rng.float(1.5, 2.0), side = new THREE.Vector2();
    // the body's sideways direction (for the writhe): across its head-to-tail line
    const a = s.spine[4], b = s.spine[N - 5];
    side.set(-(a.z - b.z), a.x - b.x).normalize();
    const ph = rng.float(0, 6.28);
    const f = {
      t: 0, sag: 0,
      lift(i) {
        const e = smoothstep(0, RISE, f.t);
        const d = (i - mid)/half;
        return H*e*(1 - 0.5*d*d) + (f.t > RISE ? Math.sin(f.t*31 + i*0.7)*0.012*smoothstep(RISE, RISE + HOLD, f.t) : 0);
      },
      shift(i, out) {
        // writhing in the air, and the tremble before it bursts
        const w = smoothstep(0.1, 0.5, f.t)*Math.sin(i*0.3 - f.t*7 + ph)*0.09*(1 - 0.5*smoothstep(RISE, RISE + HOLD, f.t));
        out[0] += side.x*w; out[2] += side.y*w;
      },
      radk(i) { const sw = smoothstep(RISE + HOLD, RISE + HOLD + SWELL, f.t); return 1 + sw*0.35*(1 - Math.abs((i - mid)/half)); },
      hide: false,
      tick(dt) {
        f.t += dt;
        f.sag = smoothstep(0, RISE, f.t);
        if (f.t >= RISE + HOLD + SWELL && !f.hide) { burst(s); f.hide = true; }
        if (f.t >= RISE + HOLD + SWELL + 0.05) return 'done';
      },
    };
    return f;
  }

  function burst(s) {
    // the centre of the body, and the floor under it
    const c = s.spine[mid], gy = cave.ground_y(c.x, c.z);
    for (let k = 0; k < 16; k++) {
      const i = rng.int(2, N - 3), p = s.spine[i];
      const q = fx.chunk();
      const out = new THREE.Vector3(p.x - c.x, 0, p.z - c.z);
      if (out.lengthSq() < 1e-4) out.set(rng.spread(1), 0, rng.spread(1));
      out.normalize();
      const sp = rng.float(1.5, 3.8);
      Object.assign(q, { life: rng.float(3.0, 4.0), x: p.x, y: p.y, z: p.z, vx: out.x*sp + rng.spread(1.2), vy: rng.float(1.0, 3.2), vz: out.z*sp + rng.spread(1.2),
        rx: rng.float(0, 6), ry: rng.float(0, 6), rz: rng.float(0, 6), wx: rng.spread(12), wy: rng.spread(12), wz: rng.spread(12),
        s: rng.float(0.035, 0.07)*(i < 8 ? 0.8 : 1), sx: rng.float(0.8, 1.6), sy: rng.float(0.6, 1.0), sz: rng.float(0.8, 1.4) });
    }
    // a mist of blood, spreading and falling
    for (let k = 0; k < 34; k++) {
      const p = s.spine[rng.int(0, N - 1)];
      fx.puff({ x: p.x, y: p.y, z: p.z, vx: rng.spread(1.4), vy: rng.float(-0.2, 1.2), vz: rng.spread(1.4), grav: 1.2, drag: 1.6,
        life: rng.float(0.7, 1.4), s0: rng.float(0.1, 0.2), s1: rng.float(0.35, 0.6), r: 0.028, g: 0.004, b: 0.003, a: 0.6, fin: 0.03 });
    }
    // droplets that fall to the floor and stay a moment
    for (let k = 0; k < 40; k++) {
      const p = s.spine[rng.int(0, N - 1)];
      fx.puff({ x: p.x, y: p.y, z: p.z, vx: rng.spread(2.6), vy: rng.float(0.2, 2.4), vz: rng.spread(2.6), grav: 9.8, drag: 0.2, floor: true,
        life: rng.float(1.2, 2.2), s0: 0.03, s1: 0.045, r: 0.045, g: 0.004, b: 0.003, a: 0.9, fin: 0.01 });
    }
    // the pop: a brief pale flash where it was
    fx.mote({ x: c.x, y: c.y, z: c.z, life: 0.12, s0: 0.9, s1: 1.4, r: 2.2, g: 2.0, b: 1.8, a: 1, fin: 0.01 });
    // dust knocked up from the floor below
    for (let k = 0; k < 14; k++) {
      const a = rng.float(0, 6.28), r = rng.float(0.1, 0.6);
      fx.puff({ x: c.x + Math.cos(a)*r, y: gy + 0.05, z: c.z + Math.sin(a)*r, vx: Math.cos(a)*rng.float(0.6, 1.4), vy: rng.float(0.1, 0.4), vz: Math.sin(a)*rng.float(0.6, 1.4),
        drag: 2.2, life: rng.float(0.8, 1.4), s0: 0.15, s1: 0.5, r: 0.03, g: 0.025, b: 0.018, a: 0.5 });
    }
  }

  return {
    name: 'LIFT', gesture: true,
    cooldown: 6.0,
    capacity: p => Math.ceil(p/1.5),
    // where he points: the middle of the body
    aim_ring: () => mid,
    cast(targets) { for (const s of targets) snakes.take(s, lift_fx(s)); },
    update() { },
  };
}
