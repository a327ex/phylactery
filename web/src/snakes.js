// snakes.js -- PLACEHOLDER snakes for round 1 (the look and the camera are being judged, not the
// snakes). Each snake is a chain of spheres following its head's trail (SNKRX's follow rule),
// slithering from the cave's edge toward the egg; within reach of the lich it shrinks away and
// a new one comes out of the dark. No attacks are drawn yet.
import * as THREE from 'three';
import { make_rng, clamp } from 'game/util.js';
import * as TX from 'game/textures.js';
import { gi_dynamic } from 'game/gi.js';

const SEGS = 32, SPACING = 0.14, MAX_R = 0.19;
const radius_at = i => {
  const t = i/(SEGS - 1);
  return MAX_R*(t < 0.18 ? 0.8 + t/0.18*0.2 : 1 - Math.pow((t - 0.18)/0.82, 1.4)*0.8);
};

export function create_snakes(R, cave, get_lich_pos, count = 9, seed = 5) {
  const rng = make_rng(seed);
  const mat = new THREE.MeshLambertMaterial({ map: TX.scales(41), color: 0xffffff });
  // a faint warm rim so a body reads against the black when little light reaches it
  mat.onBeforeCompile = (sh) => {
    sh.fragmentShader = sh.fragmentShader.replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
      totalEmissiveRadiance += vec3(0.09, 0.062, 0.034)*pow(1.0 - abs(dot(normalize(normal), normalize(vViewPosition))), 2.5);`);
  };
  if (cave.GU) gi_dynamic(mat, cave.GU);
  const body_geo = new THREE.SphereGeometry(1, 10, 7);
  const body = new THREE.InstancedMesh(body_geo, mat, count*SEGS);
  body.castShadow = true; body.receiveShadow = true;
  const head_geo = new THREE.SphereGeometry(1, 10, 7);
  const heads = new THREE.InstancedMesh(head_geo, mat, count);
  heads.castShadow = true; heads.receiveShadow = true;
  const eye_mat = new THREE.MeshBasicMaterial({ color: new THREE.Color(2.4, 2.0, 1.1) });
  const eyes = new THREE.InstancedMesh(new THREE.SphereGeometry(1, 5, 4), eye_mat, count*2);
  for (const m of [body, heads, eyes]) { m.frustumCulled = false; R.world_scene.add(m); }

  const S = [];
  const spawn = (s, delay) => {
    // out of the dark at the chamber's edge, anywhere but the tunnel mouth
    let th;
    do th = rng.float(0, Math.PI*2); while (Math.abs(Math.atan2(Math.sin(th + Math.PI/2), Math.cos(th + Math.PI/2))) < 0.5);
    const r = rng.float(14.5, 16.0);
    s.x = Math.cos(th)*r; s.z = Math.sin(th)*r;
    s.dir = Math.atan2(-s.z, -s.x) + rng.spread(0.4);
    s.phase = rng.float(0, 6.28); s.speed = rng.float(1.3, 1.9); s.freq = rng.float(2.2, 3.0);
    s.trail = [];
    for (let i = 0; i < SEGS*SPACING/0.02 + 2; i++) s.trail.push([s.x - Math.cos(s.dir)*i*0.02, s.z - Math.sin(s.dir)*i*0.02]);
    s.dying = -1; s.delay = delay; s.scale = 1;
  };
  for (let i = 0; i < count; i++) { const s = {}; spawn(s, i*0.9); S.push(s); }

  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), p = new THREE.Vector3(), sc = new THREE.Vector3(), up = new THREE.Vector3(0, 1, 0);
  const egg = cave.egg.position;

  function update(t, dt) {
    const L = get_lich_pos();
    for (const s of S) {
      if (s.delay > 0) { s.delay -= dt; continue; }
      if (s.dying >= 0) {
        s.dying += dt;
        s.scale = clamp(1 - s.dying/0.4, 0, 1);
        if (s.dying > 0.4) spawn(s, rng.float(0.2, 1.4));
        continue;
      }
      // steer toward the egg with a slither
      const want = Math.atan2(egg.z - s.z, egg.x - s.x) + Math.sin(t*s.freq + s.phase)*0.75;
      let d = want - s.dir; d = Math.atan2(Math.sin(d), Math.cos(d));
      s.dir += clamp(d, -3.2*dt, 3.2*dt);
      s.x += Math.cos(s.dir)*s.speed*dt; s.z += Math.sin(s.dir)*s.speed*dt;
      s.trail.unshift([s.x, s.z]);
      if (s.trail.length > 400) s.trail.length = 400;
      // the placeholder "attack": anything within reach of the lich, or at the egg, dissolves
      const dl = Math.hypot(s.x - L.x, s.z - L.z), de = Math.hypot(s.x - egg.x, s.z - egg.z);
      if (dl < 3.4 || de < 2.4) s.dying = 0;
    }
    // draw
    let bi = 0;
    for (let k = 0; k < S.length; k++) {
      const s = S[k];
      const hide = s.delay > 0;
      // walk the trail by arc length
      let acc = 0, ti = 0;
      const pts = [];
      let prev = s.trail[0];
      pts.push(prev);
      for (let i = 1; i < SEGS; i++) {
        const target = i*SPACING;
        while (ti < s.trail.length - 1) {
          const a = s.trail[ti], b = s.trail[ti + 1];
          const l = Math.hypot(b[0] - a[0], b[1] - a[1]);
          if (acc + l >= target) { const f = (target - acc)/(l || 1); pts.push([a[0] + (b[0] - a[0])*f, a[1] + (b[1] - a[1])*f]); break; }
          acc += l; ti++;
        }
        if (pts.length <= i) pts.push(s.trail[s.trail.length - 1]);
      }
      for (let i = 0; i < SEGS; i++) {
        const r = radius_at(i)*s.scale*(hide ? 0 : 1);
        const [x, z] = pts[i];
        p.set(x, cave.ground_y(x, z) + r*0.85, z);
        sc.set(r, r*0.9, r);
        m4.compose(p, q.identity(), sc);
        body.setMatrixAt(bi++, m4);
      }
      // head: an elongated wedge pointing along the travel direction, eyes on top
      const [hx, hz] = pts[0];
      const yaw = Math.atan2(hx - pts[2][0], hz - pts[2][1]);
      const hr = MAX_R*1.05*s.scale*(hide ? 0 : 1);
      const hy = cave.ground_y(hx, hz) + hr*1.0;
      q.setFromAxisAngle(up, yaw);
      p.set(hx + Math.sin(yaw)*0.1, hy, hz + Math.cos(yaw)*0.1);
      sc.set(hr*0.95, hr*0.7, hr*1.6);
      m4.compose(p, q, sc);
      heads.setMatrixAt(k, m4);
      for (const e of [-1, 1]) {
        const ex = hx + Math.sin(yaw)*0.2 + Math.cos(yaw)*e*hr*0.55, ez = hz + Math.cos(yaw)*0.2 - Math.sin(yaw)*e*hr*0.55;
        p.set(ex, hy + hr*0.35, ez);
        const er = 0.038*s.scale*(hide ? 0 : 1);
        m4.compose(p, q.identity(), sc.set(er, er, er));
        eyes.setMatrixAt(k*2 + (e > 0 ? 1 : 0), m4);
      }
    }
    body.instanceMatrix.needsUpdate = true; heads.instanceMatrix.needsUpdate = true; eyes.instanceMatrix.needsUpdate = true;
  }
  return { update, S };
}
