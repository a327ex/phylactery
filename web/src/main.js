// main.js -- round 5: the lich under the player's hand in the ending's cave. WASD / arrows move
// him relative to the camera; holding the left mouse button sends him toward the point under
// the cursor (a click sends him there and he stops). He floats (mover.js), and every part of
// him floats on its own spring around the 07 pose (lich.js): the legs swing as one pair, the
// torso and head lag and settle, the arms swing, the jaw clacks shut when he stops.
//
// Keys: 1-4 camera (1 = the room camera, the game's; 2-4 follow him to judge the motion),
// F fire colour, J floatiness, R prism pattern, G out-of-the-light level, P prism strength, B darkness,
// H hides the text. In 4 (FREE) right-drag orbits.
// Fixed 60 Hz step, rendering every animation frame. window.GAME is the harness API
// (tools/shoot.mjs): ready, setManual, step(n, input), state(), cam(i), juice(i).
import * as THREE from 'three';
import { DT, clamp, make_rng } from 'game/util.js';
import { create_render } from 'game/render.js';
import { build_cave, LAYOUT } from 'game/cave.js';
import { create_lich } from 'game/lich.js';
import { create_snakes } from 'game/snakes.js';
import { create_fire } from 'game/fire.js';
import { build_nav } from 'game/nav.js';
import { create_mover, MOVE } from 'game/mover.js';
import { draw_text } from 'game/hud_font.js';

const R = create_render(document.body);
R.canvas.style.cursor = 'default';
const cave = build_cave(R);
const lich = create_lich(R, { GU: cave.GU });
const EGG = cave.egg.position;

const G = { t: 0, tick: 0, cam: 0, manual: false, hud: true, dark: 1,
  static: { eye: [-3.6, 9.8, -10.4], tgt: [0.4, 0.1, 2.4] },   // owner, round 2: lower, tilted up; the far wall just shows
  free: { yaw: 200, pitch: 18, dist: 4.5 } };
window.G = G;
G.R = R; G.bake_ms = Math.round(cave.bake_ms); G.tris = cave.tris; G.cave = cave; G.gi_cached = cave.gi_cached; G.lich = lich;

// ------------------------------------------------------------------ where he can go
// Rock over 0.6 m blocks him, lower rock lifts him; the egg blocks him; so does anything the
// room camera can't see (his whole body, toes to skull, stays in its frame).
const room_cam = new THREE.PerspectiveCamera(50, R.W/R.H, 0.1, 200);
room_cam.position.set(...G.static.eye); room_cam.lookAt(...G.static.tgt);
room_cam.updateMatrixWorld(); room_cam.updateProjectionMatrix();
const nav = build_nav({ geo: cave.rock_geo, ground_y: cave.ground_y });
{
  const q = new THREE.Vector3();
  const in_frame = (x, y, z) => { q.set(x, y, z).project(room_cam); return q.z < 1 && Math.abs(q.x) < 0.92 && q.y > -0.9 && q.y < 0.86; };
  nav.block((x, z) => {
    if ((x - EGG.x)**2 + (z - EGG.z)**2 < 0.45*0.45 || x*x + z*z > 14*14) return true;
    const g = cave.ground_y(x, z);
    return !in_frame(x, g + 0.15, z) || !in_frame(x, g + 2.1, z);
  });
  nav.finish();
}
G.nav = nav;

const START = new THREE.Vector3(LAYOUT.hover.x, 0, LAYOUT.hover.z);
const mover = create_mover(nav, lich, START, Math.atan2(EGG.x - START.x, EGG.z - START.z));
const L = mover.p;                               // the lich's pelvis, world
const fire = create_fire(R, cave);
const snakes = create_snakes(R, cave, () => L, fire);
G.mover = mover; G.snakes = snakes; G.fire = fire;

