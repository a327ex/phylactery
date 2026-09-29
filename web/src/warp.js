// warp.js -- things that bend the light behind them (round 23, owner: "The general way you've done
// the prismatic effect is with glitter-like dot particles. I'd [like] this effect to feel more
// like wind visually. You know wind is portrayed visually sometimes as a kind of transparent
// slight warping of things?").
//
// Nothing here is drawn as colour: each piece writes, into R.warp_scene's target, how far (in
// screen pixels) the world behind it is shifted and how far apart its three colour channels are
// pulled (render.js bends the world image by it in the final pass). So a streak reads as a clear
// rippling line through which the cave wobbles, with rainbow fringes at its edges: the lich's
// prism as air. Each fragment is tested against the world's depth, so rock in front hides it.
//   streaks  polylines of K points the owner moves each tick (wind lines, rings on the floor):
//            across them the background is pushed out on one side and in on the other, like a
//            thin lens; ripples run along them
//   puffs    rising, spreading, swirling blobs (smoke made of warped air)
import * as THREE from 'three';
import { smoothstep } from 'game/util.js';

export const K = 24;                  // points in a streak

const DECL = /* glsl */`
uniform vec2 uRes; uniform float uProj, uTime; uniform sampler2D tDepth;
uniform float uNoDepth;
bool hidden(){ return uNoDepth < 0.5 && gl_FragCoord.z > texture2D(tDepth, gl_FragCoord.xy/uRes).x + 1e-6; }
float h1(float x){ return fract(sin(x*127.1)*43758.5453); }
float n1(float x){ float i = floor(x), f = fract(x); return mix(h1(i), h1(i + 1.0), f*f*(3.0 - 2.0*f)); }`;

// additive, signed: the shifts of overlapping pieces add up
const blend = { transparent: true, depthWrite: false, depthTest: false, side: THREE.DoubleSide, blending: THREE.CustomBlending,
  blendSrc: THREE.OneFactor, blendDst: THREE.OneFactor, blendSrcAlpha: THREE.OneFactor, blendDstAlpha: THREE.OneFactor, blendEquation: THREE.AddEquation };

