// item_lens.js -- round 28: the LENS power's object (owner: "a lens, as it appears when
// attacking but more detailed"). The attack's lens is a bare biconvex disc of clear glass
// (lens.js); this is the same glass as a thing you could hold: two ground spherical faces, a
// narrow edge ground flat and left frosted, the sharp corners eased by a bevel, a slight green
// in its thickness (old glass), polishing marks in the faces, and two conchoidal chips knocked
// out of the rim.
import * as THREE from 'three';

const R = 0.22;               // radius, m (44 cm across; the attack's is 76)
// round 29 (owner: "shouldn't a lens that does that kind of attack be convex?"): it was, 14% as
// thick as wide, but the bulge didn't read; a burning glass gathers the sun to a point by being
// thicker in the middle, so it bulges plainly now (about a quarter as thick as it is wide)
const TC = 0.105, TE = 0.012; // centre and edge thickness
const BEV = 0.0025;           // the bevel at each corner of the edge
const SEG = 288;

// polishing marks: fine arcs and a few longer scratches, as a roughness map (0 = polished)
function scratch_texture(seed = 3) {
  const S = 512, c = document.createElement('canvas');
  c.width = c.height = S;
  const g = c.getContext('2d');
  g.fillStyle = 'rgb(6,6,6)'; g.fillRect(0, 0, S, S);
  let s = seed;
  const rnd = () => ((s = Math.imul(s ^ (s >>> 15), 2246822519) + 0x9e3779b9 >>> 0)/4294967296);
  g.lineCap = 'round';
  for (let i = 0; i < 260; i++) {
    const cx = rnd()*S, cy = rnd()*S, r = 20 + rnd()*220, a0 = rnd()*6.283, da = (0.05 + rnd()*0.4)*(rnd() < 0.5 ? -1 : 1);
    g.strokeStyle = `rgba(255,255,255,${0.08 + rnd()*0.22})`;
    g.lineWidth = 0.5 + rnd()*0.8;
    g.beginPath(); g.arc(cx, cy, r, a0, a0 + da, da < 0); g.stroke();
  }
  for (let i = 0; i < 14; i++) {
    const x = rnd()*S, y = rnd()*S, a = rnd()*6.283, l = 30 + rnd()*160;
    g.strokeStyle = `rgba(255,255,255,${0.25 + rnd()*0.3})`; g.lineWidth = 0.6 + rnd()*0.7;
    g.beginPath(); g.moveTo(x, y); g.quadraticCurveTo(x + Math.cos(a + 0.3)*l*0.5, y + Math.sin(a + 0.3)*l*0.5, x + Math.cos(a)*l, y + Math.sin(a)*l); g.stroke();
  }
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.anisotropy = 4;
  return t;
}

// the profile, r outward, y up: top face, bevel, edge band, bevel, bottom face
function profile() {
  const s = (TC - TE)/2;                         // sagitta
  const Rc = (R*R + s*s)/(2*s);                  // the faces' sphere radius
  const face = [], band = [];
  const top = r => TE/2 + Math.sqrt(Rc*Rc - r*r) - (Rc - s);
  const n = 40;
  for (let i = 0; i <= n; i++) {
    const r = (R - BEV)*Math.sin(i/n*Math.PI/2);   // dense toward the rim
    face.push([r, top(r)]);
  }
  band.push([R - BEV, TE/2 - 0.0002], [R, TE/2 - BEV], [R, TE/4], [R, 0], [R, -TE/4], [R, -(TE/2 - BEV)], [R - BEV, -(TE/2 - 0.0002)]);
  return { face, band, top };
}

