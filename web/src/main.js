// main.js -- round 5: the lich under the player's hand in the ending's cave. WASD / arrows move
// him relative to the camera; holding the left mouse button sends him toward the point under
// the cursor (a click sends him there and he stops). He floats (mover.js), and every part of
// him floats on its own spring around the 07 pose (lich.js): the legs swing as one pair, the
// torso and head lag and settle, the arms swing, the jaw clacks shut when he stops.
//
// Keys: 1-4 camera (1 = the room camera, the game's; 2-4 follow him to judge the motion),
// 5-0 the six powers on/off (round 28: a removed power's object drops around the egg), I the
// inspect view (inspect.js), C the gem's cut, V what the inspect view has behind the object, O what he does when a target goes behind him, K beam colour, X beam recoil, L lens beam, F fire colour, J floatiness, R prism pattern, G out-of-the-light level, P prism strength, B darkness,
// H hides the text. In 4 (FREE) right-drag orbits.
// Round 36 (the ending): T removes every power, one after another; snakes that reach the egg coil
// round it (snakes.js, coil.js) and he is hurt (lich.js HURT); U how they coil, N his hand.
// Fixed 60 Hz step, rendering every animation frame. window.GAME is the harness API
// (tools/shoot.mjs): ready, setManual, step(n, input), state(), cam(i), juice(i).
import * as THREE from 'three';
import { DT, clamp, make_rng } from 'game/util.js';
import { create_render } from 'game/render.js';
import { build_cave, LAYOUT } from 'game/cave.js';
import { create_lich } from 'game/lich.js';
import { create_snakes } from 'game/snakes.js';
import { create_fire } from 'game/fire.js';
import { create_fx } from 'game/fx.js';
import { create_powers, FACINGS } from 'game/powers.js';
import { create_gore } from 'game/gore.js';
import { create_warp } from 'game/warp.js';
import { BEAM_LOOKS } from 'game/beam.js';
import { LENS_LOOKS } from 'game/lens.js';
import { build_nav } from 'game/nav.js';
import { create_mover, MOVE } from 'game/mover.js';
import { draw_text } from 'game/hud_font.js';
import { create_items, ITEMS, HAND_MATS, SIZES } from 'game/items.js';
import { create_inspect } from 'game/inspect.js';
import { COIL_MODES } from 'game/coil.js';

const R = create_render(document.body);
R.canvas.style.cursor = 'default';
const cave = build_cave(R);
const lich = create_lich(R, { GU: cave.GU });
const EGG = cave.egg.position;

const G = { t: 0, tick: 0, cam: 0, manual: false, hud: true, dark: 1,
  static: { eye: [-3.6, 9.8, -10.4], tgt: [0.4, 0.1, 2.4] },   // owner, round 2: lower, tilted up; the far wall just shows
  free: { yaw: 200, pitch: 18, dist: 4.5 }, egg_view: { yaw: 195, pitch: 32, dist: 3.4 } };
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

// ------------------------------------------------------------------ the lich's powers
// Round 11 (owner): fire, lift and burst, wind, leakage, prismatic beam, lens, all from the
// start; whatever is left always stops the snakes just short of the egg (powers.js). Keys 5-0
// switch each off and on (testing the removal the ending is about).
const fx = create_fx(R, cave);
const gore = create_gore(R, cave, snakes, fx, make_rng(41));        // round 20: what a burst snake becomes
const warp = create_warp(R);                                          // round 23: air that bends the light
const powers = create_powers({ R, cave, snakes, fx, gore, warp, fire, lich, mover, egg: EGG, get_L: () => L, rng: make_rng(29) });
G.powers = powers; G.fx = fx; G.gore = gore; G.warp = warp;
gore.follow(() => L);
const POWER_KEYS = ['5', '6', '7', '8', '9', '0'];

