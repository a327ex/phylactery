// body.js -- round 28: a small rigid body that drops onto the cave floor (a power's object, let
// go around the egg). Contact is a cloud of points on the object's surface (or one sphere)
// against the floor's height field, plus the egg as a round wall; sequential impulses with
// restitution and Coulomb friction, a little rolling resistance, and sleep once it lies still.
import * as THREE from 'three';

const SUB = 4;                        // substeps per 60 Hz tick
const G = 9.81;

// opts: points (body-frame Vector3s) or sphere (radius); mass; inertia (Vector3, body-frame
// diagonal); restitution; friction; floor(x, z) -> y; egg { x, z, r, top }
export function create_body(opts) {
  const b = {
    x: new THREE.Vector3(), v: new THREE.Vector3(), q: new THREE.Quaternion(), w: new THREE.Vector3(),
    asleep: false, still: 0, contact: false, landed: 0,
    on_hit: null,                     // (speed) -> void, each impact over 0.4 m/s
  };
  const m = opts.mass ?? 1, im = 1/m;
  const Ib = opts.inertia ?? new THREE.Vector3(0.01, 0.01, 0.01);
  const Ibi = new THREE.Vector3(1/Ib.x, 1/Ib.y, 1/Ib.z);
  const e = opts.restitution ?? 0.25, mu = opts.friction ?? 0.6;
  const roll = opts.rolling ?? 0.5;   // rolling resistance (1/s while in contact)
  const rr = opts.rr ?? 0;            // a ball's rolling-resistance coefficient (grit)
  const pts = opts.points || null, rad = opts.sphere || 0;
  const R = new THREE.Matrix3(), Rt = new THREE.Matrix3(), m4 = new THREE.Matrix4();
  const anchor = { x: new THREE.Vector3(1e9, 0, 0), q: new THREE.Quaternion() };
  const r = new THREE.Vector3(), p = new THREE.Vector3(), n = new THREE.Vector3(), vp = new THREE.Vector3(), t = new THREE.Vector3(), tmp = new THREE.Vector3(), tmp2 = new THREE.Vector3();

  // world inverse inertia applied to a vector: R Ibi R^T a
  const Iinv = (a, out) => { out.copy(a).applyMatrix3(Rt); out.set(out.x*Ibi.x, out.y*Ibi.y, out.z*Ibi.z); return out.applyMatrix3(R); };
  const floor_n = (x, z, out) => {
    const h = 0.03, f = opts.floor;
    return out.set(f(x - h, z) - f(x + h, z), 2*h, f(x, z - h) - f(x, z + h)).normalize();
  };
  // one contact at world point p with normal n and depth d: position fix + impulse
  function contact(pw, nn, depth, strength) {
    r.subVectors(pw, b.x);
    vp.crossVectors(b.w, r).add(b.v);
    const vn = vp.dot(nn);
    b.x.addScaledVector(nn, depth*0.6*strength);
    if (vn >= 0) return 0;
    // normal impulse
    tmp.crossVectors(r, nn); Iinv(tmp, tmp2); tmp.crossVectors(tmp2, r);
    const kn = im + nn.dot(tmp);
    const ee = -vn > 0.5 ? e : 0;                     // slow contacts don't bounce (no jitter at rest)
    const jn = -(1 + ee)*vn/kn*strength;
    b.v.addScaledVector(nn, jn*im);
    tmp.crossVectors(r, nn).multiplyScalar(jn); Iinv(tmp, tmp2); b.w.add(tmp2);
    // friction
    vp.crossVectors(b.w, r).add(b.v);
    t.copy(vp).addScaledVector(nn, -vp.dot(nn));
    const vt = t.length();
    if (vt > 1e-5) {
      t.multiplyScalar(1/vt);
      tmp.crossVectors(r, t); Iinv(tmp, tmp2); tmp.crossVectors(tmp2, r);
      const kt = im + t.dot(tmp);
      const jt = Math.min(vt/kt, mu*jn);
      b.v.addScaledVector(t, -jt*im);
      tmp.crossVectors(r, t).multiplyScalar(-jt); Iinv(tmp, tmp2); b.w.add(tmp2);
    }
    return -vn;
  }

  b.step = (dt) => {
    if (b.asleep) return;
    const h = dt/SUB;
    let touched = false;
    for (let s = 0; s < SUB; s++) {
      b.v.y -= G*h;
      b.x.addScaledVector(b.v, h);
      // q += 0.5 w q h
      const wq = new THREE.Quaternion(b.w.x*h*0.5, b.w.y*h*0.5, b.w.z*h*0.5, 0).multiply(b.q);
      b.q.set(b.q.x + wq.x, b.q.y + wq.y, b.q.z + wq.z, b.q.w + wq.w).normalize();
      m4.makeRotationFromQuaternion(b.q); R.setFromMatrix4(m4); Rt.copy(R).transpose();
      b.contact = false;
      let hit = 0;
      for (let it = 0; it < 2; it++) {
        if (rad) {
          const fy = opts.floor(b.x.x, b.x.z);
          floor_n(b.x.x, b.x.z, n);
          const d = fy + rad/Math.max(n.y, 0.5) - b.x.y;
          if (d > 0) { p.copy(b.x).addScaledVector(n, -rad); hit = Math.max(hit, contact(p, n, d*n.y, 1)); b.contact = true; }
        } else {
          // the deepest points carry the contact; all touching points share it
          let cnt = 0;
          for (const q of pts) { p.copy(q).applyMatrix3(R).add(b.x); if (p.y < opts.floor(p.x, p.z)) cnt++; }
          for (const q of pts) {
            p.copy(q).applyMatrix3(R).add(b.x);
            const fy = opts.floor(p.x, p.z);
            if (p.y >= fy) continue;
            floor_n(p.x, p.z, n);
            hit = Math.max(hit, contact(p, n, (fy - p.y)*n.y, 1/Math.max(1, cnt*0.5)));
            b.contact = true;
          }
        }
        // the egg: a round wall
        const eg = opts.egg;
        if (eg) {
          const list = rad ? [b.x] : pts.map(q => q.clone().applyMatrix3(R).add(b.x));
          for (const q of list) {
            const dx = q.x - eg.x, dz = q.z - eg.z, dd = Math.hypot(dx, dz), rr = eg.r + (rad || 0);
            if (dd < rr && q.y < eg.top && dd > 1e-4) {
              n.set(dx/dd, 0, dz/dd);
              p.copy(q).addScaledVector(n, -(rad || 0));
              contact(p, n, rr - dd, 1);
            }
          }
        }
      }
      if (b.contact) {
        // rolling resistance; nearly still, contact chatter is damped out hard
        const k = Math.exp(-(b.w.length() < 0.5 && b.v.length() < 0.08 ? 8 : roll)*h);
        b.w.multiplyScalar(k);
        b.v.x *= Math.exp(-0.4*h); b.v.z *= Math.exp(-0.4*h);
        // a ball on grit: a steady drag against rolling (stops it on a gentle slope)
        if (rr > 0) {
          const hv = Math.hypot(b.v.x, b.v.z), dv = rr*G*h;
          const s = hv > dv ? (hv - dv)/hv : 0;
          b.v.x *= s; b.v.z *= s; b.w.multiplyScalar(s > 0 ? Math.max(s, 0.9) : 0.5);
        }
      }
      if (hit > 0.4 && b.on_hit) b.on_hit(hit);
      touched = touched || b.contact;
    }
    b.contact = touched;
    if (b.contact) b.landed += dt;
    // asleep once it has stayed within a few millimetres and a degree or two for half a second
    // (contact chatter keeps the velocities from ever reading zero)
    if (!b.contact || b.x.distanceTo(anchor.x) > 0.004 || b.q.angleTo(anchor.q) > 0.03) { anchor.x.copy(b.x); anchor.q.copy(b.q); b.still = 0; }
    else b.still += dt;
    if (b.still > 0.5) { b.asleep = true; b.v.set(0, 0, 0); b.w.set(0, 0, 0); }
  };
  b.wake = () => { b.asleep = false; b.still = 0; };
  return b;
}

