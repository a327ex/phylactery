// snakes.js -- the snakes (round 3; owner: "the ones in the game have the wrong shape ... snake
// 03 feels fine, it's not an issue of species, it's just general shape"). Astra's snake 03 (a
// mamba-like build): long and slender, one continuous body lying in wide smooth S-curves, the
// neck lifted off the ground in a curve so the narrow, elongated head rides level above it, a
// long thin tail.
//
// Each snake is one tube mesh rebuilt every frame along its head's trail (serpentine
// locomotion: the body follows exactly where the head went). The front of the body rises
// off the ground; the head is part of the same tube, shaped by the radius profile and a
// flatter section. Glossy scales, a paler belly, dark glassy eyes.
//
// Behaviour is still a placeholder: they come out of the dark toward the egg; within reach of
// the lich they shrink away and another comes (no attacks drawn yet).
import * as THREE from 'three';
import { make_rng, clamp, smoothstep, lerp } from 'game/util.js';
import { gi_dynamic } from 'game/gi.js';

const LEN = 4.4, R0 = 0.08;                   // body length and body radius, metres (03 build, dream-sized: readable from the room camera)
const RINGS = 72, SIDES = 12;
const RAISE = 0.34, RAISE_LEN = 1.1;           // the head rides this high; the neck curve spans this much body
// rings crowd toward the snout (about 14 in the first 20 cm) so the head has a shape
const S_AT = i => LEN*Math.pow(i/(RINGS - 1), 1.6);
const I_AT = sl => (RINGS - 1)*Math.pow(sl/LEN, 1/1.6);

// radius profile along the body, s = 0 at the snout, in body radii; and the section's height
function radius_at(s) {
  if (s < 0.012) return lerp(0.18, 0.45, s/0.012);
  if (s < 0.05) return lerp(0.45, 0.82, (s - 0.012)/0.038);
  if (s < 0.085) return lerp(0.82, 0.95, (s - 0.05)/0.035);        // the head's widest, at the jaw
  if (s < 0.115) return lerp(0.95, 0.68, (s - 0.085)/0.03);        // the neck
  if (s < 0.3) return lerp(0.68, 0.98, smoothstep(0.115, 0.3, s));
  const tail0 = LEN*0.62;
  if (s < tail0) return 1.0;
  return lerp(1.0, 0.07, Math.pow((s - tail0)/(LEN - tail0), 0.85));
}
const flat_at = s => (s < 0.11 ? 0.62 : lerp(0.62, 0.84, smoothstep(0.11, 0.3, s)));   // head flatter than body

// scale texture: dark olive-bronze back with overlapping scale rows, pale belly
function scale_texture() {
  const W = 64, H = 256;
  const c = document.createElement('canvas'); c.width = W; c.height = H;
  const g = c.getContext('2d');
  const img = g.createImageData(W, H), d = img.data;
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const u = x/W;                                                // around: 0.5 = back, 0/1 = belly
    const back = Math.cos((u - 0.5)*Math.PI*2)*0.5 + 0.5;         // 1 on the back, 0 on the belly
    const row = (y + (Math.floor(x/4) % 2)*2) % 4, col = x % 4;
    const dia = Math.abs(col - 1.5) + Math.abs(row - 1.5);
    let k = dia < 1.4 ? 1.0 : dia < 2.4 ? 0.86 : 0.7;
    const belly = smoothstep(0.35, 0.1, back);
    const top = [60, 56, 44], side = [84, 78, 59], bel = [140, 130, 100];      // dark olive-bronze: a silhouette on the brown floor
    let col3 = back > 0.6 ? top : side;
    col3 = col3.map((v, i) => lerp(v, bel[i], belly));
    if (belly > 0.5) k = (y % 6 === 0) ? 0.78 : 1.0;             // belly plates
    const i = (y*W + x)*4;
    d[i] = col3[0]*k; d[i + 1] = col3[1]*k; d[i + 2] = col3[2]*k; d[i + 3] = 255;
  }
  g.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.magFilter = THREE.NearestFilter; t.minFilter = THREE.NearestMipmapNearestFilter;
  return t;
}