// ------------------------------------------------------------------ the lich's attacks
// FIRE (round 9; round 10, owner: "once a second is too fast, let's make him only do this to
// nearby snakes. Make him turn his head, then the snake burns"): when it is ready and a snake
// is within FIRE_RANGE of him, he picks one and the spot on it that will catch, turns his head
// to that spot (following it as it crawls), and only when his head is on it does it catch; he
// keeps looking while it catches, then lets go. Ready again FIRE_EVERY seconds after a catch.
const FIRE_EVERY = 2.5, FIRE_RANGE = 5.5;
const AIM_MIN = 0.35, AIM_MAX = 0.9, SETTLE = 0.12, HOLD = 0.7, RELEASE = 0.35;
const ATK = { on: true, state: 'idle', t: 0, next: 1.0, target: null, at: 0, w: 0, on_t: 0, rng: make_rng(29) };
const snake_dist = s => { let d = Infinity; for (let i = 0; i < s.spine.length; i += 6) d = Math.min(d, Math.hypot(s.spine[i].x - L.x, s.spine[i].z - L.z)); return d; };
// where he looks: yaw from his facing and pitch down, toward a point on the ground
const gaze_to = (c) => {
  const a = Math.atan2(c.x - L.x, c.z - L.z) - mover.yaw;
  return [Math.atan2(Math.sin(a), Math.cos(a)), Math.atan2(L.y + 0.75 - c.y, Math.max(0.3, Math.hypot(c.x - L.x, c.z - L.z)))];
};
function attack_tick() {
  const m = mover.motion;
  ATK.next -= DT;
  ATK.t += DT;
  if (ATK.state === 'idle') {
    ATK.w = Math.max(0, ATK.w - DT/RELEASE);
    if (ATK.on && ATK.next <= 0) {
      let near = snakes.live().filter(q => snake_dist(q) < FIRE_RANGE);
      // one he can look at if there is one (his head and chest turn ~83 deg either way)
      const front = near.filter(q => Math.abs(gaze_to(q.spine[Math.floor(q.spine.length*0.4)])[0]) < 1.45);
      if (front.length) near = front;
      if (near.length) {
        ATK.target = near[ATK.rng.int(0, near.length - 1)];
        ATK.at = Math.round(ATK.target.spine.length*ATK.rng.float(0.15, 0.75));
        ATK.state = 'aim'; ATK.t = 0; ATK.on_t = 0;
      } else ATK.next = 0.1;
    }
  } else if (ATK.state === 'aim') {
    ATK.w = Math.min(1, ATK.t/0.12);
    const s = ATK.target;
    if (!snakes.live().includes(s) || snake_dist(s) > FIRE_RANGE + 1) { ATK.state = 'idle'; ATK.next = 0.2; }
    else {
      // his head is on it: head + chest turn (the pose's springs) within a little of where he looks
      const [gy] = gaze_to(s.spine[ATK.at]);
      const S = lich.springs, reach = Math.max(-1.45, Math.min(1.45, gy));
      const err = Math.abs(reach - (S.hy.x + S.cy.x));
      ATK.on_t = err < 0.1 ? ATK.on_t + DT : 0;        // a beat with his head on it, then it catches
      if ((ATK.t >= AIM_MIN && ATK.on_t >= SETTLE) || ATK.t >= AIM_MAX) {
        snakes.ignite(s, ATK.at);
        ATK.state = 'hold'; ATK.t = 0; ATK.next = FIRE_EVERY;
      }
    }
  } else if (ATK.state === 'hold') {
    ATK.w = 1;
    if (ATK.t >= HOLD) { ATK.state = 'idle'; ATK.t = 0; }
  }
  m.gaze_w = ATK.w;
  if (ATK.target && ATK.w > 0) [m.gaze, m.gaze_p] = gaze_to(ATK.target.spine[ATK.at]);
}

