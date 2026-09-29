// item_lodestone.js -- the ROCK power's object (owner, round 28's board: "raw lodestone is fine").
//
// Round 30 (owner: "remove the iron filings, they make me feel weird, and make the rock a bit more
// jagged instead of curved all around"): a broken lump of magnetite, all fracture: flat and
// stepped faces meeting at sharp edges, a few chunks knocked out of it (notches with their own
// faces); iron-black with a dull grey lustre and a few bright flakes, rust in its hollows. No
// filings.
import * as THREE from 'three';
import { mesh_sdf, smax } from 'game/sdf.js';
import { fbm3, cells3, sstep, rand, vertex_mr } from 'game/shape_noise.js';

// a convex chunk: planes n.p <= w (random normals, uneven offsets, squashed to the stone's shape)
function chunk(R, count, s, jit) {
  const out = [];
  for (let i = 0; i < count; i++) {
    const y = 1 - 2*(i + 0.5)/count, r = Math.sqrt(1 - y*y), a = i*2.39996 + R.s(0.5);
    const n = new THREE.Vector3(Math.cos(a)*r + R.s(0.3), y + R.s(0.3), Math.sin(a)*r + R.s(0.3)).normalize();
    const w = 1 - R.f(0, jit);
    const m = new THREE.Vector3(n.x/s[0], n.y/s[1], n.z/s[2]);
    out.push({ n: m.clone().normalize(), w: w/m.length() });
  }
  return out;
}
const R = rand(733);
const MAIN = chunk(R, 26, [0.078, 0.05, 0.058], 0.22);
// knocked out: smaller chunks centred on the surface
const NOTCH = [0, 1, 2].map(() => {
  const a = R.f(0, 6.28), b = R.f(-0.8, 0.8);
  const c = new THREE.Vector3(Math.cos(a)*Math.cos(b)*0.07, Math.sin(b)*0.045, Math.sin(a)*Math.cos(b)*0.055);
  return { c, planes: chunk(R, 12, [0.022, 0.018, 0.02].map(v => v*R.f(0.8, 1.3)), 0.3) };
});
const convex = (planes, x, y, z) => { let d = -Infinity; for (const p of planes) d = Math.max(d, p.n.x*x + p.n.y*y + p.n.z*z - p.w); return d; };

function body(x, y, z) {
  let d = convex(MAIN, x, y, z);
  if (d > 0.02) return d;
  for (const nt of NOTCH) d = smax(d, -convex(nt.planes, x - nt.c.x, y - nt.c.y, z - nt.c.z), 0.0015);
  return d;
}
function field(x, y, z) {
  const d = body(x, y, z);
  if (d > 0.008) return d;
  return d - (fbm3(x*90, y*90, z*90, 73, 3) - 0.5)*0.0022 - (fbm3(x*300, y*300, z*300, 75, 2) - 0.5)*0.0007;
}

let CACHE = null;
function build_geo() {
  if (CACHE) return CACHE;
  const g = mesh_sdf(field, [-0.1, -0.075, -0.08, 0.1, 0.075, 0.08], 0.001);
  const P = g.attributes.position, N = g.attributes.normal, n = P.count;
  const col = new Float32Array(n*3), mr = new Float32Array(n*2);
  for (let i = 0; i < n; i++) {
    const x = P.getX(i), y = P.getY(i), z = P.getZ(i), nx = N.getX(i), ny = N.getY(i), nz = N.getZ(i);
    const open = Math.min(1, Math.max(0, body(x + nx*0.006, y + ny*0.006, z + nz*0.006)/0.006));
    const rust = sstep(0.64, 0.8, fbm3(x*30, y*30, z*30, 77, 3))*0.55 + sstep(0.7, 0.3, open)*0.4;
    const flake = cells3(x*140, y*140, z*140, 79);
    const shiny = flake.id > 0.88 ? 1 : 0;
    // iron-black, a grey lustre (not the warm light's colour: metal reflects it, so little metal)
    const v = 0.028 + 0.018*fbm3(x*70, y*70, z*70, 81, 2);
    let r = v, gg = v*1.01, b = v*1.05, metal = 0.12 + 0.5*shiny, rough = 0.55 - 0.25*shiny;
    const k = Math.min(1, rust);
    r += (0.16 - r)*k; gg += (0.085 - gg)*k; b += (0.04 - b)*k;
    metal *= 1 - k; rough += (0.92 - rough)*k;
    col[i*3] = r; col[i*3 + 1] = gg; col[i*3 + 2] = b;
    mr[i*2] = metal; mr[i*2 + 1] = rough;
  }
  g.setAttribute('color', new THREE.BufferAttribute(col, 3));
  g.setAttribute('aMR', new THREE.BufferAttribute(mr, 2));
  CACHE = g;
  return g;
}

export function build_lodestone(ctx = {}) {
  const lit = ctx.lit || (m => m);
  const mat = lit(vertex_mr(new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.5, metalness: 0.4, envMapIntensity: ctx.env_i ?? 1 })));
  const stone = new THREE.Mesh(build_geo(), mat);
  stone.castShadow = true;
  const grp = new THREE.Group();
  grp.add(stone);
  return grp;
}
