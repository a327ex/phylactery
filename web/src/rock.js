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
// Round 24 (owner: "The hand should follow the rock, the rock's movement should be more natural,
// not so flat, like floating a bit, not stopping so abruptly, not starting so abruptly, imagine it
// is being controlled by someone's mind who isn't precise like a computer"): nothing moves it by
// script any more; his mind has it: a soft spring pulls it toward where he means it to be (so it
// overshoots and settles, and floats while held), the push always easing in, never steady (slow
// wandering forces), a little drawn back before the throw; thrown, it is urged along a floating
// arc toward the snake, gathering speed rather than leaving at full speed, wandering a little off
// the line and corrected; it is his until it strikes, and his hand follows it all the way.
import * as THREE from 'three';
import { ConvexGeometry } from 'three/addons/geometries/ConvexGeometry.js';
import { smoothstep } from 'game/util.js';
import { gi_dynamic } from 'game/gi.js';

// (quick: from his gesture to the hit it has ~2 s, the time a snake 5.6 m out takes to reach the egg)
const HOLD = 0.25, STAGGER = 0.12, SPEED = 17, ACCEL = 55, GRAV = 9.8, HIT_R = 0.14;
const CONTROL_MAX = 1.4;              // s of flight before he lets go of one that has hit nothing
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
  const V = new THREE.Vector3(), V2 = new THREE.Vector3(), Q = new THREE.Quaternion(), A = new THREE.Vector3(), TG = new THREE.Vector3();

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
    Object.assign(q, { on: true, phase: 'rip', t: -k*STAGGER*(quick ? 0.4 : 1), quick, hold_t: quick ? 0.05 : HOLD, speed: quick ? SPEED*1.45 : SPEED,
      accel: quick ? ACCEL*2.2 : ACCEL, ramp: 0, ph: [rng.float(0, 6.28), rng.float(0, 6.28), rng.float(0, 6.28), rng.float(0, 6.28)], ctrl: true,
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
      // its snake has come close to the egg while it rises or is held: it hurries (emergency timing)
      if (!q.quick && q.target && (q.phase === 'rip' || q.phase === 'hold' || q.phase === 'fly') && Math.hypot(q.target.x - snakes.egg.x, q.target.z - snakes.egg.z) < 2.9) {
        q.quick = true; q.hold_t = Math.min(q.hold_t, 0.05); q.speed = SPEED*1.45; q.accel = ACCEL*2.2;
      }
      // the slow forces of an imprecise mind: never quite steady, never the same twice
      const wander = (amp, out) => out.set(
        (Math.sin(t*2.1 + q.ph[0])*0.6 + Math.sin(t*4.7 + q.ph[1])*0.4)*amp,
        (Math.sin(t*1.7 + q.ph[2])*0.6 + Math.sin(t*3.9 + q.ph[3])*0.4)*amp*0.6,
        (Math.sin(t*2.6 + q.ph[1])*0.6 + Math.sin(t*5.3 + q.ph[2])*0.4)*amp);
      // his hand on it, held: a spring toward where he means it to be (f Hz, damping z), its push
      // capped at amax and easing in over 0.15 s whenever what he wants of it changes
      const hold_on = (T, f, z, amax, wob) => {
        const w = 6.2832*f;
        q.ramp = Math.min(1, q.ramp + dt/0.15);
        A.subVectors(T, m.position).multiplyScalar(w*w).addScaledVector(q.v, -2*z*w);
        A.add(wander(wob, V));
        const l = A.length(), cap = amax*q.ramp;
        if (l > cap) A.multiplyScalar(cap/l);
        q.v.addScaledVector(A, dt);
        m.position.addScaledVector(q.v, dt);
      };
      // a slow tumble that it gathers and loses
      const spin = (to, rate) => { q.w.multiplyScalar(1 - Math.min(1, rate*dt)); if (q.w.length() < to) q.w.addScaledVector(V.set(q.ph[0] - 3, q.ph[1] - 3, q.ph[2] - 3).normalize(), to*rate*dt); };
      if (q.phase === 'rip') {
        if (!q.torn) { q.torn = true; tear(q); q.v.set(q.dir.x*0.6, q.quick ? 5 : 3.4, q.dir.z*0.6); q.ramp = 0.3; }
        // it breaks out of the floor and is drawn up beside his hand, over-rising a little and settling
        hold_on(q.hold, q.quick ? 2.4 : 1.5, 0.5, q.quick ? 90 : 40, 2.5);
        spin(2, 3);
        if (rng.next() < 0.5) aura(m.position, 0.9);
        const near = m.position.distanceTo(q.hold) < 0.2 && q.v.length() < 1.2;
        if ((q.t > (q.quick ? 0.12 : 0.3) && near) || q.t > (q.quick ? 0.25 : 0.6)) { q.phase = 'hold'; q.pt = 0; q.ramp = 0.5; }
      } else if (q.phase === 'hold') {
        q.pt += dt;
        // held: floating, bobbing, drifting on his attention; just before it goes it is drawn back
        // a little toward him (the throw gathered)
        const back = smoothstep(q.hold_t - 0.14, q.hold_t, q.pt);
        TG.copy(q.hold).addScaledVector(q.dir, -0.18*back);
        TG.y += 0.05*back + Math.sin(t*2.2 + q.ph[0])*0.03;
        hold_on(TG, 1.3, 0.42, 25, 2.0);
        spin(0.8, 2);
        if (rng.next() < 0.7) aura(m.position, 1);
        if (q.pt >= q.hold_t) {
          // thrown: along the line that takes the most, toward where its snake will be
          if (!q.target || !snakes.free(q.target) || claimed(q.target, q)) q.target = another(q);
          q.target = q.target ? best_line(m.position, q.target, q) : null;
          q.phase = 'fly'; q.ft = 0; q.ramp = 0.35; q.s_cmd = q.v.length(); q.l0 = m.position.clone();
          q.h0 = q.target ? Math.max(1, Math.hypot(q.target.spine[mid].x - m.position.x, q.target.spine[mid].z - m.position.z)) : 4;
          stats.thrown++;
          lich.kick(q.arm, 0.2);
          for (let k = 0; k < 4; k++) aura(m.position, 1.3);
        }
      } else if (q.phase === 'fly') {
        q.ft += dt;
        if (q.ctrl && q.target && (!snakes.free(q.target) || q.hit.includes(q.target))) {
          // its snake gone before it got there: another, or he lets it go
          const o = q.hit.length ? null : another(q);
          if (o) q.target = o; else q.ctrl = false;
        }
        if (q.ctrl && q.target && q.ft < CONTROL_MAX) {
          // urged at its snake along a floating arc: it gathers speed (never leaves at full
          // speed), wanders a little off the line and is corrected, and dives onto the body
          ahead(q.target, 0, TG); TG.y = cave.ground_y(TG.x, TG.z) + 0.1;
          const hx = TG.x - m.position.x, hz = TG.z - m.position.z, h = Math.max(1e-3, Math.hypot(hx, hz));
          q.s_cmd = Math.min(q.speed, q.s_cmd + q.accel*dt);
          const u = Math.min(1, 1 - h/q.h0), arc = Math.min(0.6, 0.1*q.h0)*(q.quick ? 0.5 : 1);
          const look = Math.min(1, u + q.s_cmd*0.12/q.h0);
          const y_next = m.position.y + (TG.y - m.position.y)*Math.min(1, q.s_cmd*0.12/h) + arc*4*(look*(1 - look) - u*(1 - u));
          V2.set(hx/h*q.s_cmd, (y_next - m.position.y)/0.12, hz/h*q.s_cmd);
          q.ramp = Math.min(1, q.ramp + dt/0.15);
          A.subVectors(V2, q.v).multiplyScalar(12);
          // imprecise: a slow sideways and up-and-down wander that the correction keeps catching
          const side = V.set(-hz/h, 0, hx/h).multiplyScalar((Math.sin(t*3.1 + q.ph[0])*0.7 + Math.sin(t*6.3 + q.ph[3])*0.3)*7);
          A.add(side); A.y += Math.sin(t*2.7 + q.ph[2])*3;
          const l = A.length(), cap = q.accel*1.4*q.ramp;
          if (l > cap) A.multiplyScalar(cap/l);
          q.v.addScaledVector(A, dt);
          m.position.addScaledVector(q.v, dt);
        } else {
          // his, no longer: it flies on as a thrown thing does
          q.ctrl = false;
          q.v.y -= GRAV*dt;
          m.position.addScaledVector(q.v, dt);
        }
        spin(q.ctrl ? 9 : 5, 2.5);
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
          q.ctrl = false;
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
      }
      if (q.phase === 'rip' || q.phase === 'hold') {
        const wl = q.w.length();
        if (wl > 1e-3) { Q.setFromAxisAngle(V.copy(q.w).multiplyScalar(1/wl), wl*dt); m.quaternion.premultiply(Q); }
      }
      if (q.phase === 'rest') {
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
    // his hand is on it (round 24: it follows the rock) until the last he holds has struck or gone
    busy: () => live.some(q => q.t < 0 || q.phase === 'rip' || q.phase === 'hold' || (q.phase === 'fly' && q.ctrl)),
    aim_point: () => { const q = live.find(q => q.t >= 0 && (q.phase === 'rip' || q.phase === 'hold' || (q.phase === 'fly' && q.ctrl))); return q ? q.m.position : null; },
    stats,
    // tests
    debug: () => live.map(q => [q.phase, q.hits || 0, +q.m.position.x.toFixed(2), +q.m.position.y.toFixed(2), +q.m.position.z.toFixed(2),
      q.target ? [+q.target.spine[mid].x.toFixed(2), +q.target.spine[mid].z.toFixed(2)] : null]),
  };
}