// ------------------------------------------------------------------ cameras
const v = (x, y, z) => new THREE.Vector3(x, y, z);
const F = L.clone();                             // what the follow cameras track (eased)
// the follow cameras look the way the room camera does (so WASD means the same), lower
const ROOM_H = new THREE.Vector2(G.static.tgt[0] - G.static.eye[0], G.static.tgt[2] - G.static.eye[2]).normalize();
const from_room = (pitch_deg, dist) => { const p = pitch_deg*Math.PI/180; return v(-ROOM_H.x*Math.cos(p)*dist, Math.sin(p)*dist, -ROOM_H.y*Math.cos(p)*dist); };
const SIDE_DIR = v(-ROOM_H.y, 0, ROOM_H.x);      // the room camera's right, flattened
const CAMS = [
  // this room's camera (owner, round 1: Resident Evil-like static cameras). It never moves.
  { name: 'ROOM', note: 'THE ROOM CAMERA, FIXED: THE GAME', fov: 50,
    rig: () => [v(...G.static.eye), v(...G.static.tgt)] },
  { name: 'CLOSE', note: 'FOLLOWS HIM, FROM THE ROOM CAMERA\'S SIDE, LOWER', fov: 45,
    rig: () => [F.clone().add(from_room(18, 4.6)), F.clone().add(v(0, -0.15, 0))] },
  { name: 'SIDE', note: 'FOLLOWS HIM FROM THE SIDE: A/D TO SEE HIS PROFILE', fov: 45,
    rig: () => [F.clone().addScaledVector(SIDE_DIR, 4.4).add(v(0, 0.25, 0)), F.clone().add(v(0, -0.2, 0))] },
  { name: 'FREE', note: 'RIGHT-DRAG TO ORBIT, SCROLL TO ZOOM', fov: 45,
    rig: () => {
      const fr = G.free, y = fr.yaw*Math.PI/180, p = fr.pitch*Math.PI/180;
      return [F.clone().add(v(Math.sin(y)*Math.cos(p)*fr.dist, Math.sin(p)*fr.dist, Math.cos(y)*Math.cos(p)*fr.dist)), F.clone()];
    } },
];
const CAM_FREE = CAMS.length - 1;
// a follow camera stops short of rock between it and him (the room camera is never moved)
function clear_eye(eye, from) {
  const d = eye.clone().sub(from), n = Math.ceil(d.length()/0.1);
  for (let i = 4; i <= n; i++) {
    const p = from.clone().addScaledVector(d, i/n);
    if (nav.rock_at(p.x, p.z) > p.y - 0.3) return from.clone().addScaledVector(d, Math.max(0.2, (i - 3)/n));
  }
  return eye;
}
function place_camera(dt) {
  const c = CAMS[G.cam];
  const k = 1 - Math.exp(-3.5*dt);
  F.lerp(L, k);
  let [eye, tgt] = c.rig();
  if (G.cam !== 0) eye = clear_eye(eye, F);
  cave.set_dome_visible(c.dome !== false);
  const C = R.world_camera;
  C.fov = c.fov; C.updateProjectionMatrix();
  C.position.copy(eye);
  C.up.set(0, 1, 0);
  C.lookAt(tgt);
  C.updateMatrixWorld();
}
function set_cam(i) { G.cam = clamp(i | 0, 0, CAMS.length - 1); F.copy(L); }

// ------------------------------------------------------------------ input
// keys held, the mouse's goal. The harness can hold keys too (GAME.step(n, {keys: 'wd'})).
const held = new Set();
const KEYMAP = { KeyW: 'w', ArrowUp: 'w', KeyS: 's', ArrowDown: 's', KeyA: 'a', ArrowLeft: 'a', KeyD: 'd', ArrowRight: 'd' };
const mouse = { down: false, px: 0, py: 0 };
let goal = null, best = Infinity, stall = 0, script_keys = null;
const ray = new THREE.Raycaster(), ndc = new THREE.Vector2();

// the floor point under a game pixel, marching the view ray over the height field
function floor_at_px(gx, gy) {
  ndc.set(gx/R.W*2 - 1, 1 - gy/R.H*2);
  ray.setFromCamera(ndc, R.world_camera);
  const o = ray.ray.origin, d = ray.ray.direction;
  let t0 = 0, t1 = 0;
  for (let t = 0.3; t < 60; t += 0.08) {
    const x = o.x + d.x*t, y = o.y + d.y*t, z = o.z + d.z*t;
    if (y < cave.ground_y(x, z)) { t1 = t; break; }
    t0 = t;
  }
  if (!t1) return null;
  for (let i = 0; i < 8; i++) {
    const t = (t0 + t1)/2, x = o.x + d.x*t, y = o.y + d.y*t, z = o.z + d.z*t;
    if (y < cave.ground_y(x, z)) t1 = t; else t0 = t;
  }
  const t = (t0 + t1)/2;
  return v(o.x + d.x*t, o.y + d.y*t, o.z + d.z*t);
}

