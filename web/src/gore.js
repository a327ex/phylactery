// gore.js -- what a lifted snake becomes when it bursts (round 20, owner: "The explosion for the
// snakes should be more detailed, gory, currently it looks too cheap"; round 11's was sixteen
// dark lumps, a red mist, some droplets and a pale flash).
//
// A real body coming apart, not particles standing for one:
//   PIECES   the snake's own tube torn into sections (its scales, its head, its tail), each
//            torn end capped with the wound: red muscle, a dark cavity, the white of the spine;
//            they tumble, bounce, twitch a while where they land, bleed from their ends, sink
//   MEAT     lumps of flesh from where it burst, wet dark to bright red, trailing blood
//   BONE     ribs (thin curved slivers) and vertebrae, pale
//   GUTS     strands of gut, hanging from the torn ends of pieces, and one thrown free, that
//            swing, fall and drape over the floor
//   BLOOD    jets and a spray of droplets drawn as streaks along their flight, a rain of it from
//            where it burst; where they land, splashes that stay on the floor (and a pool that
//            spreads under the burst), glossy so the light catches them; a red mist
// Everything lies a while, then goes into the ground like the other corpses.
import * as THREE from 'three';
import { smoothstep } from 'game/util.js';
import { gi_dynamic } from 'game/gi.js';

const GRAV = 9.8;
const PIECE_LIFE = 5.5, SINK_T = 1.5;
const MAXR = 36;                                  // rings in one piece, at most

