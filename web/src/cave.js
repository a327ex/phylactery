// cave.js -- the dream's cave: a round chamber of dark rock, one narrow shaft in the ceiling
// that lets a column of sunlight fall on the egg at the centre, a tunnel the lich enters by,
// stalagmites, outcrops, slabs and rubble breaking up the floor, stalactites under the dome.
//
// Light (round 2, owner: "more realistic light ... properly model light reflections"):
// - DIRECT: one directional sun. Everything casts shadows and a shadow-only lid covers the
//   scene except the shaft, so the pool on the floor and the visible column are the shadow
//   map's (render.js marches the column through it, Sun Court's method).
// - INDIRECT: baked (gi.js). Light from the pool and the sky seen up the shaft bounces around
//   the rock; static surfaces carry it per vertex, moving things sample a probe grid. No fill
//   lights: what isn't lit by the sun is lit only by what the sun lit.
//
// Colours and surface treatment follow the It Follows egg cover; the geometry does not.
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { make_rng, clamp, smoothstep, lerp } from 'game/util.js';
import * as TX from 'game/textures.js';
import { bake_gi, gi_static, gi_uniforms, export_gi, import_gi } from 'game/gi.js';
import { GI_DATA } from 'game/gi_data.js';

// ---------------------------------------------------------------- geometry noise
function h3(ix, iy, iz, seed) {
  let h = Math.imul(ix | 0, 374761393) ^ Math.imul(iy | 0, 668265263) ^ Math.imul(iz | 0, 2147483647) ^ Math.imul(seed | 0, 1442695041);
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0)/4294967296;
}
function noise3(x, y, z, seed = 0) {
  const ix = Math.floor(x), iy = Math.floor(y), iz = Math.floor(z);
  const fx = x - ix, fy = y - iy, fz = z - iz;
  const u = fx*fx*(3 - 2*fx), v = fy*fy*(3 - 2*fy), w = fz*fz*(3 - 2*fz);
  const L = (a, b, t) => a + (b - a)*t;
  const c = (dx, dy, dz) => h3(ix + dx, iy + dy, iz + dz, seed);
  return L(L(L(c(0, 0, 0), c(1, 0, 0), u), L(c(0, 1, 0), c(1, 1, 0), u), v),
           L(L(c(0, 0, 1), c(1, 0, 1), u), L(c(0, 1, 1), c(1, 1, 1), u), v), w);
}
const fbm3 = (x, y, z, seed, oct = 3) => {
  let s = 0, a = 1, t = 0, f = 1;
  for (let o = 0; o < oct; o++) { s += a*noise3(x*f, y*f, z*f, seed + o*31); t += a; a *= 0.5; f *= 2.03; }
  return s/t;
};

// World-space UVs, one projection per triangle (its dominant axis), so a texture of N texels
// spans N/32 m on every face at any orientation. Geometry must be non-indexed, in world space.
function world_uv(g, tile_m) {
  const p = g.attributes.position, n = p.count;
  const uv = new Float32Array(n*2);
  const a = new THREE.Vector3(), b = new THREE.Vector3(), c = new THREE.Vector3(), nn = new THREE.Vector3();
  for (let i = 0; i < n; i += 3) {
    a.fromBufferAttribute(p, i); b.fromBufferAttribute(p, i + 1); c.fromBufferAttribute(p, i + 2);
    nn.subVectors(c, b).cross(a.clone().sub(b));
    const ax = Math.abs(nn.x), ay = Math.abs(nn.y), az = Math.abs(nn.z);
    for (let k = 0; k < 3; k++) {
      const v = k === 0 ? a : k === 1 ? b : c;
      let u0, v0;
      if (ay >= ax && ay >= az) { u0 = v.x; v0 = v.z; }
      else if (ax >= az) { u0 = v.z; v0 = v.y; }
      else { u0 = v.x; v0 = v.y; }
      uv[(i + k)*2] = u0/tile_m; uv[(i + k)*2 + 1] = v0/tile_m;
    }
  }
  g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  return g;
}

function flat(g) {
  if (g.index) g = g.toNonIndexed();
  g.computeVertexNormals();
  return g;
}

