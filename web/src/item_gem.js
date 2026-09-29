// item_gem.js -- the PRISMATIC BEAM power's object.
//
// Round 28 (owner: "like a prismatic gem"): a cut stone traced as a real one. The eye's ray is
// split into red, green and blue, each bent by its own index (strong dispersion), and followed
// inside the stone -- total internal reflection, Fresnel at every exit -- to where it leaves and
// what it sees there. A convex stone is exactly the intersection of its facet planes, so the
// shader traces those planes directly.
//
// Round 29 (owner: "absolutely beautiful ... the shape of it could be something other than an
// actual gem, something more random and aesthetic ... keep the transparency and reflections";
// the cuts were "too regular, it should be a bit fucked up"): raw, broken shapes instead of
// cuts, every face uneven, corners chipped; and fractures inside some of them -- thin cracks
// that catch the light as rainbow sheets (an iridescent crack in quartz), traced as partial
// mirrors with a thin-film colour. C: BROKEN POINT (default) / SHARD / CLUSTER / ROUGH LUMP.
import * as THREE from 'three';
import { ConvexGeometry } from 'three/addons/geometries/ConvexGeometry.js';
import { rand } from 'game/shape_noise.js';

export const GEM_CUTS = ['BROKEN POINT', 'SHARD', 'CLUSTER', 'ROUGH LUMP'];
const MAXP = 64, MAXF = 3;

// ---------------------------------------------------------------- shapes (planes n.x <= w)
const P = (nx, ny, nz, w) => { const n = new THREE.Vector3(nx, ny, nz); const l = n.length(); return { n: n.multiplyScalar(1/l), w: w/l }; };
const through = (n, at) => ({ n: n.clone().normalize(), w: n.clone().normalize().dot(at) });

// a raw crystal point along +y: six uneven prism faces, an uneven termination (its apex off
// centre), a broken base
function point_planes(R, rad = 0.5, len = 2.4) {
  const out = [];
  const a0 = R.f(0, 6.28);
  for (let k = 0; k < 6; k++) {
    const a = a0 + k*Math.PI/3 + R.s(0.18);
    out.push(P(Math.cos(a), R.s(0.09), Math.sin(a), rad*R.f(0.7, 1.28)));
  }
  const top = len*0.5, ax = R.s(0.12), az = R.s(0.12);
  for (let k = 0; k < 6; k++) {
    const a = a0 + k*Math.PI/3 + R.s(0.25), tilt = R.f(0.62, 0.95);
    const n = new THREE.Vector3(Math.cos(a)*Math.sin(tilt), Math.cos(tilt), Math.sin(a)*Math.sin(tilt));
    out.push(through(n, new THREE.Vector3(ax + Math.cos(a)*rad*0.2, top*R.f(0.62, 0.95), az + Math.sin(a)*rad*0.2)));
  }
  for (let k = 0; k < 5; k++) {
    const a = R.f(0, 6.28), t = R.f(0.2, 1.05);
    const n = new THREE.Vector3(Math.cos(a)*Math.sin(t), -Math.cos(t), Math.sin(a)*Math.sin(t));
    out.push(through(n, new THREE.Vector3(0, -len*0.5*R.f(0.55, 0.9), 0)));
  }
  return out;
}
// a flat broken blade
function shard_planes(R) {
  // a blade: two broad faces meeting at a slant, thick along one edge and thin along the other,
  // a long taper to a broken tip
  const out = [];
  out.push(P(0.25, R.s(0.08), 1, 0.1), P(0.25, R.s(0.08), -1, 0.1));
  const a0 = R.f(0, 6.28);
  for (let k = 0; k < 7; k++) {
    const a = a0 + k*Math.PI*2/7 + R.s(0.28);
    const nx = Math.cos(a)/1.0, ny = Math.sin(a)/2.6;          // long along y
    out.push(P(nx, ny, R.s(0.45), R.f(0.55, 1.0)*Math.hypot(nx, ny)));
  }
  return out;
}
// an uneven lump
function lump_planes(R, count = 30, s = [1, 0.74, 0.86]) {
  const out = [];
  for (let i = 0; i < count; i++) {
    const y = 1 - 2*(i + 0.5)/count, r = Math.sqrt(1 - y*y), a = i*2.39996 + R.s(0.4);
    const n = new THREE.Vector3(Math.cos(a)*r + R.s(0.2), y + R.s(0.2), Math.sin(a)*r + R.s(0.2)).normalize();
    const w = R.f(0.78, 1.02);
    const m = new THREE.Vector3(n.x/s[0], n.y/s[1], n.z/s[2]);
    out.push({ n: m.clone().normalize(), w: w/m.length() });
  }
  return out;
}

