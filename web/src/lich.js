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
import { gem_material, GEM_LEVELS, PATTERNS } from 'game/gem.js';
import { build_skeleton_geometry, RIG, FINGERS } from 'game/skeleton.js';

export function create_lich(R, opts = {}) {
  const mat = gem_material({ flat: false, roughness: 0.44, color: 0xecdab2 });   // round 8: warmer ivory (owner: "more yellow, less grey")
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
    // a number per bone for the gem's PER BONE pattern
    if (!g.attributes.aBone) { let h = 0; for (const c of key) h = (h*31 + c.charCodeAt(0)) % 9973; g.setAttribute('aBone', new THREE.Float32BufferAttribute(new Float32Array(g.attributes.position.count).fill(h), 1)); }
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
      segs.tip = parent;                         // the fingertip (a beam leaves from here)
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

  // round 8 (owner: out of the light "less bright, following the surrounding's light level"):
  // the bone keeps the light it gets (lifted or dimmed in proportion to it), plus a faint warm
  // floor; bone is pale, so even unlifted it reads ~4x brighter than the dark rock beside it
  const GLOWS = [
    { name: 'FOLLOWS THE LIGHT', lift: 0, glow: 0.0015 },
    { name: 'A LITTLE BRIGHTER', lift: 0.7, glow: 0.004 },
    { name: 'DIMMER', lift: -0.35, glow: 0 },
  ];
  let glow = 0;
  const set_glow = (i) => { glow = ((i % GLOWS.length) + GLOWS.length) % GLOWS.length; GU.uGlow.value = GLOWS[glow].glow; GU.uLift.value = GLOWS[glow].lift || 0; };
  set_glow(0);
  const MODES = GEM_LEVELS.map(l => 'GEM, ' + l.name);
  let mode = 2;                               // round 8 (owner): SUBTLE, with the SOFT pattern
  mat.userData.set_level(GEM_LEVELS[mode]);

  // ---------------------------------------------------------------- the float (rounds 5-6)
  // Every part is a floating object on a soft spring, pushed around by the body's motion: m.a =
  // the pelvis' acceleration in the body frame (x = his left, y = up, z = forward), m.v its
  // velocity, m.push = where he is sent minus how he moves (big when a move starts or turns,
  // gone once he is under way), m.yaw_a the turn, m.look where he is sent relative to his facing.
  // Round 6 (owner: "arms and legs need to actually move and be independent"; arms "very light
  // and go with the flow, mostly staying down and behind as he moves, but also moving around
  // lightly"; legs "prefer the relative position they have to each other now" with "a bit more
  // freedom"; head and torso "lean towards movement direction first and then the rest of the
  // body follows"):
  // - the head leads, then the chest: both lean and turn toward the push; then the whole body
  //   leans into its speed, the hips turn, the legs trail;
  // - arms are slow, soft pendulums: moving, they settle down and behind with the hands
  //   trailing; the torso swinging above them swings them; each drifts on its own when still;
  // - each leg has its own springs (thigh, knee, ankle, twist) and its own drift, plus a pull
  //   toward the other leg, so the pair keeps its shape but never moves as one rigid piece.
  const JUICE = [
    { name: 'FLOATY', gain: 1.0, freq: 1.0, damp: 1.0 },
    { name: 'LOOSE', gain: 1.6, freq: 0.8, damp: 0.72 },
    { name: 'LIGHT', gain: 0.55, freq: 1.25, damp: 1.4 },
    { name: 'OFF: ROUND 4, RIGID', gain: 0, freq: 1.0, damp: 1.0 },
  ];
  let juice = 0;
  // arms in rig order (s = -1 hanging, s = +1 reaching): where each rests, and where both go moving
  const ARM_REST = [{ p: -0.12, e: -1.25, w: -0.25, curl: 0.55 }, { p: -0.72, e: -0.42, w: -0.35, curl: 0.32 }];
  const ARM_TRAIL = { p: 0.36, e: -0.3, w: 0.3, curl: 0.2 };
  let trail = 0;                              // how far into the trailing pose the arms are: eases in, drifts out
  const SP = (x = 0) => ({ x, v: 0, a: 0 });
  const S = {
    bp: SP(), br: SP(), py: SP(), cp: SP(), cr: SP(), cy: SP(), hp: SP(), hr: SP(), hy: SP(), jw: SP(),
    legs: [0, 1].map(() => ({ p: SP(), r: SP(), k: SP(), an: SP(), tw: SP() })),
    arms: ARM_REST.map(r => ({ p: SP(r.p), r: SP(), t: SP(), e: SP(r.e), w: SP(r.w), f: SP() })),
  };
  // recoil (round 18, owner: when the beam fires "the lich's hand + arm should have some force
  // thrown back on them so it looks realistic"): its own springs per arm, added on top of the
  // pose. A kick (lich.kick) throws the shoulder up, the elbow into a bend and the finger up, and
  // jolts the casting shoulder and the head back; while the beam pushes (lich.press) the arm is
  // held a little up and bent against it and the hand trembles; when it lets go the arm springs
  // back. The wrist's share is applied after the finger is aimed, so the aim doesn't cancel it.
  const RC = [0, 1].map(() => ({ p: SP(), e: SP(), w: SP(), kick: 0, press: 0 }));
  // X: how hard (MEDIUM: the hand thrown ~15 cm up at firing, the finger ~20 deg)
  const RECOILS = [{ name: 'MEDIUM', gain: 1 }, { name: 'HEAVY', gain: 1.7 }, { name: 'LIGHT', gain: 0.5 }, { name: 'OFF', gain: 0 }];
  let recoil = 0;
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
  const mix = (a, b, t) => a + (b - a)*t;
  const INV = new THREE.Matrix4(), TV = new THREE.Vector3(), TIP = new THREE.Vector3();
  const AQ = { e: new THREE.Quaternion(), c: new THREE.Quaternion(), r: new THREE.Quaternion(), i: new THREE.Quaternion(), t: new THREE.Quaternion() };
  const AV = { b: new THREE.Vector3(), t: new THREE.Vector3(), f: new THREE.Vector3(), d: new THREE.Vector3(), ax: new THREE.Vector3(), up: new THREE.Vector3(0, 1, 0) };
  const NO_MOTION = { a: [0, 0, 0], v: [0, 0, 0], push: [0, 0], yaw_a: 0, yaw_v: 0, look: 0, gaze: 0, gaze_p: 0, gaze_w: 0 };

  const lich = {
    root, body, mat, light, MODES, build_ms, tris, nodes: { pelvis, spine, chest, neck, head, jaw, arms, legs },
    JUICE, springs: S, GLOWS, PATTERNS, recoil: RC,
    get pattern() { return GU.uPattern.value; },
    set pattern(i) { GU.uPattern.value = ((i % PATTERNS.length) + PATTERNS.length) % PATTERNS.length; },
    get glow() { return glow; },
    set glow(i) { set_glow(i); },
    get mode() { return mode; },
    set mode(m) { mode = ((m % MODES.length) + MODES.length) % MODES.length; mat.userData.set_level(GEM_LEVELS[mode]); },
    get juice() { return juice; },
    set juice(j) { juice = ((j % JUICE.length) + JUICE.length) % JUICE.length; },
    hover_h: 1.28,          // pelvis height above the ground; the pointed toes hang ~0.3 m above it
    pose(t, dt = 1/60, m = NO_MOTION) {
      const J = JUICE[juice], g = J.gain, gt = Math.min(1, g);
      fq = J.freq; dz = J.damp;
      const [ax, ay, az] = m.a, [vx, , vz] = m.v, [px, pz] = m.push;
      const ya = m.yaw_a, speed = Math.hypot(vx, vz), still = 1 - clamp(speed/0.6, 0, 1);
      const fwd = clamp(vz/2.6, 0, 1), side = clamp(vx/2.6, -1, 1);
      // recoil: a kick jolts the casting shoulder back (the chest turns away from the beam), the
      // chest and head back a little; the arm's share goes into its recoil springs
      RC.forEach((rc, k) => {
        if (rc.kick) {
          const s = arms[k].s;
          S.cy.v += s*1.6*rc.kick; S.cp.v -= 0.9*rc.kick; S.hp.v -= 1.6*rc.kick;
          rc.p.v -= 2.6*rc.kick; rc.e.v -= 4.5*rc.kick; rc.w.v += 5.0*rc.kick;
          rc.kick = 0;
        }
        spring(rc.p, -0.03*rc.press, 2.2, 0.5, 0, dt);
        spring(rc.e, -0.06*rc.press, 2.6, 0.5, 0, dt);
        spring(rc.w, 0.035*rc.press, 3.2, 0.45, 0, dt);
      });

      // the upper body leads: the head first (fastest), then the chest, lean and turn toward
      // the push; leaning back a little when he brakes
      const idle_glance = Math.sin(t*0.33)*0.1*still;
      const gz = m.gaze_w || 0;
      // ... unless he is looking at a snake he means to burn (rounds 9-10): the head turns and
      // tilts down to the spot first, the chest follows a little
      spring(S.hp, mix(clamp((0.26*pz - 0.2*(S.bp.x + S.cp.x))*g, -0.12, 0.3), clamp((m.gaze_p || 0) - 0.27, -0.7, 0.55), gz), 2.4, 0.6, air(t, 5, 2.4, 0.03*g), dt);
      spring(S.hr, clamp((-0.22*px - 0.2*(S.br.x + S.cr.x))*g, -0.25, 0.25), 2.4, 0.6, air(t, 6, 2.4, 0.025*g), dt);
      const gc = clamp((m.gaze || 0)*0.3, -0.35, 0.35);
      spring(S.hy, mix(clamp(m.look*0.5, -0.5, 0.5)*g + idle_glance, clamp((m.gaze || 0) - gc, -1.1, 1.1), gz), 2.2, 0.75, air(t, 8, 2.2, 0.025*g), dt);
      spring(S.cp, clamp((0.24*pz + 0.05*fwd)*g, -0.1, 0.3), 1.6, 0.6, air(t, 3, 1.6, 0.02*g), dt);
      spring(S.cr, clamp(-0.2*px*g, -0.22, 0.22), 1.6, 0.6, air(t, 4, 1.6, 0.018*g), dt);
      spring(S.cy, mix(clamp(m.look*0.4*g, -0.45, 0.45), gc, gz), 1.6, 0.7, air(t, 9, 1.6, 0.02*g), dt);
      // then the whole body leans into its speed and banks into turns; the hips turn last
      spring(S.bp, clamp((0.03*vz + 0.02*az)*g, -0.2, 0.24), 0.9, 0.75, air(t, 1, 0.9, 0.012*g), dt);
      spring(S.br, clamp(-0.035*ax*g, -0.24, 0.24), 0.9, 0.75, air(t, 2, 0.9, 0.012*g), dt);
      spring(S.py, 0, 1.1, 0.45, -ya*0.05*g, dt);
      // jaw: a hinged weight under the skull; a push up or forward drops it, a stop clacks it shut
      spring(S.jw, 0, 2.3, 0.22, (ay*8 + az*3.5)*g + air(t, 7, 2.3, 0.015*g), dt);
      const JAW0 = 0.07 + Math.max(0, Math.sin(t*0.45))*0.04;
      if (JAW0 + S.jw.x < 0.0) { S.jw.x = -JAW0; if (S.jw.v < 0) S.jw.v = -S.jw.v*0.3; }
      if (JAW0 + S.jw.x > 0.42) { S.jw.x = 0.42 - JAW0; if (S.jw.v > 0) S.jw.v = 0; }

      // legs: + pitch = feet back, + roll = feet to his left. A push forward swings them back,
      // speed trails them, a stop swings them under him; each leg drifts on its own time and is
      // pulled toward the other, so the pair keeps its shape without moving as one piece.
      const pull = 14*fq*fq;
      S.legs.forEach((L, k) => {
        const O = S.legs[1 - k];
        const df = k ? 1.08 : 0.93, dd = k ? 0.9 : 1.1, sd = k ? 31 : 10, tt = t*(k ? 1.14 : 0.87);
        spring(L.p, clamp(0.045*vz*g, -0.1, 0.18), 0.75*df, 0.3*dd, (az*0.75 - ay*0.4)*g + (O.p.x - L.p.x)*pull + air(tt, sd, 0.75, 0.07*g), dt);
        spring(L.r, clamp(-0.04*vx*g, -0.16, 0.16), 0.7*df, 0.3*dd, (-ax*0.8 + ya*0.08)*g + (O.r.x - L.r.x)*pull + air(tt, sd + 2, 0.7, 0.05*g), dt);
        // the shin hangs from the knee: it lags the thigh's swing (the whip), and drifts
        spring(L.k, 0, 1.2*df, 0.3, (az*0.7 - L.p.a*0.4)*g + air(tt, sd + 4, 1.2, 0.08*g), dt);
        // the foot from the ankle, a smaller whip again; the thigh turns a little on its axis
        spring(L.an, 0, 1.7*df, 0.3, (az*0.4 - L.k.a*0.3)*g + air(tt, sd + 6, 1.7, 0.09*g), dt);
        spring(L.tw, 0, 0.9*df, 0.4, air(tt, sd + 8, 0.9, 0.1*g) - ya*0.03*g, dt);
      });
      let r0 = S.legs[0].r.x, r1 = S.legs[1].r.x;
      if (r0 - r1 > 0.03) { const c = (r0 + r1)/2; r0 = c + 0.015; r1 = c - 0.015; }   // the knees never pass through each other
      for (const l of legs) {
        const k = l.s > 0 ? 1 : 0, L = S.legs[k];
        const stagger = l.s > 0 ? 0.07 : 0;
        l.hip.rotation.set(clamp(0.1 + stagger + L.p.x, -0.35, 0.9), clamp(L.tw.x, -0.2, 0.2), -0.02*l.s + clamp(k ? r1 : r0, -0.4, 0.4));   // thighs ~12-16 deg back at rest
        l.kn.rotation.set(clamp(0.2 + stagger*0.5 + L.k.x, 0.03, 0.9), 0, 0.015*l.s);                    // shins a little further back; knees never bend forward
        l.an.rotation.set(clamp(1.0 + L.an.x, 0.55, 1.45), 0, 0);                                        // toes pointed down
      }

      // arms: light, slow pendulums (+ pitch = hand back, + roll = hand to his left). Moving,
      // both settle down and behind with the hands trailing; the body's push and the torso
      // swinging above them swing them; each drifts on its own, out of step with the other.
      trail += (fwd*gt - trail)*(1 - Math.exp(-dt/(fwd*gt > trail ? 0.35 : 0.9)));
      arms.forEach((A, k) => {
        const Q = S.arms[k], s = A.s, R0 = ARM_REST[k];
        const df = k ? 1.12 : 0.9, sd = 40 + k*17, tt = t*(k ? 1.21 : 0.79);
        // pointing (round 11): the arm he casts with rises to the target, straight, the index
        // finger out; the pose's springs carry it there, stiffer while it points
        const pt = m.point && m.point.arm === k ? m.point.w : 0;
        let aim_p = 0, aim_r = 0;
        if (pt > 0) {
          chest.updateWorldMatrix(true, false);
          INV.copy(chest.matrixWorld).invert();
          TV.set(m.point.x, m.point.y, m.point.z).applyMatrix4(INV).sub(A.sh.position).normalize();
          aim_r = Math.asin(clamp(TV.x, -1, 1)); aim_p = Math.atan2(-TV.z, -TV.y);
          aim_r = s*Math.max(-0.45, s*aim_r);                         // across the body only a little
          aim_p = clamp(aim_p, -2.4, 0.9);
        }
        const base_r = (s < 0 ? 0.12 : 0.22)*s;
        const drive = (az*0.85 + ay*Math.sin(-Q.p.x) + (S.cp.a + S.bp.a)*0.5 - s*(S.cy.a + ya)*0.3)*(1 - pt);
        spring(Q.p, mix(mix(R0.p, ARM_TRAIL.p, trail), aim_p, pt), mix(0.55*df, 2.3, pt), mix(0.34, 0.75, pt), drive*g + air(tt, sd, 0.55, 0.1*g*(1 - pt)), dt);
        spring(Q.r, mix((-0.25*side + s*0.1*fwd)*gt, aim_r - base_r, pt), mix(0.6*df, 2.3, pt), mix(0.3, 0.75, pt), (-ax + (S.cr.a + S.br.a)*0.4)*g*(1 - pt) + air(tt, sd + 3, 0.6, 0.07*g*(1 - pt)), dt);
        spring(Q.t, 0, 0.7*df, 0.4, air(tt, sd + 5, 0.7, 0.12*g*(1 - pt)), dt);
        spring(Q.e, mix(mix(R0.e, ARM_TRAIL.e, trail), -0.1, pt), mix(1.0*df, 2.6, pt), mix(0.3, 0.75, pt), (az*0.8 - Q.p.a*0.35)*g*(1 - pt) + air(tt, sd + 7, 1.0, 0.1*g*(1 - pt)), dt);
        spring(Q.w, mix(mix(R0.w, ARM_TRAIL.w, trail), 0.05, pt), mix(1.5*df, 3.0, pt), mix(0.3, 0.75, pt), (az*0.5 - Q.e.a*0.3)*g*(1 - pt) + air(tt, sd + 9, 1.5, 0.08*g*(1 - pt)), dt);
        spring(Q.f, (ARM_TRAIL.curl - R0.curl)*trail, 2.0*df, 0.3, (az*0.6 - Q.w.a*0.2)*g + air(tt, sd + 11, 2.0, 0.06*g), dt);
        const roll = s*Math.max(mix(-0.08, -0.45, pt), s*Q.r.x);      // never swings in through the ribs
        // posed here without the recoil; the recoil goes on after the finger is aimed (below)
        const rc = RC[k], tr = rc.press*Math.sin(t*31 + k*2)*0.012;
        rc.sh = clamp(Q.p.x + rc.p.x + tr, -2.4, 1.0); rc.el = clamp(Q.e.x + rc.e.x, -1.9, -0.05);
        A.sh.rotation.set(clamp(Q.p.x, -2.4, 1.0), clamp(Q.t.x, -0.35, 0.35), base_r + roll);
        A.el.rotation.set(clamp(Q.e.x, -1.9, -0.05), 0, 0);
        A.wr.rotation.set(clamp(Q.w.x, -0.9, 0.7), -s*(s < 0 ? 0.9 : 1.25), 0);
        const curl = R0.curl + clamp(Q.f.x, -0.3, 0.4);
        A.fingers.forEach((segs, i) => {
          // pointing: the index finger (0) straightens, the others close
          const c = mix(curl, i === 0 ? -0.1 : 1.05, pt);
          segs.forEach((n, j) => n.rotation.set(0, 0, -s*(c + j*(i === 0 ? 0.12*(1 - pt) : 0.12 + 0.25*pt) + i*0.03 + Math.sin(t*1.3 + i)*0.03)));
        });
        A.thumb[0].rotation.set(0.5, 0, -s*0.35);
        A.thumb[1].rotation.set(0, 0, -s*0.3);
      });

      body.position.y = 0;
      body.rotation.set(0.1 + S.bp.x, 0, S.br.x);
      pelvis.rotation.set(0, S.py.x, 0);
      spine.rotation.set(0.04 + S.cp.x*0.5, -S.py.x*0.75 + S.cy.x*0.45, S.cr.x*0.5);
      chest.rotation.set(0.03 + S.cp.x*0.5, S.cy.x*0.55, S.cr.x*0.5);
      neck.rotation.set(0.04 + S.hp.x*0.3, S.hy.x*0.3, S.hr.x*0.3);
      head.rotation.set(-0.02 + S.hp.x*0.7, S.hy.x*0.7, S.hr.x*0.7);                  // ~15 deg down in all, as in 07
      jaw.rotation.x = JAW0 + S.jw.x;

      // pointing: the index finger laid along the line to the target (the arm alone left it up
      // to ~16 deg off), turning the hand at the wrist, on the pose without the recoil; then the
      // recoil's flick of the finger up; then the recoil goes onto the shoulder and elbow, and the
      // hand, now set on the forearm, is carried with it (aiming after the recoil would undo it)
      arms.forEach((A, k) => {
        const pt = m.point && m.point.arm === k ? m.point.w : 0, rc = RC[k];
        const flick = rc.w.x + rc.press*Math.sin(t*37 + k)*0.02;
        const recoil_on = () => { A.sh.rotation.x = rc.sh; A.el.rotation.x = rc.el; };
        if (pt <= 0 && Math.abs(flick) < 1e-4) { recoil_on(); return; }
        A.el.updateWorldMatrix(true, false);
        A.el.getWorldQuaternion(AQ.e);
        AQ.c.identity();
        const tipn = A.fingers[0].tip;
        tipn.updateWorldMatrix(true, false); tipn.getWorldPosition(AV.t);
        A.fingers[0][0].getWorldPosition(AV.b);
        AV.f.subVectors(AV.t, AV.b).normalize();
        if (pt > 0 && AV.d.set(m.point.x, m.point.y, m.point.z).distanceTo(AV.t) > 0.3) {
          AV.d.sub(AV.t).normalize();
          AQ.t.setFromUnitVectors(AV.f, AV.d);
          AQ.c.slerp(AQ.t, pt);
          const ang = 2*Math.acos(clamp(AQ.c.w, -1, 1));
          if (ang > 0.8) { AQ.t.copy(AQ.c); AQ.c.identity().slerp(AQ.t, 0.8/ang); }
          AV.f.applyQuaternion(AQ.c);
        }
        // the flick: the finger tips up, about the axis across it and the vertical
        AV.ax.crossVectors(AV.f, AV.up);
        if (AV.ax.lengthSq() > 1e-6 && Math.abs(flick) > 1e-4) { AV.ax.normalize(); AQ.r.setFromAxisAngle(AV.ax, flick); AQ.c.premultiply(AQ.r); }
        // world correction -> the wrist's own frame: local' = parent^-1 * C * parent * local
        AQ.t.copy(AQ.e).invert().multiply(AQ.c).multiply(AQ.e);
        A.wr.quaternion.premultiply(AQ.t);
        recoil_on();
      });
    },
    // recoil (round 18): a kick on an arm (1 = the beam firing), and how hard it pushes while on (0..1)
    kick(k, amount = 1) { RC[k].kick += amount*lich.recoil_gain*RECOILS[recoil].gain; },
    press(k, w) { RC[k].press = w*lich.recoil_gain*RECOILS[recoil].gain; },
    recoil_gain: 1,                           // tests: 0 = no recoil, to compare against
    RECOILS,
    get recoil() { return recoil; },
    set recoil(i) { recoil = ((i % RECOILS.length) + RECOILS.length) % RECOILS.length; },
    update(t) {
      GU.uGemTime.value = t;
    },
    // where the index fingertip of an arm (0 = his right, 1 = his left) is, world
    fingertip(k, out = new THREE.Vector3()) { const n = arms[k].fingers[0].tip; n.updateWorldMatrix(true, false); return n.getWorldPosition(out); },
    // the way the index finger points (from its first joint to its tip), world
    finger_dir(k, out = new THREE.Vector3()) {
      const f = arms[k].fingers[0], n = f.tip;
      n.updateWorldMatrix(true, false); n.getWorldPosition(out);
      f[0].getWorldPosition(TV);
      return out.sub(TV).normalize();
    },
    head_pos(out = new THREE.Vector3()) { head.updateWorldMatrix(true, false); return head.getWorldPosition(out).add(TIP.set(0, 0.08, 0)); },
  };
  return lich;
}