// Wind every triangle so its normal points to the open side, as `want(centre, normal)` says
// (the GI bake gathers from that side). Non-indexed geometry, positions only.
function orient(g, want) {
  const p = g.attributes.position;
  const a = new THREE.Vector3(), b = new THREE.Vector3(), c = new THREE.Vector3(), n = new THREE.Vector3(), m = new THREE.Vector3();
  for (let i = 0; i < p.count; i += 3) {
    a.fromBufferAttribute(p, i); b.fromBufferAttribute(p, i + 1); c.fromBufferAttribute(p, i + 2);
    n.subVectors(b, a).cross(c.clone().sub(a));
    m.copy(a).add(b).add(c).multiplyScalar(1/3);
    if (!want(m, n)) { p.setXYZ(i + 1, c.x, c.y, c.z); p.setXYZ(i + 2, b.x, b.y, b.z); }
  }
  p.needsUpdate = true;
  g.computeVertexNormals();
  return g;
}

// ---------------------------------------------------------------- layout constants
export const LAYOUT = {
  egg: new THREE.Vector3(0, 0, 0),
  // the sun: nearly straight down, tilted a little so the column leans like the cover's
  sun_dir: new THREE.Vector3(0.11, 1, 0.05).normalize(),     // points TO the sun
  floor_r: 15.5,
  tunnel_theta: -Math.PI/2,                                   // tunnel mouth toward -z
  tunnel_half_w: 2.7, tunnel_h: 4.2,
  hover: new THREE.Vector3(0, 0, -2.9),                       // where the lich stops (xz), facing +z
  entrance: new THREE.Vector3(0, 0, -40),
};

