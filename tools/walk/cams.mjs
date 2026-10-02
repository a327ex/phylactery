// cams.mjs -- the fixed cameras (Resident Evil's: each watches a stretch of the walk from a set
// place; crossing into the next stretch cuts to the next). The walk is split into stretches along
// its length (s): about 10 m each, each object's stretch centred on it. For every stretch the
// builder tries a few hundred places in the air around it (high in the passage, off to its sides,
// round the chambers) and keeps the one that sees most of where he can be in it: points at his
// chest over the open floor, inside the frame and not hidden by rock (rays against the bake's
// BVH), at a distance that keeps him readable, looking down at a slant, along the way rather than
// across it, and not from the same angle as the stretch before (a cut should change the view).
// Hand-placed cameras (layout.mjs CAMERAS) replace the search where a scene needs its own shot.
import { ITEMS, AREAS, CAMERAS } from './layout.mjs';
import { intersect } from './bake.mjs';
import { make_rng } from './lib.mjs';

const FOV = 50, ASPECT = 16/9;
const TANH = Math.tan(FOV/2*Math.PI/180);

function basis(eye, tgt) {
  let fx = tgt[0] - eye[0], fy = tgt[1] - eye[1], fz = tgt[2] - eye[2];
  const fl = Math.hypot(fx, fy, fz); fx /= fl; fy /= fl; fz /= fl;
  // r = f x up
  let rx = -fz, ry = 0, rz = fx;
  const rl = Math.hypot(rx, rz) || 1; rx /= rl; rz /= rl;
  const ux = ry*fz - rz*fy, uy = rz*fx - rx*fz, uz = rx*fy - ry*fx;
  return { f: [fx, fy, fz], r: [rx, ry, rz], u: [ux, uy, uz], fl };
}
export function project(eye, Bs, p) {
  const vx = p[0] - eye[0], vy = p[1] - eye[1], vz = p[2] - eye[2];
  const z = vx*Bs.f[0] + vy*Bs.f[1] + vz*Bs.f[2];
  if (z < 0.3) return null;
  return [(vx*Bs.r[0] + vy*Bs.r[1] + vz*Bs.r[2])/(z*TANH*ASPECT), (vx*Bs.u[0] + vy*Bs.u[1] + vz*Bs.u[2])/(z*TANH), z];
}

