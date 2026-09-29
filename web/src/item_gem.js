// item_gem.js -- the PRISMATIC BEAM power's object: a traced round brilliant (round 28).
//
// A cut stone traced as a real one: the eye's ray is split into red, green and blue, each bent
// by its own index (strong dispersion), and followed inside the stone through its facets --
// total internal reflection off the pavilion, Fresnel at every exit -- to where it leaves and
// what it sees there. That is what makes a gem throw fire; a glass material (one refraction)
// looks dead. The stone is convex, so it is exactly the intersection of its facet planes and
// the shader traces those planes directly.
//
// Round 29 tried raw broken shapes (point, shard, cluster, lump) with rainbow cracks; round 30
// (owner: "let's just use the initial gem you made") restores round 28's brilliant as it was
// (its source taken from rounds/28-objects' bundle), seen in round 28's inspect environment.
import * as THREE from 'three';
import { ConvexGeometry } from 'three/addons/geometries/ConvexGeometry.js';

export const GEM_CUTS = ['ROUND BRILLIANT'];
const MAXP = 96;

// a plane through point `at` with outward normal tilted `tilt` from +y (or -y) toward azimuth a
const tilted = (a, tilt, up, at) => {
  const n = new THREE.Vector3(Math.cos(a)*Math.sin(tilt), (up ? 1 : -1)*Math.cos(tilt), Math.sin(a)*Math.sin(tilt));
  return { n, w: n.dot(at) };
};
const on_ring = (a, r, y) => new THREE.Vector3(Math.cos(a)*r, y, Math.sin(a)*r);

// ---------------------------------------------------------------- cuts (girdle radius 1)
function brilliant() {
  const P = [], D = Math.PI/180;
  const g = 0.018;                          // half the girdle's thickness
  const crown = 34.5*D, pav = 40.75*D, table = 0.56;
  const hc = g + Math.tan(crown)*(1 - table)*0.98;   // the table's height
  P.push({ n: new THREE.Vector3(0, 1, 0), w: hc });
  for (let k = 0; k < 8; k++) {
    const a = k*Math.PI/4;
    P.push(tilted(a, crown, true, on_ring(a, 1, g)));                                    // bezel (crown main)
    P.push(tilted(a + Math.PI/8, 21.5*D, true, on_ring(a + Math.PI/8, table*Math.cos(Math.PI/8), hc)));   // star
    for (const s of [-1, 1]) {
      const b = a + Math.PI/8 + s*Math.PI/16;
      P.push(tilted(b, 42*D, true, on_ring(b, 1, g)));                                   // upper girdle
      P.push(tilted(b, 42.3*D, false, on_ring(b, 1, -g)));                               // lower girdle
    }
    P.push(tilted(a, pav, false, on_ring(a, 1, -g)));                                    // pavilion main
  }
  for (let k = 0; k < 32; k++) { const a = (k + 0.5)*Math.PI/16; P.push(tilted(a, Math.PI/2, true, on_ring(a, 1, 0))); }   // the girdle
  return P;
}
const CUTS = [brilliant];

// the polyhedron: every vertex where three planes meet inside all the others
function solid(planes) {
  const V = [], eps = 1e-7;
  const m = new THREE.Matrix3(), inv = new THREE.Matrix3(), x = new THREE.Vector3();
  const N = planes.length;
  for (let i = 0; i < N; i++) for (let j = i + 1; j < N; j++) for (let k = j + 1; k < N; k++) {
    const a = planes[i].n, b = planes[j].n, c = planes[k].n;
    m.set(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z);
    const det = m.determinant();
    if (Math.abs(det) < 1e-6) continue;
    inv.copy(m).invert();
    x.set(planes[i].w, planes[j].w, planes[k].w).applyMatrix3(inv);
    let ok = true;
    for (let l = 0; l < N && ok; l++) if (planes[l].n.dot(x) > planes[l].w + 1e-5) ok = false;
    if (ok && !V.some(v => v.distanceToSquared(x) < eps)) V.push(x.clone());
  }
  const geo = new ConvexGeometry(V);
  // keep only the planes that carry a face (the shader tests fewer)
  const used = planes.filter(pl => V.filter(v => Math.abs(pl.n.dot(v) - pl.w) < 1e-4).length >= 3);
  return { geo, planes: used };
}