// ------------------------------------------------------------------ the powers' objects (round 28)
// What the gem sees on the floor: the cave from its place by the egg, captured once (only the
// cave: the lich and the snakes are hidden for it), at the level the game shows it.
let env_world = null;
{
  cave.set_darkness(G.dark);
  const rt = new THREE.WebGLCubeRenderTarget(256, { type: THREE.HalfFloatType, generateMipmaps: true, minFilter: THREE.LinearMipmapLinearFilter });
  const cc = new THREE.CubeCamera(0.05, 60, rt);
  const hidden = R.world_scene.children.filter(o => o !== cave.group && o.visible);
  for (const o of hidden) o.visible = false;
  cave.set_dome_visible(true);
  const gy = cave.ground_y(-0.53, -1.13);
  cc.position.set(-0.53, gy + 0.15, -1.13);
  cc.update(R.renderer, R.world_scene);
  for (const o of hidden) o.visible = true;
  env_world = rt.texture;
}
const items = create_items({ R, cave, fx, warp, env_world, nav, lich, mover, get_L: () => L, glance: (p) => powers.glance(p) });
const inspect = create_inspect({ R, items, ITEMS });
G.items = items; G.inspect = inspect;
function toggle_power(i) {
  const on = powers.toggle(i);
  if (on === false) items.drop(i); else if (on === true) items.take(i);
  return on;
}

// ------------------------------------------------------------------ the ending (round 36)
// Every power gone, the snakes reach the egg and coil round it; once the first grips it he is
// hurt: he points at the egg with his casting hand while the rest of him arches back (lich.js
// HURT), jolted as each one grips, shaking and sinking as the egg is covered. When it is covered
// (snakes.WIN of the shell) the game is won. He still floats where he is sent, slower, facing it.
const END = { w: 0, level: 0, grips: 0, spasm: 2, won: false, over: -1, queue: [], queue_t: 0, hand: 0 };
G.END = END;
snakes.on_grip = () => { END.grips++; lich.hit(0.5 + 0.1*Math.min(END.grips, 6) + (END.grips === 1 ? 0.5 : 0)); };
snakes.on_won = () => { END.won = true; END.over = 0; held.clear(); mouse.down = false; goal = null; lich.hit(1.7); };
// Round 37 (owner: "After the win, the game should end. The screen turns black and a message is
// written in the center, most likely, message to be defined still. The camera can remain as it
// is"): from the win nothing answers the player; the last jolt plays out for OVER.hold s, the
// screen fades to black over OVER.fade s, the game stops, and the message fades in. (On the site
// this is where site_unlock_posts('lich-survivors', { ending = 'egg', powers = 0 }) goes.)
const OVER = { hold: 1.8, fade: 2.2, text_at: 0.8, text_in: 1.4 };
const MESSAGE = ['[ YOUR MESSAGE ]'];                  // his to write; one entry per line
const over_black = () => END.won && END.over >= OVER.hold + OVER.fade;
const end_rng = make_rng(77);
function remove_all() {
  END.queue = powers.ALL.map((a, i) => i).filter(i => powers.is_on(powers.ALL[i]));
  END.queue_t = 0;
}
function ending_tick(dt) {
  // T: the powers go one after another, a breath apart (each object tossed from his hand)
  if (END.queue.length) { END.queue_t -= dt; if (END.queue_t <= 0) { toggle_power(END.queue.shift()); END.queue_t = 0.4; } }
  const hurt = END.grips > 0;
  END.w = Math.min(1, END.w + (hurt ? dt/0.45 : -dt/1.5)); if (END.w < 0) END.w = 0;
  const target = END.force_level ?? (END.won ? 1 : snakes.coverage);
  END.level += (target - END.level)*(1 - Math.exp(-dt/0.8));
  cave.egg.userData.still = Math.min(1, snakes.coiled.length);
  lich.hurt.w = END.w*END.w*(3 - 2*END.w); lich.hurt.level = END.level; lich.hurt.hand = END.hand;
  mover.face.half = 1.31;
  if (END.w <= 0) return;
  // small spasms between the jolts, harder as the egg is covered
  END.spasm -= dt;
  if (END.spasm <= 0) { lich.hit(END.w*(0.18 + 0.4*END.level)); END.spasm = end_rng.float(1.1, 3.2)*(1 - 0.4*END.level); }
  // he faces the egg and points at it with his casting hand
  mover.face.on = true;
  mover.face.yaw = Math.atan2(EGG.x - L.x, EGG.z - L.z);
  mover.face.half = mover.speed > 0.2 ? 0.7 : 0.08;
  const m = mover.motion;
  m.gaze_w = 0;
  m.point = { w: lich.hurt.w, arm: 1, x: EGG.x, y: EGG.y + 0.42, z: EGG.z };
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
  // round 28: to look at what lies around the egg
  { name: 'EGG', note: 'AROUND THE EGG: RIGHT-DRAG TO ORBIT, SCROLL TO ZOOM', fov: 45,
    rig: () => {
      const fr = G.egg_view, y = fr.yaw*Math.PI/180, p = fr.pitch*Math.PI/180, c = v(EGG.x, EGG.y + 0.15, EGG.z);
      return [c.clone().add(v(Math.sin(y)*Math.cos(p)*fr.dist, Math.sin(p)*fr.dist, Math.cos(y)*Math.cos(p)*fr.dist)), c];
    } },
  { name: 'FREE', note: 'RIGHT-DRAG TO ORBIT, SCROLL TO ZOOM', fov: 45,
    rig: () => {
      const fr = G.free, y = fr.yaw*Math.PI/180, p = fr.pitch*Math.PI/180;
      return [F.clone().add(v(Math.sin(y)*Math.cos(p)*fr.dist, Math.sin(p)*fr.dist, Math.cos(y)*Math.cos(p)*fr.dist)), F.clone()];
    } },
];
const CAM_FREE = CAMS.length - 1, CAM_EGG = CAMS.length - 2;
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
  if (G.cam !== 0 && G.cam !== CAM_EGG) eye = clear_eye(eye, F);
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
  if (END.won) return { x: 0, z: 0 };                 // round 37: the game is over
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
    const l = Math.hypot(wx, wz), sp = MOVE.speed*(1 - 0.6*END.w);   // hurt: slower
    return { x: wx/l*sp, z: wz/l*sp };
  }
  if (mouse.down) pick_goal();
  if (goal) {
    const dx = goal.x - L.x, dz = goal.z - L.z, d = Math.hypot(dx, dz);
    // stop when there, or when he stops getting closer (rock holds him short of it)
    if (mouse.down || d < best - 0.05) { best = d; stall = 0; } else stall += DT;
    if ((d < 0.12 || stall > 0.5) && !mouse.down) { goal = null; return { x: 0, z: 0 }; }
    if (d < 0.12) return { x: 0, z: 0 };
    const s = Math.min(MOVE.speed*(1 - 0.6*END.w), Math.sqrt(2*MOVE.dec*Math.max(0, d - 0.08))*0.9);
    return { x: dx/d*s, z: dz/d*s };
  }
  return { x: 0, z: 0 };
}

