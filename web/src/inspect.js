// inspect.js -- round 28: the inspect view (owner: when a power's object is taken "it has some
// text that appears, this is a common model viewer view in such games, where you can rotate the
// object around as it appears centered on the screen").
//
// The game stops; its last frame stays behind, darkened and softened; the object comes up to the
// middle of the screen in its own light (a key from above like the shaft, a warm bounce from
// below, a rim behind) and turns slowly until it is taken in hand: left-drag turns it, the wheel
// brings it closer, A/D (or the arrows) go to the next object, I or Esc puts it away. Its name
// and the text slot are drawn under it. It is drawn by the game's own pipeline (render.js'
// world_override): the same 640x360, grade, bloom and dither as everything else.
import * as THREE from 'three';
import { clamp, smoothstep, damp } from 'game/util.js';
import { draw_text } from 'game/hud_font.js';


// an environment for reflections and refraction: dark warm rock all round, the shaft's bright
// opening above, the warm pool below (radiance, linear)
function env_scene() {
  const s = new THREE.Scene();
  const m = new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false,
    vertexShader: `varying vec3 vD; void main(){ vD = normalize(position); gl_Position = projectionMatrix*modelViewMatrix*vec4(position, 1.0); }`,
    fragmentShader: `varying vec3 vD;
      float h(vec3 p){ return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719)))*43758.5453); }
      float n3(vec3 p){ vec3 i = floor(p), f = fract(p); f = f*f*(3.0 - 2.0*f);
        return mix(mix(mix(h(i), h(i + vec3(1,0,0)), f.x), mix(h(i + vec3(0,1,0)), h(i + vec3(1,1,0)), f.x), f.y),
                   mix(mix(h(i + vec3(0,0,1)), h(i + vec3(1,0,1)), f.x), mix(h(i + vec3(0,1,1)), h(i + vec3(1,1,1)), f.x), f.y), f.z); }
      void main(){
        vec3 d = normalize(vD);
        float rock = 0.55 + 0.45*n3(d*7.0) + 0.25*n3(d*23.0);
        vec3 c = vec3(0.018, 0.014, 0.01)*rock;
        // the pool below and its warm bounce up the walls
        c += vec3(0.28, 0.2, 0.11)*smoothstep(-0.6, -0.95, d.y);
        c += vec3(0.08, 0.055, 0.03)*smoothstep(0.1, -0.6, d.y);
        // the shaft's opening, a little off the top, and the column's glow around it
        float a = dot(d, normalize(vec3(0.25, 1.0, 0.35)));
        c += vec3(2.2, 2.0, 1.7)*smoothstep(0.9993, 0.9997, a);
        c += vec3(0.35, 0.28, 0.18)*pow(max(a, 0.0), 60.0);
        // a lit wall to one side: a broad soft panel, and a thin bright crack of light on the
        // other (glass shows its edges by what it reflects)
        float b = dot(d, normalize(vec3(-1.0, 0.25, 0.5)));
        c += vec3(0.32, 0.24, 0.15)*smoothstep(0.84, 0.95, b);
        vec3 k = normalize(vec3(1.0, 0.1, -0.25));
        float kx = dot(d, k), ky = d.y;
        c += vec3(2.6, 2.3, 1.9)*smoothstep(0.985, 0.995, kx)*smoothstep(0.5, 0.2, abs(ky - 0.15));
        // a few small bright points (light caught on wet rock): the gem's fire needs them
        for (int i = 0; i < 7; i++) {
          float fi = float(i);
          vec3 p = normalize(vec3(sin(fi*2.4 + 0.3), 0.35 + 0.5*sin(fi*1.7), cos(fi*2.4 + 0.3)));
          c += vec3(3.0, 2.7, 2.2)*smoothstep(0.99985, 0.99996, dot(d, p));
        }
        gl_FragColor = vec4(c, 1.0);
      }`,
  });
  s.add(new THREE.Mesh(new THREE.SphereGeometry(10, 48, 24), m));
  return s;
}