// a lathe from [r, y] points; a flag per point for which faces get planar uvs
function lathe(pts, uv_planar) {
  const pos = [], uv = [], idx = [];
  const n = pts.length;
  for (let j = 0; j <= SEG; j++) {
    const a = j/SEG*Math.PI*2, ca = Math.cos(a), sa = Math.sin(a);
    for (let i = 0; i < n; i++) {
      const [r, y] = pts[i];
      pos.push(r*ca, y, r*sa);
      if (uv_planar) uv.push(0.5 + r*ca/(2*R), 0.5 + r*sa/(2*R) + (y < 0 ? 0.37 : 0));
      else uv.push(j/SEG*6, i/(n - 1));
    }
  }
  for (let j = 0; j < SEG; j++) for (let i = 0; i < n - 1; i++) {
    const a = j*n + i, b = (j + 1)*n + i, c = (j + 1)*n + i + 1, d = j*n + i + 1;
    idx.push(a, b, d, b, c, d);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  return g;
}

// knock a chip out: vertices inside a sphere at the rim are pushed onto its surface (a
// conchoidal scoop), which only ever removes glass
function chip(g, cx, cy, cz, rad) {
  const p = g.attributes.position, v = new THREE.Vector3(), c = new THREE.Vector3(cx, cy, cz);
  for (let i = 0; i < p.count; i++) {
    v.fromBufferAttribute(p, i);
    const d = v.distanceTo(c);
    if (d < rad && d > 1e-6) { v.sub(c).multiplyScalar(rad/d).add(c); p.setXYZ(i, v.x, v.y, v.z); }
  }
}

// a faint rim where the glass turns away from the eye, so its edge still reads against dark
// rock (the attack's lens has the same)
function rim(m, k) {
  const prev = m.onBeforeCompile;
  m.onBeforeCompile = (sh, r) => {
    if (prev) prev(sh, r);
    sh.fragmentShader = sh.fragmentShader.replace('#include <lights_fragment_end>', `#include <lights_fragment_end>
  { float nv = abs(dot(normalize(normal), normalize(vViewPosition))); totalEmissiveRadiance += vec3(0.85, 0.92, 0.86)*pow(1.0 - nv, 3.0)*${k.toFixed(3)}; }`);
  };
  const key = m.customProgramCacheKey ? m.customProgramCacheKey.bind(m) : () => '';
  m.customProgramCacheKey = () => key() + '|rim' + k;
  return m;
}

export function build_lens(ctx = {}) {
  const { face, band } = profile();
  const bottom = face.map(([r, y]) => [r, -y]).reverse();
  const top_g = lathe(face, true), bot_g = lathe(bottom, true), band_g = lathe(band, false);
  // two chips on the rim: one from the top corner, a smaller one from the bottom
  const CH = [[0.9, 1, 0.017, 0.006], [3.7, -1, 0.012, 0.004]];
  for (const [a, side, rad, inward] of CH) {
    const cx = Math.cos(a)*(R + rad - inward - 0.0045), cz = Math.sin(a)*(R + rad - inward - 0.0045), cy = side*(TE/2 + rad*0.45);
    for (const g of [top_g, bot_g, band_g]) chip(g, cx, cy, cz, rad);
  }
  for (const g of [top_g, bot_g, band_g]) g.computeVertexNormals();
  const rough = scratch_texture(7);
  const lit = ctx.lit || (m => m);
  const glass = rim(lit(new THREE.MeshPhysicalMaterial({
    color: 0xffffff, metalness: 0, roughness: 0.035, roughnessMap: rough, transmission: 1, thickness: 0.075, ior: 1.52,
    dispersion: 0.9, attenuationColor: new THREE.Color(0.8, 0.93, 0.84), attenuationDistance: 0.22,
    specularIntensity: 0.7, envMapIntensity: (ctx.env_i ?? 1)*1.1, side: THREE.FrontSide,
  })), ctx.rim ?? 0);
  const frost = lit(new THREE.MeshPhysicalMaterial({
    color: 0xc9d2c8, metalness: 0, roughness: 0.5, transmission: 0.7, thickness: 0.02, ior: 1.52,
    attenuationColor: new THREE.Color(0.8, 0.92, 0.84), attenuationDistance: 0.12, envMapIntensity: ctx.env_i ?? 1,
  }));
  const g = new THREE.Group();
  for (const [geo, mat] of [[top_g, glass], [bot_g, glass], [band_g, frost]]) {
    const m = new THREE.Mesh(geo, mat);
    // clear glass casts no dark shadow (the frosted edge does: a thin ring)
    m.castShadow = mat === frost; m.userData.no_shadow = mat !== frost; m.receiveShadow = false;
    g.add(m);
  }
  g.userData.radius = R;
  return g;
}