export function place_cameras({ P, F, B, NAV, log }) {
  const rng = make_rng(77);
  const S = P.S;
  const s_of_item = ITEMS.map(it => P.nearest(it.at[0], it.at[1], 20).p.s);
  // stretches
  const zones = [];
  for (let a = 0; a < AREAS.length; a++) {
    let s0 = a === 0 ? 0 : P.areas_s[a].s0, s1 = P.areas_s[a].s1 + (a === AREAS.length - 1 ? 0 : P.S[1].s);
    const cuts = [];
    const it = ITEMS.find(i => i.area === a);
    const span = (lo, hi) => { const n = Math.max(1, Math.round((hi - lo)/10.5)); for (let k = 0; k < n; k++) cuts.push([lo + (hi - lo)*k/n, lo + (hi - lo)*(k + 1)/n]); };
    if (it) {
      const is = s_of_item[ITEMS.indexOf(it)];
      const lo = Math.max(s0, is - 5), hi = Math.min(s1, is + 5);
      if (lo - s0 > 2) span(s0, lo); else if (cuts.length === 0 && lo > s0) cuts.push([s0, lo]);
      cuts.push([lo, hi, 'item']);
      if (s1 - hi > 2) span(hi, s1); else if (hi < s1) cuts[cuts.length - 1][1] = s1;
    } else span(s0, s1);
    for (const c of cuts) zones.push({ s0: c[0], s1: c[1], area: a, item: c[2] === 'item' ? it.power : -1 });
  }
  // merge slivers into the previous stretch
  for (let i = zones.length - 1; i > 0; i--) if (zones[i].s1 - zones[i].s0 < 2.5 && zones[i].item < 0) { zones[i - 1].s1 = zones[i].s1; zones.splice(i, 1); }

  const sample_at = s => S[Math.max(0, Math.min(S.length - 1, Math.round(s/P.S[1].s)))];
  const hit = { tri: -1 };
  const free_air = (x, y, z) => {
    if (!(F.field(x, y, z) < -0.35)) return false;
    let n = 0;
    for (const d of [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]) if (intersect(B, x, y, z, d[0], d[1], d[2], 0.45, null, true) !== Infinity) n++;
    return n === 0;
  };
  const seen = (eye, p) => {
    const dx = p[0] - eye[0], dy = p[1] - eye[1], dz = p[2] - eye[2];
    const d = Math.hypot(dx, dy, dz);
    return intersect(B, eye[0], eye[1], eye[2], dx/d, dy/d, dz/d, d - 0.35, null, true) === Infinity;
  };
  const out = [];
  let prev = null;
  for (const zn of zones) {
    // where he can be in this stretch: his chest over open floor
    const pts = [];
    for (let s = zn.s0; s <= zn.s1; s += 0.8) {
      const p = sample_at(s);
      for (let u = -7; u <= 7; u += 1.2) {
        const x = p.x - p.tz*u, z = p.z + p.tx*u;
        if (!NAV.open(x, z)) continue;
        const ss = NAV.s_at(x, z);
        if (ss < zn.s0 - 0.5 || ss > zn.s1 + 0.5) continue;
        const k = NAV.at(x, z);
        pts.push([x, NAV.floor[k] + 1.45, z]);
      }
    }
    if (!pts.length) { log(`  cams: stretch ${zn.s0.toFixed(0)}-${zn.s1.toFixed(0)} has no open floor`); continue; }
    let tx = 0, ty = 0, tz = 0;
    for (const p of pts) { tx += p[0]; ty += p[1]; tz += p[2]; }
    const tgt = [tx/pts.length, ty/pts.length - 0.25, tz/pts.length];
    const mid = sample_at((zn.s0 + zn.s1)/2);
    const sub = pts.length > 48 ? pts.filter((_, i) => i % Math.ceil(pts.length/48) === 0) : pts;
    // candidates
    const cands = [];
    for (let s = zn.s0 - 9; s <= zn.s1 + 9; s += 1.5) {
      const p = sample_at(s);
      for (const u of [-1.1, -0.6, 0, 0.6, 1.1]) for (const hy of [2.3, 3.0, 3.8, 4.8, 6.0, 7.5, 9.5]) {
        const x = p.x - p.tz*u*(p.w + 1), z = p.z + p.tx*u*(p.w + 1), y = p.h + hy;
        cands.push([x, y, z]);
      }
    }
    for (let k = 0; k < 120; k++) {
      const a = rng.float(0, 6.28), r = rng.float(4, 13), y = tgt[1] + rng.float(1, 9);
      cands.push([tgt[0] + Math.cos(a)*r, y, tgt[2] + Math.sin(a)*r]);
    }
    let best = null, bs = -Infinity;
    for (const c of cands) {
      const d = Math.hypot(c[0] - tgt[0], c[1] - tgt[1], c[2] - tgt[2]);
      if (d < 3.5 || d > 18) continue;
      const pitch = Math.asin((c[1] - tgt[1])/d)*180/Math.PI;
      if (pitch < 6 || pitch > 62) continue;
      if (!free_air(c[0], c[1], c[2])) continue;
      const Bs = basis(c, tgt);
      let vis = 0;
      for (const p of sub) {
        const q = project(c, Bs, p);
        if (!q || Math.abs(q[0]) > 0.86 || q[1] < -0.82 || q[1] > 0.78) continue;
        const head = [p[0], p[1] + 0.45, p[2]];
        vis += (seen(c, p) ? 0.6 : 0) + (seen(c, head) ? 0.4 : 0);
      }
      vis /= sub.length;
      let sc = vis;
      sc -= d < 5.5 ? (5.5 - d)*0.06 : d > 12 ? (d - 12)*0.05 : 0;
      sc -= pitch < 16 ? (16 - pitch)*0.012 : pitch > 45 ? (pitch - 45)*0.01 : 0;
      const along = Math.abs(Bs.f[0]*mid.tx + Bs.f[2]*mid.tz)/Math.hypot(Bs.f[0], Bs.f[2]);
      sc += 0.12*along;
      if (prev) {
        const cosang = (Bs.f[0]*prev.f[0] + Bs.f[2]*prev.f[2])/(Math.hypot(Bs.f[0], Bs.f[2])*Math.hypot(prev.f[0], prev.f[2]));
        if (cosang > 0.92) sc -= 0.15;
      }
      if (sc > bs) { bs = sc; best = { eye: c, tgt, vis, d, pitch, f: Bs.f }; }
    }
    const man = (CAMERAS || []).find(m => m.s !== undefined ? (m.s >= zn.s0 && m.s < zn.s1) : (m.item !== undefined && m.item === zn.item));
    if (man) {
      let eye = man.eye, tg = man.tgt;
      if (!eye) {
        // relative to the object: the way ahead at it, turned by `from`
        const it = ITEMS[man.item];
        const n = P.nearest(it.at[0], it.at[1], 20).p;
        const fy = F.floor_y(it.at[0], it.at[1]);
        const a = man.from*Math.PI/180;
        const ax = n.tx*Math.cos(a) - n.tz*Math.sin(a), az = n.tx*Math.sin(a) + n.tz*Math.cos(a);
        // left of the way = (tz, -tx) rotated; look offset: x along, z to the left
        const lx = n.tz, lz = -n.tx;
        tg = [it.at[0] + n.tx*man.look[0] + lx*man.look[2], fy + man.look[1], it.at[1] + n.tz*man.look[0] + lz*man.look[2]];
        // the eye in clear air, seeing the object: turn round it a little at a time, then pull in
        const obj = [it.at[0], fy + 1.2, it.at[1]];
        let found = null;
        for (const dd of [0, 12, -12, 24, -24, 36, -36, 50, -50]) {
          const a2 = (man.from + dd)*Math.PI/180;
          const bx = n.tx*Math.cos(a2) - n.tz*Math.sin(a2), bz = n.tx*Math.sin(a2) + n.tz*Math.cos(a2);
          for (let d = man.dist; d > 2.2; d -= 0.25) {
            const e = [it.at[0] + bx*d, fy + man.height, it.at[1] + bz*d];
            if (free_air(e[0], e[1], e[2]) && seen(e, obj)) { found = e; break; }
          }
          if (found) break;
        }
        eye = found || [it.at[0] + ax*man.dist, fy + man.height, it.at[1] + az*man.dist];
        if (!found) log(`  cams: object ${man.item}: no clear view found`);
      }
      const Bs = basis(eye, tg);
      let vis = 0;
      for (const p of sub) { const q = project(eye, Bs, p); if (q && Math.abs(q[0]) < 0.86 && q[1] > -0.82 && q[1] < 0.78 && seen(eye, p)) vis++; }
      best = { eye, tgt: tg, vis: vis/sub.length, d: 0, pitch: 0, f: Bs.f, fov: man.fov };
    }
    if (!best) { log(`  cams: no place for ${zn.s0.toFixed(0)}-${zn.s1.toFixed(0)}`); continue; }
    prev = best;
    out.push({ s0: zn.s0, s1: zn.s1, area: zn.area, item: zn.item, eye: best.eye, tgt: best.tgt, fov: best.fov || FOV, vis: best.vis });
  }
  for (const c of out) log(`  cam ${AREAS[c.area].id} s ${c.s0.toFixed(1)}-${c.s1.toFixed(1)}${c.item >= 0 ? ' (object)' : ''}: sees ${(c.vis*100).toFixed(0)}%`);
  // the final room's tunnel: two hand-placed shots (its geometry is the room's, not in the BVH)
  const end = P.total;
  out.push({ s0: end, s1: end + 15, area: 8, item: -1, eye: [1.6, 3.2, -46.6], tgt: [-0.2, 0.9, -36.0], fov: 50, vis: -1 });
  out.push({ s0: end + 15, s1: end + 60, area: 8, item: -1, eye: [-1.0, 3.1, -15.5], tgt: [0.2, 1.0, -27.0], fov: 52, vis: -1 });
  return out;
}