export function create_inspect(ctx) {
  const { R, items, ITEMS } = ctx;
  const renderer = R.renderer;

  // ---------------------------------------------------------------- the environment
  const cube_rt = new THREE.WebGLCubeRenderTarget(256, { type: THREE.HalfFloatType, generateMipmaps: true, minFilter: THREE.LinearMipmapLinearFilter });
  const cube_cam = new THREE.CubeCamera(0.1, 50, cube_rt);
  cube_cam.update(renderer, env_scene());
  const pmrem = new THREE.PMREMGenerator(renderer);
  const env_pm = pmrem.fromCubemap(cube_rt.texture).texture;

  // ---------------------------------------------------------------- the scene
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x000000);
  scene.environment = env_pm;
  scene.environmentIntensity = 0.6;
  const camera = new THREE.PerspectiveCamera(30, R.W/R.H, 0.02, 30);
  camera.position.set(0, 0, 1);
  const key = new THREE.DirectionalLight(0xffe2b4, 3.2); key.position.set(0.5, 2, 1.2);
  const fill = new THREE.DirectionalLight(0xc98a52, 0.55); fill.position.set(0, -1.5, 0.8);
  const rim = new THREE.DirectionalLight(0xfff0dc, 1.6); rim.position.set(-1.2, 0.8, -1.5);
  scene.add(key, fill, rim, new THREE.AmbientLight(0x3a2a1c, 0.25));
  const sun = { dir: key.position.clone().normalize(), col: new THREE.Vector3(1, 0.9, 0.72).multiplyScalar(22) };

  // the frozen frame behind: darkened, softened (display values back to linear, before the
  // exposure the final pass applies again)
  const back_mat = new THREE.ShaderMaterial({
    uniforms: { tFrame: { value: null }, uDim: { value: 1 }, uRes: { value: new THREE.Vector2(R.W, R.H) }, uExposure: { value: 1 }, uBlur: { value: 0 }, uBlack: { value: 0 }, uGlow: { value: 0 } },
    vertexShader: `varying vec2 vUv; void main(){ vUv = position.xy*0.5 + 0.5; gl_Position = vec4(position.xy, 0.9999, 1.0); }`,
    fragmentShader: `varying vec2 vUv; uniform sampler2D tFrame; uniform float uDim, uExposure, uBlur, uBlack, uGlow; uniform vec2 uRes;
      vec3 lin(vec3 c){ return mix(c/12.92, pow((c + 0.055)/1.055, vec3(2.4)), step(0.04045, c)); }
      void main(){
        vec3 c = vec3(0.0); float wsum = 0.0;
        for (int j = -2; j <= 2; j++) for (int i = -2; i <= 2; i++) {
          float w = exp(-float(i*i + j*j)/4.0);
          c += lin(texture2D(tFrame, vUv + vec2(float(i), float(j))*uBlur/uRes).rgb)*w; wsum += w;
        }
        c /= wsum;
        vec2 q = vUv - 0.5; q.x *= uRes.x/uRes.y;
        float vig = 1.0 - 0.55*smoothstep(0.2, 0.95, length(q));
        c = c*uDim*vig*(1.0 - uBlack)/uExposure;
        // a soft warm light behind the object (what the glass has to bend, and what sets its
        // outline off the dark)
        vec2 g = vUv - vec2(0.5, 0.56); g.x *= uRes.x/uRes.y;
        c += vec3(0.105, 0.078, 0.05)*exp(-dot(g, g)/0.035)*uGlow/uExposure;
        gl_FragColor = vec4(c, 1.0);
      }`,
    depthWrite: false, depthTest: false,
  });
  const tri = new THREE.BufferGeometry();
  tri.setAttribute('position', new THREE.Float32BufferAttribute([-1, -1, 0, 3, -1, 0, -1, 3, 0], 3));
  const back = new THREE.Mesh(tri, back_mat);
  back.frustumCulled = false; back.renderOrder = -10;
  scene.add(back);

  // the object: a holder (the view's turning) around the model (centred on its bounds)
  const holder = new THREE.Group();
  scene.add(holder);
  // the traced stones see the key as a small hard light (a facet shows its image: a wide lobe
  // made a white disc on a whole face)
  const inspect_ctx = { lit: m => m, env: cube_rt.texture, env_k: 1, env_i: 1, sun, glint_pow: 9000 };

  const S = {
    active: false, t: 0, idx: 5, model: null, radius: 0.2, backdrop: 0,
    q: new THREE.Quaternion(), wv: new THREE.Vector2(0, 0), zoom: 1, zoom_t: 1, idle: 0, closing: -1,
    drag: null, saved: null,
  };

  function build(i) {
    if (S.model) { holder.remove(S.model); S.model = null; }
    const it = ITEMS[i];
    S.idx = i;
    if (!it.build) return;
    const g = it.build(inspect_ctx, items.opts);
    S.hover = g.userData.hover || null;
    const box = new THREE.Box3().setFromObject(g);
    const c = box.getCenter(new THREE.Vector3());
    const size = box.getSize(new THREE.Vector3());
    g.position.sub(c);
    const wrap = new THREE.Group(); wrap.add(g);
    // framed by its largest extent (a flat lens or a long crystal fills the view either way)
    S.model = wrap; S.radius = Math.max(size.x, size.y, size.z)*0.55;
    holder.add(wrap);
    // the first view: each object's own (the lens tipped well toward you so its glass shows)
    const v = it.view ?? [0.55, 0.4, 0.0];
    S.q.setFromEuler(new THREE.Euler(v[0], v[1], v[2], 'YXZ'));
  }

  function open(i = S.idx) {
    if (S.active) return;
    S.active = true; S.t = 0; S.closing = -1; S.idle = 0; S.zoom = S.zoom_t = 1; S.wv.set(0, 0);
    // the frame behind, drawn once more without the HUD
    const hud = R.params.hud; R.params.hud = 0; R.params.world_override = null; R.render(0); R.params.hud = hud;
    back_mat.uniforms.tFrame.value = R.freeze();
    S.saved = { bloom: R.params.bloom.strength };
    build(i);
  }
  function close() { if (S.active && S.closing < 0) S.closing = 0; }
  function next(d) {
    let i = S.idx;
    for (let k = 0; k < ITEMS.length; k++) { i = (i + d + ITEMS.length) % ITEMS.length; if (ITEMS[i].build) break; }
    build(i); S.t = 0.12; S.idle = 0; S.zoom_t = 1;
  }

  // ---------------------------------------------------------------- input
  const el = R.canvas;
  el.addEventListener('pointerdown', (e) => { if (S.active && e.button === 0) { S.drag = [e.clientX, e.clientY]; S.idle = 0; } });
  addEventListener('pointerup', (e) => { if (e.button === 0) S.drag = null; });
  el.addEventListener('pointermove', (e) => {
    if (!S.active || !S.drag) return;
    const dx = e.clientX - S.drag[0], dy = e.clientY - S.drag[1];
    S.drag = [e.clientX, e.clientY];
    const k = 3.2/Math.max(el.clientHeight, 1);
    S.wv.set(dx*k*60, dy*k*60);
    turn(dx*k, dy*k);
    S.idle = 0;
  });
  el.addEventListener('wheel', (e) => { if (S.active) { S.zoom_t = clamp(S.zoom_t*Math.exp(-e.deltaY*0.0012), 0.8, 3.2); S.idle = 0; } }, { passive: true });
  const qa = new THREE.Quaternion(), ax = new THREE.Vector3();
  function turn(yaw, pitch) {
    qa.setFromAxisAngle(ax.set(0, 1, 0), yaw); S.q.premultiply(qa);
    qa.setFromAxisAngle(ax.set(1, 0, 0), pitch); S.q.premultiply(qa);
  }

  // ---------------------------------------------------------------- per frame
  function tick(dt) {
    if (!S.active) return;
    S.t += dt;
    if (S.closing >= 0) S.closing += dt;
    S.idle += dt;
    // let go, it keeps turning a moment; left alone, it turns slowly on its own
    if (!S.drag) {
      turn(S.wv.x*dt, S.wv.y*dt);
      S.wv.multiplyScalar(Math.exp(-3.5*dt));
      const auto = 0.35*smoothstep(1.5, 3.0, S.idle);
      turn(auto*dt, 0);
    }
    S.zoom = damp(S.zoom, S.zoom_t, 10, dt);
    if (S.model && S.hover) S.hover(S.t);
    if (S.closing > 0.3) { S.active = false; R.params.world_override = null; R.params.bloom.strength = S.saved.bloom; }
  }

  function render_setup() {
    if (!S.active) return false;
    const a = smoothstep(0, 0.3, S.t)*(S.closing >= 0 ? 1 - smoothstep(0, 0.28, S.closing) : 1);
    // the object comes up from a little below and further, and settles
    const dist = S.radius/Math.tan(15*Math.PI/180)/0.62/S.zoom;
    camera.position.set(0, 0, dist);
    camera.near = dist*0.05; camera.far = dist*6; camera.updateProjectionMatrix();
    camera.lookAt(0, 0, 0);
    holder.quaternion.copy(S.q);
    const e = 1 - a;
    holder.position.set(0, -S.radius*0.9*e*e + S.radius*0.06, -S.radius*1.2*e);
    holder.scale.setScalar(0.001 + a);
    back_mat.uniforms.uDim.value = 1 - 0.78*smoothstep(0, 0.3, S.t)*(S.closing >= 0 ? 1 - smoothstep(0, 0.28, S.closing) : 1);
    back_mat.uniforms.uBlur.value = 1.6*(1 - back_mat.uniforms.uDim.value)/0.78;
    back_mat.uniforms.uExposure.value = R.params.exposure;
    back_mat.uniforms.uGlow.value = a;
    R.params.world_override = { scene, camera };
    return true;
  }

  function draw_hud(hud) {
    if (!S.active) return;
    const it = ITEMS[S.idx];
    const a = smoothstep(0.15, 0.45, S.t)*(S.closing >= 0 ? 1 - smoothstep(0, 0.15, S.closing) : 1);
    if (a <= 0) return;
    hud.globalAlpha = a;
    const ink = 'rgba(8,6,5,0.9)';
    draw_text(hud, it.name, R.W/2, R.H - 64, '#f2e3c2', 2, 'center', null, ink);
    draw_text(hud, `THE ${it.power} POWER`, R.W/2, R.H - 44, '#a8987c', 1, 'center', null, ink);
    draw_text(hud, it.build ? '[ YOUR TEXT ]' : `NOT MODELLED YET: ${it.pending}`, R.W/2, R.H - 30, '#6f6252', 1, 'center', null, ink);
    draw_text(hud, 'DRAG: TURN   WHEEL: CLOSER   A D: NEXT   C M: VARIANTS   I: PUT AWAY', R.W/2, R.H - 12, '#6a5e4e', 1, 'center', null, ink);
    hud.globalAlpha = 1;
  }

  return {
    S, open, close, next, tick, render_setup, draw_hud, scene, camera, holder, env: cube_rt.texture,
    rebuild() { if (S.active) { const q = S.q.clone(); build(S.idx); S.q.copy(q); } },
    // tests: turn to a view (radians), zoom
    pose(yaw, pitch, roll = 0, zoom = 1) { S.q.setFromEuler(new THREE.Euler(pitch, yaw, roll, 'YXZ')); S.zoom = S.zoom_t = zoom; S.wv.set(0, 0); S.idle = -1e9; },
  };
}
