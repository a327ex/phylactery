// fire.js -- the lich's first attack (round 9; owner: "A random snake is set on fire. It stops
// moving while on fire. The fire eventually stops, its blackened corpse goes into the ground as
// disappear effect.").
//
// A burn is a timeline over a body lying still: the flames spread from one point along it, burn,
// die down tail-first; the scales char black behind the flames, with cracks that glow and cool
// after the flames are gone; smoke keeps rising a little longer. snakes.js owns the body (it
// keeps `burn.spine` up to date and reads `burn.char(i)` / `burn.ember(i)` per ring); this file
// owns the particles (flames, sparks, smoke, ash) and a light per burn, lighting the rock and
// the lich like any other light (lights are pooled so their count never changes: a new light
// count would recompile every material).
//
// F cycles the fire's colour (LOOKS): natural, the lich's own prismatic fire, cold spectral fire.
import * as THREE from 'three';
import { make_rng, clamp, smoothstep, lerp } from 'game/util.js';
import { sprite_pool } from 'game/fx.js';

// timeline, seconds from ignition
export const BURN = {
  spread: 0.35,         // the flames run from the ignition point to both ends
  burn: 2.4,            // full fire until here
  die: 0.7,             // then dies down, tail first
  char: 1.3,            // a ring chars fully this long after its flames arrive
  cool: 1.0,            // the glowing cracks cool this long after the flames go
  smoke: 1.2,           // smoke rises this long after the flames go
};
BURN.out = BURN.burn + BURN.die;                  // no flames after this
BURN.end = BURN.out + Math.max(BURN.cool, BURN.smoke);   // the body is ready to sink

const LOOKS = [
  { name: 'NATURAL',
    ramp: [[1.0, 0.82, 0.42, 4.2], [1.0, 0.48, 0.09, 2.9], [0.85, 0.2, 0.035, 1.4], [0.3, 0.05, 0.015, 0.35]],
    light: [1.0, 0.52, 0.18], ember: [3.2, 0.75, 0.1], spark: [4.0, 2.4, 0.8], smoke: [0.011, 0.01, 0.009], prism: 0 },
  { name: 'THE LICH\'S (PRISMATIC)',
    ramp: [[1.0, 0.97, 0.95, 3.8], [0.85, 0.8, 1.0, 2.6], [0.7, 0.6, 1.0, 1.3], [0.4, 0.3, 0.6, 0.35]],
    light: [0.85, 0.8, 1.0], ember: [1.6, 1.0, 2.4], spark: [3.2, 3.0, 3.6], smoke: [0.01, 0.01, 0.012], prism: 1 },
  { name: 'SPECTRAL',
    ramp: [[0.85, 0.95, 1.0, 3.8], [0.35, 0.65, 1.0, 2.6], [0.2, 0.3, 1.0, 1.3], [0.15, 0.1, 0.5, 0.35]],
    light: [0.45, 0.65, 1.0], ember: [0.5, 1.2, 3.2], spark: [2.0, 3.2, 4.0], smoke: [0.009, 0.01, 0.012], prism: 0 },
];

const spectrum = (h) => { h = ((h % 1) + 1) % 1; const c = [0, 2/3, 1/3].map(o => clamp(Math.abs(((h + o) % 1)*6 - 3) - 1, 0, 1)); return c; };