// ---------------------------------------------------------------- the trace
const VS = /* glsl */`
varying vec3 vPosO; varying vec3 vNorO;
void main(){ vPosO = position; vNorO = normal; gl_Position = projectionMatrix*modelViewMatrix*vec4(position, 1.0); }`;
const FS = /* glsl */`
precision highp float;
#define MAXP ${MAXP}
#define BOUNCES 6
uniform vec4 uPlanes[MAXP];
uniform int uNP;
uniform vec3 uCamO;
uniform mat3 uToWorld;
uniform samplerCube uEnv;
uniform float uEnvK, uGlintPow, uLit, uFlip;
uniform vec3 uIor, uSunDir, uSunCol, uAbsorb, uTint;
varying vec3 vPosO; varying vec3 vNorO;
vec3 env_w(vec3 dO){
  vec3 d = normalize(uToWorld*dO);
  vec3 c = textureCube(uEnv, vec3(uFlip*d.x, d.y, d.z)).rgb*uEnvK;
  // the light itself (the sun down the shaft, or the inspect view's key): a hard glint
  float s = max(dot(d, uSunDir), 0.0);
  return c + uSunCol*(pow(s, uGlintPow) + 0.04*pow(s, uGlintPow*0.05))*uLit;
}
float schlick(float c, float n){ float f0 = (n - 1.0)/(n + 1.0); f0 *= f0; return f0 + (1.0 - f0)*pow(1.0 - clamp(c, 0.0, 1.0), 5.0); }
// follow one colour's ray inside the stone; returns what leaves, in that colour
float trace(vec3 p, vec3 d, float n, int ch){
  float acc = 0.0, thr = 1.0;
  for (int b = 0; b < BOUNCES; b++) {
    float tm = 1e9; vec3 nh = vec3(0.0, 1.0, 0.0);
    for (int i = 0; i < MAXP; i++) {
      if (i >= uNP) break;
      vec4 pl = uPlanes[i];
      float dn = dot(pl.xyz, d);
      if (dn > 1e-5) { float t = (pl.w - dot(pl.xyz, p))/dn; if (t < tm) { tm = t; nh = pl.xyz; } }
    }
    p += d*tm;
    thr *= exp(-uAbsorb[ch]*tm);
    vec3 o = refract(d, -nh, n);
    float ci = dot(d, nh);
    if (dot(o, o) < 1e-6) { d = reflect(d, -nh); continue; }       // total internal reflection
    float F = schlick(dot(o, nh), n);
    acc += thr*(1.0 - F)*env_w(o)[ch];
    thr *= F;
    d = reflect(d, -nh);
  }
  return acc + thr*env_w(d)[ch]*0.6;
}
void main(){
  vec3 N = normalize(vNorO);
  vec3 V = normalize(vPosO - uCamO);
  float c = max(-dot(V, N), 0.0);
  float F = schlick(c, uIor.g);
  vec3 col = env_w(reflect(V, N))*F;
  vec3 inside;
  for (int ch = 0; ch < 3; ch++) {
    float n = uIor[ch];
    vec3 d = refract(V, N, 1.0/n);
    inside[ch] = trace(vPosO + d*1e-4, d, n, ch);
  }
  col += (1.0 - F)*inside*uTint;
  gl_FragColor = vec4(min(col, vec3(5.0)), 1.0);      // a glint's bloom stays a sparkle, not a halo
}`;

// env: a cube texture; opts: cut index, size (girdle radius, m), ior, spread
export function gem_material(env, planes, opts = {}) {
  const U = {
    uPlanes: { value: Array.from({ length: MAXP }, (_, i) => planes[i] ? new THREE.Vector4(planes[i].n.x, planes[i].n.y, planes[i].n.z, planes[i].w) : new THREE.Vector4(0, 1, 0, 1e3)) },
    uNP: { value: Math.min(planes.length, MAXP) },
    uCamO: { value: new THREE.Vector3() }, uToWorld: { value: new THREE.Matrix3() },
    uEnv: { value: env }, uEnvK: { value: opts.env_k ?? 1 }, uFlip: { value: opts.flip ?? 1 },
    uGlintPow: { value: opts.glint_pow ?? 1400 }, uLit: { value: 1 },
    uIor: { value: new THREE.Vector3(...(opts.ior ?? [2.30, 2.43, 2.62])) },
    uSunDir: { value: new THREE.Vector3(0, 1, 0) }, uSunCol: { value: new THREE.Vector3(30, 27, 22) },
    uAbsorb: { value: new THREE.Vector3(...(opts.absorb ?? [0.02, 0.02, 0.03])) },
    uTint: { value: new THREE.Vector3(...(opts.tint ?? [1, 1, 1])) },
  };
  const m = new THREE.ShaderMaterial({ uniforms: U, vertexShader: VS, fragmentShader: FS });
  m.userData.U = U;
  return m;
}

// builds the gem (one mesh). ctx.env = the cube to see; ctx.sun = { dir, col } in world.
export function build_gem(ctx, cut = 0) {
  const { geo, planes } = solid(CUTS[cut]());
  const size = 0.065;                        // girdle radius, m
  const mat = gem_material(ctx.env, planes, { env_k: ctx.env_k ?? 1, flip: ctx.flip ?? 1, glint_pow: ctx.glint_pow ?? 1400 });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.scale.setScalar(size);
  const inv = new THREE.Matrix4(), cam = new THREE.Vector3();
  mesh.onBeforeRender = (r, s, camera) => {
    inv.copy(mesh.matrixWorld).invert();
    mat.userData.U.uCamO.value.copy(cam.setFromMatrixPosition(camera.matrixWorld).applyMatrix4(inv));
    const tw = mat.userData.U.uToWorld.value.setFromMatrix4(mesh.matrixWorld);
    // strip the scale (uniform)
    const sc = new THREE.Vector3().setFromMatrixScale(mesh.matrixWorld).x;
    tw.multiplyScalar(1/sc);
    if (ctx.sun) { mat.userData.U.uSunDir.value.copy(ctx.sun.dir); mat.userData.U.uSunCol.value.copy(ctx.sun.col); }
  };
  mesh.castShadow = true;
  const g = new THREE.Group();
  g.add(mesh);
  g.userData.mat = mat;
  g.userData.mats = [mat];
  g.userData.geo = geo;
  g.userData.scale = size;
  return g;
}