// a goal inside rock moves back toward him until it is open floor
function set_goal(p) {
  if (!p) return;
  const dx = L.x - p.x, dz = L.z - p.z, d = Math.hypot(dx, dz);
  for (let s = 0; s < d && nav.is_blocked(p.x, p.z); s += 0.1) { p.x += dx/d*0.1; p.z += dz/d*0.1; }
  p.y = cave.ground_y(p.x, p.z);
  best = Infinity; stall = 0;
  goal = p;
}
const pick_goal = () => { const [gx, gy] = R.to_game_px(mouse.px, mouse.py); set_goal(floor_at_px(gx, gy)); };

// camera-relative: W is up the screen, D is right
const cf = new THREE.Vector3();
function wanted_velocity() {
  const keys = script_keys ?? [...held].join('');
  let ix = 0, iz = 0;
  if (keys.includes('w')) iz += 1;
  if (keys.includes('s')) iz -= 1;
  if (keys.includes('d')) ix += 1;
  if (keys.includes('a')) ix -= 1;
  if (ix || iz) {
    goal = null;
    R.world_camera.getWorldDirection(cf); cf.y = 0; cf.normalize();
    const rx = -cf.z, rz = cf.x;                  // the camera's right on the floor
    let wx = cf.x*iz + rx*ix, wz = cf.z*iz + rz*ix;
    const l = Math.hypot(wx, wz);
    return { x: wx/l*MOVE.speed, z: wz/l*MOVE.speed };
  }
  if (mouse.down) pick_goal();
  if (goal) {
    const dx = goal.x - L.x, dz = goal.z - L.z, d = Math.hypot(dx, dz);
    // stop when there, or when he stops getting closer (rock holds him short of it)
    if (mouse.down || d < best - 0.05) { best = d; stall = 0; } else stall += DT;
    if ((d < 0.12 || stall > 0.5) && !mouse.down) { goal = null; return { x: 0, z: 0 }; }
    if (d < 0.12) return { x: 0, z: 0 };
    const s = Math.min(MOVE.speed, Math.sqrt(2*MOVE.dec*Math.max(0, d - 0.08))*0.9);
    return { x: dx/d*s, z: dz/d*s };
  }
  return { x: 0, z: 0 };
}

addEventListener('keydown', (e) => {
  if (KEYMAP[e.code]) { held.add(KEYMAP[e.code]); e.preventDefault(); }
  const d = /^(Digit|Numpad)([1-4])$/.exec(e.code);
  if (d) set_cam(+d[2] - 1);
  if (e.code === 'KeyH') G.hud = !G.hud;
  if (e.code === 'KeyP') lich.mode = lich.mode + 1;
  if (e.code === 'KeyJ') lich.juice = lich.juice + 1;
  if (e.code === 'KeyG') lich.glow = lich.glow + 1;
  if (e.code === 'KeyR') lich.pattern = lich.pattern + 1;
  if (e.code === 'KeyF') fire.look = fire.look + 1;
  if (e.code === 'KeyB') { G.dark = (G.dark + 1) % cave.DARK.length; cave.set_darkness(G.dark); }
});
addEventListener('keyup', (e) => { if (KEYMAP[e.code]) held.delete(KEYMAP[e.code]); });
addEventListener('blur', () => { held.clear(); mouse.down = false; });
let drag = null;
R.canvas.addEventListener('contextmenu', (e) => e.preventDefault());
R.canvas.addEventListener('pointerdown', (e) => {
  try { R.canvas.setPointerCapture(e.pointerId); } catch { }
  if (e.button === 0) { mouse.down = true; mouse.px = e.clientX; mouse.py = e.clientY; pick_goal(); }   // picked now: a quick click never falls between ticks
  if (e.button === 2 && G.cam === CAM_FREE) drag = [e.clientX, e.clientY];
});
R.canvas.addEventListener('pointerup', (e) => { if (e.button === 0) mouse.down = false; if (e.button === 2) drag = null; });
R.canvas.addEventListener('pointermove', (e) => {
  mouse.px = e.clientX; mouse.py = e.clientY;
  if (!drag || G.cam !== CAM_FREE) return;
  G.free.yaw -= (e.clientX - drag[0])*0.3;
  G.free.pitch = clamp(G.free.pitch + (e.clientY - drag[1])*0.25, -10, 88);
  drag = [e.clientX, e.clientY];
});
R.canvas.addEventListener('wheel', (e) => { if (G.cam === CAM_FREE) G.free.dist = clamp(G.free.dist*Math.exp(e.deltaY*0.001), 1.5, 30); }, { passive: true });

