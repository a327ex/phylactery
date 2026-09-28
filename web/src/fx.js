// fx.js -- the effects the powers share (round 11): point sprites (flames, glowing motes, shards,
// dust and mist), beams drawn as screen-space ribbons (so a beam is never thinner than its
// pixel width, near or far), and chunks of snake that fall, bounce and sink.
//
// Everything is pooled: a pool is allocated once and recycled, so nothing is created while
// playing. Particles are simple: position, velocity, gravity, drag, a colour (HDR for the
// additive ones, which the bloom picks up), a size going s0 -> s1 over the life.
import * as THREE from 'three';
import { clamp, smoothstep, lerp } from 'game/util.js';
import { gi_dynamic } from 'game/gi.js';

export const spectrum = (h) => { h = ((h % 1) + 1) % 1; return [0, 2/3, 1/3].map(o => clamp(Math.abs(((h + o) % 1)*6 - 3) - 1, 0, 1)); };

// a pool of point sprites: `additive` for light (flames, sparks, motes), otherwise
// alpha-blended (smoke, dust, mist). shape: 'flame' (a tongue), 'shard' (a sliver), or a soft dot
export function sprite_pool(R, N, additive, shape) {
  const pos = new Float32Array(N*3), col = new Float32Array(N*4), size = new Float32Array(N);
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('aCol', new THREE.BufferAttribute(col, 4));
  g.setAttribute('aSize', new THREE.BufferAttribute(size, 1));
  const body = shape === 'flame'
    // a tongue: round below, narrowing upward
    ? `float w = 1.0 - 0.55*clamp(q.y, 0.0, 1.0); float d = length(vec2(q.x/w, q.y*0.8 + 0.12)); float a = smoothstep(1.0, 0.25, d);`
    : shape === 'shard'
    // a thin diamond sliver
    ? `float d = abs(q.x)*2.6 + abs(q.y); float a = smoothstep(1.0, 0.55, d);`
    : `float d = length(q); float a = smoothstep(1.0, 0.1, d);`;
  const mat = new THREE.ShaderMaterial({
    uniforms: { uScale: { value: 1 } },
    vertexShader: `attribute vec4 aCol; attribute float aSize; uniform float uScale; varying vec4 vCol;
      void main(){ vec4 mv = modelViewMatrix*vec4(position, 1.0); gl_Position = projectionMatrix*mv;
        gl_PointSize = aSize > 0.0 ? max(1.0, aSize*uScale/max(-mv.z, 0.05)) : 0.0; vCol = aCol; }`,
    fragmentShader: `varying vec4 vCol;
      void main(){ vec2 q = gl_PointCoord*2.0 - 1.0; q.y = -q.y;
        ${body}
        ${additive ? `gl_FragColor = vec4(vCol.rgb*vCol.a*a, 1.0);` : `gl_FragColor = vec4(vCol.rgb, vCol.a*a);`} }`,
    transparent: true, depthWrite: false, depthTest: true,
    blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
  });
  const pts = new THREE.Points(g, mat);
  pts.frustumCulled = false;
  pts.renderOrder = additive ? 11 : 10;
  R.world_scene.add(pts);
  const P = [];
  for (let i = 0; i < N; i++) P.push({ life: 0, max: 1, x: 0, y: 0, z: 0, vx: 0, vy: 0, vz: 0, s0: 0, s1: 0, h: 0, kind: 0, burn: null });
  let next = 0;
  return {
    mat, P,
    spawn() { const p = P[next]; next = (next + 1) % N; return p; },
    write(fn) {
      for (let i = 0; i < N; i++) {
        const p = P[i];
        if (p.life <= 0) { size[i] = 0; col[i*4 + 3] = 0; continue; }
        fn(p, i, pos, col, size);
      }
      g.attributes.position.needsUpdate = true; g.attributes.aCol.needsUpdate = true; g.attributes.aSize.needsUpdate = true;
    },
  };
}