export function create_snakes(R, cave, get_lich_pos, count = 9, seed = 5) {
  const rng = make_rng(seed);
  const mat = new THREE.MeshStandardMaterial({ map: scale_texture(), roughness: 0.3, metalness: 0.0 });
  if (cave.GU) gi_dynamic(mat, cave.GU);
  // scales are glossy: their edges catch whatever light is around (the bounce light included),
  // which draws the body's outline against the floor
  {
    const prev = mat.onBeforeCompile;
    mat.onBeforeCompile = (sh, r) => {
      prev(sh, r);
      sh.fragmentShader = sh.fragmentShader.replace('#include <lights_fragment_end>', `#include <lights_fragment_end>
  {
    float rim = pow(1.0 - abs(dot(normalize(normal), normalize(vViewPosition))), 2.6);
    vec3 amb = reflectedLight.indirectDiffuse/max(diffuseColor.rgb, vec3(0.05)) + reflectedLight.directDiffuse/max(diffuseColor.rgb, vec3(0.05));
    reflectedLight.indirectSpecular += rim*amb*0.55;
  }`);
    };
    mat.customProgramCacheKey = () => 'snake_gi_rim';
  }
  const eye_mat = new THREE.MeshStandardMaterial({ color: 0x0b0a08, roughness: 0.08, metalness: 0.0 });
  const eye_geo = new THREE.SphereGeometry(1, 8, 6);
  const egg = cave.egg.position;
  const S = [];

  // one tube geometry per snake, rewritten each frame
  const make_mesh = () => {
    const n = RINGS*SIDES + 2;
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(n*3), 3));
    g.setAttribute('normal', new THREE.BufferAttribute(new Float32Array(n*3), 3));
    const uv = new Float32Array(n*2);
    for (let i = 0; i < RINGS; i++) for (let j = 0; j < SIDES; j++) { const o = (i*SIDES + j)*2; uv[o] = j/SIDES; uv[o + 1] = S_AT(i)*4; }
    g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
    const idx = [];
    for (let i = 0; i < RINGS - 1; i++) for (let j = 0; j < SIDES; j++) {
      const a = i*SIDES + j, b = i*SIDES + (j + 1)%SIDES, c = (i + 1)*SIDES + (j + 1)%SIDES, d = (i + 1)*SIDES + j;
      idx.push(a, d, c, a, c, b);
    }
    const tip = RINGS*SIDES, end = tip + 1;
    for (let j = 0; j < SIDES; j++) { idx.push(tip, (j + 1)%SIDES, j); idx.push(end, (RINGS - 1)*SIDES + j, (RINGS - 1)*SIDES + (j + 1)%SIDES); }
    g.setIndex(idx);
    const m = new THREE.Mesh(g, mat);
    m.castShadow = true; m.receiveShadow = true; m.frustumCulled = false;
    R.world_scene.add(m);
    const eyes = [0, 1].map(() => { const e = new THREE.Mesh(eye_geo, eye_mat); e.castShadow = false; R.world_scene.add(e); return e; });
    return { m, eyes };
  };

  const spawn = (s, delay) => {
    let th;
    do th = rng.float(0, Math.PI*2); while (Math.abs(Math.atan2(Math.sin(th + Math.PI/2), Math.cos(th + Math.PI/2))) < 0.5);
    const r = rng.float(14.0, 15.8);
    s.x = Math.cos(th)*r; s.z = Math.sin(th)*r;
    s.dir = Math.atan2(-s.z, -s.x) + rng.spread(0.3);
    s.phase = rng.float(0, 6.28); s.speed = rng.float(1.0, 1.35);
    s.wave = rng.float(0.95, 1.2);                               // wavelength of the S, metres
    s.amp = rng.float(0.55, 0.75);                                // heading swing, radians
    s.trail = [];
    for (let i = 0; i < 400; i++) s.trail.push([s.x - Math.cos(s.dir)*i*0.01, s.z - Math.sin(s.dir)*i*0.01]);
    s.dying = -1; s.delay = delay; s.scale = 1; s.dist = 0;
  };
  for (let i = 0; i < count; i++) { const s = make_mesh(); spawn(s, i*0.9); S.push(s); }

  const P = [], T = new THREE.Vector3(), Nn = new THREE.Vector3(), Bn = new THREE.Vector3(), UP = new THREE.Vector3(0, 1, 0);
  for (let i = 0; i < RINGS; i++) P.push(new THREE.Vector3());

  function update(t, dt) {
    const L = get_lich_pos();
    for (const s of S) {
      if (s.delay > 0) { s.delay -= dt; s.m.visible = false; s.eyes.forEach(e => (e.visible = false)); continue; }
      s.m.visible = true; s.eyes.forEach(e => (e.visible = true));
      if (s.dying >= 0) {
        s.dying += dt;
        s.scale = clamp(1 - s.dying/0.5, 0, 1);
        if (s.dying > 0.5) spawn(s, rng.float(0.2, 1.4));
      } else {
        // serpentine: steer at the egg, swinging the heading so the path is a steady S
        s.dist += s.speed*dt;
        const want = Math.atan2(egg.z - s.z, egg.x - s.x) + Math.sin(s.dist/s.wave*Math.PI*2 + s.phase)*s.amp;
        let d = want - s.dir; d = Math.atan2(Math.sin(d), Math.cos(d));
        s.dir += clamp(d, -5*dt, 5*dt);
        s.x += Math.cos(s.dir)*s.speed*dt; s.z += Math.sin(s.dir)*s.speed*dt;
        const last = s.trail[0];
        if (Math.hypot(s.x - last[0], s.z - last[1]) > 0.01) s.trail.unshift([s.x, s.z]);
        if (s.trail.length > 600) s.trail.length = 600;
        const dl = Math.hypot(s.x - L.x, s.z - L.z), de = Math.hypot(s.x - egg.x, s.z - egg.z);
        if (dl < 1.5 || de < 1.1) s.dying = 0;          // placeholder: they reach the light, then dissolve
      }
      build(s);
    }
  }

  // the spine: points along the trail by arc length, the front raised into a neck curve
  function build(s) {
    let acc = 0, ti = 0;
    const sc = s.scale;
    for (let i = 0; i < RINGS; i++) {
      const target = S_AT(i);
      let x = s.trail[s.trail.length - 1][0], z = s.trail[s.trail.length - 1][1];
      while (ti < s.trail.length - 1) {
        const a = s.trail[ti], b = s.trail[ti + 1];
        const l = Math.hypot(b[0] - a[0], b[1] - a[1]);
        if (acc + l >= target) { const f = (target - acc)/(l || 1); x = a[0] + (b[0] - a[0])*f; z = a[1] + (b[1] - a[1])*f; break; }
        acc += l; ti++;
      }
      const r = R0*radius_at(target)*sc;
      // the neck lifts the head: a smooth rise over the front RAISE_LEN metres
      const lift = RAISE*smoothstep(RAISE_LEN, 0.05, target)*sc;
      P[i].set(x, cave.ground_y(x, z) + r*flat_at(target) + lift, z);
    }
    const pos = s.m.geometry.attributes.position.array, nor = s.m.geometry.attributes.normal.array;
    for (let i = 0; i < RINGS; i++) {
      const a = P[Math.max(0, i - 1)], b = P[Math.min(RINGS - 1, i + 1)];
      T.subVectors(a, b).normalize();                             // pointing toward the head
      Bn.crossVectors(T, UP).normalize();                         // sideways
      Nn.crossVectors(Bn, T).normalize();                         // up, square to the body
      const target = S_AT(i);
      const r = R0*radius_at(target)*sc, fl = flat_at(target);
      for (let j = 0; j < SIDES; j++) {
        const ang = j/SIDES*Math.PI*2;                            // 0 = belly, pi = back
        const cx = Math.sin(ang), cy = -Math.cos(ang);
        const fy = cy < 0 ? fl*0.8 : fl;                          // a flatter belly
        const o = (i*SIDES + j)*3;
        pos[o] = P[i].x + Bn.x*cx*r + Nn.x*cy*r*fy;
        pos[o + 1] = P[i].y + Bn.y*cx*r + Nn.y*cy*r*fy;
        pos[o + 2] = P[i].z + Bn.z*cx*r + Nn.z*cy*r*fy;
        const nx = Bn.x*cx + Nn.x*cy/fy, ny = Bn.y*cx + Nn.y*cy/fy, nz = Bn.z*cx + Nn.z*cy/fy;
        const l = Math.hypot(nx, ny, nz) || 1;
        nor[o] = nx/l; nor[o + 1] = ny/l; nor[o + 2] = nz/l;
      }
    }
    // snout tip and tail tip
    const tip = RINGS*SIDES*3, end = tip + 3;
    T.subVectors(P[0], P[1]).normalize();
    pos[tip] = P[0].x + T.x*R0*0.25*sc; pos[tip + 1] = P[0].y + T.y*R0*0.25*sc; pos[tip + 2] = P[0].z + T.z*R0*0.25*sc;
    nor[tip] = T.x; nor[tip + 1] = T.y; nor[tip + 2] = T.z;
    pos[end] = P[RINGS - 1].x; pos[end + 1] = P[RINGS - 1].y; pos[end + 2] = P[RINGS - 1].z;
    nor[end] = -T.x; nor[end + 1] = 0; nor[end + 2] = -T.z;
    s.m.geometry.attributes.position.needsUpdate = true;
    s.m.geometry.attributes.normal.needsUpdate = true;
    // eyes: on the sides of the head, a little up, near the front of the widest part
    const ei = Math.round(I_AT(0.055));
    const a = P[Math.max(0, ei - 1)], b = P[ei + 1];
    T.subVectors(a, b).normalize(); Bn.crossVectors(T, UP).normalize(); Nn.crossVectors(Bn, T).normalize();
    const rr = R0*radius_at(0.055)*sc;
    s.eyes.forEach((e, k) => {
      const side = k ? 1 : -1;
      e.position.copy(P[ei]).addScaledVector(Bn, side*rr*0.8).addScaledVector(Nn, rr*0.18);   // set into the side of the head
      e.scale.setScalar(R0*0.12*sc);
    });
  }
  return { update, S };
}