// the polyhedron: every vertex where three planes meet inside all the others
function vertices(planes) {
  const V = [], m = new THREE.Matrix3(), x = new THREE.Vector3();
  const N = planes.length;
  for (let i = 0; i < N; i++) for (let j = i + 1; j < N; j++) for (let k = j + 1; k < N; k++) {
    const a = planes[i].n, b = planes[j].n, c = planes[k].n;
    m.set(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z);
    if (Math.abs(m.determinant()) < 1e-6) continue;
    x.set(planes[i].w, planes[j].w, planes[k].w).applyMatrix3(m.clone().invert());
    let ok = true;
    for (let l = 0; l < N && ok; l++) if (planes[l].n.dot(x) > planes[l].w + 1e-5) ok = false;
    if (ok && !V.some(v => v.distanceToSquared(x) < 1e-8)) V.push(x.clone());
  }
  return V;
}
// knock chips off some corners (a plane just inside a random vertex)
function chip(planes, R, n, depth) {
  const V = vertices(planes);
  for (let i = 0; i < n && V.length; i++) {
    const v = V[Math.floor(R.next()*V.length)];
    const dir = v.clone().normalize().add(new THREE.Vector3(R.s(0.5), R.s(0.5), R.s(0.5))).normalize();
    planes.push({ n: dir, w: dir.dot(v) - depth*R.f(0.6, 1.3) });
  }
  return planes;
}
function solid(planes) {
  const V = vertices(planes);
  const geo = new ConvexGeometry(V);
  const used = planes.filter(pl => V.filter(v => Math.abs(pl.n.dot(v) - pl.w) < 1e-4).length >= 3);
  const box = new THREE.Box3().setFromPoints(V);
  return { geo, planes: used, box };
}
// a crack inside: a disc (centre, normal, radius) somewhere through the middle
function fractures(R, box, n) {
  const c = box.getCenter(new THREE.Vector3()), s = box.getSize(new THREE.Vector3());
  const out = [];
  for (let i = 0; i < n; i++) {
    const p = c.clone().add(new THREE.Vector3(R.s(0.25)*s.x, R.s(0.25)*s.y, R.s(0.25)*s.z));
    const nn = new THREE.Vector3(R.s(1), R.s(1), R.s(1)).normalize();
    out.push({ c: p, n: nn, r: Math.min(s.x, s.y, s.z)*R.f(0.35, 0.6) + Math.max(s.x, s.y, s.z)*0.12 });
  }
  return out;
}
// each shape: a list of solids, each { planes, geo, fr, matrix }
function shapes(cut) {
  const R = rand(1301 + cut*17);
  if (cut === 0) {
    const s = solid(chip(point_planes(R, 0.5, 2.5), R, 3, 0.12));
    return [{ ...s, fr: fractures(R, s.box, 2), matrix: new THREE.Matrix4().makeRotationZ(0.12) }];
  }
  if (cut === 1) {
    const s = solid(chip(shard_planes(R), R, 3, 0.1));
    return [{ ...s, fr: fractures(R, s.box, 1), matrix: new THREE.Matrix4().makeRotationZ(-0.2) }];
  }
  if (cut === 2) {
    const out = [];
    const base = solid(chip(lump_planes(R, 16, [0.75, 0.38, 0.62]), R, 2, 0.08));
    out.push({ ...base, fr: [], matrix: new THREE.Matrix4().makeTranslation(0, -0.35, 0) });
    for (let k = 0; k < 6; k++) {
      const rad = k === 0 ? 0.3 : R.f(0.15, 0.25), len = k === 0 ? 2.1 : R.f(0.9, 1.6);
      const s = solid(chip(point_planes(R, rad, len), R, 1, 0.05));
      const az = R.f(0, 6.28), tilt = k === 0 ? R.f(0, 0.2) : R.f(0.3, 0.85);
      const q = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), new THREE.Vector3(Math.sin(tilt)*Math.cos(az), Math.cos(tilt), Math.sin(tilt)*Math.sin(az)));
      const off = new THREE.Vector3(0, len*0.45, 0).applyQuaternion(q);
      const pos = new THREE.Vector3(Math.cos(az)*R.f(0, 0.3), -0.3, Math.sin(az)*R.f(0, 0.22)).add(off);
      out.push({ ...s, fr: k === 0 ? fractures(R, s.box, 1) : [], matrix: new THREE.Matrix4().compose(pos, q, new THREE.Vector3(1, 1, 1)) });
    }
    return out;
  }
  const s = solid(chip(lump_planes(R, 30), R, 4, 0.1));
  return [{ ...s, fr: fractures(R, s.box, 2), matrix: new THREE.Matrix4() }];
}
const SIZE = [0.058, 0.07, 0.07, 0.062];      // m per unit, per cut

