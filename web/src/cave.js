// cave.js -- the dream's cave: a round chamber in near-black rock, one narrow shaft in the
// ceiling that lets a column of sunlight fall on the egg at the centre, a tunnel the lich
// enters by, rubble and tall broken slabs around the walls.
//
// Everything that should block the light casts shadows (shadowSide = DoubleSide), so the pool
// of light on the floor and the visible column are the SHADOW MAP's doing, not painted: the
// sun is a directional light from above and the ceiling hides all of it but the shaft. The
// column is render.js's shaft pass marching through that shadow map (Sun Court's method).
//
// Colours and surface treatment follow the It Follows egg cover; the geometry does not.
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { make_rng, clamp, smoothstep, lerp } from 'game/util.js';
import * as TX from 'game/textures.js';

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

// ---------------------------------------------------------------- layout constants
export const LAYOUT = {
  egg: new THREE.Vector3(0, 0, 0),
  // the sun: nearly straight down, tilted a little so the column leans like the cover's
  sun_dir: new THREE.Vector3(0.11, 1, 0.05).normalize(),     // points TO the sun
  floor_r: 15.5,                                              // open floor radius (walls start ~16-18)
  tunnel_theta: -Math.PI/2,                                   // tunnel mouth toward -z
  tunnel_half_w: 2.7, tunnel_h: 4.2,
  hover: new THREE.Vector3(0, 0, -3.6),                       // where the lich stops (xz), facing +z
  entrance: new THREE.Vector3(0, 0, -40),
};

