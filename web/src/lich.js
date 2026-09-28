// lich.js -- the lich: a realistic human skeleton (skeleton.js), all bones, no robe, floating;
// prismatic gem bone (gem.js, STRONG by default: owner, round 2), lit only by the scene.
//
// The rig is a tree of joints (pelvis -> spine -> chest -> neck -> head -> jaw; chest ->
// shoulder -> elbow -> wrist -> fingers; pelvis -> hip -> knee -> ankle). The resting float
// follows Astra's lich 07 (owner, round 2: "the more correct shape"): the body leaning a little
// forward, the legs held together and swept back on one diagonal, knees nearly touching, shins
// angled back a little more than the thighs, feet pointed down, one leg a little behind the
// other; one hand hanging curled before the pelvis, the other reaching forward and down.
// Round 5: that pose is only where the parts rest; each one floats on a spring around it (pose()).
import * as THREE from 'three';
import { gi_dynamic } from 'game/gi.js';
import { gem_material, GEM_LEVELS } from 'game/gem.js';
import { build_skeleton_geometry, RIG, FINGERS } from 'game/skeleton.js';

export function create_lich(R, opts = {}) {
  const mat = gem_material({ flat: false, roughness: 0.44, color: 0xefe6d2 });
  if (opts.GU) gi_dynamic(mat, opts.GU);
  const GU = mat.userData.gemU;
  const t0 = performance.now();
  const GEO = build_skeleton_geometry(opts.res || 1.45);
  const build_ms = performance.now() - t0;
  let tris = 0;

  const root = new THREE.Group();            // world placement (position + yaw), set by the caller
  const body = new THREE.Group();            // bob and lean
  root.add(body);
  const node = (parent, p = [0, 0, 0], s = 1) => { const g = new THREE.Group(); g.position.set(p[0]*s, p[1], p[2]); parent.add(g); return g; };
  const skin = (n, key) => {
    const g = GEO[key];
    if (!g) return;
    const m = new THREE.Mesh(g, mat);
    m.castShadow = true; m.receiveShadow = true;
    n.add(m);
    tris += (g.index ? g.index.count : g.attributes.position.count)/3;
  };

  const pelvis = node(body); skin(pelvis, 'pelvis');
  const spine = node(pelvis, RIG.spine); skin(spine, 'spine');
  const chest = node(spine, RIG.chest); skin(chest, 'chest');
  const neck = node(chest, RIG.neck); skin(neck, 'neck');
  const head = node(neck, RIG.head); skin(head, 'head');
  const jaw = node(head, RIG.jaw); skin(jaw, 'jaw');
  const arms = [], legs = [];
  for (const s of [-1, 1]) {
    const S = s > 0 ? 'L' : 'R';
    const sh = node(chest, RIG.shoulder, s); skin(sh, 'upper' + S);
    const el = node(sh, RIG.elbow); skin(el, 'fore' + S);
    const wr = node(el, RIG.wrist); skin(wr, 'hand' + S);
    const fingers = FINGERS.map((f, i) => {
      const segs = [];
      let parent = node(wr, [0, -0.028 - f.meta, f.z]);
      f.ph.forEach((L, j) => {
        skin(parent, `finger${S}${i}_${j}`);
        segs.push(parent);
        parent = node(parent, [0, -L, 0]);
      });
      return segs;
    });
    const thumb = [];
    let tp = node(wr, [s*0.012, -0.055, 0.046]);
    [0.034, 0.026].forEach((L, j) => {
      skin(tp, `thumb${S}_${j}`);
      thumb.push(tp);
      tp = node(tp, [0, -L, 0]);
    });
    arms.push({ s, sh, el, wr, fingers, thumb });
    const hip = node(pelvis, RIG.hip, s); skin(hip, 'thigh' + S);
    const kn = node(hip, RIG.knee, s); skin(kn, 'knee' + S); skin(kn, 'shin' + S);
    const an = node(kn, RIG.ankle); skin(an, 'foot' + S);
    legs.push({ s, hip, kn, an });
  }

  R.world_scene.add(root);
  // round 5: steered into the dark he vanished (he was lit only by the scene). GLOWS: his bones
  // shine on their own, faintly or clearly; NONE is round 4. The point light stays at zero.
  const light = new THREE.PointLight(0xffffff, 0, 0.1, 2);   // kept at zero: the lich lights nothing around him

  const GLOWS = [
    { name: 'FAINT', glow: 0.045 },
    { name: 'CLEAR', glow: 0.1 },
    { name: 'NONE (ROUND 4)', glow: 0 },
  ];
  let glow = 0;
  const set_glow = (i) => { glow = ((i % GLOWS.length) + GLOWS.length) % GLOWS.length; GU.uGlow.value = GLOWS[glow].glow; };
  set_glow(0);
  const MODES = GEM_LEVELS.map(l => 'GEM, ' + l.name);
  let mode = 0;                               // round 4: SOLID (STRONG was right for the look; the owner asked for more solid)
  mat.userData.set_level(GEM_LEVELS[mode]);

  // ---------------------------------------------------------------- the float (round 5)
  // Every part is a floating object held to the 07 pose by a soft spring and pushed around by
  // the body's motion: m.a = the pelvis' acceleration in the body frame (x = his left, y = up,
  // z = forward), m.v its velocity, m.yaw_a / m.yaw_v the turn, m.look where he wants to go
  // relative to where he faces. Hanging parts (legs, arms, jaw) lag like pendulums (a push
  // forward swings them back, a stop swings them forward past rest and they settle); upright
  // parts (chest, head) lag the other way; the body itself leans into its push and banks into
  // turns; the hips twist behind the chest when he turns; the head looks where he is going
  // first. The two legs are one pair: each has its own spring, but their difference is kept
  // small, so they stay together and only part a little in a sudden change.
  const JUICE = [
    { name: 'FLOATY', gain: 1.0, freq: 1.0, damp: 1.0 },
    { name: 'LOOSE', gain: 1.6, freq: 0.8, damp: 0.72 },
    { name: 'LIGHT', gain: 0.55, freq: 1.25, damp: 1.4 },
    { name: 'OFF: ROUND 4, RIGID', gain: 0, freq: 1.0, damp: 1.0 },
  ];
  let juice = 0;
  const SP = () => ({ x: 0, v: 0, a: 0 });
  const S = {
    bp: SP(), br: SP(), py: SP(), cp: SP(), cr: SP(), hp: SP(), hr: SP(), hy: SP(), jw: SP(),
    legs: [0, 1].map(() => ({ p: SP(), r: SP(), k: SP(), an: SP() })),
    arms: [0, 1].map(() => ({ p: SP(), r: SP(), e: SP(), w: SP(), f: SP() })),
  };
  let fq = 1, dz = 1;
  // one step of a damped spring toward `target` (radians), `f` Hz, damping ratio `z`, plus a
  // force (rad/s^2); keeps its acceleration for the parts hanging below it
  const spring = (s, target, f, z, force, dt) => {
    const w = 6.2832*f*fq, zz = Math.min(1.2, z*dz);
    s.a = w*w*(target - s.x) - 2*zz*w*s.v + force;
    s.v += s.a*dt; s.x += s.v*dt;
  };
  // air: slow, never-repeating pushes (a force that deflects a spring by about `amp` radians)
  const air = (t, k, f, amp) => { const w = 6.2832*f*fq; return w*w*amp*(Math.sin(t*0.71 + k*1.37)*0.55 + Math.sin(t*1.29 + k*2.71)*0.3 + Math.sin(t*2.17 + k*0.53)*0.15); };
  const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
  const NO_MOTION = { a: [0, 0, 0], v: [0, 0, 0], yaw_a: 0, yaw_v: 0, look: 0 };

  const lich = {
    root, body, mat, light, MODES, build_ms, tris, nodes: { pelvis, spine, chest, neck, head, jaw, arms, legs },
    JUICE, springs: S, GLOWS,
    get glow() { return glow; },
    set glow(i) { set_glow(i); },
    get mode() { return mode; },
    set mode(m) { mode = ((m % MODES.length) + MODES.length) % MODES.length; mat.userData.set_level(GEM_LEVELS[mode]); },
    get juice() { return juice; },
    set juice(j) { juice = ((j % JUICE.length) + JUICE.length) % JUICE.length; },
    hover_h: 1.28,          // pelvis height above the ground; the pointed toes hang ~0.3 m above it
    pose(t, dt = 1/60, m = NO_MOTION) {
      const J = JUICE[juice], g = J.gain;
      fq = J.freq; dz = J.damp;
      const [ax, ay, az] = m.a, [vx, , vz] = m.v;
      const ya = m.yaw_a, still = 1 - clamp(Math.hypot(vx, vz)/0.6, 0, 1);

      // body: leans into its push and a little into its speed, banks into turns
      spring(S.bp, clamp((0.03*vz + 0.02*az)*g, -0.2, 0.24), 1.0, 0.75, air(t, 1, 1.0, 0.012*g), dt);
      spring(S.br, clamp(-0.035*ax*g, -0.24, 0.24), 1.0, 0.75, air(t, 2, 1.0, 0.012*g), dt);
      // hips twist behind the chest when he starts a turn
      spring(S.py, 0, 1.1, 0.45, -ya*0.05*g, dt);
      // chest: an upright mass on the spine, it lags the push
      spring(S.cp, 0, 1.4, 0.42, -az*0.9*g + air(t, 3, 1.4, 0.015*g), dt);
      spring(S.cr, 0, 1.4, 0.42, ax*0.9*g + air(t, 4, 1.4, 0.012*g), dt);
      // head: lags too, keeps its gaze level against the lean, looks where he is going first
      const idle_glance = Math.sin(t*0.33)*0.1*still;
      spring(S.hp, clamp(-(S.bp.x + S.cp.x)*0.45, -0.2, 0.2), 1.7, 0.5, -az*0.7*g + air(t, 5, 1.7, 0.02*g), dt);
      spring(S.hr, clamp(-(S.br.x + S.cr.x)*0.4, -0.2, 0.2), 1.7, 0.5, ax*0.7*g + air(t, 6, 1.7, 0.015*g), dt);
      spring(S.hy, clamp(m.look*0.8, -0.75, 0.75)*g + idle_glance, 1.4, 0.8, -ya*0.02*g, dt);
      // jaw: a hinged weight under the skull; a push up or forward drops it, a stop clacks it shut
      spring(S.jw, 0, 2.3, 0.22, (ay*8 + az*3.5)*g + air(t, 7, 2.3, 0.015*g), dt);
      const JAW0 = 0.07 + Math.max(0, Math.sin(t*0.45))*0.04;
      if (JAW0 + S.jw.x < 0.0) { S.jw.x = -JAW0; if (S.jw.v < 0) S.jw.v = -S.jw.v*0.3; }
      if (JAW0 + S.jw.x > 0.42) { S.jw.x = 0.42 - JAW0; if (S.jw.v > 0) S.jw.v = 0; }

      // legs: a pendulum pair hanging from the hips. + pitch = feet back, + roll = feet to his left.
      // A push forward swings them back, speed trails them back, a stop swings them under him;
      // a push sideways or the start of a turn swings the trailing feet out.
      S.legs.forEach((L, k) => {
        const df = k ? 1.06 : 0.95, dd = k ? 0.92 : 1.08;          // the two differ a little
        spring(L.p, clamp(0.045*vz*g, -0.1, 0.18), 0.8*df, 0.3*dd, (az*0.75 - ay*0.4)*g + air(t, 10 + k*0.35, 0.8, 0.035*g), dt);
        spring(L.r, clamp(-0.04*vx*g, -0.16, 0.16), 0.75*df, 0.3*dd, (-ax*0.8 + ya*0.08)*g + air(t, 12 + k*0.35, 0.75, 0.025*g), dt);
        // the shin hangs from the knee: it lags the thigh's swing (the whip) and the push
        spring(L.k, 0, 1.25*df, 0.32, (az*0.7 - L.p.a*0.4)*g + air(t, 14 + k, 1.25, 0.02*g), dt);
        // the foot from the ankle, a smaller whip again
        spring(L.an, 0, 1.9*df, 0.3, (az*0.4 - L.k.a*0.3)*g, dt);
      });
      // together: each leg keeps only a part of its difference from the pair's mean
      const SPREAD = 0.4;
      const lp = (S.legs[0].p.x + S.legs[1].p.x)/2, lr = (S.legs[0].r.x + S.legs[1].r.x)/2, lk = (S.legs[0].k.x + S.legs[1].k.x)/2;
      for (const l of legs) {
        const L = S.legs[l.s > 0 ? 1 : 0];
        const p = lp + (L.p.x - lp)*SPREAD, r = lr + (L.r.x - lr)*SPREAD, k = lk + (L.k.x - lk)*SPREAD;
        const stagger = l.s > 0 ? 0.07 : 0;
        l.hip.rotation.set(clamp(0.1 + stagger + p, -0.35, 0.9), 0, -0.02*l.s + clamp(r, -0.4, 0.4));   // thighs ~12-16 deg back at rest
        l.kn.rotation.set(clamp(0.2 + stagger*0.5 + k, 0.03, 0.9), 0, 0.015*l.s);                       // shins a little further back; knees never bend forward
        l.an.rotation.set(clamp(1.0 + L.an.x, 0.6, 1.4), 0, 0);                                           // toes pointed down
      }

      // arms: pendulums from the shoulders, each on its own (a little out of step with the other).
      // + pitch = hand back, + roll = hand to his left; the elbow, wrist and fingers whip after.
      arms.forEach((A, k) => {
        const Q = S.arms[k], s = A.s;
        const rest_p = s < 0 ? -0.12 : -0.72;
        const df = k ? 1.07 : 0.93;
        spring(Q.p, clamp(0.07*vz*g, -0.16, 0.32), 0.9*df, 0.28, (az*1.0 + ay*Math.sin(-rest_p)*1.2)*g + air(t, 20 + k*3, 0.9, 0.045*g), dt);
        spring(Q.r, clamp(-0.05*vx*g, -0.2, 0.2), 0.95*df, 0.3, -ax*1.0*g + air(t, 21 + k*3, 0.95, 0.03*g), dt);
        spring(Q.e, 0, 1.5*df, 0.3, (az*0.8 - Q.p.a*0.4)*g + air(t, 22 + k*3, 1.5, 0.03*g), dt);
        spring(Q.w, 0, 2.1*df, 0.3, (az*0.5 - Q.e.a*0.3)*g + air(t, 23 + k*3, 2.1, 0.03*g), dt);
        spring(Q.f, 0, 2.6*df, 0.3, (az*0.6 - Q.w.a*0.2)*g + air(t, 24 + k*3, 2.6, 0.04*g), dt);
        const roll = s*Math.max(-0.08, s*Q.r.x);                      // never swings in through the ribs
        if (s < 0) {
          // hanging, bent at the elbow, the hand curled before the pelvis
          A.sh.rotation.set(rest_p + Q.p.x, 0, 0.12*s + roll);
          A.el.rotation.set(Math.min(-0.2, -1.25 + Q.e.x), 0, 0);
          A.wr.rotation.set(-0.25 + Q.w.x, -s*0.9, 0);
        } else {
          // reaching forward and down, toward the light
          A.sh.rotation.set(rest_p + Q.p.x, 0, 0.22*s + roll);
          A.el.rotation.set(Math.min(-0.05, -0.42 + Q.e.x), 0, 0);
          A.wr.rotation.set(-0.35 + Q.w.x, -s*1.25, 0);
        }
        const curl = (s < 0 ? 0.55 : 0.32) + clamp(Q.f.x, -0.3, 0.4);
        A.fingers.forEach((segs, i) => segs.forEach((n, j) => n.rotation.set(0, 0, -s*(curl + j*0.12 + i*0.03 + Math.sin(t*1.3 + i)*0.03))));
        A.thumb[0].rotation.set(0.5, 0, -s*0.35);
        A.thumb[1].rotation.set(0, 0, -s*0.3);
      });

      body.position.y = 0;
      body.rotation.set(0.1 + S.bp.x, 0, S.br.x);
      pelvis.rotation.set(0, S.py.x, 0);
      spine.rotation.set(0.04 + S.cp.x*0.5, -S.py.x*0.75, S.cr.x*0.5);
      chest.rotation.set(0.03 + S.cp.x*0.5, 0, S.cr.x*0.5);
      neck.rotation.set(0.04 + S.hp.x*0.3, S.hy.x*0.3, 0);
      head.rotation.set(-0.02 + S.hp.x*0.7, S.hy.x*0.7, S.hr.x);                  // ~15 deg down in all, as in 07
      jaw.rotation.x = JAW0 + S.jw.x;
    },
    update(t) {
      GU.uGemTime.value = t;
    },
  };
  return lich;
}