// ---------------------------------------------------------------- the trace
const VS = /* glsl */`
varying vec3 vPosO; varying vec3 vNorO;
void main(){ vPosO = position; vNorO = normal; gl_Position = projectionMatrix*modelViewMatrix*vec4(position, 1.0); }`;
const FS = /* glsl */`
precision highp float;
#define MAXP ${MAXP}
#define MAXF ${MAXF}
#define BOUNCES 6
uniform vec4 uPlanes[MAXP];
uniform int uNP, uNF;
uniform vec4 uFracN[MAXF];
uniform vec4 uFracC[MAXF];
uniform vec3 uCamO;
uniform mat3 uToWorld;
uniform samplerCube uEnv;
uniform float uEnvK, uGlintPow, uLit, uFlip;
uniform vec3 uIor, uSunDir, uSunCol, uAbsorb, uTint;
varying vec3 vPosO; varying vec3 vNorO;
vec3 spectrum(float h){ vec3 c = clamp(abs(fract(h + vec3(0.0, 0.6667, 0.3333))*6.0 - 3.0) - 1.0, 0.0, 1.0); return c*c*(3.0 - 2.0*c); }
vec3 env_w(vec3 dO){
  vec3 d = normalize(uToWorld*dO);
  vec3 c = textureCube(uEnv, vec3(uFlip*d.x, d.y, d.z)).rgb*uEnvK;
  float s = max(dot(d, uSunDir), 0.0);
  return c + uSunCol*(pow(s, uGlintPow) + 0.008*pow(s, uGlintPow*0.05))*uLit;
}
float schlick(float c, float n){ float f0 = (n - 1.0)/(n + 1.0); f0 *= f0; return f0 + (1.0 - f0)*pow(1.0 - clamp(c, 0.0, 1.0), 5.0); }
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
    // a crack before the far side: part of the light turns back off it in a thin-film colour
    float tf = tm; int fi = -1;
    for (int j = 0; j < MAXF; j++) {
      if (j >= uNF) break;
      vec3 fn = uFracN[j].xyz;
      float dn = dot(fn, d);
      if (abs(dn) < 1e-4) continue;
      float t = (uFracN[j].w - dot(fn, p))/dn;
      if (t > 1e-4 && t < tf && length(p + d*t - uFracC[j].xyz) < uFracC[j].w) { tf = t; fi = j; }
    }
    if (fi >= 0) {
      vec3 fn = fi == 0 ? uFracN[0].xyz : fi == 1 ? uFracN[1].xyz : uFracN[2].xyz;
      vec4 fc = fi == 0 ? uFracC[0] : fi == 1 ? uFracC[1] : uFracC[2];
      p += d*tf;
      thr *= exp(-uAbsorb[ch]*tf);
      float edge = smoothstep(fc.w, fc.w*0.55, length(p - fc.xyz));
      float c = abs(dot(fn, d));
      vec3 film = spectrum(dot(p, vec3(3.1, 2.3, 4.7))*0.45 + c*1.2 + float(fi)*0.37);
      float r = (0.18 + 0.4*pow(1.0 - c, 3.0))*edge;
      acc += thr*r*film[ch]*1.6*env_w(reflect(d, fn))[ch];
      thr *= 1.0 - r*0.7;
      p += d*1e-4;
      continue;
    }
    p += d*tm;
    thr *= exp(-uAbsorb[ch]*tm);
    vec3 o = refract(d, -nh, n);
    if (dot(o, o) < 1e-6) { d = reflect(d, -nh); continue; }
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
  gl_FragColor = vec4(min(col, vec3(2.4)), 1.0);      // a glint's bloom stays a sparkle, not a disc
}`;