export function create_gore(R, cave, snakes, fx, rng) {
  const N = snakes.RINGS, SIDES = snakes.SIDES, gy = cave.ground_y, GU = cave.GU;
  const lit = (m) => (GU ? gi_dynamic(m, GU) : m);
  const V = new THREE.Vector3(), V2 = new THREE.Vector3(), Q = new THREE.Quaternion(), M = new THREE.Matrix4(), E = new THREE.Euler(), SC = new THREE.Vector3();

  // ---------------------------------------------------------------- blood on the floor
  // four splash shapes drawn once: a blob with a ragged edge, satellite drops, a few runs
  function splat_texture(seed) {
    const S = 128, c = document.createElement('canvas'); c.width = c.height = S;
    const g = c.getContext('2d'), r = (() => { let x = seed*9301 + 49297; return () => ((x = (x*9301 + 49297) % 233280)/233280); })();
    g.fillStyle = '#fff';
    const blob = (x, y, rad, n) => {
      g.beginPath();
      for (let k = 0; k <= n; k++) {
        const a = k/n*Math.PI*2, rr = rad*(0.75 + 0.5*r());
        const px = x + Math.cos(a)*rr, py = y + Math.sin(a)*rr;
        if (k === 0) g.moveTo(px, py); else g.lineTo(px, py);
      }
      g.fill();
    };
    blob(64, 64, 20 + 10*r(), 22);
    for (let k = 0; k < 7; k++) blob(64 + (r() - 0.5)*30, 64 + (r() - 0.5)*30, 8 + 10*r(), 12);
    for (let k = 0; k < 26; k++) {
      const a = r()*Math.PI*2, d = 28 + r()*32, rad = 1 + r()*4;
      blob(64 + Math.cos(a)*d, 64 + Math.sin(a)*d, rad, 8);
      if (r() < 0.35) {                           // a run: the drop dragged out from the splash
        g.save(); g.translate(64, 64); g.rotate(a); g.fillRect(18, -rad*0.4, d - 18, rad*0.8); g.restore();
      }
    }
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.NoColorSpace;
    return t;
  }
  const DEC_N = 90, decals = [];
  const plane = new THREE.PlaneGeometry(1, 1); plane.rotateX(-Math.PI/2);
  for (let v = 0; v < 4; v++) {
    const m = lit(new THREE.MeshStandardMaterial({ color: 0x4a0604, alphaMap: splat_texture(v + 1), transparent: true, depthWrite: false,
      roughness: 0.14, metalness: 0, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 }));
    const mesh = new THREE.InstancedMesh(plane, m, DEC_N);
    mesh.frustumCulled = false; mesh.receiveShadow = true; mesh.renderOrder = 2;
    const D = [];
    for (let i = 0; i < DEC_N; i++) { D.push({ life: 0, x: 0, y: 0, z: 0, rot: 0, s0: 0, s1: 0, t: 0, grow: 0.1, sx: 1 }); mesh.setMatrixAt(i, new THREE.Matrix4().makeScale(0, 0, 0)); }
    R.world_scene.add(mesh);
    decals.push({ mesh, D, next: 0 });
  }
  // a splash where something wet lands: `s` metres across, growing to it in `grow` s, stretched along `rot` by sx
  function splash(x, z, s, grow = 0.12, rot = rng.float(0, 6.28), sx = 1) {
    const pool = decals[rng.int(0, 3)], d = pool.D[pool.next]; pool.next = (pool.next + 1) % DEC_N;
    Object.assign(d, { life: rng.float(9, 13), x, z, y: gy(x, z) + 0.012, rot, s0: s*0.35, s1: s, t: 0, grow, sx });
  }
  function update_decals(dt) {
    for (const pool of decals) {
      pool.D.forEach((d, i) => {
        if (d.life <= 0) return;
        d.life -= dt; d.t += dt;
        // it spreads, lies, then soaks away into the ground
        const s = d.s0 + (d.s1 - d.s0)*smoothstep(0, d.grow, d.t);
        const sink = d.life < 1.2 ? (1.2 - d.life)*0.06 : 0;
        if (d.life <= 0) { pool.mesh.setMatrixAt(i, M.makeScale(0, 0, 0)); return; }
        Q.setFromAxisAngle(V.set(0, 1, 0), d.rot);
        M.compose(V2.set(d.x, d.y - sink, d.z), Q, SC.set(s*d.sx, 1, s));
        pool.mesh.setMatrixAt(i, M);
      });
      pool.mesh.instanceMatrix.needsUpdate = true;
    }
  }

  // ---------------------------------------------------------------- blood in the air
  // droplets drawn as streaks along their screen-space motion; where they land they splash
  const BN = 900;
  const bpos = new Float32Array(BN*3), bvel = new Float32Array(BN*3), bcol = new Float32Array(BN*4), bsize = new Float32Array(BN);
  const bg = new THREE.BufferGeometry();
  bg.setAttribute('position', new THREE.BufferAttribute(bpos, 3));
  bg.setAttribute('aVel', new THREE.BufferAttribute(bvel, 3));
  bg.setAttribute('aCol', new THREE.BufferAttribute(bcol, 4));
  bg.setAttribute('aSize', new THREE.BufferAttribute(bsize, 1));
  const bmat = new THREE.ShaderMaterial({
    uniforms: { uScale: { value: 1 }, uRes: { value: new THREE.Vector2(640, 360) } },
    vertexShader: `attribute vec3 aVel; attribute vec4 aCol; attribute float aSize; uniform float uScale; uniform vec2 uRes;
      varying vec4 vCol; varying vec2 vDir; varying float vK;
      void main(){
        vec4 c0 = projectionMatrix*viewMatrix*vec4(position, 1.0), c1 = projectionMatrix*viewMatrix*vec4(position - aVel*0.012, 1.0);
        vec2 d = (c0.xy/max(c0.w, 1e-3) - c1.xy/max(c1.w, 1e-3))*uRes*0.5;
        float streak = length(d);
        float dot_px = aSize > 0.0 ? max(1.0, aSize*uScale/max(c0.w, 0.05)) : 0.0;
        gl_PointSize = aSize > 0.0 ? min(24.0, dot_px + streak) : 0.0;
        gl_Position = c0;
        vDir = streak > 1e-3 ? d/streak : vec2(1.0, 0.0);
        vK = dot_px/max(gl_PointSize, 1.0);          // how much of the sprite is the drop, the rest its trail
        vCol = aCol; }`,
    fragmentShader: `varying vec4 vCol; varying vec2 vDir; varying float vK;
      void main(){
        vec2 q = gl_PointCoord*2.0 - 1.0; q.y = -q.y;
        // along the motion and across it; the drop at the front, its trail thinning behind
        float u = dot(q, vDir), w = dot(q, vec2(-vDir.y, vDir.x));
        float along = (u*0.5 + 0.5);                  // 0 at the tail, 1 at the front
        float head = 1.0 - vK;
        float width = mix(0.25, 1.0, smoothstep(0.0, head + 0.001, along))*vK;
        float a = smoothstep(width + 0.02, width*0.4, abs(w))*smoothstep(0.0, 0.25, along)*step(along, 1.0);
        if (a < 0.02) discard;
        // a wet highlight toward the front
        vec3 c = mix(vCol.rgb, vCol.rgb*2.6 + vec3(0.04, 0.01, 0.01), smoothstep(0.7, 1.0, along)*0.5);
        gl_FragColor = vec4(c, vCol.a*a); }`,
    transparent: true, depthWrite: false,
  });
  const bpts = new THREE.Points(bg, bmat); bpts.frustumCulled = false; bpts.renderOrder = 10;
  R.world_scene.add(bpts);
  const B = [];
  for (let i = 0; i < BN; i++) B.push({ life: 0, x: 0, y: 0, z: 0, vx: 0, vy: 0, vz: 0, s: 0, splat: 0 });
  let bnext = 0;
  function drop(x, y, z, vx, vy, vz, s = 0.012, splat = 0.5) {
    const b = B[bnext]; bnext = (bnext + 1) % BN;
    Object.assign(b, { life: 3, x, y, z, vx, vy, vz, s, splat, dark: rng.float(0.7, 1.15) });
  }
  function update_blood(dt) {
    for (let i = 0; i < BN; i++) {
      const b = B[i];
      if (b.life <= 0) { bsize[i] = 0; continue; }
      b.life -= dt;
      b.vy -= GRAV*dt;
      const d = 1 - 0.35*dt; b.vx *= d; b.vz *= d;
      b.x += b.vx*dt; b.y += b.vy*dt; b.z += b.vz*dt;
      const g = gy(b.x, b.z);
      if (b.y < g + 0.01) {
        // it lands: a splash, stretched along the way it was going
        if (rng.next() < b.splat) {
          const sp = Math.hypot(b.vx, b.vz);
          splash(b.x, b.z, b.s*rng.float(7, 13), 0.08, Math.atan2(-b.vz, b.vx), 1 + Math.min(1.6, sp*0.35));
        }
        b.life = 0; bsize[i] = 0; continue;
      }
      bpos[i*3] = b.x; bpos[i*3 + 1] = b.y; bpos[i*3 + 2] = b.z;
      bvel[i*3] = b.vx; bvel[i*3 + 1] = b.vy; bvel[i*3 + 2] = b.vz;
      bcol[i*4] = 0.038*b.dark; bcol[i*4 + 1] = 0.0025*b.dark; bcol[i*4 + 2] = 0.002*b.dark; bcol[i*4 + 3] = 0.95;
      bsize[i] = b.s;
    }
    for (const k of ['position', 'aVel', 'aCol', 'aSize']) bg.attributes[k].needsUpdate = true;
  }

  // ---------------------------------------------------------------- the pieces of its body
  const flesh_mat = lit(new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.3, metalness: 0, side: THREE.DoubleSide, flatShading: true }));
  const CAPV = 3*SIDES + 1, MAXV = MAXR*SIDES + 2 + 2*CAPV;
  const PIECES = [];
  for (let k = 0; k < 18; k++) {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(MAXV*3), 3));
    g.setAttribute('normal', new THREE.BufferAttribute(new Float32Array(MAXV*3), 3));
    g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(MAXV*2), 2));
    g.setAttribute('aBurn', new THREE.BufferAttribute(new Float32Array(MAXV*3), 3));
    g.setAttribute('color', new THREE.BufferAttribute(new Float32Array(MAXV*3), 3));
    g.setIndex(new THREE.BufferAttribute(new Uint16Array(MAXR*SIDES*6 + 2*SIDES*3 + 2*SIDES*15), 1));
    const m = new THREE.Mesh(g, [snakes.mat, flesh_mat]);
    m.castShadow = true; m.receiveShadow = true; m.frustumCulled = false; m.visible = false;
    R.world_scene.add(m);
    PIECES.push({ m, on: false, v: new THREE.Vector3(), w: new THREE.Vector3(), t: 0, rest: 0, samples: [], r: 0.08, ends: [], landed: false, tw: 0, ax: new THREE.Vector3() });
  }
  // cut rings a..b of a snake's tube (world, as drawn last frame) into a piece; its ends are
  // torn (a wound) unless they are the snout or the tail tip
  function make_piece(s, a, b) {
    const P = PIECES.find(p => !p.on);
    if (!P) return null;
    const src = s.m.geometry.attributes, sp = src.position.array, sn = src.normal.array, su = src.uv.array;
    const g = P.m.geometry, pos = g.attributes.position.array, nor = g.attributes.normal.array, uv = g.attributes.uv.array, col = g.attributes.color.array, idx = g.index.array;
    // its centre: the middle of its spine
    const c = new THREE.Vector3();
    for (let i = a; i <= b; i++) c.add(s.spine[i]);
    c.multiplyScalar(1/(b - a + 1));
    let nv = 0, ni = 0;
    const put = (x, y, z, nx, ny, nz, u, w, r, gg, bb) => {
      pos[nv*3] = x - c.x; pos[nv*3 + 1] = y - c.y; pos[nv*3 + 2] = z - c.z;
      nor[nv*3] = nx; nor[nv*3 + 1] = ny; nor[nv*3 + 2] = nz; uv[nv*2] = u; uv[nv*2 + 1] = w;
      col[nv*3] = r; col[nv*3 + 1] = gg; col[nv*3 + 2] = bb;
      return nv++;
    };
    // the skin: its rings as they were
    for (let i = a; i <= b; i++) for (let j = 0; j < SIDES; j++) {
      const o = (i*SIDES + j);
      put(sp[o*3], sp[o*3 + 1], sp[o*3 + 2], sn[o*3], sn[o*3 + 1], sn[o*3 + 2], su[o*2], su[o*2 + 1], 1, 1, 1);
    }
    for (let i = 0; i < b - a; i++) for (let j = 0; j < SIDES; j++) {
      const p0 = i*SIDES + j, p1 = i*SIDES + (j + 1)%SIDES, p2 = (i + 1)*SIDES + (j + 1)%SIDES, p3 = (i + 1)*SIDES + j;
      idx[ni++] = p0; idx[ni++] = p3; idx[ni++] = p2; idx[ni++] = p0; idx[ni++] = p2; idx[ni++] = p1;
    }
    // the snout or the tail tip closes the skin
    const close = (ring, tipv, flip) => {
      const o = tipv*3;
      const t = put(sp[o], sp[o + 1], sp[o + 2], sn[o], sn[o + 1], sn[o + 2], 0, 0, 1, 1, 1);
      for (let j = 0; j < SIDES; j++) {
        const r0 = ring*SIDES + j, r1 = ring*SIDES + (j + 1)%SIDES;
        if (flip) { idx[ni++] = t; idx[ni++] = r1; idx[ni++] = r0; } else { idx[ni++] = t; idx[ni++] = r0; idx[ni++] = r1; }
      }
    };
    if (a === 0) close(0, N*SIDES, true);                        // the snout (the snake's own winding)
    if (b === N - 1) close(b - a, N*SIDES + 1, false);           // the tail tip
    const skin_n = ni;
    // the wounds: rim (the cut skin's edge), muscle, the dark of the body cavity, the spine
    P.ends.length = 0;
    // torn, not cut: the skin's edge ragged (in and out along the body), the flesh within
    // bulging out of it in lumps (the pressure that burst it), the dark of the body cavity at the
    // heart of it, the spine a pale knot at the back
    const wound = (i, out) => {
      const ctr = s.spine[i], nb = s.spine[Math.max(0, Math.min(N - 1, i + out))];
      const ax = V.subVectors(nb, ctr).normalize().clone();        // pointing out of the piece
      const r = s.radii[i];
      const ring = (k, reach, push, jit, colour) => {
        const first = nv;
        for (let j = 0; j < SIDES; j++) {
          const o = (i*SIDES + j)*3, rr = reach*(1 + rng.spread(jit)), pp = (push + rng.spread(jit*1.4))*r;
          const x = ctr.x + (sp[o] - ctr.x)*rr + ax.x*pp, y = ctr.y + (sp[o + 1] - ctr.y)*rr + ax.y*pp, z = ctr.z + (sp[o + 2] - ctr.z)*rr + ax.z*pp;
          const cl = colour(j);
          put(x, y, z, ax.x, ax.y, ax.z, 0, 0, cl[0], cl[1], cl[2]);
        }
        return first;
      };
      const dk = () => rng.float(0.75, 1.2);
      const rim0 = ring(0, 1.0, 0.0, 0.14, () => [0.07*dk(), 0.006, 0.004]);
      const fl0 = ring(1, 0.74, 0.34, 0.22, j => (j === SIDES/2 ? [0.42, 0.37, 0.28] : [0.16*dk(), 0.012, 0.009]));
      const in0 = ring(2, 0.36, 0.26, 0.3, () => [0.11*dk(), 0.008, 0.006]);
      const cc = put(ctr.x + ax.x*r*0.02, ctr.y + ax.y*r*0.02, ctr.z + ax.z*r*0.02, ax.x, ax.y, ax.z, 0, 0, 0.04, 0.002, 0.002);
      const band = (p, q) => {
        for (let j = 0; j < SIDES; j++) {
          const j1 = (j + 1)%SIDES;
          idx[ni++] = p + j; idx[ni++] = q + j; idx[ni++] = q + j1;
          idx[ni++] = p + j; idx[ni++] = q + j1; idx[ni++] = p + j1;
        }
      };
      band(rim0, fl0); band(fl0, in0);
      for (let j = 0; j < SIDES; j++) { idx[ni++] = in0 + j; idx[ni++] = cc; idx[ni++] = in0 + (j + 1)%SIDES; }
      P.ends.push({ local: new THREE.Vector3().subVectors(ctr, c), ax: ax.clone() });
    };
    if (a > 0) wound(a, -1);
    if (b < N - 1) wound(b, 1);
    g.clearGroups(); g.addGroup(0, skin_n, 0); g.addGroup(skin_n, ni - skin_n, 1);
    g.setDrawRange(0, ni);
    for (const k of ['position', 'normal', 'uv', 'color']) g.attributes[k].needsUpdate = true;
    g.index.needsUpdate = true;
    g.computeBoundingSphere();
    // where it touches the floor: points along its spine
    P.samples = [];
    for (let i = a; i <= b; i += Math.max(1, Math.round((b - a)/5))) P.samples.push(new THREE.Vector3().subVectors(s.spine[i], c));
    P.samples.push(new THREE.Vector3().subVectors(s.spine[b], c));
    P.r = Math.max(0.02, s.radii[Math.round((a + b)/2)]*0.8);
    P.m.position.copy(c); P.m.quaternion.identity(); P.m.scale.set(1, 1, 1); P.m.visible = true;
    P.on = true; P.t = 0; P.rest = 0; P.landed = false; P.tw = rng.float(0, 6);
    V.subVectors(s.spine[b], s.spine[a]); P.ax.copy(V.lengthSq() > 1e-6 ? V.normalize() : V.set(1, 0, 0));
    return P;
  }
  function update_pieces(dt) {
    for (const P of PIECES) {
      if (!P.on) continue;
      P.t += dt;
      const m = P.m;
      if (P.rest <= 0) {
        P.v.y -= GRAV*dt;
        m.position.addScaledVector(P.v, dt);
        const wl = P.w.length();
        if (wl > 1e-4) { Q.setFromAxisAngle(V.copy(P.w).multiplyScalar(1/wl), wl*dt); m.quaternion.premultiply(Q); }
        // the floor, under its lowest point
        let pen = 0, hx = 0, hz = 0;
        for (const sm of P.samples) {
          V.copy(sm).applyQuaternion(m.quaternion).add(m.position);
          const d = gy(V.x, V.z) + P.r - V.y;
          if (d > pen) { pen = d; hx = V.x; hz = V.z; }
        }
        if (pen > 0) {
          m.position.y += pen;
          if (!P.landed) { P.landed = true; splash(hx, hz, rng.float(0.25, 0.45), 0.25); }
          if (P.v.y < 0) {
            if (Math.abs(P.v.y) < 1.4) { P.rest = 1e-3; P.v.set(0, 0, 0); P.w.set(0, 0, 0); }
            else { P.v.y *= -0.25; P.v.x *= 0.5; P.v.z *= 0.5; P.w.multiplyScalar(0.45); }
          }
        }
        // it bleeds from its torn ends as it flies
        for (const e of P.ends) if (rng.next() < 0.35) {
          V.copy(e.local).applyQuaternion(m.quaternion).add(m.position);
          V2.copy(e.ax).applyQuaternion(m.quaternion);
          drop(V.x, V.y, V.z, P.v.x*0.6 + V2.x*0.6 + rng.spread(0.3), P.v.y*0.6 + V2.y*0.6, P.v.z*0.6 + V2.z*0.6 + rng.spread(0.3), rng.float(0.008, 0.014), 0.35);
        }
      } else {
        // where it lies: a piece that came down on its end topples over; it twitches a while (a
        // turn about its length, dying away), bleeds a little
        P.rest += dt;
        V.copy(P.ax).applyQuaternion(m.quaternion);
        if (Math.abs(V.y) > 0.2) {
          V2.crossVectors(V, UP); if (V2.lengthSq() > 1e-6) { V2.normalize(); Q.setFromAxisAngle(V2, Math.sign(V.y)*Math.min(Math.abs(V.y), 5*dt)); m.quaternion.premultiply(Q); }
          let pen = 0;
          for (const sm of P.samples) { V.copy(sm).applyQuaternion(m.quaternion).add(m.position); pen = Math.max(pen, gy(V.x, V.z) + P.r - V.y); }
          m.position.y += pen;
          let low = 1e9;
          for (const sm of P.samples) { V.copy(sm).applyQuaternion(m.quaternion).add(m.position); low = Math.min(low, V.y - gy(V.x, V.z) - P.r); }
          if (low > 0.005) m.position.y -= Math.min(low, 1.5*dt);
        }
        const tw = Math.exp(-P.rest*1.6)*Math.sin(P.rest*(13 + P.tw) + P.tw)*0.9*dt;
        if (P.rest < 2.2) { V.copy(P.ax).applyQuaternion(m.quaternion); Q.setFromAxisAngle(V, tw); m.quaternion.premultiply(Q); }
        if (P.rest < 1.0) for (const e of P.ends) if (rng.next() < 0.08) {
          V.copy(e.local).applyQuaternion(m.quaternion).add(m.position);
          drop(V.x, V.y, V.z, rng.spread(0.3), rng.float(0, 0.4), rng.spread(0.3), 0.01, 0.8);
        }
      }
      // then into the ground
      if (P.t > PIECE_LIFE) m.position.y -= 0.3/SINK_T*dt;
      if (P.t > PIECE_LIFE + SINK_T) { P.on = false; m.visible = false; }
    }
  }

  // ---------------------------------------------------------------- meat and bone
  function debris_pool(geo, mat, n, coloured) {
    const mesh = new THREE.InstancedMesh(geo, mat, n);
    mesh.castShadow = true; mesh.receiveShadow = true; mesh.frustumCulled = false;
    if (coloured) mesh.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(n*3).fill(1), 3);
    const zero = new THREE.Matrix4().makeScale(0, 0, 0);
    const D = [];
    for (let i = 0; i < n; i++) { D.push({ life: 0 }); mesh.setMatrixAt(i, zero); }
    R.world_scene.add(mesh);
    let next = 0;
    return {
      spawn(o) {
        const d = D[next], i = next; next = (next + 1) % n;
        Object.assign(d, { life: PIECE_LIFE + SINK_T, t: 0, rest: 0, landed: false, rx: rng.float(0, 6), ry: rng.float(0, 6), rz: rng.float(0, 6),
          wx: rng.spread(16), wy: rng.spread(16), wz: rng.spread(16), sx: 1, sy: 1, sz: 1, bleed: 0 }, o);
        if (coloured && o.c) { mesh.instanceColor.setXYZ(i, o.c[0], o.c[1], o.c[2]); mesh.instanceColor.needsUpdate = true; }
        return d;
      },
      update(dt) {
        for (let i = 0; i < n; i++) {
          const d = D[i];
          if (d.life <= 0) continue;
          d.life -= dt; d.t += dt;
          if (d.rest <= 0) {
            d.vy -= GRAV*dt;
            d.x += d.vx*dt; d.y += d.vy*dt; d.z += d.vz*dt;
            d.rx += d.wx*dt; d.ry += d.wy*dt; d.rz += d.wz*dt;
            const g = gy(d.x, d.z) + d.s*0.4;
            if (d.y < g) {
              d.y = g;
              if (!d.landed) { d.landed = true; if (d.bleed && rng.next() < 0.7) splash(d.x, d.z, d.s*rng.float(4, 7), 0.15, Math.atan2(-d.vz, d.vx), 1.4); }
              if (Math.abs(d.vy) < 1.0) { d.rest = 1e-3; d.vx = d.vy = d.vz = 0; }
              else { d.vy = -d.vy*0.22; d.vx *= 0.5; d.vz *= 0.5; d.wx *= 0.4; d.wy *= 0.4; d.wz *= 0.4; }
            }
            if (d.bleed && rng.next() < d.bleed) drop(d.x, d.y, d.z, d.vx*0.5 + rng.spread(0.2), d.vy*0.5, d.vz*0.5 + rng.spread(0.2), 0.008, 0.3);
          } else {
            d.rest += dt;
            if (d.life < SINK_T) d.y -= 0.12*dt;
          }
          E.set(d.rx, d.ry, d.rz); Q.setFromEuler(E);
          const k = d.life < 0.3 ? d.life/0.3 : 1;
          M.compose(V.set(d.x, d.y, d.z), Q, SC.set(d.s*d.sx*k, d.s*d.sy*k, d.s*d.sz*k));
          mesh.setMatrixAt(i, M);
        }
        mesh.instanceMatrix.needsUpdate = true;
      },
    };
  }
  // a lump of flesh: an icosphere pushed about so no two faces agree
  const lump = new THREE.IcosahedronGeometry(1, 1);
  { const p = lump.attributes.position; for (let i = 0; i < p.count; i++) { const k = 0.7 + 0.5*Math.abs(Math.sin(i*12.9898)*43758.5453 % 1); p.setXYZ(i, p.getX(i)*k, p.getY(i)*k, p.getZ(i)*k); } lump.computeVertexNormals(); }
  const meat = debris_pool(lump, lit(new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.22, metalness: 0 })), 320, true);
  const bone_mat = lit(new THREE.MeshStandardMaterial({ color: 0xb4a78e, roughness: 0.5, metalness: 0 }));
  const ribs = debris_pool(new THREE.TorusGeometry(1, 0.06, 3, 7, 1.9), bone_mat, 160, false);
  const verts = debris_pool(new THREE.DodecahedronGeometry(1, 0), bone_mat, 80, false);
  // skin torn off in scraps, scales out, red within
  const scrap_geo = new THREE.PlaneGeometry(1, 1, 2, 1);
  { const p = scrap_geo.attributes.position; for (let i = 0; i < p.count; i++) p.setZ(i, (Math.abs(p.getX(i)) > 0.2 ? 0.18 : 0)); scrap_geo.computeVertexNormals(); }
  const scraps = debris_pool(scrap_geo, lit(new THREE.MeshStandardMaterial({ color: 0x3a3629, roughness: 0.35, metalness: 0, side: THREE.DoubleSide })), 120, false);

  // ---------------------------------------------------------------- guts
  const GN = 11, GS = 6, GUTS = [];
  const gut_mat = lit(new THREE.MeshStandardMaterial({ color: 0x6e3634, roughness: 0.22, metalness: 0 }));
  for (let k = 0; k < 10; k++) {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(GN*GS*3), 3));
    g.setAttribute('normal', new THREE.BufferAttribute(new Float32Array(GN*GS*3), 3));
    const idx = [];
    for (let i = 0; i < GN - 1; i++) for (let j = 0; j < GS; j++) { const a = i*GS + j, b = i*GS + (j + 1)%GS, c = (i + 1)*GS + (j + 1)%GS, d = (i + 1)*GS + j; idx.push(a, d, c, a, c, b); }
    g.setIndex(idx);
    const m = new THREE.Mesh(g, gut_mat);
    m.castShadow = true; m.receiveShadow = true; m.frustumCulled = false; m.visible = false;
    R.world_scene.add(m);
    GUTS.push({ m, on: false, p: [...Array(GN)].map(() => new THREE.Vector3()), q: [...Array(GN)].map(() => new THREE.Vector3()), piece: null, end: 0, t: 0, len: 0.05, r: 0.011 });
  }
  function gut(from, vel, piece, end) {
    const G = GUTS.find(q => !q.on);
    if (!G) return;
    G.on = true; G.t = 0; G.piece = piece; G.end = end; G.m.visible = true;
    G.len = rng.float(0.03, 0.045); G.r = rng.float(0.013, 0.018);
    for (let i = 0; i < GN; i++) {
      G.p[i].copy(from).addScaledVector(vel, i*0.002).add(V.set(rng.spread(0.03), -i*0.012, rng.spread(0.03)));
      G.q[i].copy(G.p[i]).addScaledVector(vel, -1/60*(0.3 + i/GN));    // verlet: moving out, the free end faster
    }
  }
  const T = new THREE.Vector3(), Bn = new THREE.Vector3(), Nn = new THREE.Vector3(), UP = new THREE.Vector3(0, 1, 0);
  function update_guts(dt) {
    for (const G of GUTS) {
      if (!G.on) continue;
      G.t += dt;
      const P = G.p, Q0 = G.q;
      for (let i = 0; i < GN; i++) {
        const vx = (P[i].x - Q0[i].x)*0.985, vy = (P[i].y - Q0[i].y)*0.985, vz = (P[i].z - Q0[i].z)*0.985;
        Q0[i].copy(P[i]);
        P[i].x += vx; P[i].y += vy - GRAV*dt*dt; P[i].z += vz;
      }
      // hanging from a piece's torn end while the piece is still there
      const pc = G.piece && G.piece.on ? G.piece : null;
      for (let it = 0; it < 4; it++) {
        if (pc) { const e = pc.ends[G.end]; if (e) P[0].copy(e.local).applyQuaternion(pc.m.quaternion).add(pc.m.position); }
        for (let i = 0; i < GN - 1; i++) {
          V.subVectors(P[i + 1], P[i]); const l = V.length() || 1e-6, k = (l - G.len)/l*0.5;
          if (pc && i === 0) P[1].addScaledVector(V, -2*k); else { P[i].addScaledVector(V, k); P[i + 1].addScaledVector(V, -k); }
        }
        for (let i = 0; i < GN; i++) { const g = gy(P[i].x, P[i].z) + G.r; if (P[i].y < g) { P[i].y = g; Q0[i].x = P[i].x - (P[i].x - Q0[i].x)*0.4; Q0[i].z = P[i].z - (P[i].z - Q0[i].z)*0.4; } }
      }
      if (G.t > PIECE_LIFE) for (const p of P) p.y -= 0.25/SINK_T*dt;
      // the tube along it
      const pos = G.m.geometry.attributes.position.array, nor = G.m.geometry.attributes.normal.array;
      for (let i = 0; i < GN; i++) {
        T.subVectors(P[Math.min(GN - 1, i + 1)], P[Math.max(0, i - 1)]).normalize();
        Bn.crossVectors(T, UP); if (Bn.lengthSq() < 1e-6) Bn.set(1, 0, 0); Bn.normalize(); Nn.crossVectors(Bn, T);
        const r = G.r*(i === 0 || i === GN - 1 ? 0.6 : 1)*(1 + 0.35*Math.sin(i*2.3 + G.len*97));   // lumpy
        for (let j = 0; j < GS; j++) {
          const a = j/GS*6.2832, cx = Math.cos(a), cy = Math.sin(a), o = (i*GS + j)*3;
          nor[o] = Bn.x*cx + Nn.x*cy; nor[o + 1] = Bn.y*cx + Nn.y*cy; nor[o + 2] = Bn.z*cx + Nn.z*cy;
          pos[o] = P[i].x + nor[o]*r; pos[o + 1] = P[i].y + nor[o + 1]*r; pos[o + 2] = P[i].z + nor[o + 2]*r;
        }
      }
      G.m.geometry.attributes.position.needsUpdate = true; G.m.geometry.attributes.normal.needsUpdate = true;
      if (G.t > PIECE_LIFE + SINK_T) { G.on = false; G.m.visible = false; }
    }
  }

  // ---------------------------------------------------------------- the burst
  const MEAT_C = [[0.2, 0.012, 0.009], [0.3, 0.03, 0.022], [0.13, 0.007, 0.006], [0.4, 0.1, 0.075], [0.26, 0.06, 0.04]];
  // `toward`: round 21 (owner: the pieces and blood "should slightly come in his direction"):
  // part of what bursts is thrown toward that point (his chest), the rest all round
  const TW = new THREE.Vector3();
  function burst(s, mid, toward = null) {
    const arc = snakes.arc, c = s.spine[mid].clone(), cm = arc(mid);
    if (toward) { TW.subVectors(toward, c); TW.y = Math.max(TW.y, -0.2*TW.length()); TW.normalize(); } else TW.set(0, 0, 0);
    const pull = (o, lo, hi) => { const k = rng.float(lo, hi); o.x += TW.x*k; o.y += TW.y*k; o.z += TW.z*k; return o; };
    // where it tears apart: ~30 cm either side of the middle is torn to meat
    let a = mid, b = mid;
    while (a > 1 && cm - arc(a) < 0.28) a--;
    while (b < N - 2 && arc(b) - cm < 0.3) b++;
    const pieces = [];
    const throw_piece = (P) => {
      if (!P) return;
      const out = V.subVectors(P.m.position, c); out.y = Math.max(out.y, 0) + 0.2;
      out.normalize();
      const sp = rng.float(2.2, 4.2);
      P.v.set(out.x*sp + rng.spread(0.8), rng.float(1.2, 3.0) + out.y*sp*0.3, out.z*sp + rng.spread(0.8));
      pull(P.v, 0.9, 2.2);
      P.w.set(rng.spread(1), rng.spread(1), rng.spread(1)).normalize().multiplyScalar(rng.float(4, 11));
      pieces.push(P);
    };
    // toward the head: pieces of 30-60 cm, the last one the head
    let i1 = a;
    while (i1 > 0) {
      let i0 = i1;
      const len = rng.float(0.3, 0.6);
      while (i0 > 0 && arc(i1) - arc(i0) < len && i1 - i0 < MAXR - 1) i0--;
      if (i0 <= 2) i0 = 0;
      throw_piece(make_piece(s, i0, i1));
      i1 = i0;
    }
    // toward the tail
    let j0 = b;
    while (j0 < N - 1) {
      let j1 = j0;
      const len = rng.float(0.35, 0.7);
      while (j1 < N - 1 && arc(j1) - arc(j0) < len && j1 - j0 < MAXR - 1) j1++;
      if (j1 >= N - 3) j1 = N - 1;
      throw_piece(make_piece(s, j0, j1));
      j0 = j1;
    }
    // meat, skin scraps, ribs and vertebrae from where it tore
    const burst_at = (i, r0, o) => {
      const p = s.spine[i];
      const dir = V.set(rng.spread(1), rng.spread(1), rng.spread(1)).normalize();
      const x = p.x + dir.x*r0, y = p.y + dir.y*r0, z = p.z + dir.z*r0;
      const sp = rng.float(o.v0, o.v1);
      return { x, y, z, vx: dir.x*sp + (p.x - c.x)*1.5, vy: Math.abs(dir.y)*sp*0.8 + rng.float(0.8, 2.4), vz: dir.z*sp + (p.z - c.z)*1.5 };
    };
    for (let k = 0; k < 46; k++) {
      const i = rng.int(a, b), o = burst_at(i, s.radii[i]*0.6, { v0: 1.5, v1: 5.0 });
      const pv = pull({ x: o.vx, y: o.vy, z: o.vz }, 0.6, 2.0); o.vx = pv.x; o.vy = pv.y; o.vz = pv.z;
      meat.spawn(Object.assign(o, { s: rng.float(0.012, 0.035), sx: rng.float(0.7, 1.4), sy: rng.float(0.5, 1.0), sz: rng.float(0.7, 1.5), c: MEAT_C[rng.int(0, MEAT_C.length - 1)], bleed: 0.25 }));
    }
    for (let k = 0; k < 14; k++) {
      const i = rng.int(a, b), o = burst_at(i, s.radii[i], { v0: 1.2, v1: 3.5 });
      scraps.spawn(Object.assign(o, { s: rng.float(0.03, 0.06), sx: rng.float(0.8, 1.3), sy: rng.float(0.5, 1.0), sz: 1 }));
    }
    for (let k = 0; k < 16; k++) {
      const i = rng.int(a, b), o = burst_at(i, s.radii[i]*0.4, { v0: 1.5, v1: 4.5 });
      ribs.spawn(Object.assign(o, { s: rng.float(0.035, 0.055), sx: 1, sy: 1, sz: 1 }));
    }
    for (let k = 0; k < 6; k++) {
      const i = rng.int(a, b), o = burst_at(i, 0.01, { v0: 1.0, v1: 3.0 });
      verts.spawn(Object.assign(o, { s: rng.float(0.011, 0.016), sx: 1.3, sy: 0.9, sz: 1 }));
    }
    // guts hanging out of the pieces either side of the tear, and a loop thrown free
    const near = [...pieces].sort((p, q) => p.m.position.distanceTo(c) - q.m.position.distanceTo(c)).slice(0, 2);
    near.forEach(P => { if (P.ends.length) { const e = P.ends[P.ends.length > 1 ? (P.ends[0].local.clone().add(P.m.position).distanceTo(c) < P.ends[1].local.clone().add(P.m.position).distanceTo(c) ? 0 : 1) : 0]; V2.copy(e.local).add(P.m.position); gut(V2.clone(), P.v.clone().multiplyScalar(0.8), P, P.ends.indexOf(e)); } });
    gut(c.clone(), pull(V.set(rng.spread(2), rng.float(1, 2.5), rng.spread(2)), 1.0, 2.0).clone(), null, 0);
    // blood: a few jets, a spray all round, a rain from where it was, a pool spreading below
    for (let j = 0; j < 5; j++) {
      // two of the jets come at him
      const d = V2.set(rng.spread(1), rng.float(-0.3, 0.9), rng.spread(1)).normalize().clone();
      if (j < 2 && toward) d.copy(TW).add(V.set(rng.spread(0.5), rng.float(0, 0.4), rng.spread(0.5))).normalize();
      const sp0 = rng.float(3, 6);
      for (let k = 0; k < 26; k++) {
        const sp = sp0*rng.float(0.5, 1.1);
        drop(c.x, c.y, c.z, d.x*sp + rng.spread(0.5), d.y*sp + rng.spread(0.5), d.z*sp + rng.spread(0.5), rng.float(0.014, 0.028), 0.45);
      }
    }
    for (let k = 0; k < 80; k++) {
      const i = rng.int(a, b), p = s.spine[i], d = V2.set(rng.spread(1), rng.spread(1), rng.spread(1)).normalize();
      const sp = rng.float(0.8, 4.0);
      drop(p.x, p.y, p.z, d.x*sp + TW.x*0.9, d.y*sp + 0.8, d.z*sp + TW.z*0.9, rng.float(0.01, 0.022), 0.4);
    }
    for (let k = 0; k < 40; k++) {
      const i = rng.int(Math.max(0, a - 6), Math.min(N - 1, b + 6)), p = s.spine[i];
      drop(p.x + rng.spread(0.05), p.y, p.z + rng.spread(0.05), rng.spread(0.35), rng.float(-0.4, 0.3), rng.spread(0.35), rng.float(0.012, 0.022), 0.6);
    }
    splash(c.x, c.z, rng.float(0.7, 1.0), 1.6);
    splash(c.x + rng.spread(0.3), c.z + rng.spread(0.3), rng.float(0.4, 0.6), 1.2);
    // a red mist, hanging a moment: a dense wet cloud where it burst, thinning as it spreads
    for (let k = 0; k < 44; k++) {
      const p = s.spine[rng.int(a, b)], near = k < 16;
      fx.puff({ x: p.x, y: p.y, z: p.z, vx: rng.spread(near ? 0.6 : 1.4), vy: rng.float(-0.2, 0.9), vz: rng.spread(near ? 0.6 : 1.4), grav: 0.6, drag: 1.8,
        life: rng.float(0.8, 1.7), s0: rng.float(0.1, 0.2)*(near ? 1.5 : 1), s1: rng.float(0.3, 0.55)*(near ? 1.3 : 1), r: 0.03, g: 0.0025, b: 0.002, a: near ? 0.7 : 0.45, fin: 0.02 });
    }
  }

  return {
    burst,
    pieces: () => PIECES.map((p, i) => (p.on ? { i, t: p.t, p: p.m.position.clone() } : null)).filter(Boolean),     // tests
    update(t, dt) { update_pieces(dt); meat.update(dt); ribs.update(dt); verts.update(dt); scraps.update(dt); update_guts(dt); update_blood(dt); update_decals(dt); },
    set_camera(cam, H) { bmat.uniforms.uScale.value = cam.projectionMatrix.elements[5]*H*0.5; },
  };
}
