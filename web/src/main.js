// main.js -- round 1 scene: the ending's cave, the egg in its column of light, the prismatic
// lich hovering before it, placeholder snakes coming out of the dark; seven cameras to judge.
//
// Keys: 1-7 camera, H hides the text. In 7 (FREE) drag to orbit and scroll to zoom; the HUD
// prints yaw / pitch / distance so a framing can be reported back as numbers.
// Fixed 60 Hz step, rendering every animation frame. window.GAME is the harness API
// (tools/shoot.mjs): ready, setManual, step(n), state(), cam(i).
import * as THREE from 'three';
import { DT, clamp, lerp, smoothstep, damp } from 'game/util.js';
import { create_render } from 'game/render.js';
import { build_cave, LAYOUT } from 'game/cave.js';
import { create_lich } from 'game/lich.js';
import { create_snakes } from 'game/snakes.js';
import { draw_text } from 'game/hud_font.js';

const R = create_render(document.body);
R.canvas.style.cursor = 'default';
const cave = build_cave(R);
const lich = create_lich(R);
const L = new THREE.Vector3();                  // the lich's pelvis, world
const snakes = create_snakes(R, cave, () => L);

const G = { t: 0, tick: 0, cam: 0, manual: false, hud: true, approach_t: 0, dark: 1,
  free: { yaw: 200, pitch: 22, dist: 6.5 } };
window.G = G;

// ------------------------------------------------------------------ the lich's place
const HOVER = new THREE.Vector3(LAYOUT.hover.x, 0, LAYOUT.hover.z);
HOVER.y = cave.ground_y(HOVER.x, HOVER.z) + lich.hover_h;
const ENTRY = new THREE.Vector3(LAYOUT.entrance.x, 0, LAYOUT.entrance.z);
ENTRY.y = cave.ground_y(ENTRY.x, ENTRY.z) + lich.hover_h;
const APPROACH_SPEED = 2.4, APPROACH_HOLD = 4.0;
const approach_len = ENTRY.distanceTo(HOVER);

function lich_place() {
  let drift = 0;
  if (G.cam === 5) {
    const d = Math.min(G.approach_t*APPROACH_SPEED, approach_len);
    const f = d/approach_len;
    L.lerpVectors(ENTRY, HOVER, f);
    L.y = cave.ground_y(L.x, L.z) + lich.hover_h;
    drift = 1 - smoothstep(0.85, 1.0, f);
  } else L.copy(HOVER);
  lich.root.position.copy(L);
  lich.root.rotation.y = 0;                      // faces +z, toward the egg
  return drift;
}

// ------------------------------------------------------------------ cameras
const UP = new THREE.Vector3(0, 1, 0), F = new THREE.Vector3(0, 0, 1), SIDE = new THREE.Vector3(1, 0, 0);
const EGG = cave.egg.position;
const v = (x, y, z) => new THREE.Vector3(x, y, z);
const CAMS = [
  { name: 'CHASE', note: 'RISK OF RAIN: BEHIND AND ABOVE, OVER THE SHOULDER', fov: 60,
    rig: () => [L.clone().addScaledVector(F, -5.2).addScaledVector(UP, 2.1).addScaledVector(SIDE, -1.1), L.clone().addScaledVector(F, 3.4).addScaledVector(UP, -0.5).addScaledVector(SIDE, -0.5)] },
  { name: 'HIGH', note: 'HIGHER AND FURTHER: THE WHOLE RING AROUND THE EGG', fov: 50,
    rig: () => [L.clone().addScaledVector(F, -7.0).addScaledVector(UP, 8.0), L.clone().addScaledVector(F, 2.2).addScaledVector(UP, -1.0)] },
  { name: 'LOW', note: 'LOW BEHIND: THE LICH AND THE SHAFT ABOVE HIM', fov: 66,
    rig: () => [v(L.x + 0.9, cave.ground_y(L.x, L.z - 3.4) + 0.45, L.z - 3.4), L.clone().addScaledVector(F, 1.8).addScaledVector(UP, 1.7)] },
  { name: 'OVERHEAD', note: 'NEARLY TOP DOWN, VAMPIRE SURVIVORS READABILITY', fov: 46,
    rig: () => { const m = L.clone().lerp(EGG, 0.5); m.y = EGG.y; return [m.clone().addScaledVector(UP, 16).addScaledVector(F, -4.0), m]; }, dome: false },
  { name: 'WIDE', note: 'THE COVER: ESTABLISHING, LOW AT THE EDGE', fov: 58,
    rig: () => [v(-5.2, cave.ground_y(-5.2, -12) + 1.0, -12), v(0.3, 4.6, 0)] },
  { name: 'APPROACH', note: 'THE ENTRANCE: THE LICH DRIFTS IN FROM THE TUNNEL', fov: 60,
    rig: () => [L.clone().addScaledVector(F, -5.2).addScaledVector(UP, 2.1).addScaledVector(SIDE, -1.1), L.clone().addScaledVector(F, 3.4).addScaledVector(UP, -0.5).addScaledVector(SIDE, -0.5)] },
  { name: 'FREE', note: 'DRAG TO ORBIT, SCROLL TO ZOOM', fov: 58,
    rig: () => {
      const fr = G.free, y = fr.yaw*Math.PI/180, p = fr.pitch*Math.PI/180;
      const eye = L.clone().add(v(Math.sin(y)*Math.cos(p)*fr.dist, Math.sin(p)*fr.dist, Math.cos(y)*Math.cos(p)*fr.dist));
      return [eye, L.clone()];
    } },
];
const cam_eye = new THREE.Vector3(), cam_tgt = new THREE.Vector3();
let cam_snap = true;
function place_camera(dt) {
  const c = CAMS[G.cam];
  const [eye, tgt] = c.rig();
  if (cam_snap || G.cam !== 5) { cam_eye.copy(eye); cam_tgt.copy(tgt); cam_snap = false; }
  else { cam_eye.lerp(eye, 1 - Math.exp(-6*dt)); cam_tgt.lerp(tgt, 1 - Math.exp(-6*dt)); }
  cave.set_dome_visible(c.dome !== false);
  const C = R.world_camera;
  C.fov = c.fov; C.updateProjectionMatrix();
  C.position.copy(cam_eye);
  C.up.set(0, 1, 0);
  C.lookAt(cam_tgt);
}
function set_cam(i) {
  G.cam = clamp(i | 0, 0, CAMS.length - 1);
  cam_snap = true;
  if (G.cam === 5) G.approach_t = 0;
}