addEventListener('keydown', (e) => {
  if (END.won) return;                                 // round 37: the game is over
  // the inspect view takes the keys while it is up
  if (inspect.S.active) {
    if (e.code === 'KeyI' || e.code === 'Escape' || e.code === 'KeyE') inspect.close();
    if (e.code === 'KeyA' || e.code === 'ArrowLeft') inspect.next(-1);
    if (e.code === 'KeyD' || e.code === 'ArrowRight') inspect.next(1);
    if (e.code === 'KeyM') { items.set_hand_mat(items.opts.hand_mat + 1); inspect.rebuild(); }
    if (e.code === 'KeyH') G.hud = !G.hud;
    return;
  }
  if (e.code === 'KeyI') { held.clear(); mouse.down = false; inspect.open(); return; }
  if (e.code === 'KeyM') items.set_hand_mat(items.opts.hand_mat + 1);
  if (e.code === 'KeyZ') items.set_size(items.opts.size + 1);
  if (KEYMAP[e.code]) { held.add(KEYMAP[e.code]); e.preventDefault(); }
  const d = /^(Digit|Numpad)([1-4])$/.exec(e.code);
  if (d) set_cam(+d[2] === 4 ? CAM_FREE : +d[2] - 1);
  if (e.code === 'KeyY') set_cam(CAM_EGG);
  if (e.code === 'KeyH') G.hud = !G.hud;
  if (e.code === 'KeyP') lich.mode = lich.mode + 1;
  if (e.code === 'KeyJ') lich.juice = lich.juice + 1;
  if (e.code === 'KeyG') lich.glow = lich.glow + 1;
  if (e.code === 'KeyR') lich.pattern = lich.pattern + 1;
  if (e.code === 'KeyF') fire.look = fire.look + 1;
  if (e.code === 'KeyK') powers.beam.look = powers.beam.look + 1;
  if (e.code === 'KeyX') lich.recoil = lich.recoil + 1;
  if (e.code === 'KeyO') powers.facing = powers.facing + 1;
  if (e.code === 'KeyL') powers.lens.look = powers.lens.look + 1;
  if (e.code === 'KeyT') remove_all();
  if (e.code === 'KeyU') snakes.coil_mode = snakes.coil_mode + 1;
  if (e.code === 'KeyN') END.hand = (END.hand + 1) % lich.HANDS.length;
  const pk = /^(Digit|Numpad)([0-9])$/.exec(e.code);
  if (pk && POWER_KEYS.includes(pk[2])) toggle_power(POWER_KEYS.indexOf(pk[2]));
  if (e.code === 'KeyB') { G.dark = (G.dark + 1) % cave.DARK.length; cave.set_darkness(G.dark); }
});
addEventListener('keyup', (e) => { if (KEYMAP[e.code]) held.delete(KEYMAP[e.code]); });
addEventListener('blur', () => { held.clear(); mouse.down = false; });
let drag = null;
R.canvas.addEventListener('contextmenu', (e) => e.preventDefault());
R.canvas.addEventListener('pointerdown', (e) => {
  try { R.canvas.setPointerCapture(e.pointerId); } catch { }
  if (inspect.S.active || END.won) return;
  if (e.button === 0) { mouse.down = true; mouse.px = e.clientX; mouse.py = e.clientY; pick_goal(); }   // picked now: a quick click never falls between ticks
  if (e.button === 2 && (G.cam === CAM_FREE || G.cam === CAM_EGG)) drag = [e.clientX, e.clientY];
});
R.canvas.addEventListener('pointerup', (e) => { if (e.button === 0) mouse.down = false; if (e.button === 2) drag = null; });
R.canvas.addEventListener('pointermove', (e) => {
  mouse.px = e.clientX; mouse.py = e.clientY;
  if (!drag || (G.cam !== CAM_FREE && G.cam !== CAM_EGG)) return;
  const fr = G.cam === CAM_EGG ? G.egg_view : G.free;
  fr.yaw -= (e.clientX - drag[0])*0.3;
  fr.pitch = clamp(fr.pitch + (e.clientY - drag[1])*0.25, -10, 88);
  drag = [e.clientX, e.clientY];
});
R.canvas.addEventListener('wheel', (e) => {
  if (G.cam === CAM_FREE) G.free.dist = clamp(G.free.dist*Math.exp(e.deltaY*0.001), 1.5, 30);
  if (G.cam === CAM_EGG) G.egg_view.dist = clamp(G.egg_view.dist*Math.exp(e.deltaY*0.001), 0.8, 12);
}, { passive: true });

