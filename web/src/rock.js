// rock.js -- ROCK (round 23, owner: "let's remove the wind effect and replace it for a rock
// throwing effect. Lifts a rock with telekinesis, throws it so it hits a snake or multiple snakes
// when it makes sense"). Wind (round 11) is gone.
//
// He points; a rock tears out of the floor in front of him (dust, grit, a ripple of warped air
// across the floor) and rises beside his hand, held a moment in a shimmer of warped air
// (warp.js: the same bent light as leakage, his force made visible), trembling; then it goes.
// It flies at the snake, steered onto it as it flies (he guides it), trailing a wake of warped
// air, and crushes it: the body kinked and flattened where it hit, blood bursting out along the
// way the rock was going (gore.crush), the snake twitching as it dies, then sinking into the floor
// like the others. The rock goes on, bouncing and skidding along the floor, and crushes whatever
// else lies in its way; the throw is aimed along the line that takes the most snakes ("when it
// makes sense"). Then it lies there a while and sinks into the ground.
// With fewer powers left one gesture raises several rocks, thrown one after another.
import * as THREE from 'three';
import { ConvexGeometry } from 'three/addons/geometries/ConvexGeometry.js';
import { smoothstep } from 'game/util.js';
import { gi_dynamic } from 'game/gi.js';

// (quick: from his gesture to the hit it has ~1.5 s, the time a snake 4.6 m out takes to reach the egg)
const RIP = 0.25, HOLD = 0.18, STAGGER = 0.12, SPEED = 17, GRAV = 9.8, HIT_R = 0.14;
const REST = 3.0, SINK = 1.2;