// beams: segments drawn as camera-facing ribbons. Round 12 (owner's references: Diablo 3's
// Disintegrate, real light through a prism, Risk of Rain 2's Stone Titan, Returnal's Phrike):
// a ribbon has a width in metres at each end (w0 at p0, w1 at p1; never thinner than `w` px)
// and a style for its cross-section:
//   0 plain: the colour c, brightest along the middle (a pixel width, as before)
//   1 PRISM: white light leaving p0 and dispersing along the way into an ordered band, red on
//     one edge to violet on the other, soft-edged, a thin white core fading out as it spreads
//   2 FIRE LASER: a white-hot core in an orange sheath and a red glow, noise streaming along it
//     toward p1 and a constant flicker
//   3 PRISM IN FIRE: style 1's build in fire colours (white core, yellow, orange, red edges)
// Energy streams along styles 1-3 from p0 to p1. `held` ribbons are kept alive and faded by
// their owner (set `a` each tick); others live `life` seconds.
function ribbon_pool(R, N) {
  const V = N*4;
  const a0 = new Float32Array(V*3), a1 = new Float32Array(V*3), end = new Float32Array(V), side = new Float32Array(V);
  const col = new Float32Array(V*4), wo = new Float32Array(V*3), bb = new Float32Array(V*4);
  for (let i = 0; i < N; i++) for (let k = 0; k < 4; k++) { end[i*4 + k] = k >> 1; side[i*4 + k] = (k & 1) ? 1 : -1; }
  const idx = [];
  for (let i = 0; i < N; i++) { const b = i*4; idx.push(b, b + 1, b + 3, b, b + 3, b + 2); }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(V*3), 3));
  g.setAttribute('aP0', new THREE.BufferAttribute(a0, 3));
  g.setAttribute('aP1', new THREE.BufferAttribute(a1, 3));
  g.setAttribute('aEnd', new THREE.BufferAttribute(end, 1));
  g.setAttribute('aSide', new THREE.BufferAttribute(side, 1));
  g.setAttribute('aCol', new THREE.BufferAttribute(col, 4));
  g.setAttribute('aWO', new THREE.BufferAttribute(wo, 3));          // min width px, offset px, hue (<0: none)
  g.setAttribute('aB', new THREE.BufferAttribute(bb, 4));           // w0 m, w1 m, style, length m
  g.setIndex(idx);
  const mat = new THREE.ShaderMaterial({
    uniforms: { uRes: { value: new THREE.Vector2(640, 360) }, uTime: { value: 0 }, uProj: { value: 400 } },
    vertexShader: `attribute vec3 aP0, aP1, aWO; attribute float aEnd, aSide; attribute vec4 aCol, aB;
      uniform vec2 uRes; uniform float uProj; varying vec4 vCol; varying float vSide, vAlong, vHue, vStyle, vLen;
      void main(){
        vec4 c0 = projectionMatrix*viewMatrix*vec4(aP0, 1.0), c1 = projectionMatrix*viewMatrix*vec4(aP1, 1.0);
        vec4 c = aEnd > 0.5 ? c1 : c0;
        vec2 s0 = c0.xy/max(c0.w, 1e-3), s1 = c1.xy/max(c1.w, 1e-3);
        vec2 d = (s1 - s0)*uRes; d = length(d) > 1e-4 ? normalize(d) : vec2(1.0, 0.0);
        vec2 n = vec2(-d.y, d.x);
        float px = aB.z > 0.5 ? max(aWO.x, mix(aB.x, aB.y, aEnd)*uProj/max(c.w, 0.05)) : aWO.x;
        c.xy += n*(aSide*px*0.5 + aWO.y)*2.0/uRes*c.w;
        gl_Position = c; vCol = aCol; vSide = aSide; vAlong = aEnd; vHue = aWO.z; vStyle = aB.z; vLen = aB.w; }`,
    fragmentShader: `uniform float uTime; varying vec4 vCol; varying float vSide, vAlong, vHue, vStyle, vLen;
      vec3 spec(float h){ return clamp(abs(fract(h + vec3(0.0, 0.6667, 0.3333))*6.0 - 3.0) - 1.0, 0.0, 1.0); }
      float h1(float x){ return fract(sin(x*127.1)*43758.5453); }
      float n1(float x){ float i = floor(x), f = fract(x); return mix(h1(i), h1(i + 1.0), f*f*(3.0 - 2.0*f)); }
      void main(){
        float a = abs(vSide);
        vec3 c;
        if (vStyle < 0.5) {
          float k = 1.0 - a; k = k*k*(3.0 - 2.0*k);
          c = vCol.rgb*k;
          if (vHue >= 0.0) c *= mix(vec3(1.0), spec(vHue + vAlong*0.6 - uTime*1.5), 0.75);
        } else {
          // energy streaming from p0 to p1: bands of brightness, in metres along the beam
          float x = vAlong*vLen;
          float flow = 0.72 + 0.28*n1(x*3.0 - uTime*26.0) + 0.12*n1(x*9.0 - uTime*47.0);
          if (vStyle < 1.5 || vStyle > 2.5) {
            // the prism: dispersed further along (after the first ~35 cm it is a band)
            float disp = smoothstep(0.0, 0.35, x)*0.85 + 0.15;
            float edge = smoothstep(1.0, 0.72, a);
            float u = vSide*0.5 + 0.5;
            vec3 band = vStyle < 1.5
              ? mix(spec(u*0.76), vec3(1.0), 0.04)*(0.8 + 0.5*exp(-pow((u - 0.35)/0.3, 2.0)))
              : mix(vec3(1.0, 0.18, 0.04), mix(vec3(1.0, 0.62, 0.12), vec3(1.0, 0.95, 0.7), smoothstep(0.35, 0.0, a)), smoothstep(0.95, 0.4, a));
            float core = exp(-pow(vSide/mix(0.55, 0.12, disp), 2.0));
            c = band*edge*disp*2.1 + vec3(1.0)*core*(2.4 - 2.0*disp);          // the white core gives way to the band as it spreads
            c *= flow;
          } else {
            // the fire laser: a white core, an orange sheath, a red glow; noise eating its edges
            float wob = 0.12*(n1(x*5.0 - uTime*30.0) - 0.5);
            float aa = clamp(a + wob, 0.0, 1.0);
            vec3 sheath = mix(vec3(1.0, 0.42, 0.08), vec3(1.0, 0.12, 0.03), smoothstep(0.35, 0.85, aa));
            c = mix(vec3(1.0, 0.95, 0.82)*3.0, sheath*1.7, smoothstep(0.08, 0.32, aa))*smoothstep(1.0, 0.55, aa);
            c *= flow;
          }
          c *= vCol.rgb;
        }
        gl_FragColor = vec4(c*vCol.a, 1.0); }`,
    transparent: true, depthWrite: false, depthTest: true, blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
  });
  const mesh = new THREE.Mesh(g, mat);
  mesh.frustumCulled = false; mesh.renderOrder = 12;
  R.world_scene.add(mesh);
  const B = [];
  for (let i = 0; i < N; i++) B.push({ life: 0, max: 1, p0: new THREE.Vector3(), p1: new THREE.Vector3(), c: [1, 1, 1], w: 2, off: 0, hue: -1, a: 1, fade_in: 0.03, held: false, style: 0, w0: 0, w1: 0 });
  let next = 0;
  return {
    mat,
    spawn(p0, p1, o) {
      // held ribbons (kept alive by their owner) are skipped
      for (let k = 0; k < N && (B[next].held || B[next].life > 5); k++) next = (next + 1) % N;
      const b = B[next]; next = (next + 1) % N;
      b.p0.copy(p0); b.p1.copy(p1); b.c = o.c || [1, 1, 1]; b.w = o.w ?? 1.5; b.off = o.off || 0; b.hue = o.hue ?? -1; b.a = o.a ?? 1;
      b.max = b.life = o.life ?? 1; b.fade_in = o.fade_in ?? 0.03; b.held = !!o.held; b.style = o.style || 0; b.w0 = o.w0 || 0; b.w1 = o.w1 ?? b.w0;
      return b;
    },
    release(b) { b.held = false; b.life = 0; },
    update(t, dt) {
      mat.uniforms.uTime.value = t;
      for (let i = 0; i < N; i++) {
        const b = B[i];
        if (!b.held && b.life > 0) b.life -= dt;
        const on = b.held || b.life > 0, u = b.held ? 0.5 : 1 - b.life/b.max;
        const al = !on ? 0 : b.held ? b.a : b.a*smoothstep(0, b.fade_in/b.max, u)*(1 - smoothstep(0.5, 1, u));
        const len = b.p0.distanceTo(b.p1);
        for (let k = 0; k < 4; k++) {
          const v = i*4 + k;
          a0[v*3] = b.p0.x; a0[v*3 + 1] = b.p0.y; a0[v*3 + 2] = b.p0.z;
          a1[v*3] = b.p1.x; a1[v*3 + 1] = b.p1.y; a1[v*3 + 2] = b.p1.z;
          col[v*4] = b.c[0]; col[v*4 + 1] = b.c[1]; col[v*4 + 2] = b.c[2]; col[v*4 + 3] = al;
          wo[v*3] = on ? b.w : 0; wo[v*3 + 1] = b.off; wo[v*3 + 2] = b.hue;
          bb[v*4] = on ? b.w0 : 0; bb[v*4 + 1] = on ? b.w1 : 0; bb[v*4 + 2] = b.style; bb[v*4 + 3] = len;
        }
      }
      for (const k of ['aP0', 'aP1', 'aCol', 'aWO', 'aB']) g.attributes[k].needsUpdate = true;
    },
  };
}