// ------------------------------------------------------------------ hud
const hud = R.hud_canvas.getContext('2d');
const gp = new THREE.Vector3();
function draw_hud() {
  hud.clearRect(0, 0, R.W, R.H);
  if (inspect.S.active) { if (G.hud) inspect.draw_hud(hud); return; }
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
  draw_text(hud, `${G.cam === CAM_EGG ? 'Y' : G.cam === CAM_FREE ? 4 : G.cam + 1} ${c.name}`, 8, 8, '#f2e3c2', 1, 'left', null, ink);
  draw_text(hud, c.note, 8, 19, '#a8987c', 1, 'left', null, ink);
  draw_text(hud, `U COIL: ${COIL_MODES[snakes.coil_mode]}`, 8, R.H - 169, '#f2e3c2', 1, 'left', null, ink);
  draw_text(hud, `N HIS HAND: ${lich.HANDS[END.hand]}`, 8, R.H - 158, '#f2e3c2', 1, 'left', null, ink);
  draw_text(hud, `Z ON THE FLOOR: ${SIZES[items.opts.size].name}`, 8, R.H - 147, '#f2e3c2', 1, 'left', null, ink);
  draw_text(hud, `M HAND: ${HAND_MATS[items.opts.hand_mat]}`, 8, R.H - 125, '#f2e3c2', 1, 'left', null, ink);
  draw_text(hud, `O BEHIND HIM: ${FACINGS[powers.facing]}`, 8, R.H - 114, '#a8987c', 1, 'left', null, ink);
  draw_text(hud, `K BEAM COLOUR: ${BEAM_LOOKS[powers.beam.look]}`, 8, R.H - 103, '#a8987c', 1, 'left', null, ink);
  draw_text(hud, `X BEAM RECOIL: ${lich.RECOILS[lich.recoil].name}`, 8, R.H - 92, '#a8987c', 1, 'left', null, ink);
  draw_text(hud, `L LENS BEAM: ${LENS_LOOKS[powers.lens.look]}`, 8, R.H - 81, '#a8987c', 1, 'left', null, ink);
  draw_text(hud, `F FIRE: ${fire.LOOKS[fire.look].name}`, 8, R.H - 70, '#a8987c', 1, 'left', null, ink);
  draw_text(hud, `J FLOATINESS: ${lich.JUICE[lich.juice].name}`, 8, R.H - 59, '#a8987c', 1, 'left', null, ink);
  draw_text(hud, `R PRISM PATTERN: ${lich.PATTERNS[lich.pattern]}`, 8, R.H - 48, '#a8987c', 1, 'left', null, ink);
  draw_text(hud, `G OUT OF THE LIGHT: ${lich.GLOWS[lich.glow].name}`, 8, R.H - 37, '#a8987c', 1, 'left', null, ink);
  draw_text(hud, `P PRISM STRENGTH: ${lich.MODES[lich.mode]}`, 8, R.H - 26, '#a8987c', 1, 'left', null, ink);
  draw_text(hud, `B DARKNESS: ${cave.DARK[G.dark].name}`, 8, R.H - 15, '#a8987c', 1, 'left', null, ink);
  // the powers he has (5-0), how strong each is, and how many snakes got to the egg
  powers.ALL.forEach((a, i) => {
    const on = powers.is_on(a);
    draw_text(hud, `${POWER_KEYS[i]} ${a.name}${on ? '' : ': REMOVED'}`, R.W - 8, 8 + i*11, on ? '#f2e3c2' : '#6a5e4e', 1, 'right', null, ink);
  });
  draw_text(hud, `EACH POWER X${powers.power.toFixed(1)}`, R.W - 8, 8 + 6*11 + 3, '#a8987c', 1, 'right', null, ink);
  draw_text(hud, `REACHED THE EGG: ${snakes.reached}`, R.W - 8, 8 + 7*11 + 3, snakes.reached ? '#e0a070' : '#a8987c', 1, 'right', null, ink);
  if (snakes.coiled.length) draw_text(hud, `COILED ROUND IT: ${snakes.coiled.length}   COVERED: ${Math.round(snakes.coverage*100)}% OF ${Math.round(snakes.WIN*100)}`, R.W - 8, 8 + 8*11 + 3, '#e0a070', 1, 'right', null, ink);
  if (END.won) draw_text(hud, 'THE EGG IS COVERED: WON', R.W - 8, 8 + 9*11 + 3, '#f2e3c2', 1, 'right', null, ink);
  draw_text(hud, 'T: REMOVE EVERY POWER (THE ENDING)', R.W - 8, R.H - 48, '#f2e3c2', 1, 'right', null, ink);
  draw_text(hud, 'I: INSPECT THE OBJECTS   5-0: REMOVE A POWER (ITS OBJECT DROPS)', R.W - 8, R.H - 37, '#f2e3c2', 1, 'right', null, ink);
  draw_text(hud, 'WASD OR HOLD LEFT MOUSE: MOVE', R.W - 8, R.H - 26, '#8a7c66', 1, 'right', null, ink);
  draw_text(hud, '1-4 Y CAMERA   U N Z M O K X L F J R G P B   H HIDE', R.W - 8, R.H - 15, '#8a7c66', 1, 'right', null, ink);
}

