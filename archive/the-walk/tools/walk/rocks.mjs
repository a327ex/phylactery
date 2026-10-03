// rocks.mjs -- what lies in the cave besides its walls: fractured blocks piled against the walls
// and strewn over the floors (cave.js's construction: convex hulls of scattered points), and each
// biome's own formations: basalt columns and lava cracks, stalactites and stalagmites and the
// hanging skeletons of lifted snakes, stones floating round the lodestone, fungi and twisted
// pillars round a pool, crystals and the great beams, sandstone ledges and the ring that holds the
// lens. Everything keeps clear of the way (the path's lane) and of where each object waits.
import { block, prism, cap, tube, torus, hull, quat_euler, frame } from './geo.mjs';
import { ITEMS, AREAS, SHAFTS, SUN_XZ, CHAMBERS } from './layout.mjs';
import { make_rng, smoothstep, lerp, clamp, fbm3, noise3, h3 } from './lib.mjs';
import { cells2 } from './field.mjs';
import * as THREE from 'three';

export function formations(ctx) {
  const { P, F, add, add_mesh, points } = ctx;
  const rng = make_rng(1234);
  const field = F.field, floor_y = F.floor_y;
  const air = (x, y, z) => field(x, y, z) < 0;
  const lane = (x, z) => { const n = P.nearest(x, z, 30); return n ? n.d : 99; };
  const area_at = (x, z) => { const n = P.nearest(x, z, 30); return n ? n.p.area : -1; };
  const item_d = (x, z) => { let d = 99; for (const it of ITEMS) d = Math.min(d, Math.hypot(x - it.at[0], z - it.at[1])); return d; };
  const in_seam = (x, z) => z > -49.5;
  function ceiling_y(x, z, from) {
    let y = from;
    while (y < 40 && field(x, y, z) < 0) y += 0.25;
    let a = y - 0.25, b = y;
    for (let i = 0; i < 6; i++) { const m = (a + b)/2; if (field(x, m, z) < 0) a = m; else b = m; }
    return (a + b)/2;
  }
  // does (x, z) lie by a wall? -> the direction toward the rock, or null
  const DIRS = []; for (let k = 0; k < 12; k++) DIRS.push([Math.cos(k/12*Math.PI*2), Math.sin(k/12*Math.PI*2)]);
  function wall_dir(x, z, r = 1.1) {
    const y = floor_y(x, z) + 0.6;
    if (!air(x, y, z)) return null;
    let sx = 0, sz = 0, n = 0;
    for (const [dx, dz] of DIRS) if (!air(x + dx*r, floor_y(x + dx*r, z + dz*r) + 0.6, z + dz*r)) { sx += dx; sz += dz; n++; }
    if (!n) return null;
    const l = Math.hypot(sx, sz) || 1;
    return [sx/l, sz/l, n];
  }
  // area bounding boxes (from the path samples + the chambers)
  const boxes = AREAS.map(() => ({ x0: Infinity, x1: -Infinity, z0: Infinity, z1: -Infinity }));
  for (const p of P.S) { const b = boxes[p.area]; b.x0 = Math.min(b.x0, p.x - p.w - 2); b.x1 = Math.max(b.x1, p.x + p.w + 2); b.z0 = Math.min(b.z0, p.z - p.w - 2); b.z1 = Math.max(b.z1, p.z + p.w + 2); }
  for (const c of CHAMBERS) { const b = boxes[c.area]; const R = Math.max(c.r[0], c.r[1]) + 3; b.x0 = Math.min(b.x0, c.c[0] - R); b.x1 = Math.max(b.x1, c.c[0] + R); b.z0 = Math.min(b.z0, c.c[1] - R); b.z1 = Math.max(b.z1, c.c[1] + R); }
  const chamber_of = a => CHAMBERS.find(c => c.area === a);
  const in_chamber = (x, z, a, k = 1) => {
    const c = chamber_of(a); if (!c) return false;
    const dx = x - c.c[0], dz = z - c.c[1], cr = Math.cos(-c.rot), sr = Math.sin(-c.rot);
    const px = dx*cr - dz*sr, pz = dx*sr + dz*cr;
    return (px/c.r[0])**2 + (pz/c.r[1])**2 < k*k;
  };
  const rand_in = (a) => { const b = boxes[a]; return [rng.float(b.x0, b.x1), rng.float(b.z0, b.z1)]; };
  const placed = [];          // [x, z, r] footprints, so formations do not pile into each other
  const free = (x, z, r) => { for (const p of placed) if ((p[0] - x)**2 + (p[1] - z)**2 < (p[2] + r)**2) return false; return true; };
  const rock_mat = a => AREAS[a].biome + '.rock';

  // ---------------------------------------------------------------- blocks against the walls
  const add_block = (a, x, z, w, h, d, o = {}) => {
    const q = quat_euler(rng.spread(o.tilt ?? 0.35), o.yaw ?? rng.float(0, Math.PI*2), rng.spread(o.tilt ?? 0.35));
    const c = [x, floor_y(x, z) + h*(0.5 - (o.sink ?? 0.25)) + (o.lift || 0), z];
    add(a, o.mat || rock_mat(a), block(rng, w, h, d, { corners: o.corners ?? 0.55, n: o.n ?? 12, c, q }));
    return c;
  };
  for (let a = 0; a < AREAS.length; a++) {
    const bio = AREAS[a].biome;
    let n = 0;
    for (let tries = 0; tries < 9000 && n < (bio === 'crystal' ? 70 : 140); tries++) {
      const [x, z] = rand_in(a);
      if (area_at(x, z) !== a || in_seam(x, z)) continue;
      const wd = wall_dir(x, z, 1.0);
      if (!wd) continue;
      if (lane(x, z) < 1.6 || item_d(x, z) < 2.6) continue;
      const big = in_chamber(x, z, a, 1.1) ? 1 : 0.55;
      const s = (lerp(0.5, 2.6, Math.pow(rng.next(), 1.6))*big + 0.25)*(bio === 'sandstone' ? 1.1 : 1);
      if (!free(x, z, s*0.4)) continue;
      // pushed a little into the wall
      const px = x + wd[0]*s*0.3, pz = z + wd[1]*s*0.3;
      if (bio === 'sandstone') add_block(a, px, pz, s*rng.float(1.1, 1.8), s*rng.float(0.35, 0.6), s*rng.float(0.9, 1.4), { tilt: 0.12, sink: 0.3 });
      else add_block(a, px, pz, s*rng.float(0.8, 1.5), s*rng.float(0.5, 1.1), s*rng.float(0.7, 1.3), { tilt: 0.45, sink: 0.3 });
      placed.push([px, pz, s*0.35]);
      n++;
    }
    // stones and grit on the open floor
    for (let tries = 0, k = 0; tries < 6000 && k < (a === 7 || a === 0 ? 70 : 110); tries++) {
      const [x, z] = rand_in(a);
      if (area_at(x, z) !== a || in_seam(x, z)) continue;
      if (!air(x, floor_y(x, z) + 0.6, z) || item_d(x, z) < 1.6) continue;
      const ld = lane(x, z);
      const s = lerp(0.05, ld > 1.8 ? 0.45 : 0.16, Math.pow(rng.next(), 2.2));
      add_block(a, x, z, s*rng.float(0.9, 1.6), s*rng.float(0.4, 0.9), s*rng.float(0.8, 1.3), { tilt: 0.8, sink: 0.35, n: 8 });
      k++;
    }
    // piles: a base of two or three blocks, one or two resting on them, a few fallen pieces
    const ch = chamber_of(a);
    if (ch && bio !== 'crystal') {
      for (let k = 0, tries = 0; k < 5 && tries < 300; tries++) {
        const [x, z] = rand_in(a);
        if (!in_chamber(x, z, a, 0.85) || lane(x, z) < 3.4 || item_d(x, z) < 4.5 || !free(x, z, 1.8)) continue;
        if (!air(x, floor_y(x, z) + 2.5, z)) continue;
        const S = lerp(0.8, 1.8, rng.next());
        for (let b = 0; b < rng.int(2, 3); b++) {
          const an = rng.float(0, 6.28), d = rng.float(0.2, 0.8)*S;
          add_block(a, x + Math.cos(an)*d, z + Math.sin(an)*d, S*rng.float(1.0, 1.6), S*rng.float(0.6, 1.0), S*rng.float(0.8, 1.3), { tilt: 0.3, sink: 0.2 });
        }
        for (let b = 0; b < rng.int(0, 2); b++) add_block(a, x + rng.spread(0.4*S), z + rng.spread(0.4*S), S*rng.float(0.7, 1.1), S*rng.float(0.4, 0.7), S*rng.float(0.6, 1.0), { tilt: 0.6, sink: 0, lift: S*0.7 });
        for (let b = 0; b < rng.int(3, 6); b++) {
          const an = rng.float(0, 6.28), d = S*rng.float(1.0, 2.0), s = S*rng.float(0.15, 0.4);
          add_block(a, x + Math.cos(an)*d, z + Math.sin(an)*d, s*rng.float(0.8, 1.5), s*rng.float(0.5, 1), s, { tilt: 0.7, sink: 0.3 });
        }
        placed.push([x, z, S*1.6]);
        k++;
      }
    }
  }

  const R = {};          // what the game needs to know: anchors, emitters, animated pieces

  // ---------------------------------------------------------------- 1 FIRE: basalt, ash, lava
  {
    const a = 1, it = ITEMS[0];
    const hexcol = (x, z, r, hgt, mat = 'basalt.rock', tilt = 0.05) => {
      const y0 = floor_y(x, z) - 0.3;
      const dir = [rng.spread(tilt), 1, rng.spread(tilt)];
      add(a, mat, prism([x, y0, z], dir, hgt + 0.3, r, r*rng.float(0.92, 1.0), { n: 6, rot: rng.float(0, 1), jitter: 0.04, rng }));
    };
    // the altar: one column under the mask, its neighbours lower, packed round it
    const ax = it.at[0], az = it.at[1];
    const top = floor_y(ax, az) + it.lift - 0.13;
    hexcol(ax, az, 0.44, top - floor_y(ax, az), 'basalt.rock', 0.0);
    {
      const back = ctx.behind ? ctx.behind(0, 0.62) : [ax, az + 0.62];
      hexcol(back[0], back[1], 0.36, top - floor_y(back[0], back[1]) + 0.75, 'basalt.rock', 0.0);
      placed.push([back[0], back[1], 0.5]);
    }
    // a pool of lava at its foot, on the camera's side: the light the mask is seen by
    {
      const f = ctx.behind ? ctx.behind(0, -1.15) : [ax, az - 1.1];
      const P2 = [], y = floor_y(f[0], f[1]) + 0.05;
      for (let k = 0; k < 12; k++) {
        const a0 = k/12*Math.PI*2, a1 = (k + 1)/12*Math.PI*2, r0 = 0.32*(1 + 0.3*(h3(k, 1, 0, 51) - 0.5)), r1 = 0.32*(1 + 0.3*(h3((k + 1) % 12, 1, 0, 51) - 0.5));
        P2.push(f[0], y, f[1], f[0] + Math.cos(a1)*r1*1.4, y, f[1] + Math.sin(a1)*r1, f[0] + Math.cos(a0)*r0*1.4, y, f[1] + Math.sin(a0)*r0);
      }
      add(a, 'lava_hot', P2);
      R.lava_pool = [f[0], y, f[1]];
    }
    for (let k = 0; k < 6; k++) {
      const an = k/6*Math.PI*2 + 0.25, d = 0.78 + rng.spread(0.05);
      const x = ax + Math.cos(an)*d, z = az + Math.sin(an)*d;
      if (lane(x, z) < 1.0) continue;
      hexcol(x, z, 0.38, (top - floor_y(x, z))*rng.float(0.35, 0.75));
    }
    placed.push([ax, az, 1.3]);
    R.altar_top = top;
    // column clusters against the walls
    for (let k = 0, tries = 0; k < 16 && tries < 4000; tries++) {
      const [x, z] = rand_in(a);
      if (area_at(x, z) !== a) continue;
      const wd = wall_dir(x, z, 1.4);
      if (!wd || lane(x, z) < 2.2 || item_d(x, z) < 3.2 || !free(x, z, 1.0)) continue;
      const inch = in_chamber(x, z, a, 1.05);
      const cr = rng.float(0.32, 0.5);
      const N = inch ? rng.int(5, 12) : rng.int(2, 5);
      for (let c = 0; c < N; c++) {
        // packed: a hex lattice round the cluster's centre, toward the wall
        const ring = Math.floor(Math.sqrt(c)), an = c*2.4;
        const x2 = x + Math.cos(an)*ring*cr*1.75 + wd[0]*0.5, z2 = z + Math.sin(an)*ring*cr*1.75 + wd[1]*0.5;
        if (lane(x2, z2) < 1.5) continue;
        const ceil = ceiling_y(x2, z2, floor_y(x2, z2) + 0.5);
        const hmax = Math.max(0.6, ceil - floor_y(x2, z2) + 0.4);
        const hgt = Math.min(hmax, (inch ? rng.float(1.2, 6.5) : rng.float(0.8, 3.0))*(1 - 0.4*ring/3));
        hexcol(x2, z2, cr*rng.float(0.92, 1.05), hgt);
      }
      placed.push([x, z, cr*4]);
      k++;
    }
    // fallen columns
    for (let k = 0, tries = 0; k < 6 && tries < 600; tries++) {
      const [x, z] = rand_in(a);
      if (!in_chamber(x, z, a, 0.9) || lane(x, z) < 2.4 || item_d(x, z) < 3 || !free(x, z, 1.4)) continue;
      const yaw = rng.float(0, 6.28), L = rng.float(1.2, 2.8), r = rng.float(0.3, 0.45);
      const y = floor_y(x, z) + r*0.6;
      add(a, 'basalt.rock', prism([x - Math.cos(yaw)*L/2, y, z - Math.sin(yaw)*L/2], [Math.cos(yaw), rng.spread(0.12), Math.sin(yaw)], L, r, r, { n: 6, rot: rng.float(0, 1), jitter: 0.05, rng }));
      placed.push([x, z, L*0.5]);
      k++;
    }
    // lava in the cracks: cells of a 2D cellular pattern; the cracks between them glow
    const lava = [], hot = [], embers = [];
    const b = boxes[a];
    const C = 0.16;
    for (let x = b.x0; x < b.x1; x += C) for (let z = b.z0; z < b.z1; z += C) {
      if (area_at(x, z) !== a) continue;
      const ld = lane(x, z), idd = item_d(x, z);
      if (ld < 1.1 || idd < 1.25) continue;
      const fy = floor_y(x, z);
      if (!air(x, fy + 0.5, z)) continue;
      const [d1, d2, id] = cells2(x*0.36, z*0.36, 7);
      const e = d2 - d1;
      // a crack glows only where a slower pattern says this stretch of it is still open
      const open = noise3(x*0.55, 0.5, z*0.55, 17);
      if (open < 0.52 && idd > 2.2) continue;
      const wmax = (0.035 + 0.05*smoothstep(0.52, 0.8, open))*(0.6 + 0.4*smoothstep(1.1, 3.0, ld)) + 0.04*(1 - smoothstep(1.3, 2.6, idd));
      if (e > wmax) continue;
      if (!in_chamber(x, z, a, 1.15) && noise3(x*0.5, 0, z*0.5, 9) < 0.55) continue;
      const strong = e < wmax*0.45 && h3(Math.floor(x*2), Math.floor(z*2), 0, 3) > 0.3;
      const y = fy + 0.06;
      const q = [x, y, z, x + C, y, z + C, x + C, y, z, x, y, z, x, y, z + C, x + C, y, z + C];      // facing up
      (strong ? hot : lava).push(...q);
      if (h3(Math.floor(x*6), Math.floor(z*6), 1, 5) > 0.985) embers.push([x + C/2, y, z + C/2]);
      void id;
    }
    add(a, 'lava', lava, { no_uv: false });
    add(a, 'lava_hot', hot);
    R.embers = embers;
  }

  // ---------------------------------------------------------------- 2 LIFT: limestone, glow-worms
  {
    const a = 2, it = ITEMS[1];
    const ch = chamber_of(a);
    const cone_up = (x, z, hgt, r, mat = 'limestone.rock') => {
      const y0 = floor_y(x, z) - 0.2;
      add(a, mat, prism([x, y0, z], [rng.spread(0.06), 1, rng.spread(0.06)], hgt*0.82 + 0.2, r, r*0.35, { n: 7, tip: hgt*0.18, jitter: 0.1, rng, rot: rng.float(0, 1), rings: 2 }));
    };
    // the hand's stalagmite: rising to a broken, level top just under the hand
    const ax = it.at[0], az = it.at[1];
    const top = floor_y(ax, az) + it.lift - 0.22;
    {
      const y0 = floor_y(ax, az) - 0.25, hgt = top - y0;
      add(a, 'limestone.rock', prism([ax, y0, az], [0, 1, 0], hgt, 0.55, 0.2, { n: 8, jitter: 0.08, rng, rings: 4,
        wobble: t => [Math.sin(t*5)*0.04, Math.cos(t*4)*0.04] }));
      R.stalagmite_top = top;
    }
    // votive stalagmites round it, like candles before a shrine
    for (let k = 0; k < 9; k++) {
      const an = rng.float(0, 6.28), d = rng.float(1.0, 2.2);
      const x = ax + Math.cos(an)*d, z = az + Math.sin(an)*d;
      if (lane(x, z) < 1.0) continue;
      cone_up(x, z, rng.float(0.15, 0.7), rng.float(0.06, 0.14));
    }
    placed.push([ax, az, 1.2]);
    // stalagmites on the floor, stalactites from the ceiling
    for (let k = 0, tries = 0; k < 70 && tries < 5000; tries++) {
      const [x, z] = rand_in(a);
      if (area_at(x, z) !== a || lane(x, z) < 1.7 || item_d(x, z) < 2.4) continue;
      if (!air(x, floor_y(x, z) + 0.5, z)) continue;
      const hgt = lerp(0.2, 2.8, Math.pow(rng.next(), 1.8));
      if (!free(x, z, hgt*0.12)) continue;
      cone_up(x, z, hgt, hgt*rng.float(0.16, 0.24));
      placed.push([x, z, hgt*0.12]);
      k++;
    }
    const tites = [];
    for (let k = 0, tries = 0; k < 160 && tries < 6000; tries++) {
      const [x, z] = rand_in(a);
      if (area_at(x, z) !== a) continue;
      const fy = floor_y(x, z);
      if (!air(x, fy + 1.0, z)) continue;
      const cy = ceiling_y(x, z, fy + 1.0);
      const room = cy - fy;
      if (room < 3.2) continue;
      const len = Math.min(room - 2.6, lerp(0.3, 3.6, Math.pow(rng.next(), 1.7))*(room > 10 ? 1.5 : 1));
      if (len < 0.25) continue;
      const r = len*rng.float(0.12, 0.2);
      add(a, 'limestone.rock', prism([x, cy + 0.35, z], [rng.spread(0.05), -1, rng.spread(0.05)], len*0.8 + 0.35, r, r*0.3, { n: 7, tip: len*0.2, jitter: 0.12, rng, rot: rng.float(0, 1), rings: 2 }));
      tites.push([x, cy, z, len]);
      k++;
    }
    // the skeletons of lifted snakes, hanging from the ceiling over the shrine
    const bones = [];
    for (let k = 0, tries = 0; k < 18 && tries < 3000; tries++) {
      const an = rng.float(0, 6.28), d = Math.sqrt(rng.next())*Math.min(ch.r[0], ch.r[1])*0.75;
      const x = ch.c[0] + Math.cos(an)*d, z = ch.c[1] + Math.sin(an)*d;
      const fy = floor_y(x, z);
      if (!air(x, fy + 1.0, z)) continue;
      const cy = ceiling_y(x, z, fy + 1.0);
      const room = cy - fy;
      if (room < 7) continue;
      const hang = Math.min(room - (lane(x, z) < 3 ? 3.6 : 2.4), rng.float(4.0, 8.0));
      if (hang < 1.2) continue;
      const sk = snake_skeleton(rng, [x, cy + 0.2, z], hang, rng.float(0, 6.28));
      add(a, 'bone', sk);
      bones.push([x, cy, z, hang]);
      k++;
    }
    // glow-worms: points on the ceiling (drawn as single pixels) over the chamber, thicker where
    // it is high; the ceiling round them glows a little in the bake (bake-only emitters)
    const worms = [];
    for (let k = 0, tries = 0; k < 2600 && tries < 40000; tries++) {
      const [x, z] = rand_in(a);
      if (!in_chamber(x, z, a, 1.15) && !(area_at(x, z) === a && rng.chance(0.25))) continue;
      const fy = floor_y(x, z);
      if (!air(x, fy + 1.0, z)) continue;
      const cy = ceiling_y(x, z, fy + 1.0);
      if (cy - fy < 4.5) continue;
      worms.push([x, cy - 0.04 - rng.float(0, 0.25), z, rng.float(0.5, 1)]);
      k++;
    }
    // and thinly along the passages of the other dark stretches
    for (const pa of [0, 1, 3, 6, 7]) {
      for (let k = 0, tries = 0; k < (pa === 1 ? 60 : 160) && tries < 20000; tries++) {
        const [x, z] = rand_in(pa);
        if (area_at(x, z) !== pa || in_chamber(x, z, pa, 1.05) || in_seam(x, z)) continue;
        const fy = floor_y(x, z);
        if (!air(x, fy + 1.0, z)) continue;
        const cy = ceiling_y(x, z, fy + 1.0);
        if (cy - fy < 2.6 || cy - fy > 9) continue;
        worms.push([x, cy - 0.04 - rng.float(0, 0.15), z, rng.float(0.35, 0.8)]);
        k++;
      }
    }
    R.glowworms = worms;
    R.bones = bones;
    R.tites = tites;
  }

  // ---------------------------------------------------------------- 3 ROCK: iron, floating stones
  {
    const a = 3, it = ITEMS[2];
    const ax = it.at[0], az = it.at[1], fy0 = floor_y(ax, az);
    // a ring of pebbles on the floor under it, laid along the field's lines
    for (let k = 0; k < 90; k++) {
      const an = rng.float(0, 6.28), d = rng.float(0.5, 3.4);
      const x = ax + Math.cos(an)*d, z = az + Math.sin(an)*d;
      if (lane(x, z) < 0.5 && d > 1.4) continue;
      const s = rng.float(0.05, 0.16)*(1.2 - d/4);
      const q = quat_euler(rng.spread(0.2), -an, rng.spread(0.2));
      add(a, 'iron.rock', block(rng, s*2.4, s*0.6, s, { c: [x, floor_y(x, z) + s*0.15, z], q, n: 8 }));
    }
    // the stones that float: their own meshes, at rest where they hang
    const floaters = [];
    for (let k = 0, tries = 0; k < 42 && tries < 3000; tries++) {
      const an = rng.float(0, 6.28), d = lerp(0.9, 5.0, Math.pow(rng.next(), 1.1));
      const x = ax + Math.cos(an)*d, z = az + Math.sin(an)*d;
      const fy = floor_y(x, z);
      const y = fy + lerp(0.4, 3.6, rng.next())*(d < 2 ? 0.7 : 1);
      if (!air(x, y, z) || !air(x, y + 0.6, z) || !air(x, y - 0.5, z)) continue;
      // keep the way under them clear (he passes beneath)
      if (lane(x, z) < 1.4 && y - fy < 2.6) continue;
      const s = lerp(0.1, 0.55, Math.pow(rng.next(), 1.7));
      const T = block(rng, s*rng.float(0.9, 1.5), s*rng.float(0.6, 1.0), s*rng.float(0.8, 1.3), { c: [0, 0, 0], q: quat_euler(rng.spread(3), rng.spread(3), rng.spread(3)) });
      const at = [x, y, z];
      floaters.push({ T, at, s, d });
      add_mesh(a, 'iron.rock', T, at, 'floater');
      k++;
    }
    R.floaters = floaters;
    R.lodestone_y = fy0 + it.lift;
    // a few tall blocks of iron rock standing about
    for (let k = 0, tries = 0; k < 7 && tries < 800; tries++) {
      const [x, z] = rand_in(a);
      if (!in_chamber(x, z, a, 0.95) || lane(x, z) < 2.6 || item_d(x, z) < 3.5 || !free(x, z, 1.2)) continue;
      const hgt = rng.float(1.8, 4.2);
      add_block(a, x, z, rng.float(0.8, 1.4), hgt, rng.float(0.7, 1.2), { tilt: 0.12, sink: 0.15, corners: 0.8 });
      placed.push([x, z, 0.9]);
      k++;
    }
  }

  // ---------------------------------------------------------------- 4 LEAKAGE: the warped pool
  {
    const a = 4, it = ITEMS[3];
    const pool = F.pools[0];
    // the water: level, where the floor dips below it
    const wl = pool.level;
    const W = [];
    const C = 0.35;
    for (let x = pool.c[0] - pool.r[0]*1.3; x < pool.c[0] + pool.r[0]*1.3; x += C) for (let z = pool.c[1] - pool.r[1]*1.3; z < pool.c[1] + pool.r[1]*1.3; z += C) {
      const ys = [floor_y(x, z), floor_y(x + C, z), floor_y(x + C, z + C), floor_y(x, z + C)];
      if (Math.min(...ys) > wl) continue;
      W.push(x, wl, z, x + C, wl, z + C, x + C, wl, z, x, wl, z, x, wl, z + C, x + C, wl, z + C);
    }
    add(a, 'water', W);
    R.water = { level: wl, c: pool.c, r: pool.r };
    // fungi: pale stems, glowing caps; thick by the walls and the water
    const caps = [];
    const fungus = (x, z, size, lean = 0) => {
      const fy = floor_y(x, z);
      const hgt = size*rng.float(0.8, 2.0);
      const lx = rng.spread(lean), lz = rng.spread(lean);
      const spine = [];
      for (let k = 0; k <= 4; k++) { const t = k/4; spine.push([x + lx*t*t, fy - 0.05 + hgt*t, z + lz*t*t]); }
      add(a, 'fungus_stem', tube(spine, t => size*0.14*(1.2 - 0.4*t), { n: 6 }));
      const top = spine[4];
      const cr = size*rng.float(0.5, 0.9);
      add(a, 'fungus_cap', cap([top[0], top[1] - cr*0.15, top[2]], cr, cr*rng.float(0.35, 0.6), { seg: 10, rings: 3, jitter: 0.08, rng }));
      caps.push([top[0], top[1], top[2], cr]);
    };
    for (let k = 0, tries = 0; k < 120 && tries < 8000; tries++) {
      const [x, z] = rand_in(a);
      if (area_at(x, z) !== a || lane(x, z) < 1.5 || item_d(x, z) < 1.8) continue;
      const fy = floor_y(x, z);
      if (fy < wl + 0.04 || !air(x, fy + 1.0, z)) continue;
      const wd = wall_dir(x, z, 1.6);
      const by_water = (() => { const dx = (x - pool.c[0])/pool.r[0], dz = (z - pool.c[1])/pool.r[1]; return Math.sqrt(dx*dx + dz*dz) < 1.35; })();
      if (!wd && !by_water && !rng.chance(0.15)) continue;
      const big = in_chamber(x, z, a, 1.0) && rng.chance(0.2);
      const size = big ? rng.float(0.5, 1.1) : rng.float(0.1, 0.4);
      if (!free(x, z, size*0.5)) continue;
      // in clusters: a few small ones round each
      fungus(x, z, size, size*0.6);
      for (let c = 0; c < rng.int(0, 4); c++) {
        const an = rng.float(0, 6.28), d = size*rng.float(0.6, 1.6);
        const x2 = x + Math.cos(an)*d, z2 = z + Math.sin(an)*d;
        if (lane(x2, z2) > 1.3 && floor_y(x2, z2) > wl + 0.04) fungus(x2, z2, size*rng.float(0.3, 0.6), 0.2);
      }
      placed.push([x, z, size*0.6]);
      k++;
    }
    R.caps = caps;
    // twisted pillars, swollen where the leakage bent them
    for (let k = 0, tries = 0; k < 6 && tries < 1500; tries++) {
      const [x, z] = rand_in(a);
      if (!in_chamber(x, z, a, 0.92) || lane(x, z) < 2.6 || item_d(x, z) < 3.4 || !free(x, z, 1.4)) continue;
      const fy = floor_y(x, z);
      if (fy < wl + 0.1 || !air(x, fy + 1, z)) continue;
      const cy = ceiling_y(x, z, fy + 1);
      if (cy - fy > 9) continue;
      const spine = [], NS = 18, tw = rng.float(1.5, 3.5), amp = rng.float(0.25, 0.6), ph = rng.float(0, 6.28);
      for (let s = 0; s <= NS; s++) {
        const t = s/NS;
        spine.push([x + Math.cos(ph + t*tw*6.28)*amp*Math.sin(t*Math.PI), fy - 0.3 + (cy - fy + 0.6)*t, z + Math.sin(ph + t*tw*6.28)*amp*Math.sin(t*Math.PI)]);
      }
      const r0 = rng.float(0.35, 0.6);
      add(a, 'warped.rock', tube(spine, (t) => r0*(1.4 - 0.7*Math.sin(t*Math.PI) + 0.35*Math.sin(t*19 + ph)*Math.sin(t*Math.PI)) + (t < 0.1 || t > 0.9 ? 0.4 : 0), { n: 9, jitter: 0.06, rng }));
      placed.push([x, z, r0*2]);
      k++;
    }
    // swollen blisters of rock along the walls
    for (let k = 0, tries = 0; k < 18 && tries < 3000; tries++) {
      const [x, z] = rand_in(a);
      if (area_at(x, z) !== a) continue;
      const wd = wall_dir(x, z, 1.2);
      if (!wd || lane(x, z) < 1.9 || item_d(x, z) < 2.6 || !free(x, z, 0.9)) continue;
      const s = rng.float(0.6, 1.6);
      const cx = x + wd[0]*s*0.4, cz = z + wd[1]*s*0.4, cy = floor_y(x, z) + s*rng.float(0.1, 1.2);
      const pts = [];
      for (let i = 0; i < 40; i++) {
        const u = rng.float(-1, 1), th = rng.float(0, 6.28), sq = Math.sqrt(1 - u*u);
        const bump = 1 + 0.25*(noise3(sq*Math.cos(th)*2, u*2, sq*Math.sin(th)*2, 77 + k) - 0.5);
        pts.push(new THREE.Vector3(sq*Math.cos(th)*s*bump, u*s*0.75*bump, sq*Math.sin(th)*s*bump));
      }
      add(a, 'warped.rock', hull(pts, [cx, cy, cz]));
      placed.push([cx, cz, s*0.8]);
      k++;
    }
    R.pool_y = wl;
  }

  // ---------------------------------------------------------------- 5 BEAM: crystals
  {
    const a = 5, it = ITEMS[4];
    const ch = chamber_of(a);
    const crystal = (b, dir, L, r, mat = 'crystal') => {
      add(a, mat, prism(b, dir, L, r, r*rng.float(0.85, 1.0), { n: 6, tip: r*rng.float(1.2, 2.2), rot: rng.float(0, 1), jitter: 0.03, rng }));
    };
    // the gem's cluster: crystals radiating up and out round a cup at its height
    const ax = it.at[0], az = it.at[1], fy = floor_y(ax, az), top = fy + it.lift - 0.12;
    add(a, 'crystal.rock', block(rng, 1.1, 0.5, 1.0, { c: [ax, fy + 0.05, az], n: 14 }));
    for (let k = 0; k < 5; k++) {
      const an = k/5*Math.PI*2 + 0.3, lean = 0.12;
      crystal([ax + Math.cos(an)*0.09, fy - 0.1, az + Math.sin(an)*0.09], [Math.cos(an)*lean, 1, Math.sin(an)*lean], top - fy - 0.05, 0.13);
    }
    for (let k = 0; k < 11; k++) {
      const an = k/11*Math.PI*2 + rng.spread(0.25), el = rng.float(0.35, 0.95);
      const dir = [Math.cos(an)*Math.cos(el), Math.sin(el), Math.sin(an)*Math.cos(el)];
      const L = rng.float(0.18, 0.55)*(k % 4 === 0 ? 1.4 : 1);
      const base = [ax + Math.cos(an)*0.16, top - rng.float(0.05, 0.3), az + Math.sin(an)*0.16];
      if (lane(base[0] + dir[0]*L, base[2] + dir[2]*L) < 0.7) continue;
      crystal(base, dir, L, L*rng.float(0.09, 0.13));
    }
    placed.push([ax, az, 1.3]);
    R.gem_top = top;
    // clusters on the floor and against the walls
    for (let k = 0, tries = 0; k < 22 && tries < 5000; tries++) {
      const [x, z] = rand_in(a);
      if (area_at(x, z) !== a || lane(x, z) < 1.8 || item_d(x, z) < 2.8 || !free(x, z, 0.8)) continue;
      const fyx = floor_y(x, z);
      if (!air(x, fyx + 0.6, z)) continue;
      const wd = wall_dir(x, z, 1.4);
      const out = wd ? [-wd[0], -wd[1]] : [0, 0];
      const N = rng.int(4, 14), big = in_chamber(x, z, a, 0.95) ? 1.4 : 0.8;
      for (let c = 0; c < N; c++) {
        const an = rng.float(0, 6.28), el = rng.float(0.45, 1.35);
        let dir = [Math.cos(an)*Math.cos(el) + out[0]*0.8, Math.sin(el), Math.sin(an)*Math.cos(el) + out[1]*0.8];
        const L = lerp(0.3, 2.6, Math.pow(rng.next(), 1.6))*big;
        const b = [x + rng.spread(0.3) + (wd ? wd[0]*0.4 : 0), fyx - 0.15, z + rng.spread(0.3) + (wd ? wd[1]*0.4 : 0)];
        const l = Math.hypot(...dir); dir = dir.map(v => v/l);
        if (lane(b[0] + dir[0]*L, b[2] + dir[2]*L) < 1.3 && b[1] + dir[1]*L < fyx + 2.6) continue;
        crystal(b, dir, L, L*rng.float(0.07, 0.12));
      }
      placed.push([x, z, 0.9]);
      k++;
    }
    // the great beams: across the chamber, high over the way
    for (let k = 0, tries = 0; k < 6 && tries < 3000; tries++) {
      const an = rng.float(0, 6.28), el = rng.float(0.15, 0.6);
      const d = Math.min(ch.r[0], ch.r[1])*rng.float(0.6, 0.95);
      const bx = ch.c[0] + Math.cos(an)*d, bz = ch.c[1] + Math.sin(an)*d;
      const fyb = floor_y(bx, bz);
      const by = fyb + rng.float(0.2, 3.5);
      const tow = an + Math.PI + rng.spread(0.7);
      const dir = [Math.cos(tow)*Math.cos(el), Math.sin(el), Math.sin(tow)*Math.cos(el)];
      const L = rng.float(6, 11), r = rng.float(0.32, 0.65);
      // must clear the way by the lich's height wherever it passes over it, and stay in the air
      let ok = true;
      for (let t = 0.15; t <= 1.0; t += 0.05) {
        const x = bx + dir[0]*L*t, y = by + dir[1]*L*t, z = bz + dir[2]*L*t;
        if (lane(x, z) < 2.0 && y - floor_y(x, z) < 2.9 + r) { ok = false; break; }
        if (t > 0.3 && !air(x, y, z)) { ok = false; break; }
        if (item_d(x, z) < 1.6) { ok = false; break; }
      }
      if (!ok) continue;
      crystal([bx - dir[0]*1.5, by - dir[1]*1.5, bz - dir[2]*1.5], dir, L, r, 'crystal');
      k++;
    }
  }

  // ---------------------------------------------------------------- 6 LENS: sandstone, the ring
  {
    const a = 6, it = ITEMS[5];
    const ax = it.at[0], az = it.at[1], fy = floor_y(ax, az);
    const ry = fy + it.lift - 0.04;
    // three weathered pillars of the sandstone, the lens resting level on their tops (hoodoos:
    // the softer beds worn away under harder caps)
    for (let k = 0; k < 3; k++) {
      const an = k/3*Math.PI*2 + 0.4 + rng.spread(0.2);
      const r = 0.44 + rng.spread(0.03);
      const px = ax + Math.cos(an)*r, pz = az + Math.sin(an)*r;
      const y0 = floor_y(px, pz) - 0.2, L = ry - y0 - 0.01;
      add(a, 'brown.rock', prism([px, y0, pz], [rng.spread(0.05), 1, rng.spread(0.05)], L, rng.float(0.16, 0.22), rng.float(0.09, 0.13), { n: 5, jitter: 0.18, rng, rings: 4, rot: rng.float(0, 6),
        wobble: t => [Math.sin(t*9 + k)*0.03, Math.cos(t*7 + k)*0.03] }));
      // the cap the lens rests on
      add(a, 'brown.rock', block(rng, 0.3, 0.07, 0.26, { c: [px - Math.cos(an)*0.04, ry - 0.035, pz - Math.sin(an)*0.04], q: quat_euler(0, -an, 0), n: 10, corners: 0.8 }));
    }
    // fallen stones round their feet
    for (let k = 0; k < 7; k++) {
      const an = rng.float(0, 6.28), d = rng.float(0.6, 1.5), s = rng.float(0.06, 0.18);
      const x = ax + Math.cos(an)*d, z = az + Math.sin(an)*d;
      if (lane(x, z) < 0.8) continue;
      add_block(a, x, z, s*1.5, s*0.6, s, { tilt: 0.5, sink: 0.3, n: 8 });
    }
    placed.push([ax, az, 1.3]);
    R.ring_y = ry;
    // the burned point: where the lens's light falls (the sun's lean below the lens), black glass
    const fx = ax - SUN_XZ[0]*(ry - fy), fz = az - SUN_XZ[1]*(ry - fy);
    const GL = [], CORE = [];
    const disc = (out, cx, cz, r, n, y) => {
      for (let k = 0; k < n; k++) {
        const a0 = k/n*Math.PI*2, a1 = (k + 1)/n*Math.PI*2;
        const r0 = r*(1 + 0.25*(h3(k, 0, 0, 41) - 0.5)), r1 = r*(1 + 0.25*(h3((k + 1) % n, 0, 0, 41) - 0.5));
        out.push(cx, y, cz, cx + Math.cos(a1)*r1, y, cz + Math.sin(a1)*r1, cx + Math.cos(a0)*r0, y, cz + Math.sin(a0)*r0);
      }
    };
    disc(GL, fx, fz, 0.42, 14, floor_y(fx, fz) + 0.015);
    disc(CORE, fx, fz, 0.06, 8, floor_y(fx, fz) + 0.02);
    add(a, 'glass', GL);
    add(a, 'glass_core', CORE);
    R.burn = [fx, floor_y(fx, fz), fz];
    // ledges: flat sandstone slabs stacked against the walls
    for (let k = 0, tries = 0; k < 24 && tries < 4000; tries++) {
      const [x, z] = rand_in(a);
      if (area_at(x, z) !== a) continue;
      const wd = wall_dir(x, z, 1.3);
      if (!wd || lane(x, z) < 1.8 || item_d(x, z) < 2.8 || !free(x, z, 0.9)) continue;
      const s = rng.float(0.8, 2.2);
      let y = 0;
      for (let l = 0; l < rng.int(1, 4); l++) {
        const hgt = s*rng.float(0.18, 0.35);
        add_block(a, x + wd[0]*0.3 + rng.spread(0.2), z + wd[1]*0.3 + rng.spread(0.2), s*rng.float(1.0, 1.6)*(1 - l*0.15), hgt, s*rng.float(0.8, 1.2)*(1 - l*0.15), { tilt: 0.06, sink: 0.2, lift: y, corners: 0.85 });
        y += hgt*0.8;
      }
      placed.push([x, z, s*0.7]);
      k++;
    }
  }

  // ---------------------------------------------------------------- 0 THE WAKING: where he lies
  {
    // a low slab under the thin light, the rock round it worn
    const a = 0;
    void a;
  }
  return R;
}