export function build_cave(R, seed = 7) {
  const rng = make_rng(seed);
  const group = new THREE.Group();
  R.world_scene.add(group);
  const S = LAYOUT.sun_dir;
  const sun_xz = new THREE.Vector2(S.x/S.y, S.z/S.y);        // horizontal drift per metre of height

  // ---------------------------------------------------------------- ground height
  const MOUND = 0.34;
  function ground_y(x, z) {
    const r2 = x*x + z*z;
    let y = (fbm3(x*0.23, 0, z*0.23, 91) - 0.5)*0.55 + (noise3(x*0.9, 7.1, z*0.9, 93) - 0.5)*0.12;
    y += MOUND*Math.exp(-r2/5.0);                              // the egg's low mound
    y -= 0.18*smoothstep(4, 12, Math.sqrt(r2));                // the bowl dips a little toward the walls
    return y;
  }

  // ---------------------------------------------------------------- materials
  const tx = { rock: TX.rock(11), floor: TX.floor(21), egg: TX.egg_shell(31) };
  const lam = (map, extra = {}) => new THREE.MeshLambertMaterial(Object.assign({ map, color: 0xffffff }, extra));
  const M = {
    rock: lam(tx.rock, { flatShading: true, shadowSide: THREE.DoubleSide }),
    wall: lam(tx.rock, { flatShading: true, side: THREE.DoubleSide, shadowSide: THREE.DoubleSide }),
    floor: lam(tx.floor, { flatShading: true }),
    egg: lam(tx.egg),
  };
  const TILE = 64/TX.TEXELS_PER_METER;                          // 2 m per 64-texel tile

  // ---------------------------------------------------------------- chamber shell (a lathe)
  // Profile (height, radius): walls bulge out a little above the floor, close into a low dome,
  // and leave one narrow shaft that climbs toward the sky along the sun's direction.
  const PROFILE = [
    [-0.8, 16.8], [0.8, 17.4], [2.6, 17.8], [4.8, 17.2], [7.2, 15.4], [9.4, 12.6], [11.2, 9.6],
    [12.6, 6.8], [13.6, 4.4], [14.3, 2.6], [15.0, 1.75], [16.5, 1.55], [19.0, 1.7], [22.0, 1.6],
    [25.5, 1.8], [29.0, 1.9],
  ];
  const TOP = PROFILE[PROFILE.length - 1][0];
  const M_SEG = 72;
  const rings = [];
  for (let k = 0; k < PROFILE.length; k++) {
    const [h, r] = PROFILE[k];
    const shaft = smoothstep(11.5, 15.0, h);                     // the column's axis leans with the sun
    const cx = sun_xz.x*h*shaft, cz = sun_xz.y*h*shaft;
    const ring = [];
    for (let j = 0; j < M_SEG; j++) {
      const th = j/M_SEG*Math.PI*2;
      const ct = Math.cos(th), st = Math.sin(th);
      // vertical slabs: high angular frequency, low vertical frequency; plus broad lumps
      const slab = noise3(th*9.0/(Math.PI*2)*6, h*0.09, 3.3, 17) - 0.5;
      const lump = fbm3(ct*1.6, h*0.16, st*1.6, 23) - 0.5;
      const fine = noise3(ct*5.1, h*0.7, st*5.1, 29) - 0.5;
      const k_d = h < 14 ? 1 : 0.35;                             // the shaft is smoother
      const rr = r*(1 + (slab*0.30 + lump*0.34 + fine*0.10)*k_d);
      const hy = h + (noise3(ct*3, h*0.5, st*3, 37) - 0.5)*(h < 14 ? 1.2 : 0.4);
      ring.push(new THREE.Vector3(cx + ct*rr, hy, cz + st*rr));
    }
    rings.push(ring);
  }
  // triangles, facing inward; faces inside the tunnel mouth are left out
  const pos = [];
  const tth = LAYOUT.tunnel_theta;
  const in_mouth = (a, b, c) => {
    const mx = (a.x + b.x + c.x)/3, my = (a.y + b.y + c.y)/3, mz = (a.z + b.z + c.z)/3;
    if (mz > -8) return false;
    const ex = mx/(LAYOUT.tunnel_half_w + 0.6), ey = my/(LAYOUT.tunnel_h + 0.5);
    return ex*ex + ey*ey < 1 || (Math.abs(mx) < LAYOUT.tunnel_half_w + 0.6 && my < 0);
  };
  // the walls and the dome are separate meshes: a camera from above (OVERHEAD) sees through
  // the dome, which keeps casting its shadow (its material stops writing colour and depth)
  const DOME_H = 8.5;
  const dome_pos = [];
  const tri = (a, b, c) => {
    if (in_mouth(a, b, c)) return;
    const my = (a.y + b.y + c.y)/3;
    (my > DOME_H ? dome_pos : pos).push(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z);
  };
  for (let k = 0; k < rings.length - 1; k++) {
    for (let j = 0; j < M_SEG; j++) {
      const a = rings[k][j], b = rings[k][(j + 1) % M_SEG], c = rings[k + 1][(j + 1) % M_SEG], d = rings[k + 1][j];
      tri(a, c, b); tri(a, d, c);
    }
  }
  const shell_of = (arr, mat) => {
    let g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(arr, 3));
    g = world_uv(flat(g), TILE);
    const m = new THREE.Mesh(g, mat);
    m.castShadow = true; m.receiveShadow = true;
    group.add(m);
    return m;
  };
  shell_of(pos, M.wall);
  const dome_mat = M.wall.clone();
  const dome = shell_of(dome_pos, dome_mat);
  void tth;
  // a shadow-only lid over everything, holed at the shaft: no sunlight reaches the scene except
  // down the shaft (it is never drawn; it only writes the shadow map)
  {
    const hy = TOP - 1.0, hole = 1.5;
    const g = new THREE.RingGeometry(hole, 80, 24, 1);
    const m = new THREE.Mesh(g, new THREE.MeshBasicMaterial({ colorWrite: false, depthWrite: false, side: THREE.DoubleSide }));
    m.rotation.x = -Math.PI/2;
    m.position.set(sun_xz.x*hy, hy, sun_xz.y*hy);
    m.castShadow = true;
    m.frustumCulled = false;
    group.add(m);
  }

  // ---------------------------------------------------------------- tunnel
  {
    const RING = 18, z0 = -12.5, z1 = -46, N = 16;
    const rings_t = [];
    for (let k = 0; k <= N; k++) {
      const z = lerp(z0, z1, k/N);
      const ring = [];
      for (let j = 0; j <= RING; j++) {
        // an arch from the right floor over the top to the left floor, walls sunk below ground
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
    // an end cap so the far end is rock, not void
    const e = rings_t[N], ec = new THREE.Vector3(0, 1.5, z1 - 1.5);
    for (let j = 0; j < RING; j++) tp.push(ec.x, ec.y, ec.z, e[j].x, e[j].y, e[j].z, e[j + 1].x, e[j + 1].y, e[j + 1].z);
    let tg = new THREE.BufferGeometry();
    tg.setAttribute('position', new THREE.Float32BufferAttribute(tp, 3));
    tg = world_uv(flat(tg), TILE);
    const tm = new THREE.Mesh(tg, M.wall);
    tm.castShadow = true; tm.receiveShadow = true;
    group.add(tm);
  }

  // ---------------------------------------------------------------- floor
  {
    const x0 = -21, x1 = 21, z0 = -47, z1 = 21, CELL = 0.8;
    const nx = Math.round((x1 - x0)/CELL), nz = Math.round((z1 - z0)/CELL);
    const P = [];
    const vy = (x, z) => ground_y(x, z);
    const jit = (i, j, s) => (h3(i, j, 0, s) - 0.5)*CELL*0.55;
    const vx = (i, j) => [x0 + i*CELL + (i > 0 && i < nx ? jit(i, j, 61) : 0), z0 + j*CELL + (j > 0 && j < nz ? jit(i, j, 67) : 0)];
    for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) {
      const [ax, az] = vx(i, j), [bx, bz] = vx(i + 1, j), [cx, cz] = vx(i + 1, j + 1), [dx, dz] = vx(i, j + 1);
      // drop cells well outside both the chamber and the tunnel
      const mx = (ax + cx)/2, mz = (az + cz)/2;
      const in_ch = mx*mx + mz*mz < 19.5*19.5, in_tu = Math.abs(mx) < 3.1 && mz < -12;
      if (!in_ch && !in_tu) continue;
      P.push(ax, vy(ax, az), az, dx, vy(dx, dz), dz, cx, vy(cx, cz), cz);
      P.push(ax, vy(ax, az), az, cx, vy(cx, cz), cz, bx, vy(bx, bz), bz);
    }
    let g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(P, 3));
    g = world_uv(flat(g), TILE);
    const m = new THREE.Mesh(g, M.floor);
    m.receiveShadow = true; m.castShadow = true;
    group.add(m);
  }

  // ---------------------------------------------------------------- rubble, boulders, slabs
  const rocks = [];
  const add_rock = (x, z, s, sy = 1, tilt = 0.3, sink = 0.35, detail = 0) => {
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
    const mtx = new THREE.Matrix4().compose(new THREE.Vector3(x, ground_y(x, z) + s*sy*(1 - sink*2), z), q, new THREE.Vector3(s, s*sy, s));
    g.applyMatrix4(mtx);
    rocks.push(flat(g));
  };
  // boulders along the walls, thinning toward the open floor
  for (let i = 0; i < 90; i++) {
    const th = rng.float(0, Math.PI*2);
    if (Math.abs(Math.atan2(Math.sin(th - LAYOUT.tunnel_theta), Math.cos(th - LAYOUT.tunnel_theta))) < 0.24) continue;
    const r = rng.float(12.5, 17.5);
    const s = rng.float(0.4, 1.6)*smoothstep(11, 16, r) + 0.25;
    add_rock(Math.cos(th)*r, Math.sin(th)*r, s, rng.float(0.6, 1.2));
  }
  // scattered stones on the open floor
  for (let i = 0; i < 70; i++) {
    const th = rng.float(0, Math.PI*2), r = rng.float(3.2, 13);
    if (Math.abs(Math.cos(th)*r) < 2.2 && Math.sin(th)*r < -2) continue;     // keep the lich's path clear
    add_rock(Math.cos(th)*r, Math.sin(th)*r, rng.float(0.08, 0.28), rng.float(0.5, 1), 0.6, 0.3);
  }
  // rubble around the egg's mound
  for (let i = 0; i < 26; i++) {
    const th = rng.float(0, Math.PI*2), r = rng.float(0.75, 2.1);
    add_rock(Math.cos(th)*r, Math.sin(th)*r, rng.float(0.07, 0.2), rng.float(0.5, 0.9), 0.7, 0.25);
  }
  // tall broken slabs leaning against the walls (the cover's fractured vertical plates)
  for (let i = 0; i < 34; i++) {
    const th = rng.float(0, Math.PI*2);
    if (Math.abs(Math.atan2(Math.sin(th - LAYOUT.tunnel_theta), Math.cos(th - LAYOUT.tunnel_theta))) < 0.3) continue;
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
    // face the centre, lean back against the wall
    const yaw = Math.atan2(x, z);
    const q = new THREE.Quaternion().setFromEuler(new THREE.Euler(-rng.float(0.05, 0.3), yaw, rng.spread(0.12), 'YXZ'));
    g.applyMatrix4(new THREE.Matrix4().compose(new THREE.Vector3(x, ground_y(x, z) + hgt*0.42, z), q, new THREE.Vector3(1, 1, 1)));
    rocks.push(flat(g));
  }
  {
    let g = mergeGeometries(rocks, false);
    g = world_uv(g, TILE);
    const m = new THREE.Mesh(g, M.rock);
    m.castShadow = true; m.receiveShadow = true;
    group.add(m);
  }

  // ---------------------------------------------------------------- the egg
  const egg = new THREE.Group();
  {
    let g = new THREE.SphereGeometry(0.5, 24, 16);
    const p = g.attributes.position;
    for (let i = 0; i < p.count; i++) {
      const x = p.getX(i), y = p.getY(i), z = p.getZ(i);
      const taper = 1 - 0.14*clamp(y/0.5, 0, 1) + 0.03*clamp(-y/0.5, 0, 1);
      p.setXYZ(i, x*0.78*taper, y, z*0.78*taper);
    }
    g.computeVertexNormals();
    const m = new THREE.Mesh(g, M.egg);
    m.position.y = 0.5;
    m.castShadow = true; m.receiveShadow = true;
    egg.add(m);
    egg.userData.shell = m;
  }
  egg.position.set(0, ground_y(0, 0) - 0.04, 0);
  group.add(egg);

  // ---------------------------------------------------------------- lighting
  const hemi = new THREE.HemisphereLight(0x30343f, 0x5a3e26, 0.45);
  group.add(hemi);
  const sun = new THREE.DirectionalLight(0xffe4b0, 6.5);
  sun.position.copy(S).multiplyScalar(40);
  sun.target.position.set(0, 0, 0);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  {
    // orthographic frustum fitted around the whole cave in light space, texel-snapped
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

  // warm bounce off the pool of light: the mound, the lich's underside, nearby stones
  const bounce = new THREE.PointLight(0xd8a458, 7.0, 13, 1.4);
  bounce.position.set(0, 1.0, 0);
  group.add(bounce);
  // light thrown back up off the pool onto the walls around it: rock near the column reads,
  // rock far from it stays black
  const ring_lights = [];
  for (let i = 0; i < 4; i++) {
    const a = i/4*Math.PI*2 + 0.4;
    const l = new THREE.PointLight(0xc79a5c, 9.0, 15, 1.3);
    l.position.set(Math.cos(a)*7.5, 3.2, Math.sin(a)*7.5);
    group.add(l);
    ring_lights.push(l);
  }
  // the upper shaft catches light the whole way down (the cover's bright throat)
  const throat = new THREE.PointLight(0xffd79a, 60, 16, 1.6);
  throat.position.set(sun_xz.x*22, 22, sun_xz.y*22);
  group.add(throat);
  // a glimpse of sky at the top of the shaft: an HDR cap for the bloom to catch
  {
    const g = new THREE.CircleGeometry(2.6, 16);
    const m = new THREE.Mesh(g, new THREE.MeshBasicMaterial({ color: new THREE.Color(7.0, 6.2, 4.4), side: THREE.DoubleSide }));
    m.rotation.x = Math.PI/2;
    m.position.set(sun_xz.x*(TOP - 0.3), TOP - 0.3, sun_xz.y*(TOP - 0.3));
    group.add(m);
  }

  // ---------------------------------------------------------------- atmosphere (render.js)
  const P = R.params;
  R.world_scene.background = new THREE.Color(0x000000);
  P.sky.on = false;
  Object.assign(P.fog, { near: 7, far: 46, max: 0.72, curve: 1.25, sky: 0.0, base_y: 0, falloff: 0.0, height_mix: 0.0 });
  P.fog.color.setRGB(0.006, 0.0055, 0.005);
  P.shafts = { on: true, light: sun, color: [1.0, 0.78, 0.42], density: 0.03, max_dist: 48, steps: 40, phase: 0.35, ambient: 0.0,
    streak: 0.85, rise: 1.0 };
  P.dither_dark = [0.04, 0.16];
  R.set_shadow_light(sun);
  R.rebuild();
  P.bloom = { strength: 0.55, threshold: 0.85 };
  P.vignette = 0.32;
  P.contrast = 1.05; P.saturation = 1.04;
  P.lift = [0.004, 0.003, 0.009];

  // dust in the column: single game pixels drifting down and around, only inside the beam
  const DUST = 160;
  const dust_pos = new Float32Array(DUST*3), dust_col = new Float32Array(DUST*3), dust = [];
  for (let i = 0; i < DUST; i++) {
    dust.push({ h: rng.float(0.3, 20), a: rng.float(0, 6.283), r: Math.sqrt(rng.next())*1.35, v: rng.float(0.03, 0.12), w: rng.float(0.05, 0.25), b: rng.float(0.4, 1) });
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
      const k = d.b*tw*(0.55 + 0.45*Math.min(1, d.h/10));
      dust_col[i*3] = 1.5*k; dust_col[i*3 + 1] = 1.25*k; dust_col[i*3 + 2] = 0.8*k;
    }
    dust_geo.attributes.position.needsUpdate = true;
    dust_geo.attributes.color.needsUpdate = true;
  }

  // how dark the cave is away from the column: the cover's near-black against VS readability
  const DARK = [
    { name: 'COVER DARK', hemi: 0.2, ring: 0.0, fog: [6, 34, 0.86] },
    { name: 'DIM', hemi: 0.45, ring: 3.5, fog: [7, 42, 0.78] },
    { name: 'READABLE', hemi: 0.8, ring: 9.0, fog: [7, 46, 0.72] },
  ];

  let t_shake = 0;
  return {
    set_dome_visible(on) { dome_mat.colorWrite = on; dome_mat.depthWrite = on; },
    DARK,
    set_darkness(i) {
      const d = DARK[((i % DARK.length) + DARK.length) % DARK.length];
      hemi.intensity = d.hemi;
      for (const l of ring_lights) l.intensity = d.ring;
      Object.assign(P.fog, { near: d.fog[0], far: d.fog[1], max: d.fog[2] });
      return d.name;
    },
    group, ground_y, egg, sun, LAYOUT,
    update(t, dt) {
      update_dust(t, dt);
      // the egg trembles now and then: it will hatch soon
      t_shake -= dt;
      const shell = egg.userData.shell;
      const k = Math.max(0, Math.sin(t*0.9)*Math.sin(t*2.3) - 0.55)*1.6;
      shell.rotation.z = Math.sin(t*38)*0.035*k;
      shell.rotation.x = Math.cos(t*31)*0.025*k;
    },
  };
}
