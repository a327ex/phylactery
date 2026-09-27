// lich.js -- the lich: all bones, no robe, floating; the bones are prismatic, a rainbow glow
// flowing up through them (owner, 2026-09-27: "a lich, all bones, no robe or anything, and its
// bones are prismatic, like a rainbow glow going through them").
//
// Built from primitives in a small hierarchy (pelvis -> spine -> chest -> neck/skull, shoulders
// -> elbows -> hands, hips -> knees -> feet) so the pose can breathe. One shared material: pale
// bone lit by the scene, plus an emissive rainbow whose hue runs along world height and time,
// with a brighter band travelling upward; HDR, so the bloom pass makes it glow. A point light
// carries the colour at the chest onto the floor around the lich.
import * as THREE from 'three';

const PRISM_DECL = /* glsl */`
uniform float uTime, uGlow, uBand, uMode;
uniform vec3 uBase;
varying vec3 vPW;
vec3 prism(float h){
  vec3 c = 0.5 + 0.5*cos(6.28318*(h + vec3(0.0, 0.333, 0.667)));
  return pow(c, vec3(1.6));
}`;

export function prism_material(opts = {}) {
  const m = new THREE.MeshLambertMaterial({ color: 0xece4d4 });
  const U = {
    uTime: { value: 0 }, uGlow: { value: opts.glow ?? 1.6 }, uBand: { value: opts.band ?? 1.0 }, uMode: { value: opts.mode ?? 0 },
    uBase: { value: new THREE.Vector3() },
  };
  m.userData.U = U;
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, U);
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vPW;')
      .replace('#include <project_vertex>', '#include <project_vertex>\n  vPW = (modelMatrix*vec4(transformed, 1.0)).xyz;');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', '#include <common>\n' + PRISM_DECL)
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
  {
    float y = vPW.y - uBase.y;
    float h = y*0.85 + dot(vPW.xz - uBase.xz, vec2(0.35, 0.22)) - uTime*0.32;
    vec3 rb = prism(h);
    if (uMode < 0.5) {
      // A: RAINBOW BONES -- every bone is the rainbow, flowing upward, a brighter band climbing
      float band = 0.55 + 0.45*uBand*smoothstep(0.55, 1.0, 0.5 + 0.5*sin(y*4.2 - uTime*2.6));
      totalEmissiveRadiance += rb*uGlow*band;
      diffuseColor.rgb = mix(diffuseColor.rgb, rb, 0.25);
    } else if (uMode < 1.5) {
      // B: PALE BONE, A RAINBOW PASSING -- white bone; waves of rainbow light rise through it
      float wave = smoothstep(0.86, 1.0, 0.5 + 0.5*sin(y*2.6 - uTime*2.0));
      totalEmissiveRadiance += rb*uGlow*(0.02 + 1.6*wave);
      diffuseColor.rgb = vec3(0.96, 0.94, 0.9);
    } else {
      // C: PRISM EDGES -- white bone that splits light at its edges, like cut crystal
      float rim = pow(1.0 - abs(dot(normalize(normal), normalize(vViewPosition))), 3.2);
      totalEmissiveRadiance += rb*uGlow*(0.02 + 1.7*rim);
      diffuseColor.rgb = vec3(0.96, 0.94, 0.9);
    }
  }`);
  };
  return m;
}

export function create_lich(R, opts = {}) {
  const mat = prism_material(opts);
  const U = mat.userData.U;
  const socket = new THREE.MeshBasicMaterial({ color: 0x050407 });
  const glint = new THREE.MeshBasicMaterial({ color: new THREE.Color(3.2, 3.0, 2.6) });

  const root = new THREE.Group();            // world placement (position + yaw), set by the caller
  const body = new THREE.Group();            // bob and lean
  root.add(body);
  const meshes = [];
  const part = (parent, geo, x, y, z, rx = 0, ry = 0, rz = 0, m = mat) => {
    const mesh = new THREE.Mesh(geo, m);
    mesh.position.set(x, y, z); mesh.rotation.set(rx, ry, rz);
    mesh.castShadow = m === mat;
    parent.add(mesh);
    meshes.push(mesh);
    return mesh;
  };
  const node = (parent, x, y, z) => { const g = new THREE.Group(); g.position.set(x, y, z); parent.add(g); return g; };
  // a bone of length L hanging down from its node (a capsule whose top is at the node)
  const TH = 1.55;                           // bone thickness over anatomical, so limbs read at 640x360
  const bone = (parent, L, r, x = 0, z = 0) => { r *= TH; return part(parent, new THREE.CapsuleGeometry(r, Math.max(0.001, L - 2*r), 2, 6), x, -L/2, z); };

  // pelvis (the root of the skeleton, local y = 0)
  const pelvis = node(body, 0, 0, 0);
  for (const s of [-1, 1]) {
    const il = part(pelvis, new THREE.SphereGeometry(1, 8, 6), 0.085*s, 0.02, -0.01, 0, 0, 0.5*s);
    il.scale.set(0.085, 0.065, 0.035);
  }
  part(pelvis, new THREE.BoxGeometry(0.07, 0.07, 0.05), 0, 0.0, -0.035);                // sacrum
  const pub = part(pelvis, new THREE.TorusGeometry(0.06, 0.012, 4, 10, Math.PI), 0, -0.035, 0.03, Math.PI/2 + 0.3, 0, 0);
  void pub;

  // spine: vertebrae up to the chest, with a gentle S
  const spine = node(pelvis, 0, 0.04, -0.04);
  const NV = 9;
  for (let i = 0; i < NV; i++) {
    const t = i/(NV - 1);
    part(spine, new THREE.BoxGeometry(0.065 - t*0.014, 0.042, 0.055), 0, t*0.5, Math.sin(t*Math.PI)*-0.03);
  }
  // chest: ribs as open ellipses around the spine, sloping down at the front
  const chest = node(spine, 0, 0.36, 0.02);
  const RIBS = [[0.16, 0.115], [0.12, 0.135], [0.08, 0.145], [0.04, 0.148], [0.0, 0.142], [-0.04, 0.128], [-0.08, 0.11]];
  for (const [y, r] of RIBS) {
    const g = new THREE.TorusGeometry(r, 0.016, 4, 14, Math.PI*1.72);
    const rib = part(chest, g, 0, y, 0.0, Math.PI/2 - 0.35, 0, Math.PI/2 + Math.PI*0.14);
    rib.scale.set(1, 0.78, 1);
  }
  part(chest, new THREE.BoxGeometry(0.03, 0.2, 0.02), 0, 0.06, 0.125, -0.25, 0, 0);       // sternum
  for (const s of [-1, 1]) {
    const cl = part(chest, new THREE.CapsuleGeometry(0.012, 0.13, 2, 5), 0.075*s, 0.2, 0.07, 0, 0.35*s, Math.PI/2 - 0.2*s);
    void cl;
  }
  // neck and skull
  const neck = node(chest, 0, 0.23, -0.02);
  part(neck, new THREE.CylinderGeometry(0.022, 0.026, 0.08, 6), 0, 0.03, 0);
  const head = node(neck, 0, 0.1, 0.0);
  head.scale.setScalar(1.3);
  const cranium = part(head, new THREE.SphereGeometry(1, 12, 9), 0, 0.07, -0.005);
  cranium.scale.set(0.092, 0.1, 0.112);
  const face = part(head, new THREE.SphereGeometry(1, 10, 7), 0, 0.025, 0.05);
  face.scale.set(0.075, 0.07, 0.07);
  const jaw = node(head, 0, -0.005, 0.03);
  const jm = part(jaw, new THREE.BoxGeometry(0.1, 0.03, 0.08), 0, -0.02, 0.025);
  void jm;
  for (const s of [-1, 1]) {
    part(head, new THREE.SphereGeometry(0.031, 8, 6), 0.037*s, 0.052, 0.104, 0, 0, 0, socket);
    part(head, new THREE.SphereGeometry(0.0085, 5, 4), 0.035*s, 0.052, 0.126, 0, 0, 0, glint);
    const cheek = part(head, new THREE.SphereGeometry(1, 6, 5), 0.058*s, 0.018, 0.084);      // cheekbones
    cheek.scale.set(0.022, 0.016, 0.02);
  }
  part(head, new THREE.ConeGeometry(0.015, 0.032, 3), 0, 0.016, 0.122, -0.2, 0, Math.PI, socket);   // nose hole
  part(head, new THREE.BoxGeometry(0.062, 0.018, 0.012), 0, -0.004, 0.114);                       // upper teeth
  part(head, new THREE.BoxGeometry(0.058, 0.006, 0.014), 0, -0.016, 0.112, 0, 0, 0, socket);     // the mouth's gap

  // arms (reaching forward and down, toward the egg)
  const arms = [];
  for (const s of [-1, 1]) {
    const sh = node(chest, 0.175*s, 0.19, 0.0);
    bone(sh, 0.3, 0.02);
    const el = node(sh, 0, -0.3, 0);
    bone(el, 0.26, 0.014, 0.012, 0); bone(el, 0.26, 0.012, -0.012, 0.01);
    const wr = node(el, 0, -0.27, 0);
    part(wr, new THREE.BoxGeometry(0.05, 0.07, 0.018), 0, -0.035, 0);
    const fingers = [];
    for (let f = 0; f < 4; f++) {
      const fg = node(wr, (f - 1.5)*0.013, -0.07, 0);
      bone(fg, 0.075, 0.0055);
      fingers.push(fg);
    }
    const th = node(wr, 0.028*s, -0.03, 0.01);
    bone(th, 0.055, 0.006);
    th.rotation.z = 0.6*s;
    arms.push({ s, sh, el, wr, fingers, th });
  }
  // legs (hanging, trailing a little behind)
  const legs = [];
  for (const s of [-1, 1]) {
    const hip = node(pelvis, 0.09*s, -0.03, 0);
    bone(hip, 0.42, 0.022);
    const kn = node(hip, 0, -0.42, 0);
    const pat = part(kn, new THREE.SphereGeometry(0.022, 6, 5), 0, 0, 0.022);
    void pat;
    bone(kn, 0.4, 0.016, 0.01, 0); bone(kn, 0.39, 0.01, -0.016, -0.01);
    const an = node(kn, 0, -0.41, 0);
    part(an, new THREE.BoxGeometry(0.05, 0.025, 0.13), 0, -0.012, 0.035);
    legs.push({ s, hip, kn, an });
  }

  // chest light: the prism colour spilling onto the floor
  // below the feet, so it colours the floor and not the lich's own bones
  const light = new THREE.PointLight(0xffffff, 2.4, 4.2, 1.6);
  light.position.set(0, -1.05, 0.1);
  body.add(light);

  R.world_scene.add(root);

  const tmp = new THREE.Vector3(), col = new THREE.Color();
  const MODES = ['A RAINBOW BONES', 'B PALE BONE, RAINBOW PASSING', 'C PRISM EDGES'];
  const lich = {
    root, body, mat, light, MODES,
    get mode() { return U.uMode.value | 0; },
    set mode(m) { U.uMode.value = ((m % MODES.length) + MODES.length) % MODES.length; },
    hover_h: 1.25,          // pelvis height above the ground
    pose(t, drift = 0) {
      // bob, a slow sway, a lean into the direction of travel
      body.position.y = Math.sin(t*1.25)*0.07;
      body.rotation.x = 0.16 + drift*0.22 + Math.sin(t*0.8)*0.025;
      body.rotation.z = Math.sin(t*0.63)*0.03;
      spine.rotation.x = -0.08 + Math.sin(t*1.25 + 0.6)*0.03;
      head.rotation.x = 0.08 + Math.sin(t*0.9 + 1.0)*0.05;
      head.rotation.y = Math.sin(t*0.37)*0.12;
      jaw.rotation.x = 0.06 + Math.max(0, Math.sin(t*0.5))*0.05;
      for (const a of arms) {
        const w = Math.sin(t*1.1 + a.s)*0.06;
        a.sh.rotation.set(-0.95 + w - drift*0.3, 0, 0.22*a.s);
        a.el.rotation.set(-0.45 + w*0.6, 0, -0.08*a.s);
        a.wr.rotation.set(-0.2, 0, 0.1*a.s);
        a.fingers.forEach((f, i) => f.rotation.set(-0.25 - i*0.05 + Math.sin(t*1.7 + i)*0.06, 0, (i - 1.5)*0.08*a.s));
      }
      for (const l of legs) {
        const w = Math.sin(t*1.25 + l.s*0.8)*0.07;
        l.hip.rotation.set(0.12 + w + drift*0.25, 0, 0.05*l.s);
        l.kn.rotation.set(0.45 + w*0.8 + drift*0.2, 0, 0);
        l.an.rotation.set(0.7, 0, 0);
      }
    },
    update(t) {
      U.uTime.value = t;
      root.getWorldPosition(tmp);
      U.uBase.value.copy(tmp);
      // the chest light takes the rainbow colour at chest height (same formula as the shader)
      const h = 0.45*0.85 - t*0.32;
      const f = x => Math.pow(0.5 + 0.5*Math.cos(6.28318*(h + x)), 1.6);
      col.setRGB(f(0), f(0.333), f(0.667));
      light.color.copy(col);
    },
  };
  return lich;
}