// a snake's skeleton hanging from a ceiling point: the spine hangs down `hang` metres in a slack
// curve, the rest of its 4.4 m coiled loosely at the bottom; vertebrae as small blocks, ribs as
// thin curved slivers on both sides, the skull at the end
export function snake_skeleton(rng, top, hang, yaw) {
  const LEN = 4.4, N = 64, T = [];
  const sp = [];
  const sway = rng.float(0.2, 0.6), ph = rng.float(0, 6.28);
  for (let i = 0; i <= N; i++) {
    const s = i/N*LEN;
    let x, y, z;
    if (s < hang) {
      const t = s/hang;
      x = Math.sin(t*2.2 + ph)*sway*t; y = -s; z = Math.cos(t*1.7 + ph)*sway*0.6*t;
    } else {
      // the rest hangs in a loose loop round the low end
      const u = (s - hang);
      const r = 0.25 + 0.1*Math.sin(u*2);
      const end = [Math.sin(2.2 + ph)*sway, -hang, Math.cos(1.7 + ph)*sway*0.6];
      x = end[0] + Math.sin(u/r*0.9)*r; y = end[1] - (1 - Math.cos(u/r*0.9))*r*0.6 - u*0.05; z = end[2] + (Math.cos(u/r*0.9) - 1)*r;
    }
    const c = Math.cos(yaw), sn = Math.sin(yaw);
    sp.push([top[0] + x*c - z*sn, top[1] + y, top[2] + x*sn + z*c]);
  }
  const push = (arr) => { for (const v of arr) T.push(v); };
  for (let i = 0; i < N; i++) {
    const a = sp[i], b = sp[i + 1];
    const d = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
    const F = frame(d[0], d[1], d[2]);
    const s = i/N;
    const w = s < 0.05 ? 0.045 : s > 0.8 ? lerp(0.04, 0.012, (s - 0.8)/0.2) : 0.04;
    const mid = [(a[0] + b[0])/2, (a[1] + b[1])/2, (a[2] + b[2])/2];
    // a vertebra: a squat octahedron
    const L = Math.hypot(...d)*0.5;
    const P = (du, dv, dd) => [mid[0] + F.u[0]*du + F.v[0]*dv + F.d[0]*dd, mid[1] + F.u[1]*du + F.v[1]*dv + F.d[1]*dd, mid[2] + F.u[2]*du + F.v[2]*dv + F.d[2]*dd];
    const px = P(w, 0, 0), nx = P(-w, 0, 0), py = P(0, w*0.8, 0), ny = P(0, -w*0.8, 0), pz = P(0, 0, L), nz = P(0, 0, -L);
    const oct = [];
    for (const [p, q] of [[px, py], [py, nx], [nx, ny], [ny, px]]) { oct.push(...p, ...q, ...pz, ...q, ...p, ...nz); }
    for (let k = 0; k < oct.length; k += 9) {
      const sub = oct.slice(k, k + 9);
      const cx = (sub[0] + sub[3] + sub[6])/3 - mid[0], cy = (sub[1] + sub[4] + sub[7])/3 - mid[1], cz = (sub[2] + sub[5] + sub[8])/3 - mid[2];
      const ux = sub[3] - sub[0], uy = sub[4] - sub[1], uz = sub[5] - sub[2], vx = sub[6] - sub[0], vy = sub[7] - sub[1], vz = sub[8] - sub[2];
      const n = [uy*vz - uz*vy, uz*vx - ux*vz, ux*vy - uy*vx];
      if (n[0]*cx + n[1]*cy + n[2]*cz < 0) push([...sub.slice(0, 3), ...sub.slice(6, 9), ...sub.slice(3, 6)]); else push(sub);
    }
    // ribs on the body's front two thirds: a pair of curved slivers per vertebra
    if (s > 0.06 && s < 0.72 && i % 1 === 0) {
      const rl = 0.11*(1 - Math.abs(s - 0.35)*1.2);
      for (const side of [-1, 1]) {
        const r0 = P(side*w*0.8, 0, 0), r1 = P(side*(w + rl*0.6), -rl*0.5, -L*0.3), r2 = P(side*(w + rl*0.5), -rl*1.1, -L*0.6);
        const th = 0.012;
        const r0b = [r0[0] + F.d[0]*th, r0[1] + F.d[1]*th, r0[2] + F.d[2]*th], r1b = [r1[0] + F.d[0]*th, r1[1] + F.d[1]*th, r1[2] + F.d[2]*th];
        // both faces (a thin plate), so it shows from either side
        push([...r0, ...r1, ...r1b]); push([...r0, ...r1b, ...r1]);
        push([...r0, ...r1b, ...r0b]); push([...r0, ...r0b, ...r1b]);
        push([...r1, ...r2, ...r1b]); push([...r1, ...r1b, ...r2]);
      }
    }
  }
  // the skull: a small elongated block at the end
  const e = sp[N], e2 = sp[N - 2];
  const dd = [e[0] - e2[0], e[1] - e2[1], e[2] - e2[2]];
  const F = frame(...dd);
  const pts = [];
  for (const su of [-1, 1]) for (const sv of [-1, 1]) for (const sd of [0, 1]) pts.push(new THREE.Vector3(F.u[0]*su*0.05 + F.v[0]*sv*0.035 + F.d[0]*sd*0.13, F.u[1]*su*0.05 + F.v[1]*sv*0.035 + F.d[1]*sd*0.13, F.u[2]*su*0.05 + F.v[2]*sv*0.035 + F.d[2]*sd*0.13));
  pts.push(new THREE.Vector3(F.d[0]*0.2, F.d[1]*0.2, F.d[2]*0.2));
  push(hull(pts, e));
  return T;
}