export function create_fire(R, cave, seed = 13) {
  const rng = make_rng(seed);
  const flames = sprite_pool(R, 900, true, 'flame');
  const sparks = sprite_pool(R, 160, true, 'dot');
  const smoke = sprite_pool(R, 320, false, 'dot');
  const LIGHTS = [0, 1, 2, 3].map(() => {
    const l = new THREE.PointLight(0xffffff, 0, 7, 2);
    l.castShadow = false;
    R.world_scene.add(l);
    return { l, burn: null };
  });
  let look = 0;
  const burns = [];

  // a burn over a body of `rings` spine points: `burn.spine[i]` (Vector3, world) and `burn.r[i]`
  // (radius, m) are kept current by the caller
  function start(rings, spine, radii, ignite_at) {
    const b = { t: 0, rings, spine, r: radii, at: ignite_at, acc: 0, sacc: 0, kacc: 0, light: null, done: false, flash: 1 };
    const free = LIGHTS.find(L => !L.burn) || LIGHTS.reduce((a, L) => (L.burn.t > a.burn.t ? L : a));
    if (free.burn) free.burn.light = null;
    free.burn = b; b.light = free;
    // the ignition: a burst of flame and sparks at the point it catches
    const p0 = spine[ignite_at];
    for (let k = 0; k < 10; k++) emit_flame(b, ignite_at, 1.3);
    for (let k = 0; k < 14; k++) emit_spark(p0, 1.3);
    burns.push(b);
    return b;
  }

  // where along the body the flames are, 0..1 per ring (spread from the ignition point, then
  // dying down from the tail)
  function flame_at(b, i) {
    const d = Math.abs(i - b.at)/b.rings;                     // body fractions from the ignition
    const arrive = d*BURN.spread/0.6;
    if (b.t < arrive) return 0;
    const up = smoothstep(arrive, arrive + 0.12, b.t);
    const die_start = BURN.burn + (1 - i/(b.rings - 1))*BURN.die*0.6;   // the tail goes first
    const down = 1 - smoothstep(die_start, die_start + BURN.die*0.4, b.t);
    return up*down;
  }
  const arrive_t = (b, i) => Math.abs(i - b.at)/b.rings*BURN.spread/0.6;

  function emit_flame(b, i, boost = 1) {
    const p = flames.spawn(), c = b.spine[i], r = b.r[i];
    const a = rng.float(0, Math.PI*2);
    p.x = c.x + Math.cos(a)*r*0.8; p.z = c.z + Math.sin(a)*r*0.8; p.y = c.y + r*rng.float(0.2, 0.9);
    p.vx = rng.spread(0.18)*boost; p.vz = rng.spread(0.18)*boost; p.vy = rng.float(0.55, 1.15)*boost;
    p.max = p.life = rng.float(0.34, 0.66)*(boost > 1 ? 1.2 : 1);
    p.s0 = rng.float(0.12, 0.24)*(boost > 1 ? 1.35 : 1); p.s1 = p.s0*0.3;
    p.h = rng.next();
  }
  function emit_spark(c, boost = 1) {
    const p = sparks.spawn();
    p.x = c.x + rng.spread(0.1); p.y = c.y + 0.05; p.z = c.z + rng.spread(0.1);
    p.vx = rng.spread(0.9)*boost; p.vz = rng.spread(0.9)*boost; p.vy = rng.float(1.2, 2.6)*boost;
    p.max = p.life = rng.float(0.45, 1.0); p.s0 = 0.035; p.s1 = 0.02; p.h = rng.next();
  }
  function emit_smoke(c, r, k = 1, lit = 0) {
    const p = smoke.spawn();
    p.lit = lit;
    p.x = c.x + rng.spread(r); p.y = c.y + r*0.8 + rng.float(0.05, 0.3); p.z = c.z + rng.spread(r);
    p.vx = rng.spread(0.08); p.vz = rng.spread(0.08); p.vy = rng.float(0.35, 0.6);
    p.max = p.life = rng.float(1.4, 2.4); p.s0 = rng.float(0.25, 0.4)*k; p.s1 = p.s0*rng.float(2.0, 2.8); p.h = rng.next();
  }
  // the corpse going into the ground: a low ring of ash and grit
  function ash(spine, rings) {
    for (let k = 0; k < 40; k++) {
      const i = rng.int(0, rings - 1), c = spine[i];
      const p = smoke.spawn();
      p.x = c.x + rng.spread(0.12); p.y = c.y; p.z = c.z + rng.spread(0.12);
      p.vx = rng.spread(0.35); p.vz = rng.spread(0.35); p.vy = rng.float(0.05, 0.3);
      p.max = p.life = rng.float(0.6, 1.1); p.s0 = rng.float(0.1, 0.2); p.s1 = p.s0*2.2; p.h = -1; p.lit = 0;   // h < 0: grit coloured
    }
  }

  function update(t, dt) {
    const L = LOOKS[look];
    for (let bi = burns.length - 1; bi >= 0; bi--) {
      const b = burns[bi];
      b.t += dt;
      // flames: about 110 a second along a whole burning body, where the fire is
      let lit = 0;
      for (let i = 0; i < b.rings; i++) lit += flame_at(b, i);
      const frac = lit/b.rings;
      b.acc += 170*frac*dt;
      while (b.acc >= 1) {
        b.acc -= 1;
        // pick a ring weighted by its flame
        let i = 0;
        for (let tries = 0; tries < 8; tries++) { i = rng.int(0, b.rings - 1); if (rng.next() < flame_at(b, i)) break; }
        if (flame_at(b, i) > 0.05) emit_flame(b, i);
      }
      b.kacc += 7*frac*dt;
      while (b.kacc >= 1) { b.kacc -= 1; const i = rng.int(0, b.rings - 1); if (flame_at(b, i) > 0.3) emit_spark(b.spine[i]); }
      // smoke: through the fire and a little after, thinning out
      const smoky = b.t < BURN.out ? 0.5 + 0.5*frac : 1 - smoothstep(BURN.out, BURN.out + BURN.smoke, b.t);
      b.sacc += 16*smoky*dt;
      while (b.sacc >= 1) { b.sacc -= 1; const i = rng.int(0, b.rings - 1); emit_smoke(b.spine[i], b.r[i], b.t < BURN.out ? 1 : 0.7, b.t < BURN.out ? frac : 0); }
      // the light: at the body's burning middle, flickering, a flash when it catches
      if (b.light) {
        let cx = 0, cy = 0, cz = 0, w = 0;
        for (let i = 0; i < b.rings; i += 4) { const f = flame_at(b, i) + 1e-3; cx += b.spine[i].x*f; cy += b.spine[i].y*f; cz += b.spine[i].z*f; w += f; }
        const l = b.light.l;
        l.position.set(cx/w, cy/w + 0.35, cz/w);
        b.flash = Math.max(0, b.flash - dt*3.5);
        const flick = 0.82 + 0.1*Math.sin(t*23 + bi) + 0.08*Math.sin(t*37.3 + bi*2.1) + rng.spread(0.05);
        l.color.setRGB(...L.light);
        l.intensity = 3.2*frac*flick*(1 + 1.2*b.flash);
      }
      if (b.t > BURN.end) {
        if (b.light) { b.light.l.intensity = 0; b.light.burn = null; b.light = null; }
        b.done = true;
        burns.splice(bi, 1);
      }
    }

    // particles
    flames.write((p, i, pos, col, size) => {
      p.life -= dt;
      const u = 1 - p.life/p.max;                     // 0 born .. 1 gone
      p.vx += Math.sin(t*9 + p.h*40)*0.6*dt; p.vz += Math.cos(t*8 + p.h*33)*0.6*dt; p.vy += 0.5*dt;   // buoyant, a little turbulent
      p.x += p.vx*dt; p.y += p.vy*dt; p.z += p.vz*dt;
      pos[i*3] = p.x; pos[i*3 + 1] = p.y; pos[i*3 + 2] = p.z;
      // colour down the ramp: core -> body -> tip -> gone
      const k = Math.min(2.999, u*3), j = Math.floor(k), f = k - j, a = L.ramp[j], b = L.ramp[j + 1];
      let r = lerp(a[0], b[0], f), g = lerp(a[1], b[1], f), bl = lerp(a[2], b[2], f), e = lerp(a[3], b[3], f);
      if (L.prism) { const s = spectrum(p.h + t*0.15); const m = 0.45*smoothstep(0.1, 0.6, u); r = lerp(r, s[0], m); g = lerp(g, s[1], m); bl = lerp(bl, s[2], m); }
      const fade = smoothstep(0, 0.12, u)*(1 - smoothstep(0.7, 1, u));
      col[i*4] = r*e; col[i*4 + 1] = g*e; col[i*4 + 2] = bl*e; col[i*4 + 3] = fade;
      size[i] = lerp(p.s0, p.s1, u);
    });
    sparks.write((p, i, pos, col, size) => {
      p.life -= dt;
      const u = 1 - p.life/p.max;
      p.vy -= 1.6*dt; p.vx *= 1 - 0.8*dt; p.vz *= 1 - 0.8*dt;
      p.x += p.vx*dt; p.y += p.vy*dt; p.z += p.vz*dt;
      pos[i*3] = p.x; pos[i*3 + 1] = p.y; pos[i*3 + 2] = p.z;
      const tw = 0.6 + 0.4*Math.sin(t*50 + p.h*90);
      let c = L.spark;
      if (L.prism) { const s = spectrum(p.h); c = [lerp(c[0], s[0]*4, 0.5), lerp(c[1], s[1]*4, 0.5), lerp(c[2], s[2]*4, 0.5)]; }
      col[i*4] = c[0]; col[i*4 + 1] = c[1]; col[i*4 + 2] = c[2]; col[i*4 + 3] = tw*(1 - u*u);
      size[i] = lerp(p.s0, p.s1, u);
    });
    smoke.write((p, i, pos, col, size) => {
      p.life -= dt;
      const u = 1 - p.life/p.max;
      p.vy *= 1 - 0.35*dt; p.vx += Math.sin(t*1.7 + p.h*20)*0.08*dt;
      p.x += p.vx*dt; p.y += p.vy*dt; p.z += p.vz*dt;
      pos[i*3] = p.x; pos[i*3 + 1] = p.y; pos[i*3 + 2] = p.z;
      // dark, as smoke is where nothing lights it; warmed by the flames it leaves while young
      const c = p.h < 0 ? [0.016, 0.014, 0.011] : L.smoke, w = (p.lit || 0)*0.07*(1 - u)*(1 - u);
      col[i*4] = c[0] + L.light[0]*w; col[i*4 + 1] = c[1] + L.light[1]*w; col[i*4 + 2] = c[2] + L.light[2]*w;
      col[i*4 + 3] = (p.h < 0 ? 0.55 : 0.4)*smoothstep(0, 0.15, u)*(1 - smoothstep(0.45, 1, u));
      size[i] = lerp(p.s0, p.s1, u);
    });
  }

  // before each render: how many pixels one metre at one metre spans (the sprites' size)
  function set_camera(cam, H) {
    const s = cam.projectionMatrix.elements[5]*H*0.5;
    flames.mat.uniforms.uScale.value = s; sparks.mat.uniforms.uScale.value = s; smoke.mat.uniforms.uScale.value = s;
  }

  return {
    start, update, set_camera, ash, LOOKS, BURN,
    get look() { return look; },
    set look(i) { look = ((i % LOOKS.length) + LOOKS.length) % LOOKS.length; },
    // per ring: how burnt (0..1) and how brightly its cracks glow (0..1)
    char(b, i) { const a = arrive_t(b, i); return smoothstep(a, a + BURN.char, b.t); },
    ember(b, i) {
      const a = arrive_t(b, i);
      const on = smoothstep(a + 0.15, a + 0.7, b.t);
      const off = 1 - smoothstep(BURN.out - 0.2, BURN.out + BURN.cool, b.t);
      return on*off;
    },
    flame_at,
    ember_colour: () => LOOKS[look].ember,
    get burning() { return burns.length; },
  };
}
