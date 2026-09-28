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
// Behaviour: they come out of the dark toward the egg (reaching it they shrink away: a
// placeholder). Round 9: set on fire (fire.js) a snake stops where it is, its lifted neck sinks
// as it dies, its scales char black with glowing cracks that cool; then the black corpse sinks
// into the ground in a puff of ash, and another comes.
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
// the corpse sinking: how far below its bed it is, eased
const SINK_T = 1.5, SINK_D = 0.34;
const RESPAWN = [2.0, 5.0];                  // seconds in the dark before a gone snake comes back
const sink_depth = s => (s.sink < 0 ? 0 : SINK_D*smoothstep(0, SINK_T, s.sink));
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

export function create_snakes(R, cave, get_lich_pos, fire, count = 8, seed = 5) {
  const rng = make_rng(seed);
  const mat = new THREE.MeshStandardMaterial({ map: scale_texture(), roughness: 0.3, metalness: 0.0 });
  if (cave.GU) gi_dynamic(mat, cave.GU);
  // scales are glossy: their edges catch whatever light is around (the bounce light included),
  // which draws the body's outline against the floor
  // burning (round 9): aBurn per vertex = (how charred, how brightly its cracks glow, how much
  // prismatic light shines in it: the beam and the leakage, round 11)
  const uEmber = { value: new THREE.Color(3.2, 0.75, 0.1) }, uSnakeT = { value: 0 };
  {
    const prev = mat.onBeforeCompile;
    mat.onBeforeCompile = (sh, r) => {
      prev(sh, r);
      sh.uniforms.uEmber = uEmber; sh.uniforms.uSnakeT = uSnakeT;
      sh.vertexShader = sh.vertexShader
        .replace('#include <common>', `#include <common>
attribute vec3 aBurn;
varying vec3 vBurn;`)
        .replace('#include <begin_vertex>', `#include <begin_vertex>
  vBurn = aBurn;`);
      sh.fragmentShader = sh.fragmentShader
        .replace('#include <common>', `#include <common>
varying vec3 vBurn;
uniform vec3 uEmber;
uniform float uSnakeT;`)
        .replace('#include <map_fragment>', `#include <map_fragment>
  diffuseColor.rgb = mix(diffuseColor.rgb, vec3(0.02, 0.018, 0.016), vBurn.x);`)
        .replace('#include <roughnessmap_fragment>', `#include <roughnessmap_fragment>
  roughnessFactor = mix(roughnessFactor, 0.85, vBurn.x);`)
        .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
  {
    // cracks between the charred scales, glowing while the body is hot
    vec2 cu = vMapUv;
    float c1 = abs(sin(cu.y*9.0 + sin(cu.x*18.85)*1.3));
    float c2 = abs(sin(cu.x*12.57 + cu.y*3.1 + sin(cu.y*5.0)));
    float crack = smoothstep(0.24, 0.0, min(c1, c2));
    totalEmissiveRadiance += uEmber*vBurn.y*(0.03 + 0.8*crack);
    // prismatic light inside it (beam, leakage): a pale shimmer running with a rainbow
    vec3 hue = clamp(abs(fract(cu.y*0.35 + cu.x + uSnakeT*0.3 + vec3(0.0, 0.6667, 0.3333))*6.0 - 3.0) - 1.0, 0.0, 1.0);
    totalEmissiveRadiance += mix(vec3(1.0), hue, 0.6)*vBurn.z*vBurn.z*1.6;
  }`)
        .replace('#include <lights_fragment_end>', `#include <lights_fragment_end>
  {
    float rim = pow(1.0 - abs(dot(normalize(normal), normalize(vViewPosition))), 2.6);
    vec3 amb = reflectedLight.indirectDiffuse/max(diffuseColor.rgb, vec3(0.05)) + reflectedLight.directDiffuse/max(diffuseColor.rgb, vec3(0.05));
    reflectedLight.indirectSpecular += rim*amb*0.55*(1.0 - 0.85*vBurn.x);
  }`);
    };
    mat.customProgramCacheKey = () => 'snake_gi_rim_burn';
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
    g.setAttribute('aBurn', new THREE.BufferAttribute(new Float32Array(n*3), 3));
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
    const spine = [], radii = new Float32Array(RINGS);
    for (let i = 0; i < RINGS; i++) spine.push(new THREE.Vector3());
    return { m, eyes, spine, radii };
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
    s.burn = null; s.sag = 0; s.sink = -1; s.burnt = false;
    s.fx = null; s.leak = 0; s.claim = null;
    s.m.geometry.attributes.aBurn.array.fill(0); s.m.geometry.attributes.aBurn.needsUpdate = true;
  };
  for (let i = 0; i < count; i++) { const s = make_mesh(); spawn(s, i*1.6); S.push(s); }
  // gone (burst, shattered, dissolved, ...): out of sight until it comes back out of the dark
  const respawn = (s) => spawn(s, rng.float(RESPAWN[0], RESPAWN[1]));
  let reached = 0;
  const reach_log = [];               // tests: what each one that got through was doing

  const P = [], T = new THREE.Vector3(), Nn = new THREE.Vector3(), Bn = new THREE.Vector3(), UP = new THREE.Vector3(0, 1, 0);
  const RK = new Float32Array(RINGS), GL = new Float32Array(RINGS), SH = [0, 0, 0];
  for (let i = 0; i < RINGS; i++) P.push(new THREE.Vector3());

  function update(t, dt) {
    uSnakeT.value = t;
    for (const s of S) {
      if (s.delay > 0) { s.delay -= dt; s.m.visible = false; s.eyes.forEach(e => (e.visible = false)); continue; }
      const hide = !!(s.fx && s.fx.hide);
      s.m.visible = !hide; s.eyes.forEach(e => (e.visible = !hide));
      if (s.sink >= 0) {
        // the black corpse goes into the ground
        s.sink += dt;
        if (s.sink > SINK_T) { respawn(s); continue; }
      } else if (s.burn) {
        // on fire: it stops where it is; its neck sinks to the ground as it dies
        s.sag = Math.min(1, s.sag + dt/1.6);
        if (s.burn.done) { s.burn = null; s.burnt = true; s.sink = 0; build(s); fire.ash(s.spine, RINGS); }
      } else if (s.dying >= 0) {
        s.dying += dt;
        s.scale = clamp(1 - s.dying/0.5, 0, 1);
        if (s.dying > 0.5) respawn(s);
      } else if (s.fx) {
        // another power has it (lifted, blown, cut, pierced): that power moves it
        const r = s.fx.tick ? s.fx.tick(dt, s) : undefined;
        if (r === 'done') { respawn(s); continue; }
        if (r === 'free') s.fx = null;
      } else {
        // serpentine: steer at the egg, swinging the heading so the path is a steady S; a
        // dissolving snake (leakage) slows as it goes
        const sp = s.speed*(1 - 0.85*smoothstep(0, 0.8, s.leak));
        s.dist += sp*dt;
        const want = Math.atan2(egg.z - s.z, egg.x - s.x) + Math.sin(s.dist/s.wave*Math.PI*2 + s.phase)*s.amp;
        let d = want - s.dir; d = Math.atan2(Math.sin(d), Math.cos(d));
        s.dir += clamp(d, -5*dt, 5*dt);
        s.x += Math.cos(s.dir)*sp*dt; s.z += Math.sin(s.dir)*sp*dt;
        const last = s.trail[0];
        if (Math.hypot(s.x - last[0], s.z - last[1]) > 0.01) s.trail.unshift([s.x, s.z]);
        if (s.trail.length > 600) s.trail.length = 600;
        if (Math.hypot(s.x - egg.x, s.z - egg.z) < 1.1) { s.dying = 0; reached++; reach_log.push({ t: +t.toFixed(2), claim: s.claim, until: s.claim_until, leak: +s.leak.toFixed(2), speed: s.speed }); }   // it reached the egg (placeholder: it shrinks away)
      }
      if (s.leak >= 1.12 && !s.burn && s.sink < 0) { respawn(s); continue; }   // dissolved into nothing
      build(s);
    }
  }

  // the spine: points along the trail by arc length, the front raised into a neck curve
  function build(s) {
    let acc = 0, ti = 0;
    const sc = s.scale, fx = s.fx;
    // per ring: radius factor (cuts, dissolving, swelling) and prismatic glow
    const f = s.leak*1.12;
    for (let i = 0; i < RINGS; i++) {
      const u = (RINGS - 1 - i)/(RINGS - 1);                     // 0 at the tail: it dissolves tail first
      RK[i] = s.leak > 0 ? smoothstep(f, f + 0.12, u) : 1;
      GL[i] = s.leak > 0 ? Math.max(s.leak*0.45, Math.exp(-(((u - f)/0.07)**2))) : 0;
      if (fx) { if (fx.radk) RK[i] *= fx.radk(i); if (fx.glow) GL[i] = Math.max(GL[i], fx.glow(i)); }
    }
    for (let i = 0; i < RINGS; i++) {
      const target = S_AT(i);
      let x = s.trail[s.trail.length - 1][0], z = s.trail[s.trail.length - 1][1];
      while (ti < s.trail.length - 1) {
        const a = s.trail[ti], b = s.trail[ti + 1];
        const l = Math.hypot(b[0] - a[0], b[1] - a[1]);
        if (acc + l >= target) { const f = (target - acc)/(l || 1); x = a[0] + (b[0] - a[0])*f; z = a[1] + (b[1] - a[1])*f; break; }
        acc += l; ti++;
      }
      const r = R0*radius_at(target)*sc*RK[i];
      // the neck lifts the head: a smooth rise over the front RAISE_LEN metres (it sinks as a
      // burning snake dies); a sinking corpse goes down through the floor; other powers lift
      // and shift it
      let lift = RAISE*smoothstep(RAISE_LEN, 0.05, target)*sc*(1 - smoothstep(0, 1, s.sag));
      SH[0] = SH[1] = SH[2] = 0;
      if (fx) { if (fx.sag !== undefined) lift *= 1 - fx.sag; if (fx.lift) lift += fx.lift(i); if (fx.shift) fx.shift(i, SH); }
      P[i].set(x + SH[0], cave.ground_y(x, z) + R0*radius_at(target)*sc*flat_at(target) + lift + SH[1] - sink_depth(s), z + SH[2]);
      s.spine[i].copy(P[i]); s.radii[i] = r;
    }
    // how burnt each ring is, how its cracks glow, how it glows with prismatic light
    const glowing = s.leak > 0 || (fx && fx.glow);
    const charred = s.burn || s.burnt || (fx && fx.char);
    if (charred || glowing || s.fxw) {
      const ab = s.m.geometry.attributes.aBurn, a = ab.array;
      for (let i = 0; i < RINGS; i++) {
        let c = s.burn ? fire.char(s.burn, i) : s.burnt ? 1 : 0, e = s.burn ? fire.ember(s.burn, i) : 0;
        if (fx && fx.char) { c = Math.max(c, fx.char(i)); e = Math.max(e, fx.ember ? fx.ember(i) : 0); }
        for (let j = 0; j < SIDES; j++) { const o = (i*SIDES + j)*3; a[o] = c; a[o + 1] = e; a[o + 2] = GL[i]; }
      }
      const tip = RINGS*SIDES*3, last = (RINGS - 1)*SIDES*3;
      for (let k = 0; k < 3; k++) { a[tip + k] = a[k]; a[tip + 3 + k] = a[last + k]; }
      ab.needsUpdate = true;
      s.fxw = charred || glowing;                                // wrote something: clear it once the effect ends
    }
    const pos = s.m.geometry.attributes.position.array, nor = s.m.geometry.attributes.normal.array;
    for (let i = 0; i < RINGS; i++) {
      const a = P[Math.max(0, i - 1)], b = P[Math.min(RINGS - 1, i + 1)];
      T.subVectors(a, b).normalize();                             // pointing toward the head
      Bn.crossVectors(T, UP).normalize();                         // sideways
      Nn.crossVectors(Bn, T).normalize();                         // up, square to the body
      const target = S_AT(i);
      const r = R0*radius_at(target)*sc*RK[i], fl = flat_at(target);
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
    const tr = R0*0.25*sc*RK[0];
    pos[tip] = P[0].x + T.x*tr; pos[tip + 1] = P[0].y + T.y*tr; pos[tip + 2] = P[0].z + T.z*tr;
    nor[tip] = T.x; nor[tip + 1] = T.y; nor[tip + 2] = T.z;
    pos[end] = P[RINGS - 1].x; pos[end + 1] = P[RINGS - 1].y; pos[end + 2] = P[RINGS - 1].z;
    nor[end] = -T.x; nor[end + 1] = 0; nor[end + 2] = -T.z;
    s.m.geometry.attributes.position.needsUpdate = true;
    s.m.geometry.attributes.normal.needsUpdate = true;
    // eyes: on the sides of the head, a little up, near the front of the widest part
    const ei = Math.round(I_AT(0.055));
    const a = P[Math.max(0, ei - 1)], b = P[ei + 1];
    T.subVectors(a, b).normalize(); Bn.crossVectors(T, UP).normalize(); Nn.crossVectors(Bn, T).normalize();
    const rr = R0*radius_at(0.055)*sc*RK[ei];
    s.eyes.forEach((e, k) => {
      const side = k ? 1 : -1;
      e.position.copy(P[ei]).addScaledVector(Bn, side*rr*0.8).addScaledVector(Nn, rr*0.18);   // set into the side of the head
      e.scale.setScalar(R0*0.12*sc*RK[ei]);
    });
  }
  // set one on fire (the lich's attack): it stops, and burns from a point along its body
  function ignite(s, at = Math.round(RINGS*rng.float(0.15, 0.75))) {
    if (!free(s)) return false;
    at = Math.max(0, Math.min(RINGS - 1, at));
    s.burn = fire.start(RINGS, s.spine, s.radii, at);
    return true;
  }
  // give it to another power (lift, wind, beam, lens): `fx` drives it from now on (see build())
  function take(s, fx) { if (!free(s)) return false; s.fx = fx; return true; }
  // out of the dark and crawling (a dissolving one still counts)
  const free = s => s.delay <= 0 && s.dying < 0 && !s.burn && s.sink < 0 && !s.fx;
  const live = () => S.filter(free);
  function set_ember(c) { uEmber.value.setRGB(c[0], c[1], c[2]); }
  return { update, S, ignite, take, live, free, set_ember, respawn, RINGS, egg, reach_log, arc: S_AT, ring_at: I_AT, get reached() { return reached; } };
}