export function create_rock(ctx) {
  const { R, snakes, fx, cave, rng, gore, warp, lich, get_L } = ctx;
  const N = snakes.RINGS, mid = Math.round(N*0.4);

  // ---------------------------------------------------------------- the rocks
  const mat = new THREE.MeshLambertMaterial({ map: cave.rock_tex, color: 0xffffff, flatShading: true });
  if (cave.GU) gi_dynamic(mat, cave.GU);
  const make_geo = () => {
    const pts = [];
    const sx = rng.float(0.17, 0.23), sy = rng.float(0.13, 0.17), sz = rng.float(0.15, 0.2);
    for (let i = 0; i < 16; i++) { const v = new THREE.Vector3(rng.spread(2), rng.spread(2), rng.spread(2)); if (v.length() > 1) v.normalize(); pts.push(new THREE.Vector3(v.x*sx, v.y*sy, v.z*sz)); }
    const g = new ConvexGeometry(pts);                // already non-indexed
    g.computeVertexNormals();
    // the cave's rock texture, projected along each face's main axis (2 m to a tile, as the cave)
    const p = g.attributes.position, uv = new Float32Array(p.count*2), n = g.attributes.normal;
    for (let i = 0; i < p.count; i++) {
      const ax = Math.abs(n.getX(i)), ay = Math.abs(n.getY(i)), az = Math.abs(n.getZ(i));
      const [u, v] = ay >= ax && ay >= az ? [p.getX(i), p.getZ(i)] : ax >= az ? [p.getZ(i), p.getY(i)] : [p.getX(i), p.getY(i)];
      uv[i*2] = u/2 + 0.37; uv[i*2 + 1] = v/2 + 0.61;
    }
    g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
    return { g, r: (sx + sy + sz)/3 };
  };
  const POOL = [];
  for (let i = 0; i < 8; i++) {
    const { g, r } = make_geo();
    const m = new THREE.Mesh(g, mat);
    m.castShadow = true; m.receiveShadow = true; m.visible = false; m.frustumCulled = false;
    R.world_scene.add(m);
    POOL.push({ m, r, on: false });
  }
  const live = [];
  const stats = { thrown: 0, hits: 0, multi: 0, missed: 0 };      // tests
  const V = new THREE.Vector3(), V2 = new THREE.Vector3(), Q = new THREE.Quaternion();

  // ---------------------------------------------------------------- crushed
  function crush_fx(s, c, dir) {
    const side = new THREE.Vector3(-dir.z, 0, dir.x), ph = rng.float(0, 6);
    const f = {
      t: 0, sag: 0,
      // flattened where it hit
      radk(i) { return 1 - 0.55*Math.exp(-(((i - c)/3.5)**2)); },
      shift(i, out) {
        // kinked along the way the rock went, then twitching as it dies, then into the floor
        const k = Math.exp(-(((i - c)/6)**2))*0.16*(1 - Math.exp(-f.t*25));
        const tw = Math.exp(-f.t*1.6)*Math.sin(f.t*17 + i*0.22 + ph)*0.045*Math.min(1, Math.abs(i - c)/10);
        out[0] += dir.x*k + side.x*tw; out[2] += dir.z*k + side.z*tw;
        out[1] -= 0.05*Math.exp(-(((i - c)/3)**2));
        if (f.t > 2.0) out[1] -= 0.34*smoothstep(2.0, 3.2, f.t);
      },
      char(i) { return 0.35*Math.exp(-(((i - c)/2.5)**2)); },
      tick(dt) {
        f.t += dt;
        f.sag = smoothstep(0, 0.3, f.t);
        if (f.t > 3.25) return 'done';
      },
    };
    return f;
  }
  // what the rock is going through: a free snake whose body it touches
  function hits(q, cb) {
    const p = q.m.position;
    for (const s of snakes.S) {
      if (!snakes.free(s) || q.hit.includes(s)) continue;
      let best = 1e9, bi = -1;
      for (let j = 2; j < N - 2; j++) { const d = s.spine[j].distanceTo(p); if (d < best) { best = d; bi = j; } }
      if (best < q.r + HIT_R) cb(s, bi);
    }
  }

  // ---------------------------------------------------------------- aiming
  // where a snake's middle will be `dt` from now (it crawls on toward the egg)
  const ahead = (s, dt, out) => {
    const a = s.spine[mid], b = s.spine[Math.min(N - 1, mid + 4)];
    V.subVectors(a, b).setY(0); const l = V.length() || 1;
    return out.copy(a).addScaledVector(V, (s.speed || 1.1)*dt/l);
  };
  // of the lines through a free snake, the one whose ~4 m beyond it crosses the most bodies
  // taken by another rock of his, in the air or about to be
  const claimed = (s, q) => live.some(o => o !== q && o.target === s && (o.phase !== 'rest'));
  // a snake for a rock whose own is gone: the free one nearest the egg that no other rock has
  const another = (q) => {
    let best = null, bd = 1e9;
    for (const s of snakes.S) {
      if (!snakes.free(s) || claimed(s, q)) continue;
      const d = Math.hypot(s.x - snakes.egg.x, s.z - snakes.egg.z);
      if (d < bd && d < 7) { bd = d; best = s; }
    }
    return best;
  };
  function best_line(from, first, q) {
    const cands = [first, ...snakes.S.filter(s => s !== first && snakes.free(s) && !claimed(s, q) && s.spine[mid].distanceTo(first.spine[mid]) < 4)];
    let best = { s: first, n: 0 };
    const P0 = new THREE.Vector3(), D = new THREE.Vector3();
    for (const c of cands) {
      ahead(c, from.distanceTo(c.spine[mid])/SPEED, P0);
      D.subVectors(P0, from).setY(0).normalize();
      let n = 0;
      for (const s of snakes.S) {
        if (!snakes.free(s)) continue;
        for (let j = 4; j < N - 4; j += 5) {
          V.subVectors(s.spine[j], P0).setY(0);
          const along = V.dot(D), across = Math.abs(V.x*D.z - V.z*D.x);
          if (along > -0.6 && along < 4 && across < 0.3) { n++; break; }
        }
      }
      if (n > best.n) best = { s: c, n };
    }
    return best.s;
  }

  // ---------------------------------------------------------------- one rock
  // quick (something about to reach the egg): it tears out and goes almost at once
  function raise(target, k, arm, quick = false) {
    const q = POOL.find(p => !p.on);
    if (!q) return;
    const L = get_L();
    const dir = V.subVectors(target.spine[mid], L).setY(0).normalize().clone();
    const side = new THREE.Vector3(-dir.z, 0, dir.x);
    // out of the floor in front of him, up beside his hand
    const off = (k - 0.5*(k > 0 ? 1 : 0))*0.45*(k % 2 ? 1 : -1);
    const from = L.clone().addScaledVector(dir, 1.15).addScaledVector(side, off*1.2);
    from.y = cave.ground_y(from.x, from.z) - q.r*0.8;
    const hold = L.clone().addScaledVector(dir, 0.85).addScaledVector(side, 0.35*(arm ? 1 : -1) + off);
    hold.y = L.y + 0.35 + k*0.12;
    Object.assign(q, { on: true, phase: 'rip', t: -k*STAGGER*(quick ? 0.4 : 1), rip: quick ? 0.14 : RIP, hold_t: quick ? 0.04 : HOLD, speed: quick ? SPEED*1.45 : SPEED,
      torn: false, hits: 0, from, hold, target, arm, hit: [], v: new THREE.Vector3(), w: new THREE.Vector3(),
      rest: 0, bounced: 0, wake: 0, dir });
    q.m.position.copy(from); q.m.visible = true;
    q.m.quaternion.setFromEuler(new THREE.Euler(rng.float(0, 6), rng.float(0, 6), rng.float(0, 6)));
    live.push(q);
  }
  // it tears out of the floor: dust, grit thrown up, a ripple of warped air across the floor
  function tear(q) {
    const p = q.from, gy = cave.ground_y(p.x, p.z);
    for (let k = 0; k < 16; k++) {
      const a = rng.float(0, 6.28), r = rng.float(0.05, 0.35);
      fx.puff({ x: p.x + Math.cos(a)*r, y: gy + 0.05, z: p.z + Math.sin(a)*r, vx: Math.cos(a)*rng.float(0.5, 1.4), vy: rng.float(0.3, 1.2), vz: Math.sin(a)*rng.float(0.5, 1.4),
        drag: 2.0, life: rng.float(0.8, 1.5), s0: 0.12, s1: 0.45, r: 0.035, g: 0.03, b: 0.022, a: 0.55 });
    }
    for (let k = 0; k < 9; k++) {
      const c = fx.chunk();
      Object.assign(c, { life: rng.float(1.5, 2.5), x: p.x + rng.spread(0.2), y: gy + 0.05, z: p.z + rng.spread(0.2), vx: rng.spread(1.6), vy: rng.float(1.5, 3.2), vz: rng.spread(1.6),
        rx: 0, ry: 0, rz: 0, wx: rng.spread(10), wy: rng.spread(10), wz: rng.spread(10), s: rng.float(0.018, 0.04), sx: 1, sy: rng.float(0.6, 1), sz: 1 });
    }
    for (let k = 0; k < 5; k++) warp.puff({ x: p.x + rng.spread(0.3), y: gy + 0.2, z: p.z + rng.spread(0.3), vy: 0.5, life: 0.7, s0: 0.2, s1: 0.7, amp: 3.5, spin: rng.spread(3) });
  }
  // his force round it while it is held, and the wake behind it as it flies
  const aura = (p, big) => warp.puff({ x: p.x + rng.spread(0.12), y: p.y + rng.spread(0.12), z: p.z + rng.spread(0.12), vx: rng.spread(0.2), vy: rng.spread(0.2), vz: rng.spread(0.2),
    drag: 2, life: rng.float(0.25, 0.45), s0: 0.3*big, s1: 0.55*big, amp: 3.2, spin: rng.spread(4) });

  function update(t, dt) {
    for (let i = live.length - 1; i >= 0; i--) {
      const q = live[i], m = q.m;
      q.t += dt;
      if (q.t < 0) continue;
      if (q.phase === 'rip') {
        if (!q.torn) { q.torn = true; tear(q); }
        // up out of the floor, easing in beside his hand
        const u = smoothstep(0, q.rip, q.t);
        m.position.lerpVectors(q.from, q.hold, u);
        m.position.y += Math.sin(u*Math.PI)*0.25;
        Q.setFromAxisAngle(V.set(0.3, 1, 0.2).normalize(), dt*3); m.quaternion.premultiply(Q);
        if (q.t >= q.rip) { q.phase = 'hold'; q.pt = 0; }
      } else if (q.phase === 'hold') {
        q.pt += dt;
        // held: it trembles in the air, turning slowly, in a shimmer of warped air
        m.position.copy(q.hold).add(V.set(Math.sin(t*37 + i)*0.012, Math.sin(t*43 + i*2)*0.012 + Math.sin(t*3)*0.02, Math.cos(t*31 + i)*0.012));
        Q.setFromAxisAngle(V.set(0.2, 1, 0.4).normalize(), dt*1.5); m.quaternion.premultiply(Q);
        if (rng.next() < 0.7) aura(m.position, 1);
        if (q.pt >= q.hold_t) {
          // thrown: along the line that takes the most, at where its snake will be when it gets there
          if (!q.target || !snakes.free(q.target) || claimed(q.target, q)) q.target = another(q);
          const s = q.target ? best_line(m.position, q.target, q) : null;
          const goal = s ? ahead(s, m.position.distanceTo(s.spine[mid])/q.speed, new THREE.Vector3()) : m.position.clone().addScaledVector(q.dir, 4).setY(0);
          goal.y = cave.ground_y(goal.x, goal.z) + 0.12;
          q.target = s;
          const h = Math.hypot(goal.x - m.position.x, goal.z - m.position.z), T = Math.max(0.12, h/q.speed);
          q.v.set((goal.x - m.position.x)/T, (goal.y - m.position.y)/T + 0.5*GRAV*T, (goal.z - m.position.z)/T);
          q.w.set(rng.spread(1), rng.spread(1), rng.spread(1)).normalize().multiplyScalar(rng.float(8, 14));
          q.phase = 'fly'; q.ft = 0; stats.thrown++;
          lich.kick(q.arm, 0.3);
          for (let k = 0; k < 4; k++) aura(m.position, 1.3);
        }
      } else if (q.phase === 'fly') {
        q.ft += dt;
        // steered onto its snake until it has it (he guides it): turned toward where it is, and
        // its fall reckoned again for the way left, so it arrives at the body rather than the floor
        if (q.target && !q.hit.includes(q.target) && snakes.free(q.target)) {
          ahead(q.target, 0, V2); V2.y = cave.ground_y(V2.x, V2.z) + 0.1;
          const hx = V2.x - m.position.x, hz = V2.z - m.position.z, h = Math.hypot(hx, hz);
          const hs = Math.max(q.speed*0.6, Math.hypot(q.v.x, q.v.z));
          if (h > 0.05) {
            q.v.x = hx/h*hs; q.v.z = hz/h*hs;
            const T = Math.max(0.03, h/hs);
            q.v.y = (V2.y - m.position.y)/T + 0.5*GRAV*T;
          }
        }
        q.v.y -= GRAV*dt;
        m.position.addScaledVector(q.v, dt);
        const wl = q.w.length();
        if (wl > 1e-3) { Q.setFromAxisAngle(V.copy(q.w).multiplyScalar(1/wl), wl*dt); m.quaternion.premultiply(Q); }
        // its wake
        q.wake += dt*40*Math.min(1, q.v.length()/6);
        while (q.wake >= 1) { q.wake -= 1; warp.puff({ x: m.position.x, y: m.position.y, z: m.position.z, vx: -q.v.x*0.05, vy: 0.05, vz: -q.v.z*0.05, drag: 3, life: rng.float(0.25, 0.4), s0: 0.22, s1: 0.5, amp: 3.4, spin: rng.spread(3) }); }
        // what it goes through is crushed; it loses a little each time
        hits(q, (s, j) => {
          const dir = V2.copy(q.v).setY(0).normalize().clone();
          snakes.take(s, crush_fx(s, Math.max(3, j), dir));
          s.claim = null;
          q.hit.push(s);
          gore.crush(s.spine[j], dir, s.radii[j]);
          q.v.multiplyScalar(0.78);
          q.hits = (q.hits || 0) + 1; stats.hits++; if (q.hits === 2) stats.multi++;
        });
        // the floor: it bounces, skids, and comes to rest
        const gy = cave.ground_y(m.position.x, m.position.z) + q.r*0.75;
        if (m.position.y < gy) {
          m.position.y = gy;
          if (q.v.y < 0) {
            for (let k = 0; k < 8; k++) fx.puff({ x: m.position.x + rng.spread(0.15), y: gy - q.r*0.5, z: m.position.z + rng.spread(0.15), vx: rng.spread(0.8) + q.v.x*0.1, vy: rng.float(0.2, 0.7), vz: rng.spread(0.8) + q.v.z*0.1,
              drag: 2.2, life: rng.float(0.7, 1.2), s0: 0.1, s1: 0.35, r: 0.035, g: 0.03, b: 0.022, a: 0.45 });
            q.v.y = Math.abs(q.v.y) > 1.5 ? -q.v.y*0.32 : 0;
            q.v.x *= 0.72; q.v.z *= 0.72; q.w.multiplyScalar(0.6);
            q.bounced++;
          }
          // skidding along the floor
          const d = 1 - Math.min(1, 2.2*dt); q.v.x *= d; q.v.z *= d;
        }
        if (q.bounced && Math.hypot(q.v.x, q.v.z) < 0.6 && Math.abs(q.v.y) < 0.3) { q.phase = 'rest'; q.rest = 0; if (!q.hits) stats.missed++; }
      } else if (q.phase === 'rest') {
        q.rest += dt;
        if (q.rest > REST) m.position.y -= (q.r*2.4/SINK)*dt;
        if (q.rest > REST + SINK) { q.on = false; m.visible = false; live.splice(i, 1); }
      }
    }
  }

  return {
    name: 'ROCK', gesture: true,
    cooldown: 5.0,
    engage: 5.6,                      // it needs the time to rise and fly: it takes them further out
    capacity: p => Math.ceil(p/1.5),
    // where he points: the middle of the body
    aim_ring: () => mid,
    cast(targets, from, ring, arm = 1, quick = false) { targets.forEach((s, k) => raise(s, k, arm, quick)); },
    update,
    // something about to reach the egg while he holds a rock: another tears out for it at once
    extend(more, arm = 1) { more.filter(s => snakes.free(s) && !claimed(s, null)).slice(0, 2).forEach((s, k) => raise(s, k, arm, true)); },
    // his hand stays up until the last of this gesture's rocks has gone
    busy: () => live.some(q => q.phase === 'rip' || q.phase === 'hold' || q.t < 0),
    aim_point: () => { const q = live.find(q => q.phase === 'hold' || q.phase === 'rip'); return q && q.target && snakes.free(q.target) ? q.target.spine[mid] : null; },
    stats,
    // tests
    debug: () => live.map(q => [q.phase, q.hits || 0, +q.m.position.x.toFixed(2), +q.m.position.y.toFixed(2), +q.m.position.z.toFixed(2),
      q.target ? [+q.target.spine[mid].x.toFixed(2), +q.target.spine[mid].z.toFixed(2)] : null]),
  };
}