function gem_material(env, sol, opts = {}) {
  const V4 = (n, w) => new THREE.Vector4(n.x, n.y, n.z, w);
  const U = {
    uPlanes: { value: Array.from({ length: MAXP }, (_, i) => sol.planes[i] ? V4(sol.planes[i].n, sol.planes[i].w) : new THREE.Vector4(0, 1, 0, 1e3)) },
    uNP: { value: Math.min(sol.planes.length, MAXP) },
    uFracN: { value: Array.from({ length: MAXF }, (_, i) => sol.fr[i] ? V4(sol.fr[i].n, sol.fr[i].n.dot(sol.fr[i].c)) : new THREE.Vector4(0, 1, 0, 0)) },
    uFracC: { value: Array.from({ length: MAXF }, (_, i) => sol.fr[i] ? V4(sol.fr[i].c, sol.fr[i].r) : new THREE.Vector4()) },
    uNF: { value: Math.min(sol.fr.length, MAXF) },
    uCamO: { value: new THREE.Vector3() }, uToWorld: { value: new THREE.Matrix3() },
    uEnv: { value: env }, uEnvK: { value: opts.env_k ?? 1 }, uFlip: { value: opts.flip ?? 1 },
    uGlintPow: { value: opts.glint_pow ?? 1400 }, uLit: { value: 1 },
    uIor: { value: new THREE.Vector3(2.30, 2.43, 2.62) },
    uSunDir: { value: new THREE.Vector3(0, 1, 0) }, uSunCol: { value: new THREE.Vector3(30, 27, 22) },
    uAbsorb: { value: new THREE.Vector3(0.02, 0.02, 0.03) },
    uTint: { value: new THREE.Vector3(1, 1, 1) },
  };
  const m = new THREE.ShaderMaterial({ uniforms: U, vertexShader: VS, fragmentShader: FS });
  m.userData.U = U;
  return m;
}

const CACHE = new Map();
// builds the stone (one mesh per solid). ctx.env = the cube to see; ctx.sun = { dir, col }.
export function build_gem(ctx, cut = 0) {
  if (!CACHE.has(cut)) CACHE.set(cut, shapes(cut));
  const sols = CACHE.get(cut), size = SIZE[cut];
  const g = new THREE.Group();
  const mats = [];
  const inv = new THREE.Matrix4(), cam = new THREE.Vector3(), sc = new THREE.Vector3();
  for (const sol of sols) {
    const mat = gem_material(ctx.env, sol, { env_k: ctx.env_k ?? 1, flip: ctx.flip ?? 1, glint_pow: ctx.glint_pow ?? 1400 });
    const mesh = new THREE.Mesh(sol.geo, mat);
    mesh.applyMatrix4(sol.matrix);
    mesh.position.multiplyScalar(size);
    mesh.scale.setScalar(size);
    mesh.onBeforeRender = (r, s, camera) => {
      mesh.updateMatrixWorld();
      inv.copy(mesh.matrixWorld).invert();
      mat.userData.U.uCamO.value.copy(cam.setFromMatrixPosition(camera.matrixWorld).applyMatrix4(inv));
      const k = sc.setFromMatrixScale(mesh.matrixWorld).x;
      mat.userData.U.uToWorld.value.setFromMatrix4(mesh.matrixWorld).multiplyScalar(1/k);
      if (ctx.sun) { mat.userData.U.uSunDir.value.copy(ctx.sun.dir); mat.userData.U.uSunCol.value.copy(ctx.sun.col); }
    };
    mesh.castShadow = true;
    g.add(mesh);
    mats.push(mat);
  }
  g.userData.mats = mats;
  g.userData.mat = mats[0];
  return g;
}