// chunks of a burst snake: small dark lumps with the snake's colour, thrown, bouncing once or
// twice on the floor, then sinking into it
function chunk_pool(R, cave, N) {
  const geo = new THREE.IcosahedronGeometry(1, 0);
  const mat = new THREE.MeshStandardMaterial({ color: 0x3a3629, roughness: 0.45, metalness: 0, flatShading: true });
  if (cave.GU) gi_dynamic(mat, cave.GU);
  const mesh = new THREE.InstancedMesh(geo, mat, N);
  mesh.castShadow = true; mesh.receiveShadow = true; mesh.frustumCulled = false;
  R.world_scene.add(mesh);
  const C = [], M = new THREE.Matrix4(), Q = new THREE.Quaternion(), E = new THREE.Euler(), V = new THREE.Vector3(), Sc = new THREE.Vector3();
  for (let i = 0; i < N; i++) C.push({ life: 0, x: 0, y: 0, z: 0, vx: 0, vy: 0, vz: 0, rx: 0, ry: 0, rz: 0, wx: 0, wy: 0, wz: 0, s: 0, sink: 0, sx: 1, sy: 1, sz: 1, rest: 0 });
  let next = 0;
  const zero = new THREE.Matrix4().makeScale(0, 0, 0);
  for (let i = 0; i < N; i++) mesh.setMatrixAt(i, zero);
  return {
    spawn() { const c = C[next]; next = (next + 1) % N; c.sink = 0; c.rest = 0; return c; },
    update(dt) {
      for (let i = 0; i < N; i++) {
        const c = C[i];
        if (c.life <= 0) { mesh.setMatrixAt(i, zero); continue; }
        c.life -= dt;
        const gy = cave.ground_y(c.x, c.z);
        if (c.rest <= 0) {
          c.vy -= 9.8*dt;
          c.x += c.vx*dt; c.y += c.vy*dt; c.z += c.vz*dt;
          c.rx += c.wx*dt; c.ry += c.wy*dt; c.rz += c.wz*dt;
          if (c.y < gy + c.s*0.5) {
            c.y = gy + c.s*0.5;
            if (Math.abs(c.vy) < 1.2) { c.rest = 1e-3; c.vx = c.vz = c.vy = 0; }
            else { c.vy = -c.vy*0.28; c.vx *= 0.55; c.vz *= 0.55; c.wx *= 0.5; c.wy *= 0.5; c.wz *= 0.5; }
          }
        } else {
          // lying still, then going into the ground with the rest of it
          c.rest += dt;
          if (c.rest > 1.4) c.y -= 0.12*dt;
        }
        E.set(c.rx, c.ry, c.rz); Q.setFromEuler(E);
        const k = c.life < 0.4 ? c.life/0.4 : 1;
        M.compose(V.set(c.x, c.y, c.z), Q, Sc.set(c.s*c.sx*k, c.s*c.sy*k, c.s*c.sz*k));
        mesh.setMatrixAt(i, M);
      }
      mesh.instanceMatrix.needsUpdate = true;
    },
  };
}