// round 37: the end: black over everything, then the message in the centre
const ss = (a, b, x) => { const t = clamp((x - a)/(b - a), 0, 1); return t*t*(3 - 2*t); };
function draw_over() {
  if (!END.won) return;
  const k = ss(OVER.hold, OVER.hold + OVER.fade, END.over);
  if (k > 0) { hud.fillStyle = `rgba(0,0,0,${k.toFixed(3)})`; hud.fillRect(0, 0, R.W, R.H); }
  const t0 = OVER.hold + OVER.fade + OVER.text_at, a = ss(t0, t0 + OVER.text_in, END.over);
  if (a <= 0) return;
  hud.globalAlpha = a;
  const LH = 18, y0 = Math.round(R.H/2 - (MESSAGE.length*LH)/2);
  MESSAGE.forEach((line, i) => draw_text(hud, line, R.W/2, y0 + i*LH, '#f2e3c2', 2, 'center'));
  hud.globalAlpha = 1;
}

// ------------------------------------------------------------------ sim + render
function tick() {
  if (END.won) { END.over += DT; if (over_black()) return; }   // round 37: once it is black, the game has stopped
  if (inspect.S.active) { inspect.tick(DT); return; }       // the game waits while he looks
  G.tick++;
  G.t += DT;
  mover.tick(G.t, DT, wanted_velocity());
  powers.tick(G.t, DT);
  ending_tick(DT);
  lich.pose(G.t, DT, mover.motion);
  powers.after_pose(G.t);
  lich.update(G.t);
  cave.update(G.t, DT);
  snakes.set_ember(fire.ember_colour());
  snakes.update(G.t, DT);
  fire.update(G.t, DT);
  fx.update(G.t, DT);
  gore.update(G.t, DT);
  warp.update(G.t, DT);
  items.update(G.t, DT);
}
function render(dt) {
  if (!inspect.render_setup()) R.params.world_override = null;
  place_camera(0);
  fire.set_camera(R.world_camera, R.H);
  fx.set_camera(R.world_camera, R.H);
  gore.set_camera(R.world_camera, R.H);
  warp.set_camera(R.world_camera, R.H);
  draw_hud();
  draw_over();
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
  egg_cam(yaw, pitch, dist) { Object.assign(G.egg_view, { yaw, pitch, dist }); set_cam(CAM_EGG); render(0); return 'EGG'; },
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
  // powers: set which are on (a list of 6 booleans), read the director, force one now
  powers(list) { if (list) list.forEach((v, i) => powers.set(i, v)); return powers.state(); },
  force(i, x, z) { return powers.force(i, x, z); },
  beam_look(m) { powers.beam.look = m; return BEAM_LOOKS[powers.beam.look]; },
  recoil(m) { lich.recoil = m; return lich.RECOILS[lich.recoil].name; },
  facing(m) { powers.facing = m; return FACINGS[powers.facing]; },
  lens_look(m) { powers.lens.look = m; return LENS_LOOKS[powers.lens.look]; },
  reached() { return snakes.reached; },
  // round 36: the ending
  remove_all() { remove_all(); return END.queue.length; },
  coil_mode(i) { snakes.coil_mode = i; return COIL_MODES[snakes.coil_mode]; },
  hand(i) { END.hand = i % lich.HANDS.length; return lich.HANDS[END.hand]; },
  hit(a) { lich.hit(a); return true; },
  // tests: hurt him without snakes (grips > 0), at a given level (null = the coverage)
  hurt(level = null) { END.grips = Math.max(1, END.grips); END.force_level = level; return true; },
  ending() {
    return { w: r3(END.w), level: r3(END.level), grips: END.grips, won: END.won, won_t: snakes.won_t, over: r3(END.over), black: over_black(), coverage: r3(snakes.coverage), reached: snakes.reached,
      coiled: snakes.coiled.map(s => ({ phase: s.coil.phase, h: r3(s.coil.h), of: r3(s.coil.Qlen), turns: s.coil.band.turns ? r3(s.coil.band.turns) : null, axis: s.coil.band.axis.map(r3), lift_max: r3(Math.max(...s.coil.lift)) })),
      crawling: snakes.S.filter(s => snakes.free(s)).length, snakes: snakes.S.length };
  },
  // round 28: the objects
  drop(i) { if (powers.is_on(powers.ALL[i])) toggle_power(i); return items.state()[i]; },
  restore(i) { if (!powers.is_on(powers.ALL[i])) toggle_power(i); return items.state()[i]; },
  items() { return items.state(); },
  inspect(i) { inspect.open(i); render(0); return ITEMS[inspect.S.idx].name; },
  inspect_pose(yaw, pitch, roll = 0, zoom = 1) { inspect.pose(yaw, pitch, roll, zoom); render(0); return true; },
  inspect_close() { inspect.close(); return true; },
  hand_mat(i) { const c = items.set_hand_mat(i); inspect.rebuild(); render(0); return c; },
  floor_size(i) { return items.set_size(i); },
  // tests: advance (no rendering) until a condition holds, at most `max` ticks; returns ticks run
  until(src, max = 3600) { const f = new Function('G', 'return (' + src + ');'); let n = 0; while (n < max && !f(G)) { tick(); place_camera(DT); n++; } render(n*DT); return n; },
  // set the snake nearest (x, z) alight now; returns its index
  ignite_near(x, z) {
    const live = snakes.live(); if (!live.length) return -1;
    live.sort((a, b) => Math.hypot(a.x - x, a.z - z) - Math.hypot(b.x - x, b.z - z));
    snakes.ignite(live[0], 30);
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
