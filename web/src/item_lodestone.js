// item_lodestone.js -- round 29: the ROCK power's object (owner, round 28's board: "raw lodestone
// is fine"). A lump of magnetite: iron-black with a dull metallic lustre, a couple of flat broken
// faces, rust in its hollows; and what makes it a lodestone: iron filings standing up out of it in
// bristling beards at its two poles, each a little chain of needles following the field's lines
// (a dipole along the stone's length), a few more lying flat over the rest of it.
import * as THREE from 'three';
import { mesh_sdf, smax, ellipsoid } from 'game/sdf.js';
import { fbm3, cells3, sstep, rand, vertex_mr } from 'game/shape_noise.js';

function body(x, y, z) {
  let d = ellipsoid(x, y, z, 0, 0, 0, 0.074, 0.047, 0.053);
  if (d > 0.02) return d;
  d -= (fbm3(x*17 + 3, y*17, z*17, 71, 3) - 0.5)*0.026;            // lumps
  d -= (fbm3(x*55, y*55, z*55 + 7, 73, 2) - 0.5)*0.007;             // knobs
  // two faces where it broke off
  d = smax(d, x*0.35 + y*0.2 + z*0.91 - 0.034, 0.005);
  d = smax(d, -x*0.1 - y*0.97 + z*0.2 - 0.033, 0.004);
  return d;
}
function field(x, y, z) {
  const d = body(x, y, z);
  if (d > 0.008) return d;
  return d - (fbm3(x*260, y*260, z*260, 75, 2) - 0.5)*0.0011;       // grain
}

// the dipole's field direction at p (moment along +x through the middle)
const B = (p, out) => {
  const r = p.length() || 1e-6, rx = p.x/r, ry = p.y/r, rz = p.z/r;
  return out.set(3*rx*rx - 1, 3*rx*ry, 3*rx*rz).normalize();
};

let CACHE = null;
function build_geo() {
  if (CACHE) return CACHE;
  const g = mesh_sdf(field, [-0.1, -0.075, -0.08, 0.1, 0.075, 0.08], 0.0012);
  const P = g.attributes.position, N = g.attributes.normal, n = P.count;
  const col = new Float32Array(n*3), mr = new Float32Array(n*2);
  for (let i = 0; i < n; i++) {
    const x = P.getX(i), y = P.getY(i), z = P.getZ(i), nx = N.getX(i), ny = N.getY(i), nz = N.getZ(i);
    const open = Math.min(1, Math.max(0, body(x + nx*0.006, y + ny*0.006, z + nz*0.006)/0.006));
    const rust = sstep(0.62, 0.78, fbm3(x*30, y*30, z*30, 77, 3))*0.6 + sstep(0.7, 0.3, open)*0.4;
    const flake = cells3(x*140, y*140, z*140, 79);
    const shiny = flake.id > 0.88 ? 1 : 0;
    const v = 0.02 + 0.014*fbm3(x*70, y*70, z*70, 81, 2);
    let r = v, gg = v, b = v*1.06, metal = 0.35 + 0.45*shiny, rough = 0.4 - 0.18*shiny;
    const k = Math.min(1, rust);
    r += (0.16 - r)*k; gg += (0.085 - gg)*k; b += (0.04 - b)*k;
    metal *= 1 - k; rough += (0.92 - rough)*k;
    col[i*3] = r; col[i*3 + 1] = gg; col[i*3 + 2] = b;
    mr[i*2] = metal; mr[i*2 + 1] = rough;
  }
  g.setAttribute('color', new THREE.BufferAttribute(col, 3));
  g.setAttribute('aMR', new THREE.BufferAttribute(mr, 2));

  // the filings: chains of needles from roots on the surface, crowded at the poles
  const R = rand(91), M = [];
  const p = new THREE.Vector3(), q = new THREE.Vector3(), d = new THREE.Vector3(), nn = new THREE.Vector3(), jit = new THREE.Vector3();
  const needle = (a, b, th) => M.push([a.clone(), b.clone(), th]);
  for (let tries = 0, roots = 0; tries < 90000 && roots < 700; tries++) {
    const i = Math.floor(R.next()*n);
    p.fromBufferAttribute(P, i); nn.fromBufferAttribute(N, i);
    const pole = sstep(0.05, 0.078, Math.abs(p.x) + 0.2*Math.abs(nn.x)*0.02);
    if (R.next() > pole*0.97 + 0.004) continue;
    roots++;
    const chains = 1 + Math.floor(R.next()*2.5*pole);
    for (let c = 0; c < chains; c++) {
      q.copy(p).addScaledVector(nn, -0.0005);
      const segs = 1 + Math.floor(R.next()*(1.5 + 3.5*pole));
      for (let s = 0; s < segs; s++) {
        B(q, d);
        if (d.dot(nn) < 0) d.negate();
        d.addScaledVector(nn, 0.35).add(jit.set(R.s(0.3), R.s(0.3), R.s(0.3))).normalize();
        const L = R.f(0.0022, 0.0042)*(1 - s*0.06);
        const e = q.clone().addScaledVector(d, L);
        needle(q, e, R.f(0.00025, 0.00042));
        q.copy(e);
      }
    }
  }
  // a few lying flat over the rest of it
  for (let k = 0; k < 360; k++) {
    const i = Math.floor(R.next()*n);
    p.fromBufferAttribute(P, i); nn.fromBufferAttribute(N, i);
    d.set(R.s(1), R.s(1), R.s(1)).addScaledVector(nn, -d.dot(nn)).normalize();
    const L = R.f(0.002, 0.004);
    needle(p.clone().addScaledVector(nn, 0.0003).addScaledVector(d, -L/2), p.clone().addScaledVector(nn, 0.0003).addScaledVector(d, L/2), R.f(0.0003, 0.0005));
  }
  CACHE = { g, M };
  return CACHE;
}

export function build_lodestone(ctx = {}) {
  const lit = ctx.lit || (m => m);
  const { g, M } = build_geo();
  const mat = lit(vertex_mr(new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.5, metalness: 0.5, envMapIntensity: ctx.env_i ?? 1 })));
  const stone = new THREE.Mesh(g, mat);
  stone.castShadow = true;
  // one needle: a thin box 1 m long along y, scaled per instance
  const ng = new THREE.BoxGeometry(1, 1, 1); ng.translate(0, 0.5, 0);
  const fmat = lit(new THREE.MeshStandardMaterial({ color: 0x1c1c20, roughness: 0.4, metalness: 0.8, envMapIntensity: ctx.env_i ?? 1 }));
  const inst = new THREE.InstancedMesh(ng, fmat, M.length);
  const m4 = new THREE.Matrix4(), qq = new THREE.Quaternion(), up = new THREE.Vector3(0, 1, 0), dir = new THREE.Vector3(), sc = new THREE.Vector3();
  M.forEach(([a, b, th], i) => {
    dir.subVectors(b, a); const L = dir.length(); dir.multiplyScalar(1/L);
    qq.setFromUnitVectors(up, dir);
    m4.compose(a, qq, sc.set(th, L, th));
    inst.setMatrixAt(i, m4);
  });
  inst.instanceMatrix.needsUpdate = true;
  inst.computeBoundingSphere(); inst.computeBoundingBox();
  inst.castShadow = true;
  inst.userData.no_contact = true;
  const grp = new THREE.Group();
  grp.add(stone, inst);
  return grp;
}
