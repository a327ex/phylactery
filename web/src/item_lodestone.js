// item_lodestone.js -- the ROCK power's object (owner, round 28's board: "raw lodestone is fine").
//
// Round 30 (owner: "remove the iron filings, they make me feel weird, and make the rock a bit more
// jagged instead of curved all around"): a broken lump of magnetite, all fracture: flat and
// stepped faces meeting at sharp edges, a few chunks knocked out of it (notches with their own
// faces); iron-black with a dull grey lustre and a few bright flakes, rust in its hollows. No
// filings.
//
// Round 31 (owner: "a more destroyed look, it looks a bit too plastic right now"): weathered and
// broken all over: the faces pocked with cavities and pits, cracks running across them, the edges
// crumbled, a granular, lumpy surface at three scales; matte, speckled grain to grain, a brown
// weathering crust in patches, grey dust in the pits; the metal only in small bright flakes.
import * as THREE from 'three';
import { named } from 'game/util.js';
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
// what weathering did to its surface: lumps at three scales, pits and cavities, cracks, crumbled
// edges (where the surface is sharpest the noise bites deepest)
function wear(x, y, z) {
  const lump = (fbm3(x*45, y*45, z*45, 73, 3) - 0.5)*0.004 + (fbm3(x*140, y*140, z*140, 74, 2) - 0.5)*0.0018 + (fbm3(x*420, y*420, z*420, 75, 2) - 0.5)*0.0007;
  const pc = cells3(x*180, y*180, z*180, 76);
  const pit = pc.id > 0.5 ? sstep(0.42, 0.08, pc.d1)*(0.0006 + 0.0012*pc.id) : 0;
  const vc = cells3(x*55, y*55, z*55, 77);
  const vug = vc.id > 0.8 ? sstep(0.35, 0.05, vc.d1)*0.003 : 0;
  const cc = cells3(x*28 + 3.3, y*28, z*28, 78);
  const crack = sstep(0.05, 0.012, cc.edge)*sstep(0.45, 0.6, fbm3(x*18, y*18, z*18, 79, 2));
  return { disp: lump - pit - vug - crack*0.0012, pit: pit > 0 ? 1 : 0, vug: vug > 0 ? 1 : 0, crack };
}
function field(x, y, z) {
  const d = body(x, y, z);
  if (d > 0.01) return d;
  // crumbled edges: near an edge between faces the field is shallow; noise there bites deeper
  const e = 0.0035, gx = body(x + e, y, z) - body(x - e, y, z), gy = body(x, y + e, z) - body(x, y - e, z), gz = body(x, y, z + e) - body(x, y, z - e);
  const edge = 1 - Math.min(1, Math.hypot(gx, gy, gz)/(2*e));
  const crumble = edge*sstep(0.45, 0.7, fbm3(x*70, y*70, z*70, 80, 3))*0.006;
  return d - wear(x, y, z).disp + crumble;
}

let CACHE = null;
function build_geo() {
  if (CACHE) return CACHE;
  const g = mesh_sdf(field, [-0.1, -0.075, -0.08, 0.1, 0.075, 0.08], 0.0009);
  const P = g.attributes.position, N = g.attributes.normal, n = P.count;
  const col = new Float32Array(n*3), mr = new Float32Array(n*2);
  for (let i = 0; i < n; i++) {
    const x = P.getX(i), y = P.getY(i), z = P.getZ(i), nx = N.getX(i), ny = N.getY(i), nz = N.getZ(i);
    const open = Math.min(1, Math.max(0, field(x + nx*0.004, y + ny*0.004, z + nz*0.004)/0.004));
    const wr = wear(x, y, z);
    const crust = sstep(0.58, 0.74, fbm3(x*26, y*26, z*26, 82, 3));
    const grain = cells3(x*400, y*400, z*400, 83);
    const flake = cells3(x*160, y*160, z*160, 84);
    const shiny = flake.id > 0.93 && wr.pit === 0 ? 1 : 0;
    // iron-black, speckled grain to grain, matte; the metal only in small flakes
    const v = 0.022 + 0.022*grain.id + 0.012*fbm3(x*70, y*70, z*70, 81, 2);
    let r = v, gg = v*1.01, b = v*1.04, metal = 0.55*shiny, rough = 0.86 - 0.5*shiny;
    // the weathering crust: brown, dull
    const k = Math.min(1, crust*0.8 + sstep(0.75, 0.35, open)*0.35);
    r += (0.12 - r)*k; gg += (0.07 - gg)*k; b += (0.04 - b)*k;
    metal *= 1 - k; rough += (0.95 - rough)*k;
    // grey dust in the pits, cavities and cracks; dark where the surface folds in
    const dust = Math.max(wr.pit*0.7, wr.vug*0.8, wr.crack*0.6);
    r += (0.07 - r)*dust; gg += (0.066 - gg)*dust; b += (0.062 - b)*dust;
    const dark = sstep(0.55, 0.1, open)*0.6;
    r *= 1 - dark; gg *= 1 - dark; b *= 1 - dark;
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
  const mat = lit(vertex_mr(named(new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.85, metalness: 0, envMapIntensity: (ctx.env_i ?? 1)*0.7 }), 'item.lodestone')));
  const stone = new THREE.Mesh(build_geo(), mat);
  stone.castShadow = true;
  const grp = new THREE.Group();
  grp.add(stone);
  return grp;
}