export function create_warp(R) {
  const U = { uRes: { value: new THREE.Vector2(R.W, R.H) }, uProj: { value: 400 }, uTime: { value: 0 }, tDepth: { value: R.targets.rt_world.depthTexture }, uNoDepth: { value: 0 } };

  // ---------------------------------------------------------------- streaks
  const NS = 64, NV = NS*K*2;
  const pos = new Float32Array(NV*3), prv = new Float32Array(NV*3), nxt = new Float32Array(NV*3);
  const side = new Float32Array(NV), along = new Float32Array(NV), prm = new Float32Array(NV*4), fade = new Float32Array(NV);
  for (let s = 0; s < NS; s++) for (let k = 0; k < K; k++) for (let e = 0; e < 2; e++) { const v = (s*K + k)*2 + e; side[v] = e ? 1 : -1; along[v] = k/(K - 1); }
  const idx = [];
  for (let s = 0; s < NS; s++) for (let k = 0; k < K - 1; k++) { const a = (s*K + k)*2; idx.push(a, a + 1, a + 3, a, a + 3, a + 2); }
  const sg = new THREE.BufferGeometry();
  sg.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  sg.setAttribute('aPrev', new THREE.BufferAttribute(prv, 3));
  sg.setAttribute('aNext', new THREE.BufferAttribute(nxt, 3));
  sg.setAttribute('aSide', new THREE.BufferAttribute(side, 1));
  sg.setAttribute('aU', new THREE.BufferAttribute(along, 1));
  sg.setAttribute('aP', new THREE.BufferAttribute(prm, 4));          // width m, amp px, chroma, phase
  sg.setAttribute('aA', new THREE.BufferAttribute(fade, 1));
  sg.setIndex(idx);
  const smat = new THREE.ShaderMaterial({
    uniforms: U, ...blend,
    vertexShader: `attribute vec3 aPrev, aNext; attribute float aSide, aU, aA; attribute vec4 aP;
      uniform vec2 uRes; uniform float uProj;
      varying float vSide, vU, vA, vAmp, vCh, vPh; varying vec2 vN, vT;
      void main(){
        mat4 PV = projectionMatrix*viewMatrix;
        vec4 c = PV*vec4(position, 1.0), cp = PV*vec4(aPrev, 1.0), cn = PV*vec4(aNext, 1.0);
        vec2 d = (cn.xy/max(cn.w, 1e-3) - cp.xy/max(cp.w, 1e-3))*uRes;
        d = length(d) > 1e-4 ? normalize(d) : vec2(1.0, 0.0);
        vec2 n = vec2(-d.y, d.x);
        float px = max(3.0, aP.x*uProj/max(c.w, 0.05));
        c.xy += n*aSide*px*0.5*2.0/uRes*c.w;
        gl_Position = c;
        vSide = aSide; vU = aU; vA = aA; vAmp = aP.y*min(1.0, px/3.0 + 0.3); vCh = aP.z; vPh = aP.w; vN = n; vT = d; }`,
    fragmentShader: `${DECL}
      varying float vSide, vU, vA, vAmp, vCh, vPh; varying vec2 vN, vT;
      void main(){
        if (uNoDepth > 1.5) { gl_FragColor = vec4(5.0, 0.0, 0.0, vA); return; }
        if (vA <= 0.0 || hidden()) discard;
        float x = vSide;
        // a thin lens across it: pushed out on one side, in on the other; strongest in its middle
        float g = -x*exp(-x*x*2.2)*2.3;
        float env = smoothstep(0.0, 0.18, vU)*smoothstep(1.0, 0.7, vU);
        float rip = 0.7 + 0.3*sin(vU*19.0 - uTime*15.0 + vPh) + 0.15*(n1(vU*9.0 + vPh*3.0 - uTime*6.0) - 0.5);
        float k = vAmp*env*rip*vA;
        vec2 off = vN*g*k + vT*exp(-x*x*2.0)*k*0.35;        // and dragged a little along it, like wind
        gl_FragColor = vec4(off, vCh*env*exp(-x*x*1.5)*vA, 0.32*exp(-x*x*2.0)*env*vA); }`,
  });
  const smesh = new THREE.Mesh(sg, smat); smesh.frustumCulled = false;
  R.warp_scene.add(smesh);
  const S = [];
  for (let i = 0; i < NS; i++) S.push({ on: false, pts: [...Array(K)].map(() => new THREE.Vector3()), w: 0.1, amp: 3, chroma: 0.7, a: 0, ph: Math.random()*6.28 });

  // ---------------------------------------------------------------- puffs
  const NP = 500;
  const ppos = new Float32Array(NP*3), pprm = new Float32Array(NP*4);
  const pg = new THREE.BufferGeometry();
  pg.setAttribute('position', new THREE.BufferAttribute(ppos, 3));
  pg.setAttribute('aP', new THREE.BufferAttribute(pprm, 4));         // size m, amp px, rotation, alpha
  const pmat = new THREE.ShaderMaterial({
    uniforms: U, ...blend,
    vertexShader: `attribute vec4 aP; uniform float uProj; varying vec4 vP; varying float vSeed;
      void main(){ vec4 mv = modelViewMatrix*vec4(position, 1.0); gl_Position = projectionMatrix*mv;
        gl_PointSize = aP.w > 0.0 ? clamp(aP.x*uProj/max(-mv.z, 0.05), 2.0, 96.0) : 0.0; vP = aP; vSeed = fract(position.x*3.1 + position.z*1.7); }`,
    fragmentShader: `${DECL}
      varying vec4 vP; varying float vSeed;
      void main(){
        if (hidden()) discard;
        vec2 q = gl_PointCoord*2.0 - 1.0; q.y = -q.y;
        float r = length(q);
        if (r > 1.0) discard;
        float fall = smoothstep(1.0, 0.1, r);
        float c = cos(vP.z), s = sin(vP.z);
        vec2 qr = vec2(c*q.x - s*q.y, s*q.x + c*q.y);
        // a swirl with lumps in it: air turning over, smoke made of it
        float lump = 0.6 + 0.8*n1(qr.x*3.0 + vSeed*17.0 + uTime*1.3)*n1(qr.y*3.0 + vSeed*9.0 - uTime*1.1);
        vec2 off = (vec2(-qr.y, qr.x)*0.9 + qr*0.35)*vP.y*fall*lump*vP.w;
        gl_FragColor = vec4(off, 0.9*fall*vP.w, 0.3*fall*vP.w); }`,
  });
  const pts = new THREE.Points(pg, pmat); pts.frustumCulled = false;
  R.warp_scene.add(pts);
  const P = [];
  for (let i = 0; i < NP; i++) P.push({ life: 0 });
  let pnext = 0;

  return {
    // a streak for the caller to move: set .pts (K points, first = tail), .w (m), .amp (px), .chroma, .a (0..1)
    streak() {
      const s = S.find(q => !q.on);
      if (!s) return null;
      s.on = true; s.a = 0; s.w = 0.1; s.amp = 3; s.chroma = 0.7; s.ph = Math.random()*6.28;
      return s;
    },
    release(s) { if (s) { s.on = false; s.a = 0; } },
    // a puff: x y z, vx vy vz, life, s0 -> s1 (m across), amp (px), spin (rad/s), drag, rise (m/s^2)
    puff(o) {
      const p = P[pnext]; pnext = (pnext + 1) % NP;
      Object.assign(p, { vx: 0, vy: 0, vz: 0, drag: 0.8, rise: 0, spin: 1, rot: Math.random()*6.28, amp: 3.5, s0: 0.15, s1: 0.5 }, o, { max: o.life });
      return p;
    },
    update(t, dt) {
      U.uTime.value = t;
      S.forEach((s, i) => {
        for (let k = 0; k < K; k++) {
          const p = s.pts[k], a = s.pts[Math.max(0, k - 1)], b = s.pts[Math.min(K - 1, k + 1)];
          for (let e = 0; e < 2; e++) {
            const v = (i*K + k)*2 + e;
            pos[v*3] = p.x; pos[v*3 + 1] = p.y; pos[v*3 + 2] = p.z;
            prv[v*3] = a.x; prv[v*3 + 1] = a.y; prv[v*3 + 2] = a.z;
            nxt[v*3] = b.x; nxt[v*3 + 1] = b.y; nxt[v*3 + 2] = b.z;
            prm[v*4] = s.w; prm[v*4 + 1] = s.amp; prm[v*4 + 2] = s.chroma; prm[v*4 + 3] = s.ph;
            fade[v] = s.on ? s.a : 0;
          }
        }
      });
      for (const k of ['position', 'aPrev', 'aNext', 'aP', 'aA']) sg.attributes[k].needsUpdate = true;
      for (let i = 0; i < NP; i++) {
        const p = P[i];
        if (p.life <= 0) { pprm[i*4 + 3] = 0; continue; }
        p.life -= dt;
        const u = 1 - p.life/p.max, d = 1 - p.drag*dt;
        p.vx *= d; p.vy = p.vy*d + p.rise*dt; p.vz *= d;
        p.x += p.vx*dt; p.y += p.vy*dt; p.z += p.vz*dt; p.rot += p.spin*dt;
        ppos[i*3] = p.x; ppos[i*3 + 1] = p.y; ppos[i*3 + 2] = p.z;
        pprm[i*4] = p.s0 + (p.s1 - p.s0)*u; pprm[i*4 + 1] = p.amp; pprm[i*4 + 2] = p.rot;
        pprm[i*4 + 3] = smoothstep(0, 0.15, u)*(1 - smoothstep(0.45, 1, u));
      }
      pg.attributes.position.needsUpdate = true; pg.attributes.aP.needsUpdate = true;
    },
    set_camera(cam, H) { U.uProj.value = cam.projectionMatrix.elements[5]*H*0.5; },
    // tests
    buf: () => ({ pos: Array.from(pos.slice(0, 12)).map(v => +v.toFixed(2)), prm: Array.from(prm.slice(0, 8)).map(v => +v.toFixed(2)), fade: Array.from(fade.slice(0, 4)), side: Array.from(side.slice(0, 4)), idx: sg.index.array.length, count: sg.attributes.position.count, drawRange: [sg.drawRange.start, sg.drawRange.count] }),
    debug: () => ({ streaks: S.filter(s => s.on).map(s => [+s.a.toFixed(2), s.pts[0].toArray().map(v => +v.toFixed(2)), s.pts[K - 1].toArray().map(v => +v.toFixed(2))]).slice(0, 5), n: S.filter(s => s.on).length, puffs: P.filter(p => p.life > 0).length }),
    U,
  };
}