// ------------------------------------------------------------------ hud
const hud = R.hud_canvas.getContext('2d');
function draw_hud() {
  hud.clearRect(0, 0, R.W, R.H);
  if (!G.hud) return;
  const c = CAMS[G.cam];
  const ink = 'rgba(8,6,5,0.85)';
  draw_text(hud, `${G.cam + 1} ${c.name}`, 8, 8, '#f2e3c2', 1, 'left', null, ink);
  draw_text(hud, c.note, 8, 19, '#a8987c', 1, 'left', null, ink);
  if (G.cam === 6) {
    const f = G.free;
    draw_text(hud, `YAW ${Math.round(((f.yaw % 360) + 360) % 360)}  PITCH ${Math.round(f.pitch)}  DIST ${f.dist.toFixed(1)}`, 8, 30, '#a8987c', 1, 'left', null, ink);
  }
  draw_text(hud, `P LICH: ${lich.MODES[lich.mode]}`, 8, R.H - 26, '#a8987c', 1, 'left', null, ink);
  draw_text(hud, `D DARKNESS: ${cave.DARK[G.dark].name}`, 8, R.H - 15, '#a8987c', 1, 'left', null, ink);
  draw_text(hud, '1-7 CAMERA   P LICH   D DARKNESS   H HIDE TEXT', R.W - 8, R.H - 15, '#8a7c66', 1, 'right', null, ink);
}

// ------------------------------------------------------------------ sim + render
function tick() {
  G.tick++;
  G.t += DT;
  if (G.cam === 5) {
    G.approach_t += DT;
    if (G.approach_t > approach_len/APPROACH_SPEED + APPROACH_HOLD) G.approach_t = 0;
  }
  const drift = lich_place();
  lich.pose(G.t, drift);
  lich.update(G.t);
  cave.update(G.t, DT);
  snakes.update(G.t, DT);
}
function render(dt) {
  place_camera(dt);
  draw_hud();
  R.render(dt);
}

// ------------------------------------------------------------------ input
addEventListener('keydown', (e) => {
  const d = /^(Digit|Numpad)([1-7])$/.exec(e.code);
  if (d) set_cam(+d[2] - 1);
  if (e.code === 'KeyH') G.hud = !G.hud;
  if (e.code === 'KeyP') lich.mode = lich.mode + 1;
  if (e.code === 'KeyD') { G.dark = (G.dark + 1) % cave.DARK.length; cave.set_darkness(G.dark); }
});
let drag = null;
R.canvas.addEventListener('pointerdown', (e) => { if (G.cam === 6) { drag = [e.clientX, e.clientY]; R.canvas.setPointerCapture(e.pointerId); } });
R.canvas.addEventListener('pointerup', () => { drag = null; });
R.canvas.addEventListener('pointermove', (e) => {
  if (!drag || G.cam !== 6) return;
  G.free.yaw -= (e.clientX - drag[0])*0.3;
  G.free.pitch = clamp(G.free.pitch + (e.clientY - drag[1])*0.25, -10, 88);
  drag = [e.clientX, e.clientY];
});
R.canvas.addEventListener('wheel', (e) => { if (G.cam === 6) G.free.dist = clamp(G.free.dist*Math.exp(e.deltaY*0.001), 2, 30); }, { passive: true });

let last = performance.now(), acc = 0;
function frame(now) {
  requestAnimationFrame(frame);
  let dt = (now - last)/1000; last = now;
  if (G.manual) return;
  if (!(dt >= 0)) dt = 0;
  if (dt > 0.25) dt = 0.25;
  acc += dt;
  let n = 0;
  while (acc >= DT && n < 8) { tick(); acc -= DT; n++; }
  if (n >= 8) acc = 0;
  render(dt);
}

// ------------------------------------------------------------------ harness API
window.GAME = {
  ready: false,
  setManual(on) { G.manual = !!on; return G.manual; },
  step(n = 1) { for (let i = 0; i < (n | 0); i++) tick(); render(n*DT); return G.tick; },
  cam(i, free) { set_cam(i); if (free) Object.assign(G.free, free); render(0); return CAMS[G.cam].name; },
  hud(on) { G.hud = !!on; render(0); return G.hud; },
  mode(m) { lich.mode = m; render(0); return lich.MODES[lich.mode]; },
  dark(i) { G.dark = i; const n = cave.set_darkness(i); render(0); return n; },
  snakes() { return snakes.S.map(s => [+s.x.toFixed(2), +s.z.toFixed(2), s.dying, +s.delay.toFixed(2)]); },
  state() { return { t: G.t, tick: G.tick, cam: CAMS[G.cam].name, lich: L.toArray().map(x => +x.toFixed(3)) }; },
};
cave.set_darkness(G.dark);
lich_place();
tick();
render(0);
window.GAME.ready = true;
requestAnimationFrame(frame);