// the diagonal inertia of a solid box w x h x d of mass m (a stand-in for any object)
export const box_inertia = (m, w, h, d) => new THREE.Vector3(m*(h*h + d*d)/12, m*(w*w + d*d)/12, m*(w*w + h*h)/12);

// contact points from a geometry: its vertices, thinned to about n by keeping the extremes
// (a mesh's hull carries the contact; interior points never touch first)
export function contact_points(geo, n = 48, seed = 1) {
  const P = geo.attributes.position, out = [];
  const dirs = [];
  // fibonacci directions: for each, the vertex furthest along it
  for (let i = 0; i < n; i++) {
    const y = 1 - 2*(i + 0.5)/n, rr = Math.sqrt(1 - y*y), a = i*2.39996323 + seed;
    dirs.push(new THREE.Vector3(Math.cos(a)*rr, y, Math.sin(a)*rr));
  }
  const v = new THREE.Vector3();
  for (const d of dirs) {
    let best = -Infinity, bi = 0;
    for (let i = 0; i < P.count; i++) { v.fromBufferAttribute(P, i); const s = v.dot(d); if (s > best) { best = s; bi = i; } }
    const q = new THREE.Vector3().fromBufferAttribute(P, bi);
    if (!out.some(o => o.distanceToSquared(q) < 1e-6)) out.push(q);
  }
  return out;
}
