// lift.js -- LIFT AND BURST (round 11, owner): he points; the snake is lifted off the floor by
// an unseen hand under its middle (head and tail hanging, the body writhing), held a moment,
// swells, and bursts. With fewer powers left one gesture lifts several at once.
// Round 20 (owner: "When lifting, if there are multiple snakes in the general vicinity of the
// lift they should be lifted together. His arm should follow as the snakes are lifted (follow
// up) and then only go back down once they're killed. The explosion for the snakes should be
// more detailed, gory, currently it looks too cheap"):
//   - every free snake whose middle is within GROUP_R of a target's goes up with it, a beat
//     apart, and so do any that come about to reach the egg while he holds them (extend)
//   - it is a channel: his hand follows the lifted bodies up (aim_point) and holds on them until
//     the last one bursts; only then does it come down
//   - the burst is gore.js: the body torn into its own pieces, meat, ribs and vertebrae, guts,
//     jets and rain of blood that splash the floor and stay (the pale flash is gone)
import * as THREE from 'three';
import { smoothstep } from 'game/util.js';

const RISE = 0.8, HOLD = 0.4, SWELL = 0.2;
const GROUP_R = 1.8;                  // metres between the middles of snakes lifted together

export function create_lift(ctx) {
  const { snakes, fx, cave, rng, gore } = ctx;
  const N = snakes.RINGS, mid = Math.round(N*0.45), half = N*0.55;
  const held = [];                    // the lifts of the last cast, until they burst
  const AIM = new THREE.Vector3();

  function lift_fx(s, delay = 0) {
    const H = rng.float(1.5, 2.0), side = new THREE.Vector2();
    // the body's sideways direction (for the writhe): across its head-to-tail line
    const a = s.spine[4], b = s.spine[N - 5];
    side.set(-(a.z - b.z), a.x - b.x).normalize();
    const ph = rng.float(0, 6.28);
    const f = {
      t: -delay, sag: 0, s,
      lift(i) {
        const e = smoothstep(0, RISE, f.t);
        const d = (i - mid)/half;
        return H*e*(1 - 0.5*d*d) + (f.t > RISE ? Math.sin(f.t*31 + i*0.7)*0.012*smoothstep(RISE, RISE + HOLD, f.t) : 0);
      },
      shift(i, out) {
        // writhing in the air, and the tremble before it bursts (harder as it swells)
        const w = smoothstep(0.1, 0.5, f.t)*Math.sin(i*0.3 - f.t*7 + ph)*0.09*(1 - 0.5*smoothstep(RISE, RISE + HOLD, f.t));
        const sw = smoothstep(RISE + HOLD, RISE + HOLD + SWELL, f.t);
        const tr = sw*Math.sin(f.t*70 + i*1.3)*0.012*(1 - Math.abs((i - mid)/half));
        out[0] += side.x*(w + tr); out[1] += tr*0.6; out[2] += side.y*(w + tr);
      },
      radk(i) { const sw = smoothstep(RISE + HOLD, RISE + HOLD + SWELL, f.t); return 1 + sw*0.45*(1 - Math.abs((i - mid)/half)); },
      hide: false,
      tick(dt) {
        f.t += dt;
        f.sag = smoothstep(0, RISE, Math.max(0, f.t));
        if (f.t >= RISE + HOLD + SWELL && !f.hide) { gore.burst(s, mid); f.hide = true; }
        if (f.t >= RISE + HOLD + SWELL + 0.05) return 'done';
      },
    };
    return f;
  }

  const lift = (s, delay) => { const f = lift_fx(s, delay); if (snakes.take(s, f)) held.push(f); };

  return {
    name: 'LIFT', gesture: true,
    cooldown: 6.0,
    capacity: p => Math.ceil(p/1.5),
    // where he points: the middle of the body
    aim_ring: () => mid,
    cast(targets) {
      held.length = 0;
      targets.forEach((s, k) => lift(s, k*0.08));
      // the others near them go up too
      let k = targets.length;
      for (const s of snakes.S) {
        if (!snakes.free(s)) continue;
        if (targets.some(q => q.spine[mid].distanceTo(s.spine[mid]) < GROUP_R)) lift(s, 0.08*k++);
      }
    },
    update() { for (let i = held.length - 1; i >= 0; i--) if (held[i].hide) held.splice(i, 1); },
    // while any is still up his hand stays on them, following them as they rise
    busy: () => held.length > 0,
    aim_point() {
      if (!held.length) return null;
      AIM.set(0, 0, 0);
      for (const f of held) AIM.add(f.s.spine[mid]);
      return AIM.multiplyScalar(1/held.length);
    },
    // something about to reach the egg while he holds them: up it goes as well
    extend(more) { for (const s of more) if (snakes.free(s)) lift(s, 0); },
    get held() { return held.length; },
  };
}