// ------------------------------------------------------------------ hud
const hud = R.hud_canvas.getContext('2d');
const gp = new THREE.Vector3();
function draw_hud() {
  hud.clearRect(0, 0, R.W, R.H);
  // where the mouse sent him: a small pale cross on the floor
  if (goal) {
    gp.copy(goal).project(R.world_camera);
    if (gp.z < 1) {
      const x = Math.round((gp.x*0.5 + 0.5)*R.W), y = Math.round((0.5 - gp.y*0.5)*R.H);
      hud.fillStyle = 'rgba(242,227,194,0.7)';
      for (const [dx, dy] of [[0, 0], [-2, 0], [2, 0], [0, -1], [0, 1]]) hud.fillRect(x + dx, y + dy, 1, 1);
    }
  }
  if (!G.hud) return;
  const c = CAMS[G.cam];
  const ink = 'rgba(8,6,5,0.85)';
  draw_text(hud, `${G.cam + 1} ${c.name}`, 8, 8, '#f2e3c2', 1, 'left', null, ink);
  draw_text(hud, c.note, 8, 19, '#a8987c', 1, 'left', null, ink);
  draw_text(hud, `F FIRE: ${fire.LOOKS[fire.look].name}`, 8, R.H - 70, '#f2e3c2', 1, 'left', null, ink);
  draw_text(hud, `J FLOATINESS: ${lich.JUICE[lich.juice].name}`, 8, R.H - 59, '#a8987c', 1, 'left', null, ink);
  draw_text(hud, `R PRISM PATTERN: ${lich.PATTERNS[lich.pattern]}`, 8, R.H - 48, '#a8987c', 1, 'left', null, ink);
  draw_text(hud, `G OUT OF THE LIGHT: ${lich.GLOWS[lich.glow].name}`, 8, R.H - 37, '#a8987c', 1, 'left', null, ink);
  draw_text(hud, `P PRISM STRENGTH: ${lich.MODES[lich.mode]}`, 8, R.H - 26, '#a8987c', 1, 'left', null, ink);
  draw_text(hud, `B DARKNESS: ${cave.DARK[G.dark].name}`, 8, R.H - 15, '#a8987c', 1, 'left', null, ink);
  draw_text(hud, 'WASD OR HOLD LEFT MOUSE: MOVE', R.W - 8, R.H - 26, '#8a7c66', 1, 'right', null, ink);
  draw_text(hud, '1-4 CAMERA   F J R G P B   H HIDE TEXT', R.W - 8, R.H - 15, '#8a7c66', 1, 'right', null, ink);
}

// ------------------------------------------------------------------ sim + render
function tick() {
  G.tick++;
  G.t += DT;
  mover.tick(G.t, DT, wanted_velocity());
  attack_tick();
  lich.pose(G.t, DT, mover.motion);
  lich.update(G.t);
  cave.update(G.t, DT);
  snakes.set_ember(fire.ember_colour());
  snakes.update(G.t, DT);
  fire.update(G.t, DT);
}
function render(dt) {
  place_camera(0);
  fire.set_camera(R.world_camera, R.H);
  draw_hud();
  R.render(dt);
}

let last = performance.now(), acc = 0;
function frame(now) {
  requestAnimationFrame(frame);
  let dt = (now - last)/1000; last = now;
  if (G.manual) return;
  if (!(dt >= 0)) dt = 0;
  if (dt > 0.25) dt = 0.25;
  acc += dt;
  let n = 0;
  while (acc >= DT && n < 8) { tick(); place_camera(DT); acc -= DT; n++; }
  if (n >= 8) acc = 0;
  render(dt);
}