export function build_cave(R, seed = 7, opts = {}) {
  const rng = make_rng(seed);
  const group = new THREE.Group();
  R.world_scene.add(group);
  const S = LAYOUT.sun_dir;
  const sun_xz = new THREE.Vector2(S.x/S.y, S.z/S.y);        // horizontal drift per metre of height
  const GU = gi_uniforms();

  // keep-clear zones: the egg's mound and the lich's lane in from the tunnel
  const clear = (x, z, pad = 0) => (x*x + z*z < (3.2 + pad)*(3.2 + pad)) || (Math.abs(x) < 2.6 + pad && z < -1 && z > -20);

  // ---------------------------------------------------------------- ground height
  const MOUND = 0.3;
  function ground_y(x, z) {
    const r2 = x*x + z*z, r = Math.sqrt(r2);
    let y = (fbm3(x*0.21, 0, z*0.21, 91) - 0.5)*0.7 + (noise3(x*0.9, 7.1, z*0.9, 93) - 0.5)*0.14;
    // low ridges of rock breaking through the floor
    const rid = 1 - Math.abs(fbm3(x*0.13, 3.3, z*0.13, 97, 2)*2 - 1);
    y += Math.pow(rid, 6)*0.55*smoothstep(3.5, 7, r);
    y += MOUND*Math.exp(-r2/4.0);                              // the egg's low mound
    y += smoothstep(12.5, 17.5, r)*1.4;                        // the floor climbs into the walls
    return y;
  }

  // ---------------------------------------------------------------- materials
  const tx = { rock: TX.rock(11), floor: TX.floor(21), egg: TX.egg_shell(31) };
  const lam = (map, extra = {}) => gi_static(new THREE.MeshLambertMaterial(Object.assign({ map, color: 0xffffff }, extra)), GU);
  const M = {
    rock: lam(tx.rock, { flatShading: true, shadowSide: THREE.DoubleSide }),
    wall: lam(tx.rock, { flatShading: true, side: THREE.DoubleSide, shadowSide: THREE.DoubleSide }),
    dome: lam(tx.rock, { flatShading: true, side: THREE.DoubleSide, shadowSide: THREE.DoubleSide }),
    floor: lam(tx.floor, { flatShading: true }),
    egg: lam(tx.egg),
  };
  const TILE = 64/TX.TEXELS_PER_METER;                          // 2 m per 64-texel tile
  const statics = [];
  const add_static = (g, mat, cast = true) => {
    const m = new THREE.Mesh(g, mat);
    m.castShadow = cast; m.receiveShadow = true;
    group.add(m);
    statics.push(m);
    return m;
  };

  // ---------------------------------------------------------------- chamber shell (a lathe)
  const PROFILE = [
    [-0.8, 16.8], [0.8, 17.4], [2.6, 17.8], [4.8, 17.2], [7.2, 15.4], [9.4, 12.6], [11.2, 9.6],
    [12.6, 6.8], [13.6, 4.4], [14.3, 2.6], [15.0, 2.1], [16.5, 1.95], [19.0, 2.05], [22.0, 1.95],
    [25.5, 2.1], [29.0, 2.2],
  ];
  const TOP = PROFILE[PROFILE.length - 1][0];
  const axis_at = h => { const k = smoothstep(11.5, 15.0, h); return [sun_xz.x*h*k, sun_xz.y*h*k]; };
  // the dome's height above a given radius (for hanging stalactites)
  const dome_h_at = r => {
    for (let k = 4; k < 10; k++) {
      const [h0, r0] = PROFILE[k], [h1, r1] = PROFILE[k + 1];
      if (r <= r0 && r >= r1) return lerp(h0, h1, (r0 - r)/(r0 - r1));
    }
    return 12;
  };
  const M_SEG = 72;
  const rings = [];
  for (let k = 0; k < PROFILE.length; k++) {
    const [h, r] = PROFILE[k];
    const [cx, cz] = axis_at(h);
    const ring = [];
    for (let j = 0; j < M_SEG; j++) {
      const th = j/M_SEG*Math.PI*2;
      const ct = Math.cos(th), st = Math.sin(th);
      const slab = noise3(th*9.0/(Math.PI*2)*6, h*0.09, 3.3, 17) - 0.5;
      const lump = fbm3(ct*1.6, h*0.16, st*1.6, 23) - 0.5;
      const fine = noise3(ct*5.1, h*0.7, st*5.1, 29) - 0.5;
      const k_d = h < 14 ? 1 : 0.35;
      const rr = r*(1 + (slab*0.30 + lump*0.34 + fine*0.10)*k_d);
      const hy = h + (noise3(ct*3, h*0.5, st*3, 37) - 0.5)*(h < 14 ? 1.2 : 0.4);
      ring.push(new THREE.Vector3(cx + ct*rr, hy, cz + st*rr));
    }
    rings.push(ring);
  }
  const in_mouth = (a, b, c) => {
    const mx = (a.x + b.x + c.x)/3, my = (a.y + b.y + c.y)/3, mz = (a.z + b.z + c.z)/3;
    if (mz > -8) return false;
    const ex = mx/(LAYOUT.tunnel_half_w + 0.6), ey = my/(LAYOUT.tunnel_h + 0.5);
    return ex*ex + ey*ey < 1 || (Math.abs(mx) < LAYOUT.tunnel_half_w + 0.6 && my < 0);
  };
  const DOME_H = 8.5;
  const wall_pos = [], dome_pos = [];
  const tri = (a, b, c) => {
    if (in_mouth(a, b, c)) return;
    ((a.y + b.y + c.y)/3 > DOME_H ? dome_pos : wall_pos).push(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z);
  };
  for (let k = 0; k < rings.length - 1; k++) for (let j = 0; j < M_SEG; j++) {
    const a = rings[k][j], b = rings[k][(j + 1) % M_SEG], c = rings[k + 1][(j + 1) % M_SEG], d = rings[k + 1][j];
    tri(a, c, b); tri(a, d, c);
  }
  // inward: toward the axis at the triangle's height
  const inward = (m, n) => { const [ax, az] = axis_at(m.y); return n.x*(ax - m.x) + n.z*(az - m.z) > 0; };
  const shell_geo = arr => {
    let g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(arr, 3));
    return world_uv(orient(flat(g), inward), TILE);
  };
  add_static(shell_geo(wall_pos), M.wall);
  const dome = add_static(shell_geo(dome_pos), M.dome);
  void dome;

  // a shadow-only lid over everything, holed at the shaft: no sunlight reaches the scene except
  // down the shaft (never drawn; it writes the shadow map and blocks the GI bake's rays)
  const LID_Y = TOP - 1.0, LID_HOLE = 1.9;
  const lid = (() => {
    const g = new THREE.RingGeometry(LID_HOLE, 80, 24, 1);
    const m = new THREE.Mesh(g, new THREE.MeshBasicMaterial({ colorWrite: false, depthWrite: false, side: THREE.DoubleSide }));
    m.rotation.x = -Math.PI/2;
    m.position.set(sun_xz.x*LID_Y, LID_Y, sun_xz.y*LID_Y);
    m.castShadow = true;
    m.frustumCulled = false;
    group.add(m);
    return m;
  })();

  // ---------------------------------------------------------------- tunnel
  {
    const RING = 18, z0 = -12.5, z1 = -46, N = 16;
    const rings_t = [];
    for (let k = 0; k <= N; k++) {
      const z = lerp(z0, z1, k/N);
      const ring = [];
      for (let j = 0; j <= RING; j++) {
        const a = lerp(-0.12, 1.12, j/RING)*Math.PI;
        const w = LAYOUT.tunnel_half_w + 0.9, hh = LAYOUT.tunnel_h + 0.6;
        let x = Math.cos(a)*w, y = Math.max(Math.sin(a), -0.35)*hh;
        const d = 1 + (fbm3(x*0.4, y*0.4, z*0.25, 51) - 0.5)*0.42 + (noise3(j*0.9, 2.2, z*0.6, 53) - 0.5)*0.12;
        x *= d; y = y > 0 ? y*d : y - 0.6;
        ring.push(new THREE.Vector3(x, y, z));
      }
      rings_t.push(ring);
    }
    const tp = [];
    for (let k = 0; k < N; k++) for (let j = 0; j < RING; j++) {
      const a = rings_t[k][j], b = rings_t[k][j + 1], c = rings_t[k + 1][j + 1], d = rings_t[k + 1][j];
      tp.push(a.x, a.y, a.z, c.x, c.y, c.z, b.x, b.y, b.z, a.x, a.y, a.z, d.x, d.y, d.z, c.x, c.y, c.z);
    }
    const e = rings_t[N], ec = new THREE.Vector3(0, 1.5, z1 - 1.5);
    for (let j = 0; j < RING; j++) tp.push(ec.x, ec.y, ec.z, e[j].x, e[j].y, e[j].z, e[j + 1].x, e[j + 1].y, e[j + 1].z);
    let tg = new THREE.BufferGeometry();
    tg.setAttribute('position', new THREE.Float32BufferAttribute(tp, 3));
    const tin = (m, n) => (m.z < z1 - 0.5 ? n.z > 0 : n.x*(0 - m.x) + n.y*(1.4 - m.y) > 0);
    tg = world_uv(orient(flat(tg), tin), TILE);
    add_static(tg, M.wall);
  }

  // ---------------------------------------------------------------- floor
  {
    const x0 = -21, x1 = 21, z0 = -47, z1 = 21, CELL = 0.7;
    const nx = Math.round((x1 - x0)/CELL), nz = Math.round((z1 - z0)/CELL);
    const P = [];
    const vy = (x, z) => ground_y(x, z);
    const jit = (i, j, s) => (h3(i, j, 0, s) - 0.5)*CELL*0.55;
    const vx = (i, j) => [x0 + i*CELL + (i > 0 && i < nx ? jit(i, j, 61) : 0), z0 + j*CELL + (j > 0 && j < nz ? jit(i, j, 67) : 0)];
    for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) {
      const [ax, az] = vx(i, j), [bx, bz] = vx(i + 1, j), [cx, cz] = vx(i + 1, j + 1), [dx, dz] = vx(i, j + 1);
      const mx = (ax + cx)/2, mz = (az + cz)/2;
      const in_ch = mx*mx + mz*mz < 19.5*19.5, in_tu = Math.abs(mx) < 3.1 && mz < -12;
      if (!in_ch && !in_tu) continue;
      P.push(ax, vy(ax, az), az, dx, vy(dx, dz), dz, cx, vy(cx, cz), cz);
      P.push(ax, vy(ax, az), az, cx, vy(cx, cz), cz, bx, vy(bx, bz), bz);
    }
    let g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(P, 3));
    g = world_uv(orient(flat(g), (m, n) => n.y > 0), TILE);
    add_static(g, M.floor);
  }

  // ---------------------------------------------------------------- rocks and formations
  const rocks = [];
  const outward_from = c => (m, n) => n.x*(m.x - c.x) + n.y*(m.y - c.y) + n.z*(m.z - c.z) > 0;
  const add_rock = (x, z, s, sy = 1, tilt = 0.3, sink = 0.35, detail = 0, y_off = 0) => {
    let g = new THREE.IcosahedronGeometry(1, detail);
    g = flat(g);
    const p = g.attributes.position;
    const sd = rng.int(1, 9999);
    for (let i = 0; i < p.count; i++) {
      const vx = p.getX(i), vyy = p.getY(i), vz = p.getZ(i);
      const d = 0.75 + noise3(vx*1.3 + sd, vyy*1.3, vz*1.3, sd)*0.5;
      p.setXYZ(i, vx*d, vyy*d, vz*d);
    }
    const q = new THREE.Quaternion().setFromEuler(new THREE.Euler(rng.spread(tilt), rng.float(0, Math.PI*2), rng.spread(tilt)));
    const c = new THREE.Vector3(x, ground_y(x, z) + s*sy*(1 - sink*2) + y_off, z);
    g.applyMatrix4(new THREE.Matrix4().compose(c, q, new THREE.Vector3(s, s*sy, s)));
    rocks.push(orient(flat(g), outward_from(c)));
  };
  const ang_from_tunnel = th => Math.abs(Math.atan2(Math.sin(th - LAYOUT.tunnel_theta), Math.cos(th - LAYOUT.tunnel_theta)));
  // boulders along the walls, thinning toward the open floor
  for (let i = 0; i < 90; i++) {
    const th = rng.float(0, Math.PI*2);
    if (ang_from_tunnel(th) < 0.24) continue;
    const r = rng.float(12.5, 17.5);
    const s = rng.float(0.4, 1.6)*smoothstep(11, 16, r) + 0.25;
    add_rock(Math.cos(th)*r, Math.sin(th)*r, s, rng.float(0.6, 1.2));
  }
  // scattered stones on the open floor
  for (let i = 0; i < 90; i++) {
    const th = rng.float(0, Math.PI*2), r = rng.float(3.2, 13);
    const x = Math.cos(th)*r, z = Math.sin(th)*r;
    if (Math.abs(x) < 2.2 && z < -2) continue;
    add_rock(x, z, rng.float(0.08, 0.3), rng.float(0.5, 1), 0.6, 0.3);
  }
  // rubble around the egg's mound
  for (let i = 0; i < 22; i++) {
    const th = rng.float(0, Math.PI*2), r = rng.float(0.7, 1.9);
    add_rock(Math.cos(th)*r, Math.sin(th)*r, rng.float(0.06, 0.17), rng.float(0.5, 0.9), 0.7, 0.25);
  }
  // outcrops: masses of fused boulders rising out of the floor
  const OUTCROPS = [];
  for (let n = 0, tries = 0; n < 7 && tries < 200; tries++) {
    const th = rng.float(0, Math.PI*2), r = rng.float(6.5, 12.5);
    const x = Math.cos(th)*r, z = Math.sin(th)*r;
    if (clear(x, z, 1.8) || OUTCROPS.some(o => Math.hypot(o[0] - x, o[1] - z) < 5)) continue;
    OUTCROPS.push([x, z]); n++;
    const H = rng.float(1.2, 2.8), W = rng.float(1.2, 2.2);
    for (let k = 0; k < 4; k++) {
      const ox = rng.spread(W*0.7), oz = rng.spread(W*0.7);
      add_rock(x + ox, z + oz, W*rng.float(0.55, 0.9), H/W*rng.float(0.7, 1.1), 0.25, 0.2, 1);
    }
    add_rock(x, z, W*0.6, 0.7, 0.4, 0.1, 1, H*0.55);           // a cap on top
  }
  // stalagmites: clusters of tapered, lumpy columns
  const stalag = (x, z, h, r0, lean) => {
    const pts = [];
    const NS = 7;
    for (let k = 0; k <= NS; k++) {
      const t = k/NS;
      const rr = r0*Math.pow(1 - t, 0.85)*(1 + (noise3(x*3, t*4, z*3, 71) - 0.5)*0.5) + (k === NS ? 0 : 0.02);
      pts.push(new THREE.Vector2(Math.max(rr, 0.015), t*h - 0.3));
    }
    let g = new THREE.LatheGeometry(pts, 8);
    g = flat(g);
    const p = g.attributes.position;
    const sd = rng.int(1, 9999);
    for (let i = 0; i < p.count; i++) {
      const vx = p.getX(i), vyy = p.getY(i), vz = p.getZ(i);
      const t = clamp(vyy/h, 0, 1);
      const d = 1 + (noise3(vx*4 + sd, vyy*1.8, vz*4, sd) - 0.5)*0.45;
      p.setXYZ(i, vx*d + lean[0]*t*t*h, vyy, vz*d + lean[1]*t*t*h);
    }
    const c = new THREE.Vector3(x, ground_y(x, z), z);
    g.applyMatrix4(new THREE.Matrix4().makeRotationY(rng.float(0, 6.28)).setPosition(c));
    rocks.push(orient(flat(g), (m, n) => n.x*(m.x - c.x - lean[0]*0) + n.z*(m.z - c.z) + n.y*0.3 > 0));
  };
  const CLUSTERS = [];
  for (let n = 0, tries = 0; n < 11 && tries < 300; tries++) {
    const th = rng.float(0, Math.PI*2), r = rng.float(4.5, 15.5);
    const x = Math.cos(th)*r, z = Math.sin(th)*r;
    if (clear(x, z, 1.2) || ang_from_tunnel(th) < 0.3 && r > 11) continue;
    if (CLUSTERS.some(o => Math.hypot(o[0] - x, o[1] - z) < 3.2) || OUTCROPS.some(o => Math.hypot(o[0] - x, o[1] - z) < 3)) continue;
    CLUSTERS.push([x, z]); n++;
    const big = smoothstep(7, 15, r);                           // taller toward the walls
    const cnt = rng.int(2, 6);
    for (let k = 0; k < cnt; k++) {
      const sx = x + rng.spread(1.1), sz = z + rng.spread(1.1);
      const h = (k === 0 ? 1.4 : rng.float(0.35, 0.9))*lerp(1.2, 4.2, big)*rng.float(0.7, 1.15);
      stalag(sx, sz, h, h*rng.float(0.13, 0.2) + 0.1, [rng.spread(0.04), rng.spread(0.04)]);
    }
  }
  // tall broken slabs leaning against the walls
  for (let i = 0; i < 34; i++) {
    const th = rng.float(0, Math.PI*2);
    if (ang_from_tunnel(th) < 0.3) continue;
    const r = rng.float(15.2, 17.2);
    const x = Math.cos(th)*r, z = Math.sin(th)*r;
    const hgt = rng.float(2.5, 7.5), wid = rng.float(0.9, 2.4), dep = rng.float(0.35, 0.8);
    let g = new THREE.BoxGeometry(wid, hgt, dep, 2, 4, 1);
    const p = g.attributes.position, sd = rng.int(1, 9999);
    for (let k = 0; k < p.count; k++) {
      const vx = p.getX(k), vyy = p.getY(k), vz = p.getZ(k);
      const top = vyy/hgt + 0.5;
      p.setXYZ(k, vx*(1 - top*0.45) + (noise3(vx, vyy*0.6, vz, sd) - 0.5)*0.5, vyy + (noise3(vx*2, vyy, vz, sd + 3) - 0.5)*0.6, vz + (noise3(vx, vyy, vz*2, sd + 5) - 0.5)*0.3);
    }
    g = flat(g);
    const yaw = Math.atan2(x, z);
    const q = new THREE.Quaternion().setFromEuler(new THREE.Euler(-rng.float(0.05, 0.3), yaw, rng.spread(0.12), 'YXZ'));
    const c = new THREE.Vector3(x, ground_y(x, z) + hgt*0.42, z);
    g.applyMatrix4(new THREE.Matrix4().compose(c, q, new THREE.Vector3(1, 1, 1)));
    rocks.push(orient(flat(g), outward_from(c)));
  }
  {
    const g = world_uv(mergeGeometries(rocks, false), TILE);
    add_static(g, M.rock);
  }
  // stalactites under the dome (they belong to the dome: hidden with it from above)
  {
    const tites = [];
    for (let i = 0; i < 40; i++) {
      const th = rng.float(0, Math.PI*2), r = rng.float(4.5, 13);
      const x = Math.cos(th)*r, z = Math.sin(th)*r;
      const top = dome_h_at(r) + 0.6;
      const h = rng.float(0.5, 2.6)*smoothstep(3.5, 9, r) + 0.3;
      const pts = [];
      for (let k = 0; k <= 5; k++) { const t = k/5; pts.push(new THREE.Vector2(Math.max(0.015, (h*0.16 + 0.06)*Math.pow(1 - t, 1.1)), -t*h)); }
      let g = flat(new THREE.LatheGeometry(pts, 6));
      const p = g.attributes.position, sd = rng.int(1, 9999);
      for (let k = 0; k < p.count; k++) {
        const vx = p.getX(k), vyy = p.getY(k), vz = p.getZ(k);
        const d = 1 + (noise3(vx*5 + sd, vyy*2, vz*5, sd) - 0.5)*0.5;
        p.setXYZ(k, vx*d, vyy, vz*d);
      }
      const c = new THREE.Vector3(x, top, z);
      g.applyMatrix4(new THREE.Matrix4().setPosition(c));
      tites.push(orient(flat(g), (m, n) => n.x*(m.x - c.x) + n.z*(m.z - c.z) - n.y*0.3 > 0));
    }
    add_static(world_uv(mergeGeometries(tites, false), TILE), M.dome);
  }

  // ---------------------------------------------------------------- the egg (0.8 m tall)
  const EGG_S = 0.8;
  const egg = new THREE.Group();
  {
    let g = new THREE.SphereGeometry(0.5, 24, 16);
    const p = g.attributes.position;
    for (let i = 0; i < p.count; i++) {
      const x = p.getX(i), y = p.getY(i), z = p.getZ(i);
      const taper = 1 - 0.14*clamp(y/0.5, 0, 1) + 0.03*clamp(-y/0.5, 0, 1);
      p.setXYZ(i, x*0.78*taper*EGG_S, y*EGG_S, z*0.78*taper*EGG_S);
    }
    g.computeVertexNormals();
    g = g.toNonIndexed();                                        // keeps the smooth normals
    const m = new THREE.Mesh(g, M.egg);
    m.position.y = 0.5*EGG_S;
    m.castShadow = true; m.receiveShadow = true;
    egg.add(m);
    egg.userData.shell = m;
    statics.push(m);
  }
  egg.position.set(0, ground_y(0, 0) - 0.03, 0);
  group.add(egg);

  // ---------------------------------------------------------------- the sun
  const SUN_E = opts.sun_E || 9.0;
  const SUN_COL = new THREE.Color(0xffe6b8);
  const sun = new THREE.DirectionalLight(SUN_COL, SUN_E);
  sun.position.copy(S).multiplyScalar(40);
  sun.target.position.set(0, 0, 0);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  {
    const sc = sun.shadow.camera;
    const X = new THREE.Vector3(1, 0, 0);
    const Rx = X.clone().sub(S.clone().multiplyScalar(X.dot(S))).normalize();
    const Uy = new THREE.Vector3().crossVectors(S, Rx);
    sc.up.copy(Uy);
    let a0 = Infinity, a1 = -Infinity, b0 = Infinity, b1 = -Infinity;
    for (const cx of [-21, 21]) for (const cy of [-1.5, TOP + 1]) for (const cz of [-48, 21]) {
      const v = new THREE.Vector3(cx, cy, cz);
      a0 = Math.min(a0, v.dot(Rx)); a1 = Math.max(a1, v.dot(Rx)); b0 = Math.min(b0, v.dot(Uy)); b1 = Math.max(b1, v.dot(Uy));
    }
    const tx_ = (a1 - a0)/2048, ty_ = (b1 - b0)/2048;
    sc.left = Math.floor(a0/tx_)*tx_; sc.right = Math.ceil(a1/tx_)*tx_; sc.bottom = Math.floor(b0/ty_)*ty_; sc.top = Math.ceil(b1/ty_)*ty_;
    sc.near = 1; sc.far = 90;
    sc.updateProjectionMatrix();
  }
  sun.shadow.bias = -0.0005;
  sun.shadow.normalBias = 0.03;
  group.add(sun, sun.target);
  // a glimpse of sky at the top of the shaft: an HDR cap for the bloom to catch
  const SKY_L = [2.4, 2.5, 2.7];
  {
    const g = new THREE.CircleGeometry(2.8, 16);
    const m = new THREE.Mesh(g, new THREE.MeshBasicMaterial({ color: new THREE.Color(9, 8.4, 7.2), side: THREE.DoubleSide }));
    m.rotation.x = Math.PI/2;
    m.position.set(sun_xz.x*(TOP - 0.3), TOP - 0.3, sun_xz.y*(TOP - 0.3));
    group.add(m);
  }

  // ---------------------------------------------------------------- bake the bounce light
  const t0 = performance.now();
  const baked = bake_gi(statics, {
    sun_dir: S, sun_E: [SUN_COL.r*SUN_E, SUN_COL.g*SUN_E, SUN_COL.b*SUN_E],
    sky: { y: LID_Y, cx: sun_xz.x*LID_Y, cz: sun_xz.y*LID_Y, r: LID_HOLE, L: SKY_L },
    rays: opts.rays || 64, bounces: opts.bounces || 3, occluders: [lid], seed: 5, denoise: 0.9,
    cache: import_gi(GI_DATA),
    // the column: radius of the shaft, radiance per metre of chord = shaft colour x mean phase x
    // density (render.js draws it with the same law)
    beam: { x: 0, z: 0, r: LID_HOLE*0.95, h: 60, L: [1.0*0.5*0.022, 0.8*0.5*0.022, 0.46*0.5*0.022] },
    grid: { min: [-17, 0.2, -24], max: [17, 6.5, 17], n: [18, 6, 22], rays: 64 },
  });
  const bake_ms = performance.now() - t0;
  GU.uGIUp.value = baked.probes.up; GU.uGIDown.value = baked.probes.down;
  GU.uGIMin.value.copy(baked.probes.min); GU.uGIMax.value.copy(baked.probes.max);

  // ---------------------------------------------------------------- atmosphere (render.js)
  const P = R.params;
  R.world_scene.background = new THREE.Color(0x000000);
  P.sky.on = false;
  Object.assign(P.fog, { near: 8, far: 50, max: 0.6, curve: 1.3, sky: 0.0, base_y: 0, falloff: 0.0, height_mix: 0.0 });
  P.fog.color.setRGB(0.004, 0.0037, 0.0034);
  P.shafts = { on: true, light: sun, color: [1.0, 0.8, 0.46], density: 0.022, max_dist: 48, steps: 40, phase: 0.35, ambient: 0.0,
    streak: 0.85, rise: 1.0 };
  P.dither_dark = [0.04, 0.16];
  R.set_shadow_light(sun);
  R.rebuild();
  P.bloom = { strength: 0.32, threshold: 1.25 };
  P.vignette = 0.3;
  P.contrast = 1.04; P.saturation = 1.04;
  P.lift = [0.003, 0.002, 0.006];

  // dust in the column
  const DUST = 160;
  const dust_pos = new Float32Array(DUST*3), dust_col = new Float32Array(DUST*3), dust = [];
  for (let i = 0; i < DUST; i++) {
    dust.push({ h: rng.float(0.3, 20), a: rng.float(0, 6.283), r: Math.sqrt(rng.next())*1.6, v: rng.float(0.03, 0.12), w: rng.float(0.05, 0.25), b: rng.float(0.4, 1) });
  }
  const dust_geo = new THREE.BufferGeometry();
  dust_geo.setAttribute('position', new THREE.BufferAttribute(dust_pos, 3));
  dust_geo.setAttribute('color', new THREE.BufferAttribute(dust_col, 3));
  const dust_pts = new THREE.Points(dust_geo, new THREE.PointsMaterial({ size: 1, sizeAttenuation: false, vertexColors: true,
    transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }));
  dust_pts.frustumCulled = false;
  group.add(dust_pts);
  function update_dust(t, dt) {
    for (let i = 0; i < DUST; i++) {
      const d = dust[i];
      d.h -= d.v*dt; d.a += d.w*dt;
      if (d.h < 0.2) d.h = 20;
      const cx = sun_xz.x*d.h, cz = sun_xz.y*d.h;
      dust_pos[i*3] = cx + Math.cos(d.a)*d.r; dust_pos[i*3 + 1] = d.h; dust_pos[i*3 + 2] = cz + Math.sin(d.a)*d.r;
      const tw = 0.6 + 0.4*Math.sin(t*1.7 + i*1.3);
      const k = d.b*tw*(0.55 + 0.45*Math.min(1, d.h/10))*0.6;
      dust_col[i*3] = 1.5*k; dust_col[i*3 + 1] = 1.25*k; dust_col[i*3 + 2] = 0.8*k;
    }
    dust_geo.attributes.position.needsUpdate = true;
    dust_geo.attributes.color.needsUpdate = true;
  }

  // exposure: a realistic range (the pool is hundreds of times brighter than the far rock), so
  // how much of the cave shows is how the "camera" is exposed; the pool rolls off in the shoulder
  // The bake is physical; its LEVEL is art direction (owner, round 1: "between dim and
  // readable"). The bounce keeps its realistic distribution -- bright by the pool and the
  // column, soft falloff, dark in occluded corners -- scaled as a whole.
  const DARK = [
    { name: 'DIMMER', gi: 5, exposure: 2.2 },
    { name: 'BETWEEN DIM AND READABLE', gi: 10, exposure: 2.2 },
    { name: 'BRIGHTER', gi: 18, exposure: 2.2 },
  ];

  const dome_mats = [M.dome];
  return {
    group, ground_y, egg, sun, LAYOUT, GU, bake_ms, tris: baked.tris, gi_cached: baked.cached,
    export_gi: () => export_gi(baked.data),
    set_dome_visible(on) { for (const m of dome_mats) { m.colorWrite = on; m.depthWrite = on; } },
    DARK,
    set_darkness(i) {
      const d = DARK[((i % DARK.length) + DARK.length) % DARK.length];
      P.exposure = d.exposure;
      GU.uGIScale.value = d.gi;
      return d.name;
    },
    update(t, dt) {
      update_dust(t, dt);
      const shell = egg.userData.shell;
      const k = Math.max(0, Math.sin(t*0.9)*Math.sin(t*2.3) - 0.55)*1.6;
      shell.rotation.z = Math.sin(t*38)*0.035*k;
      shell.rotation.x = Math.cos(t*31)*0.025*k;
    },
  };
}