// the particles every power uses: `motes` (additive dots: sparks, prismatic motes), `shards`
// (additive slivers), `puffs` (alpha: dust, ash, mist), plus ribbons and chunks.
// Each particle: x y z, vx vy vz, grav (m/s^2 down), drag (1/s), s0 -> s1 size, r g b (HDR for
// the additive pools), a (peak alpha), hue (>= 0: tinted by a rainbow drifting at hr per second),
// floor (true: stops on the ground).
export function create_fx(R, cave) {
  const motes = sprite_pool(R, 1600, true, 'dot');
  const shards = sprite_pool(R, 400, true, 'shard');
  const puffs = sprite_pool(R, 600, false, 'dot');
  const ribbons = ribbon_pool(R, 160);
  const chunks = chunk_pool(R, cave, 160);
  const init = (p, o) => {
    p.x = o.x; p.y = o.y; p.z = o.z; p.vx = o.vx || 0; p.vy = o.vy || 0; p.vz = o.vz || 0;
    p.max = p.life = o.life; p.s0 = o.s0; p.s1 = o.s1 ?? o.s0; p.r = o.r; p.g = o.g; p.b = o.b; p.a = o.a ?? 1;
    p.grav = o.grav || 0; p.drag = o.drag || 0; p.hue = o.hue ?? -1; p.hr = o.hr || 0; p.floor = !!o.floor; p.fin = o.fin ?? 0.1;
    return p;
  };
  const step = (t, dt) => (p, i, pos, col, size) => {
    p.life -= dt;
    const u = 1 - p.life/p.max;
    p.vy -= p.grav*dt;
    const d = 1 - p.drag*dt; p.vx *= d; p.vy *= d; p.vz *= d;
    p.x += p.vx*dt; p.y += p.vy*dt; p.z += p.vz*dt;
    if (p.floor) { const gy = cave.ground_y(p.x, p.z) + 0.02; if (p.y < gy) { p.y = gy; p.vy = 0; p.vx *= 0.5; p.vz *= 0.5; } }
    pos[i*3] = p.x; pos[i*3 + 1] = p.y; pos[i*3 + 2] = p.z;
    let r = p.r, g = p.g, b = p.b;
    if (p.hue >= 0) { const s = spectrum(p.hue + t*p.hr); r *= 0.35 + 0.65*s[0]*1.4; g *= 0.35 + 0.65*s[1]*1.4; b *= 0.35 + 0.65*s[2]*1.4; }
    col[i*4] = r; col[i*4 + 1] = g; col[i*4 + 2] = b;
    col[i*4 + 3] = p.a*smoothstep(0, p.fin, u)*(1 - smoothstep(0.55, 1, u));
    size[i] = lerp(p.s0, p.s1, u);
  };
  return {
    mote: (o) => init(motes.spawn(), o),
    shard: (o) => init(shards.spawn(), o),
    puff: (o) => init(puffs.spawn(), o),
    ribbon: (p0, p1, o) => ribbons.spawn(p0, p1, o),
    release: (b) => ribbons.release(b),
    chunk: () => chunks.spawn(),
    update(t, dt) {
      const f = step(t, dt);
      motes.write(f); shards.write(f); puffs.write(f);
      ribbons.update(t, dt);
      chunks.update(dt);
    },
    set_camera(cam, H) {
      const s = cam.projectionMatrix.elements[5]*H*0.5;
      motes.mat.uniforms.uScale.value = s; shards.mat.uniforms.uScale.value = s; puffs.mat.uniforms.uScale.value = s;
      ribbons.mat.uniforms.uProj.value = s;
    },
  };
}