// ------------------------------------------------------------------ harness API
const r3 = x => +x.toFixed(3);
window.GAME = {
  ready: false,
  setManual(on) { G.manual = !!on; return G.manual; },
  // input: { keys: 'wd' } holds those keys for the n ticks; { goto: [x, z] } sends him there
  step(n = 1, input = {}) {
    if (input.goto) set_goal(v(input.goto[0], 0, input.goto[1]));
    script_keys = input.keys ?? null;
    for (let i = 0; i < (n | 0); i++) { tick(); place_camera(DT); }
    script_keys = null;
    render(n*DT);
    return G.tick;
  },
  cam(i, free) { set_cam(i); if (free) Object.assign(G.free, free); render(0); return CAMS[G.cam].name; },
  hud(on) { G.hud = !!on; render(0); return G.hud; },
  // inspection: camera 4 looks at a fixed point from a direction (degrees) and distance
  view_at(x, y, z, yaw, pitch, dist, fov = 45) {
    const p = v(x, y, z), a = yaw*Math.PI/180, b = pitch*Math.PI/180;
    CAMS[CAM_FREE].rig = () => [p.clone().add(v(Math.sin(a)*Math.cos(b)*dist, Math.sin(b)*dist, Math.cos(a)*Math.cos(b)*dist)), p.clone()];
    CAMS[CAM_FREE].fov = fov; G.cam = CAM_FREE; render(0); return [x, y, z];
  },
  place(x, z, yaw) { mover.place(x, z, yaw); F.copy(L); render(0); return [x, z]; },
  juice(i) { lich.juice = i; return lich.JUICE[lich.juice].name; },
  // the light arriving on his bones (per unit albedo), read back from the linear world target:
  // [direct, bounce] medians and 90th percentiles over his visible pixels
  gem_probe() {
    const U = lich.mat.userData.gemU;
    U.uGemDebug.value = 1; render(0);
    const rt = R.targets.rt_world, buf = new Uint16Array(R.W*R.H*4);
    R.renderer.readRenderTargetPixels(rt, 0, 0, R.W, R.H, buf);
    U.uGemDebug.value = 0; render(0);
    // and what the screen shows there (the final 8-bit image): mean brightness and colourfulness
    const fin = new Uint8Array(R.W*R.H*4);
    R.renderer.readRenderTargetPixels(R.targets.rt_final, 0, 0, R.W, R.H, fin);
    const f16 = h => { const s = h & 0x8000 ? -1 : 1, e = (h >> 10) & 31, m = h & 1023; return e === 0 ? s*m*Math.pow(2, -24) : e === 31 ? NaN : s*(1 + m/1024)*Math.pow(2, e - 15); };
    const d = [], b = [];
    for (let i = 0; i < R.W*R.H; i++) if (f16(buf[i*4 + 2]) > 700) { d.push(f16(buf[i*4])); b.push(f16(buf[i*4 + 1])); }
    const q = (a, t) => { a.sort((x, y) => x - y); return +(a[Math.floor((a.length - 1)*t)] || 0).toFixed(4); };
    let lum = 0, sat = 0, n = 0, hx = 0, hy = 0, x0 = R.W, x1 = 0, y0 = R.H, y1 = 0;
    for (let i = 0; i < R.W*R.H; i++) if (f16(buf[i*4 + 2]) > 700) {
      const r = fin[i*4]/255, g = fin[i*4 + 1]/255, bb = fin[i*4 + 2]/255, mx = Math.max(r, g, bb), mn = Math.min(r, g, bb);
      const sv = mx > 0.02 ? (mx - mn)/mx : 0;
      const px_ = i % R.W, py_ = Math.floor(i/R.W);
      x0 = Math.min(x0, px_); x1 = Math.max(x1, px_); y0 = Math.min(y0, py_); y1 = Math.max(y1, py_);
      lum += 0.2126*r + 0.7152*g + 0.0722*bb; sat += sv; n++;
      // hue as an angle, weighted by saturation: a rainbow spreads, one tint doesn't
      if (mx - mn > 1e-3) {
        let h = mx === r ? (g - bb)/(mx - mn) : mx === g ? 2 + (bb - r)/(mx - mn) : 4 + (r - g)/(mx - mn);
        h *= Math.PI/3; hx += sv*Math.cos(h); hy += sv*Math.sin(h);
      }
    }
    // what surrounds him on screen: the rest of his box, grown by a quarter of his height
    const gpad = Math.round((y1 - y0)*0.25);
    let al = 0, an = 0;
    for (let y = Math.max(0, y0 - gpad); y <= Math.min(R.H - 1, y1 + gpad); y++) for (let x = Math.max(0, x0 - gpad); x <= Math.min(R.W - 1, x1 + gpad); x++) {
      const i = y*R.W + x;
      if (f16(buf[i*4 + 2]) > 700) continue;
      al += (0.2126*fin[i*4] + 0.7152*fin[i*4 + 1] + 0.0722*fin[i*4 + 2])/255; an++;
    }
    return { around_lum: +(al/Math.max(an, 1)).toFixed(3), px: d.length, direct: [q(d, 0.5), q(d, 0.9)], bounce: [q(b, 0.5), q(b, 0.9)], screen_lum: +(lum/n).toFixed(3), screen_sat: +(sat/n).toFixed(3), hue_spread: +(1 - Math.hypot(hx, hy)/Math.max(sat, 1e-6)).toFixed(3) };
  },
  glow(i) { lich.glow = i; render(0); return lich.GLOWS[lich.glow].name; },
  pattern(i) { lich.pattern = i; render(0); return lich.PATTERNS[lich.pattern]; },
  fire_look(i) { fire.look = i; return fire.LOOKS[fire.look].name; },
  attacks(on) { ATK.on = !!on; return ATK.on; },
  attack_state() { return { state: ATK.state, t: +ATK.t.toFixed(2), next: +ATK.next.toFixed(2), w: +ATK.w.toFixed(2), target: ATK.target ? snakes.S.indexOf(ATK.target) : -1, head: +(lich.springs.hy.x + lich.springs.cy.x).toFixed(3), gaze: +(mover.motion.gaze || 0).toFixed(3) }; },
  // set the snake nearest (x, z) alight now; returns its index
  ignite_near(x, z) {
    const live = snakes.live(); if (!live.length) return -1;
    live.sort((a, b) => Math.hypot(a.x - x, a.z - z) - Math.hypot(b.x - x, b.z - z));
    ATK.target = live[0]; ATK.at = 30; snakes.ignite(live[0], 30); ATK.state = 'hold'; ATK.t = 0;
    return snakes.S.indexOf(live[0]);
  },
  snake_at(i) { const s = snakes.S[i]; const c = s.spine[20]; return { x: +c.x.toFixed(2), z: +c.z.toFixed(2), burning: !!s.burn, sink: +s.sink.toFixed(2), burnt: s.burnt, fire: fire.burning }; },
  mode(m) { lich.mode = m; render(0); return lich.MODES[lich.mode]; },
  dark(i) { G.dark = i; const n = cave.set_darkness(i); render(0); return n; },
  snakes() { return snakes.S.map(s => [+s.x.toFixed(2), +s.z.toFixed(2), s.dying, +s.delay.toFixed(2)]); },
  springs() {
    const S = lich.springs;
    return { body: [r3(S.bp.x), r3(S.br.x)], chest: [r3(S.cp.x), r3(S.cr.x)], head: [r3(S.hp.x), r3(S.hr.x), r3(S.hy.x)], jaw: r3(S.jw.x),
      legs: S.legs.map(l => [r3(l.p.x), r3(l.r.x), r3(l.k.x)]), arms: S.arms.map(a => [r3(a.p.x), r3(a.r.x), r3(a.e.x)]) };
  },
  state() {
    return { t: r3(G.t), tick: G.tick, cam: CAMS[G.cam].name, juice: lich.JUICE[lich.juice].name, lich: L.toArray().map(r3),
      speed: r3(mover.speed), yaw: r3(mover.yaw), goal: goal ? [r3(goal.x), r3(goal.z)] : null, motion: { a: mover.motion.a.map(r3), v: mover.motion.v.map(r3) } };
  },
  nav_map() {
    // the walkable map as rows of characters ('#' blocked, '.' open), every 2nd cell
    const out = [];
    for (let j = nav.nz - 1; j >= 0; j -= 2) { let s = ''; for (let i = 0; i < nav.nx; i += 2) s += nav.blocked[j*nav.nx + i] ? '#' : '.'; out.push(s); }
    return out;
  },
};
cave.set_darkness(G.dark);
tick();
render(0);
window.GAME.ready = true;
requestAnimationFrame(frame);
