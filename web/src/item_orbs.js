// item_orbs.js -- round 28: the LEAKAGE power's object (owner: "the orbs Shun uses around him
// before he becomes a Karma demon", Shin Sekai Yori). In the anime (ep. 10, his house; the
// frames in reference/objects/leak-shun/) they are clear glass spheres of a few sizes drifting
// in the air near him: dark green in their depth, a darker rim where the glass is thickest, a
// hard star of a glint.
//
// Each sphere is traced as solid glass: the eye's ray refracts in, crosses, and either leaves
// (seeing the world behind, upside down, as a glass ball does) or reflects inside and tries
// again; red, green and blue bend a little differently (faint rainbow fringes at the rim);
// glass absorbs along its path, more in red and blue, so the middle of a thick ball is green.
// In the inspect view they hover around each other; on the floor each is its own rolling ball.
import * as THREE from 'three';

// radii, m (a few sizes, like the anime's)
export const ORB_R = [0.05, 0.036, 0.042, 0.028, 0.032];

const VS = /* glsl */`
varying vec3 vPosO;
void main(){ vPosO = position; gl_Position = projectionMatrix*modelViewMatrix*vec4(position, 1.0); }`;
const FS = /* glsl */`
precision highp float;
uniform vec3 uCamO;
uniform mat3 uToWorld;
uniform samplerCube uEnv;
uniform float uEnvK, uGlintPow, uLit, uFlip;
uniform vec3 uIor, uSunDir, uSunCol, uAbsorb;
varying vec3 vPosO;
vec3 env_w(vec3 dO){
  vec3 d = normalize(uToWorld*dO);
  vec3 c = textureCube(uEnv, vec3(uFlip*d.x, d.y, d.z)).rgb*uEnvK;
  float s = max(dot(d, uSunDir), 0.0);
  return c + uSunCol*(pow(s, uGlintPow) + 0.03*pow(s, uGlintPow*0.04))*uLit;
}
float schlick(float c, float n){ float f0 = (n - 1.0)/(n + 1.0); f0 *= f0; return f0 + (1.0 - f0)*pow(1.0 - clamp(c, 0.0, 1.0), 5.0); }
// one colour through the ball (unit sphere, object space), from surface point p going d
float through(vec3 p, vec3 d, float n, int ch){
  float acc = 0.0, thr = 1.0;
  for (int b = 0; b < 3; b++) {
    float t = -2.0*dot(p, d);
    p += d*t;
    thr *= exp(-uAbsorb[ch]*t);
    vec3 N = normalize(p);
    vec3 o = refract(d, -N, n);
    if (dot(o, o) < 1e-6) { d = reflect(d, -N); continue; }
    float F = schlick(dot(o, N), n);
    acc += thr*(1.0 - F)*env_w(o)[ch];
    thr *= F;
    d = reflect(d, -N);
  }
  return acc;
}
void main(){
  vec3 P = normalize(vPosO);
  vec3 V = normalize(vPosO - uCamO);
  float c = max(-dot(V, P), 0.0);
  float F = schlick(c, uIor.g);
  vec3 col = env_w(reflect(V, P))*F;
  vec3 inside;
  for (int ch = 0; ch < 3; ch++) { float n = uIor[ch]; inside[ch] = through(P, refract(V, P, 1.0/n), n, ch); }
  col += (1.0 - F)*inside;
  gl_FragColor = vec4(min(col, vec3(5.0)), 1.0);
}`;

function orb_material(ctx) {
  const U = {
    uCamO: { value: new THREE.Vector3() }, uToWorld: { value: new THREE.Matrix3() },
    uEnv: { value: ctx.env }, uEnvK: { value: ctx.env_k ?? 1 }, uFlip: { value: ctx.flip ?? 1 },
    uGlintPow: { value: ctx.glint_pow ?? 1400 }, uLit: { value: 1 },
    uIor: { value: new THREE.Vector3(1.505, 1.52, 1.54) },
    uSunDir: { value: new THREE.Vector3(0, 1, 0) }, uSunCol: { value: new THREE.Vector3(30, 27, 22) },
    uAbsorb: { value: new THREE.Vector3(0.55, 0.14, 0.45) },      // per unit radius: green glass
  };
  const m = new THREE.ShaderMaterial({ uniforms: U, vertexShader: VS, fragmentShader: FS });
  m.userData.U = U;
  return m;
}

// ctx.env = the cube to see; ctx.sun = { dir, col } (world). Returns a group of spheres; each
// has userData.r (its radius) and userData.mat. g.userData.hover(t) floats them around each
// other (the inspect view).
export function build_orbs(ctx = {}) {
  const g = new THREE.Group();
  const geo = new THREE.SphereGeometry(1, 48, 32);
  const inv = new THREE.Matrix4(), cam = new THREE.Vector3(), sc = new THREE.Vector3();
  const orbs = ORB_R.map((r, i) => {
    const mat = orb_material(ctx);
    const m = new THREE.Mesh(geo, mat);
    m.scale.setScalar(r);
    m.userData.r = r; m.userData.mat = mat;
    m.castShadow = false; m.userData.no_shadow = true;         // clear glass: no dark shadow
    m.onBeforeRender = (rr, s, camera) => {
      m.updateMatrixWorld();
      inv.copy(m.matrixWorld).invert();
      mat.userData.U.uCamO.value.copy(cam.setFromMatrixPosition(camera.matrixWorld).applyMatrix4(inv));
      const k = sc.setFromMatrixScale(m.matrixWorld).x;
      mat.userData.U.uToWorld.value.setFromMatrix4(m.matrixWorld).multiplyScalar(1/k);
      if (ctx.sun) { mat.userData.U.uSunDir.value.copy(ctx.sun.dir); mat.userData.U.uSunCol.value.copy(ctx.sun.col); }
    };
    g.add(m);
    return m;
  });
  // a loose cluster: each on its own slow tilted orbit around the middle, bobbing
  const ORBIT = ORB_R.map((r, i) => ({ rad: 0.015 + 0.045*i, speed: (0.3 + 0.1*i)*(i % 2 ? -1 : 1), tilt: [0.2, -0.5, 0.7, -0.3, 0.45][i], ph: i*1.9, bob: 0.012 + 0.004*i }));
  const place = (t) => {
    orbs.forEach((m, i) => {
      const o = ORBIT[i], a = o.ph + t*o.speed;
      const x = Math.cos(a)*o.rad, z = Math.sin(a)*o.rad;
      // orbits mostly across the view (x, y), a little depth
      m.position.set(x, Math.sin(t*0.7 + o.ph)*o.bob + z*Math.cos(o.tilt), z*Math.sin(o.tilt));
    });
    // never through each other: overlapping pairs pushed apart
    for (let it = 0; it < 3; it++) for (let i = 0; i < orbs.length; i++) for (let j = i + 1; j < orbs.length; j++) {
      const a = orbs[i].position, b = orbs[j].position, d = a.distanceTo(b), min = (ORB_R[i] + ORB_R[j])*1.15;
      if (d < min && d > 1e-6) { const k = (min - d)/d*0.5; const dx = (b.x - a.x)*k, dy = (b.y - a.y)*k, dz = (b.z - a.z)*k; a.x -= dx; a.y -= dy; a.z -= dz; b.x += dx; b.y += dy; b.z += dz; }
    }
  };
  place(0);
  g.userData.orbs = orbs;
  g.userData.hover = place;
  return g;
}
