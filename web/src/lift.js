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
// Round 21 (owner, the gore accepted: "the lich's arm should do a little pull, as though he were
// doing a curl, and the snakes pieces and blood should slightly come in his direction"): the
// snakes lifted together burst together, on his pull: the curl starts CURL_LEAD before, the
// swell peaks as his fist closes, and what bursts is thrown partly toward him.
import * as THREE from 'three';
import { smoothstep } from 'game/util.js';

const RISE = 0.8, HOLD = 0.4, SWELL = 0.2, STAGGER = 0.08;
const GROUP_R = 1.8;                  // metres between the middles of snakes lifted together
const CURL_LEAD = 0.08;               // his pull starts this long before they burst
const AFTER = 0.3;                    // and his hand stays in it this long after (the next gesture waits)

export function create_lift(ctx) {
  const { snakes, rng, gore, lich, get_L } = ctx;
  const N = snakes.RINGS, mid = Math.round(N*0.45), half = N*0.55;
  const held = [];                    // the lifts of the last cast, until they burst
  const groups = [];                  // snakes lifted together, and when they burst
  const AIM = new THREE.Vector3(), TOWARD = new THREE.Vector3();

  function lift_fx(s, delay, grp) {
    const H = rng.float(1.5, 2.0), side = new THREE.Vector2();
    // the body's sideways direction (for the writhe): across its head-to-tail line
    const a = s.spine[4], b = s.spine[N - 5];
    side.set(-(a.z - b.z), a.x - b.x).normalize();
    const ph = rng.float(0, 6.28);
    const f = {
      t: -delay, sag: 0, s, grp,
      lift(i) {
        const e = smoothstep(0, RISE, f.t);
        const d = (i - mid)/half;
        return H*e*(1 - 0.5*d*d) + (f.t > RISE ? Math.sin(f.t*31 + i*0.7)*0.012*smoothstep(RISE, RISE + HOLD, f.t) : 0);
      },
      shift(i, out) {
        // writhing in the air, and the tremble before it bursts (harder as it swells)
        const w = smoothstep(0.1, 0.5, f.t)*Math.sin(i*0.3 - f.t*7 + ph)*0.09*(1 - 0.5*smoothstep(RISE, RISE + HOLD, f.t));
        const sw = smoothstep(grp.at - SWELL, grp.at, grp.t);
        const tr = sw*Math.sin(f.t*70 + i*1.3)*0.012*(1 - Math.abs((i - mid)/half));
        out[0] += side.x*(w + tr); out[1] += tr*0.6; out[2] += side.y*(w + tr);
      },
      radk(i) { const sw = smoothstep(grp.at - SWELL, grp.at, grp.t); return 1 + sw*0.45*(1 - Math.abs((i - mid)/half)); },
      hide: false,
      tick(dt) {
        f.t += dt;
        f.sag = smoothstep(0, RISE, Math.max(0, f.t));
        if (grp.t >= grp.at && !f.hide) {
          // thrown partly toward him (his chest)
          const L = get_L();
          TOWARD.set(L.x, L.y + 0.4, L.z);
          gore.burst(s, mid, TOWARD);
          f.hide = true;
        }
        if (f.hide && grp.t >= grp.at + 0.05) return 'done';
      },
    };
    return f;
  }

  // a group: they rise a beat apart, and all burst together once the last is up and held
  const group = (n, arm) => {
    const g = { t: 0, at: RISE + HOLD + SWELL + STAGGER*Math.max(0, n - 1), arm, curled: false, aim: new THREE.Vector3(), aimed: false };
    groups.push(g);
    return g;
  };
  const lift = (s, delay, grp) => { const f = lift_fx(s, delay, grp); if (snakes.take(s, f)) held.push(f); };

  return {
    name: 'LIFT', gesture: true,
    cooldown: 6.0,
    capacity: p => Math.ceil(p/1.5),
    // where he points: the middle of the body
    aim_ring: () => mid,
    cast(targets, from, ring, arm = 1) {
      held.length = 0;
      // the others near them go up too
      const all = [...targets];
      for (const s of snakes.S) {
        if (!snakes.free(s) || all.includes(s)) continue;
        if (targets.some(q => q.spine[mid].distanceTo(s.spine[mid]) < GROUP_R)) all.push(s);
      }
      const g = group(all.length, arm);
      all.forEach((s, k) => lift(s, k*STAGGER, g));
    },
    update(dt = 1/60) {
      for (let i = held.length - 1; i >= 0; i--) if (held[i].hide) held.splice(i, 1);
      for (let i = groups.length - 1; i >= 0; i--) {
        const g = groups[i];
        g.t += dt;
        // his pull: it is what bursts them
        if (!g.curled && g.t >= g.at - CURL_LEAD) { g.curled = true; lich.curl(g.arm); }
        if (g.t > g.at + 0.5) groups.splice(i, 1);
      }
    },
    // while any is still up his hand stays on them, following them as they rise, and through his
    // pull a moment after they burst; one group at a time (the one that bursts next: an extra one
    // lifted while he holds these is far from them, and pointing between the two points at nothing)
    busy: () => held.length > 0 || groups.some(g => g.t < g.at + AFTER),
    aim_point() {
      const g = groups.find(q => q.t < q.at + AFTER);
      if (!g) return g === undefined && held.length ? held[0].s.spine[mid] : AIM;
      const up = held.filter(f => f.grp === g && !f.hide);
      if (up.length) {
        g.aim.set(0, 0, 0);
        for (const f of up) g.aim.add(f.s.spine[mid]);
        g.aim.multiplyScalar(1/up.length); g.aimed = true;
      }
      if (g.aimed) AIM.copy(g.aim);
      return AIM;
    },
    // something about to reach the egg while he holds them: up it goes as well, bursting with its
    // own pull once it is up
    extend(more, arm = 1) {
      // not in the middle of his pull (it waits the 0.3 s out; one ~2.6 m from the egg needs ~1.2 s to reach it)
      if (groups.some(g => g.t >= g.at - CURL_LEAD && g.t < g.at + AFTER)) return;
      const add = more.filter(s => snakes.free(s));
      if (!add.length) return;
      const g = group(add.length, arm);
      add.forEach((s, k) => lift(s, k*STAGGER, g));
    },
    get held() { return held.length; },
    debug: () => ({ held: held.map(f => [f.hide, +f.s.spine[mid].x.toFixed(2), +f.s.spine[mid].y.toFixed(2), +f.s.spine[mid].z.toFixed(2)]), groups: groups.map(g => [+g.t.toFixed(2), +g.at.toFixed(2)]), aim: [AIM.x, AIM.y, AIM.z].map(v => +v.toFixed(2)) }),     // tests
  };
}
