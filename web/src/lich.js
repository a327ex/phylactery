// lich.js -- the lich: a realistic human skeleton (skeleton.js), all bones, no robe, floating;
// prismatic gem bone (gem.js, STRONG by default: owner, round 2), lit only by the scene.
//
// The rig is a tree of joints (pelvis -> spine -> chest -> neck -> head -> jaw; chest ->
// shoulder -> elbow -> wrist -> fingers; pelvis -> hip -> knee -> ankle). The resting float
// follows Astra's lich 07 (owner, round 2: "the more correct shape"): the body leaning a little
// forward, the legs held together and swept back on one diagonal, knees nearly touching, shins
// angled back a little more than the thighs, feet pointed down, one leg a little behind the
// other; one hand hanging curled before the pelvis, the other reaching forward and down.
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
  const light = new THREE.PointLight(0xffffff, 0, 0.1, 2);   // kept at zero: the lich emits nothing

  const MODES = GEM_LEVELS.map(l => 'GEM, ' + l.name);
  let mode = 0;                               // round 4: SOLID (STRONG was right for the look; the owner asked for more solid)
  mat.userData.set_level(GEM_LEVELS[mode]);
  const lich = {
    root, body, mat, light, MODES, build_ms, tris, nodes: { pelvis, spine, chest, neck, head, jaw, arms, legs },
    get mode() { return mode; },
    set mode(m) { mode = ((m % MODES.length) + MODES.length) % MODES.length; mat.userData.set_level(GEM_LEVELS[mode]); },
    hover_h: 1.28,          // pelvis height above the ground; the pointed toes hang ~0.3 m above it
    pose(t, drift = 0) {
      // breathing float: a slow bob, a slight sway
      body.position.y = Math.sin(t*1.1)*0.05;
      body.rotation.set(0.1 + drift*0.1 + Math.sin(t*0.7)*0.015, 0, Math.sin(t*0.55)*0.018);
      spine.rotation.x = 0.04 + Math.sin(t*1.1 + 0.5)*0.012;
      chest.rotation.x = 0.03;
      neck.rotation.x = 0.04;
      head.rotation.set(-0.02 + Math.sin(t*0.8 + 1)*0.03, Math.sin(t*0.33)*0.08, 0);     // ~15 deg down in all, as in 07
      jaw.rotation.x = 0.07 + Math.max(0, Math.sin(t*0.45))*0.04;
      for (const a of arms) {
        const w = Math.sin(t*0.9 + a.s)*0.03;
        if (a.s < 0) {
          // hanging, bent at the elbow, the hand curled before the pelvis
          a.sh.rotation.set(-0.12 + w, 0, 0.12*a.s);
          a.el.rotation.set(-1.25 + w, 0, 0);
          a.wr.rotation.set(-0.25, -a.s*0.9, 0);
        } else {
          // reaching forward and down, toward the light
          a.sh.rotation.set(-0.72 + w, 0, 0.22*a.s);
          a.el.rotation.set(-0.42 + w*0.6, 0, 0);
          a.wr.rotation.set(-0.35, -a.s*1.25, 0);
        }
        const curl = a.s < 0 ? 0.55 : 0.32;
        a.fingers.forEach((segs, i) => segs.forEach((n, j) => n.rotation.set(0, 0, -a.s*(curl + j*0.12 + i*0.03 + Math.sin(t*1.3 + i)*0.03))));
        a.thumb[0].rotation.set(0.5, 0, -a.s*0.35);
        a.thumb[1].rotation.set(0, 0, -a.s*0.3);
      }
      for (const l of legs) {
        const w = Math.sin(t*1.0 + 0.4)*0.03 + l.s*Math.sin(t*0.8)*0.01;
        const stagger = l.s > 0 ? 0.07 : 0;
        l.hip.rotation.set(0.1 + stagger + w + drift*0.15, 0, -0.02*l.s);   // thighs ~12-16 deg back in all
        l.kn.rotation.set(0.2 + stagger*0.5 + w*0.5, 0, 0.015*l.s);        // shins a little further back
        l.an.rotation.set(1.0, 0, 0);                                       // toes pointed down
      }
    },
    update(t) {
      GU.uGemTime.value = t;
    },
  };
  return lich;
}
