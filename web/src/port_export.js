// port_export.js -- the port to Anchor (2026-09-30): what the Anchor build loads instead of making
// it at start (the sculpted skeleton and objects, the cave and its light bake, the canvas
// textures, the environment maps), written through the harness (PUT /__out/<dir>/...):
//   <dir>/manifest.json        what each file is (tools/port_assets.py turns it into Lua)
//   <dir>/geo/<name>.<attr>.f32, <name>.index.u32    geometry, little-endian, three.js's order
//   <dir>/tex/<name>.rgba      8-bit texels as GL received them (rows bottom-up when flipY)
//   <dir>/tex/<name>.f32       float texels (data textures, 3D probe grids)
// Test-only: nothing in the game calls it (GAME.port_export in main.js).
import * as THREE from 'three';
import { contact_points } from 'game/body.js';

const FILTER = { [THREE.NearestFilter]: 'nearest', [THREE.LinearFilter]: 'linear', [THREE.NearestMipmapNearestFilter]: 'nearest_mipmap_nearest',
  [THREE.NearestMipmapLinearFilter]: 'nearest_mipmap_linear', [THREE.LinearMipmapNearestFilter]: 'linear_mipmap_nearest', [THREE.LinearMipmapLinearFilter]: 'linear_mipmap_linear' };
const WRAP = { [THREE.ClampToEdgeWrapping]: 'clamp', [THREE.RepeatWrapping]: 'repeat', [THREE.MirroredRepeatWrapping]: 'mirror' };

export function create_exporter(dir) {
  const manifest = { geometries: {}, textures: {} };
  const jobs = [];
  const put = (path, body) => { jobs.push(fetch(`/__out/${dir}/${path}`, { method: 'PUT', body })); };
  const f32 = (a) => (a instanceof Float32Array ? a : new Float32Array(a));

  function geometry(g, name) {
    if (manifest.geometries[name]) return name;
    const meta = { attrs: {}, order: [] };
    for (const [k, a] of Object.entries(g.attributes)) {
      if (a.isInterleavedBufferAttribute) throw new Error('interleaved attribute ' + k + ' in ' + name);
      const arr = a.normalized ? Float32Array.from(a.array, v => v/(a.array instanceof Uint8Array ? 255 : a.array instanceof Uint16Array ? 65535 : 1)) : f32(a.array);
      put(`geo/${name}.${k}.f32`, arr);
      meta.attrs[k] = { size: a.itemSize, count: a.count };
      meta.order.push(k);
    }
    if (g.index) { put(`geo/${name}.index.u32`, Uint32Array.from(g.index.array)); meta.index = g.index.count; }
    if (!g.boundingSphere) g.computeBoundingSphere();
    const bs = g.boundingSphere;
    meta.bs = [bs.center.x, bs.center.y, bs.center.z, bs.radius];
    meta.draw_range = [g.drawRange.start, g.drawRange.count === Infinity ? -1 : g.drawRange.count];
    meta.groups = g.groups.map(gr => [gr.start, gr.count, gr.materialIndex]);
    manifest.geometries[name] = meta;
    return name;
  }

  // an 8-bit texture from its canvas / image, as GL receives it
  function texture(t, name) {
    if (manifest.textures[name]) return name;
    const img = t.image;
    const w = img.width, h = img.height;
    let px;
    if (img.data && !(img instanceof HTMLCanvasElement)) px = new Uint8Array(img.data.buffer.slice(0));
    else {
      const c = document.createElement('canvas'); c.width = w; c.height = h;
      const g = c.getContext('2d'); g.drawImage(img, 0, 0);
      px = new Uint8Array(g.getImageData(0, 0, w, h).data.buffer);
    }
    if (t.flipY) { const out = new Uint8Array(px.length); for (let y = 0; y < h; y++) out.set(px.subarray(y*w*4, (y + 1)*w*4), (h - 1 - y)*w*4); px = out; }
    put(`tex/${name}.rgba`, px);
    manifest.textures[name] = { kind: 'rgba8', w, h, srgb: t.colorSpace === THREE.SRGBColorSpace, min: FILTER[t.minFilter], mag: FILTER[t.magFilter],
      wrap_s: WRAP[t.wrapS], wrap_t: WRAP[t.wrapT], mipmaps: t.generateMipmaps, offset: [t.offset.x, t.offset.y], repeat: [t.repeat.x, t.repeat.y] };
    return name;
  }

  // a float data texture (2D or 3D): its texels as given to GL
  function data_texture(t, name) {
    if (manifest.textures[name]) return name;
    const img = t.image;
    put(`tex/${name}.f32`, f32(img.data));
    manifest.textures[name] = { kind: t.isData3DTexture ? 'f32_3d' : 'f32', w: img.width, h: img.height, d: img.depth || 0,
      format: t.format === THREE.RGBAFormat ? 'rgba' : t.format === THREE.RGFormat ? 'rg' : t.format === THREE.RedFormat ? 'r' : 'rgb',
      min: FILTER[t.minFilter], mag: FILTER[t.magFilter], wrap_s: WRAP[t.wrapS], wrap_t: WRAP[t.wrapT], wrap_r: WRAP[t.wrapR] };
    return name;
  }

  // a render target's texels read back (float for half/float targets)
  function target_texture(renderer, rt, name, extra = {}) {
    if (manifest.textures[name]) return name;
    const w = rt.width, h = rt.height;
    const half = rt.texture.type === THREE.HalfFloatType || rt.texture.type === THREE.FloatType;
    const buf = half ? new Float32Array(w*h*4) : new Uint8Array(w*h*4);
    if (rt.texture.type === THREE.HalfFloatType) {
      const hb = new Uint16Array(w*h*4);
      renderer.readRenderTargetPixels(rt, 0, 0, w, h, hb);
      const u = new Uint32Array(1), f = new Float32Array(u.buffer);
      for (let i = 0; i < hb.length; i++) {
        const x = hb[i], s = (x & 0x8000) << 16, e = (x >> 10) & 31, m = x & 1023;
        if (e === 0) buf[i] = (m/1024)*Math.pow(2, -14)*(s ? -1 : 1);
        else if (e === 31) buf[i] = m ? NaN : (s ? -Infinity : Infinity);
        else { u[0] = s | ((e - 15 + 127) << 23) | (m << 13); buf[i] = f[0]; }
      }
    } else renderer.readRenderTargetPixels(rt, 0, 0, w, h, buf);
    put(`tex/${name}.${half ? 'f32' : 'rgba'}`, buf);
    manifest.textures[name] = { kind: half ? 'f32' : 'rgba8', format: 'rgba', w, h, d: 0, min: FILTER[rt.texture.minFilter], mag: FILTER[rt.texture.magFilter],
      wrap_s: WRAP[rt.texture.wrapS], wrap_t: WRAP[rt.texture.wrapT], ...extra };
    return name;
  }

  const trs = (o) => ({ p: o.position.toArray(), q: o.quaternion.toArray(), s: o.scale.toArray() });

  return {
    manifest, geometry, texture, data_texture, target_texture, trs, put,
    async finish(extra = {}) {
      Object.assign(manifest, extra);
      put('manifest.json', JSON.stringify(manifest));
      await Promise.all(jobs);
      return { geometries: Object.keys(manifest.geometries).length, textures: Object.keys(manifest.textures).length, files: jobs.length };
    },
  };
}

// ---------------------------------------------------------------------------- the cave
export function export_cave(X, cave) {
  const P = cave._port;
  const meshes = P.statics.map((m, i) => {
    const name = X.geometry(m.geometry, `cave_${i}`);
    return { geo: name, material: m.material.name, cast: m.castShadow, receive: m.receiveShadow, parent: m.parent === cave.egg ? 'egg' : 'group', trs: X.trs(m) };
  });
  const lid = { geo: X.geometry(P.lid.geometry, 'cave_lid'), material: P.lid.material.name, trs: X.trs(P.lid) };
  const disc = cave.group.children.find(c => c.material && c.material.name === 'cave.sun_disc');
  const sun_disc = { geo: X.geometry(disc.geometry, 'cave_sun_disc'), trs: X.trs(disc) };
  const tex = {};
  for (const [k, t] of Object.entries(P.tx)) tex[k] = X.texture(t, `cave_${k}`);
  const GU = cave.GU;
  const gi = { up: X.data_texture(GU.uGIUp.value, 'gi_up'), down: X.data_texture(GU.uGIDown.value, 'gi_down'),
    min: GU.uGIMin.value.toArray(), max: GU.uGIMax.value.toArray() };
  const s = cave.sun, sc = s.shadow.camera;
  const sun = { color: [s.color.r, s.color.g, s.color.b], intensity: s.intensity, position: s.position.toArray(), target: s.target.position.toArray(),
    shadow: { map_size: [s.shadow.mapSize.x, s.shadow.mapSize.y], bias: s.shadow.bias, normal_bias: s.shadow.normalBias, radius: s.shadow.radius,
      camera: { left: sc.left, right: sc.right, top: sc.top, bottom: sc.bottom, near: sc.near, far: sc.far, up: sc.up.toArray() } } };
  const materials = {};
  for (const [k, m] of Object.entries(P.M)) materials[k] = { name: m.name, map: `cave_${m.map === P.tx.rock ? 'rock' : m.map === P.tx.floor ? 'floor' : 'egg'}`,
    side: m.side, shadow_side: m.shadowSide, flat: m.flatShading, color: [m.color.r, m.color.g, m.color.b] };
  return { meshes, lid, sun_disc, tex, gi, sun, materials, dust: P.dust.map(d => ({ ...d })), egg: { position: cave.egg.position.toArray(),
    shell: X.trs(cave.egg.userData.shell) }, consts: { SKY_L: P.SKY_L, DIRECT_K: P.DIRECT_K, SUN_E: P.SUN_E, LID_Y: P.LID_Y, TOP: P.TOP } };
}

// ---------------------------------------------------------------------------- the lich's bones
export function export_lich(X, lich) {
  const geo = {};
  for (const [k, g] of Object.entries(lich._port.GEO)) geo[k] = X.geometry(g, `bone_${k}`);
  const m = lich.mat;
  return { geo, material: { color: [m.color.r, m.color.g, m.color.b], roughness: m.roughness, metalness: m.metalness, ior: m.ior,
    specular_intensity: m.specularIntensity, iridescence: m.iridescence, iridescence_ior: m.iridescenceIOR,
    iridescence_thickness_range: m.iridescenceThicknessRange.slice(), flat: m.flatShading } };
}

// ---------------------------------------------------------------------------- the rest of the statics
// Found by material name in the world scene (scene order = creation order): the snakes' scales and
// eyes, the chunks, gore's shapes and splashes, the rocks' hulls, the lens, its patch, the flakes.
export function export_statics(X, R) {
  const by = {};
  R.world_scene.traverse(o => { if ((o.isMesh || o.isPoints) && o.material && !Array.isArray(o.material)) (by[o.material.name] ||= []).push(o); });
  const one = (name) => { const l = by[name]; if (!l || !l.length) throw new Error('no mesh for ' + name); return l[0]; };
  X.texture(one('snakes.body').material.map, 'snake_scales');
  X.geometry(one('snakes.eye').geometry, 'sphere_1_8_6');
  X.geometry(one('fx.chunks').geometry, 'icosahedron_1_0');
  const splats = by['gore.splat'];
  X.geometry(splats[0].geometry, 'gore_plane');
  splats.forEach((m, i) => X.texture(m.material.alphaMap, `gore_splat_${i + 1}`));
  X.geometry(one('gore.meat').geometry, 'gore_lump');
  const bones = by['gore.bone'];
  X.geometry(bones[0].geometry, 'gore_rib');
  X.geometry(bones[1].geometry, 'dodecahedron_1_0');
  X.geometry(one('gore.scraps').geometry, 'gore_scrap');
  by['rock.stone'].forEach((m, i) => X.geometry(m.geometry, `rock_${i}`));
  X.geometry(one('lens.glass').geometry, 'lens_glass');
  X.geometry(one('lens.patch').geometry, 'plane_2_2');
  X.geometry(one('leak.flakes').geometry, 'circle_1_5');
  return { rocks: by['rock.stone'].length, splats: splats.length };
}

// ---------------------------------------------------------------------------- the objects (items.js, inspect.js)
// Every object as built for the cave (items.W) and as the inspect view builds it (with its own
// lights' ctx), as node trees: meshes (geometry, material index, transform, shadow flags, the
// userData the game reads), materials with every parameter and uniform the game sets, textures
// (canvas ones as RGBA, cube render targets face by face, the prefiltered environment as floats).
const half_to_f32 = (hb, out) => {
  const u = new Uint32Array(1), f = new Float32Array(u.buffer);
  for (let i = 0; i < hb.length; i++) {
    const x = hb[i], s = (x & 0x8000) << 16, e = (x >> 10) & 31, m = x & 1023;
    if (e === 0) out[i] = (m/1024)*Math.pow(2, -14)*(s ? -1 : 1);
    else if (e === 31) out[i] = m ? NaN : (s ? -Infinity : Infinity);
    else { u[0] = s | ((e - 15 + 127) << 23) | (m << 13); out[i] = f[0]; }
  }
  return out;
};
function cube_target(X, renderer, rt, name) {
  if (X.manifest.textures[name]) return name;
  const n = rt.width;
  for (let k = 0; k < 6; k++) {
    let buf;
    if (rt.texture.type === THREE.HalfFloatType) { const hb = new Uint16Array(n*n*4); renderer.readRenderTargetPixels(rt, 0, 0, n, n, hb, k); buf = half_to_f32(hb, new Float32Array(n*n*4)); }
    else { buf = new Uint8Array(n*n*4); renderer.readRenderTargetPixels(rt, 0, 0, n, n, buf, k); }
    X.put(`tex/${name}.face${k}.${buf instanceof Float32Array ? 'f32' : 'rgba'}`, buf);
  }
  X.manifest.textures[name] = { kind: rt.texture.type === THREE.HalfFloatType ? 'cube_f32' : 'cube_rgba8', w: n, h: n, d: 0,
    min: FILTER[rt.texture.minFilter], mag: FILTER[rt.texture.magFilter], mipmaps: rt.texture.generateMipmaps };
  return name;
}
const MAT_KEYS = ['side', 'transparent', 'opacity', 'depthWrite', 'depthTest', 'colorWrite', 'blending', 'vertexColors', 'flatShading', 'roughness', 'metalness',
  'envMapIntensity', 'transmission', 'thickness', 'ior', 'dispersion', 'attenuationDistance', 'specularIntensity', 'iridescence', 'iridescenceIOR', 'clearcoat',
  'clearcoatRoughness', 'sheen', 'sheenRoughness', 'emissiveIntensity', 'alphaTest', 'polygonOffset', 'polygonOffsetFactor', 'polygonOffsetUnits', 'premultipliedAlpha',
  'toneMapped', 'fog', 'forceSinglePass', 'shadowSide', 'reflectivity', 'anisotropy', 'lights'];
const COLOR_KEYS = ['color', 'emissive', 'specularColor', 'attenuationColor', 'sheenColor'];
const TEX_KEYS = ['map', 'roughnessMap', 'alphaMap', 'envMap', 'normalMap', 'metalnessMap', 'emissiveMap'];
function export_objects(X, R) {
  const tex_names = new Map(), geo_names = new Map();
  let ti = 0, gi = 0;
  const tex = (t) => {
    if (!t) return null;
    if (tex_names.has(t)) return tex_names.get(t);
    let name;
    const rt = t.userData && t.userData.rt;
    if (rt && rt.isWebGLCubeRenderTarget) name = cube_target(X, R.renderer, rt, `obj_cube_${ti++}`);
    else if (rt) name = X.target_texture(R.renderer, rt, `obj_rt_${ti++}`);
    else if (t.isDataTexture || t.isData3DTexture) name = X.data_texture(t, `obj_data_${ti++}`);
    else { name = X.texture(t, `obj_tex_${ti++}`); X.manifest.textures[name].anisotropy = t.anisotropy; }
    tex_names.set(t, name);
    return name;
  };
  const geo = (g) => { if (geo_names.has(g)) return geo_names.get(g); const name = X.geometry(g, `obj_geo_${gi++}`); geo_names.set(g, name); return name; };
  const num = (v) => (v === Infinity ? 'Infinity' : v === -Infinity ? '-Infinity' : v);
  const value = (v) => {
    if (v === null || v === undefined) return null;
    if (typeof v === 'number') return num(v);
    if (typeof v === 'boolean') return v;
    if (v.isTexture) return { tex: tex(v) };
    if (v.isColor) return { color: [v.r, v.g, v.b] };
    if (v.isVector2) return { v: [v.x, v.y] };
    if (v.isVector3) return { v: [v.x, v.y, v.z] };
    if (v.isVector4) return { v: [v.x, v.y, v.z, v.w] };
    if (v.isMatrix3) return { m3: Array.from(v.elements) };
    if (v.isMatrix4) return { m4: Array.from(v.elements) };
    if (Array.isArray(v)) return { list: v.map(value) };
    return null;
  };
  const mats = [], mat_ix = new Map();
  const mat = (m) => {
    if (mat_ix.has(m)) return mat_ix.get(m);
    const o = { type: m.type, name: m.name, props: {}, colors: {}, textures: {}, uniforms: {} };
    for (const k of MAT_KEYS) if (m[k] !== undefined) o.props[k] = num(m[k]);
    for (const k of COLOR_KEYS) if (m[k] && m[k].isColor) o.colors[k] = [m[k].r, m[k].g, m[k].b];
    for (const k of TEX_KEYS) if (m[k]) o.textures[k] = tex(m[k]);
    const U = m.isShaderMaterial ? m.uniforms : (m.userData && m.userData.U);
    if (U) for (const [k, u] of Object.entries(U)) o.uniforms[k] = value(u.value);
    mats.push(o); mat_ix.set(m, mats.length - 1);
    return mats.length - 1;
  };
  const node = (o) => {
    const n = { t: o.isInstancedMesh ? 'InstancedMesh' : o.isMesh ? 'Mesh' : o.isGroup ? 'Group' : 'Object3D', name: o.name, trs: X.trs(o), visible: o.visible,
      ro: o.renderOrder, cs: o.castShadow, rs: o.receiveShadow, fc: o.frustumCulled,
      ud: { no_shadow: !!o.userData.no_shadow, no_contact: !!o.userData.no_contact, r: o.userData.r }, children: o.children.map(node) };
    if (o.isMesh) { n.geo = geo(o.geometry); n.mat = Array.isArray(o.material) ? o.material.map(mat) : mat(o.material); }
    return n;
  };
  return { tex, geo, mat, node, mats };
}
// items.js make_body's points: the surface points and box of each object at each floor size
// (the same computation, done here once; the Anchor build reads them)
function body_points(w, k) {
  w.g.updateMatrixWorld(true);
  const P = [];
  w.g.traverse(o => { if (o.isMesh && !o.isInstancedMesh && !o.userData.no_contact) { const g = o.geometry, p = g.attributes.position; o.updateMatrix(); const m = new THREE.Matrix4().compose(o.position, o.quaternion, o.scale); const step = Math.max(1, Math.floor(p.count/6000)); for (let i = 0; i < p.count; i += step) P.push(new THREE.Vector3().fromBufferAttribute(p, i).applyMatrix4(m)); } });
  const pg = new THREE.BufferGeometry().setFromPoints(P);
  for (const q of P) q.multiplyScalar(k);
  const pts = contact_points(pg.setFromPoints(P), 64);
  const bb = new THREE.Box3().setFromPoints(P), sz = bb.getSize(new THREE.Vector3());
  return { pts: pts.map(q => [q.x, q.y, q.z]), sz: [sz.x, sz.y, sz.z] };
}
export function export_items(X, R, items, inspect, ITEMS, HAND_MATS, SIZES) {
  const O = export_objects(X, R);
  const contact = items.W.map(w => (w && !w.it.balls ? SIZES.map(sz => body_points(w, w.it.fixed_k ?? sz.k*(w.it.floor_mul ?? 1))) : null));
  const box = (g) => { const b = new THREE.Box3().setFromObject(g); const c = b.getCenter(new THREE.Vector3()), s = b.getSize(new THREE.Vector3()); return { c: c.toArray(), s: s.toArray() }; };
  const world = items.W.map(w => (w ? { node: O.node(w.g), r0: w.r0, orbs: (w.g.userData.orbs || []).map(m => w.g.children.indexOf(m)) } : null));
  // the inspect view's builds, one per object
  const insp = ITEMS.map((it, i) => {
    if (!it.build) return null;
    const g = it.build(inspect.ctx, items.opts);
    g.updateMatrixWorld(true);
    return { node: O.node(g), box: box(g), orbs: (g.userData.orbs || []).map(m => g.children.indexOf(m)) };
  });
  // the hand's geometry and its colour / metalness-roughness variants
  const hand_mesh = items.W[1].g.children[0];
  const hg = hand_mesh.geometry, hname = O.geo(hg);
  const variants = (hg.userData.cols || []).map((c, k) => {
    X.put(`geo/${hname}.color_${k}.f32`, new Float32Array(c.array));
    X.put(`geo/${hname}.aMR_${k}.f32`, new Float32Array(hg.userData.mrs[k].array));
    return k;
  });
  // the inspect view's environment (scene.environment), its lights
  const amb = inspect.scene.children.find(o => o.isAmbientLight);
  const env = { pmrem: O.tex(inspect.env_pm), intensity: inspect.scene.environmentIntensity,
    lights: [inspect.key, inspect.fill, inspect.rim].map(l => ({ color: [l.color.r, l.color.g, l.color.b], intensity: l.intensity, position: l.position.toArray() })),
    ambient: [amb.color.r, amb.color.g, amb.color.b, amb.intensity],
    camera: { fov: inspect.camera.fov, near: inspect.camera.near, far: inspect.camera.far } };
  return { world, inspect: insp, mats: O.mats, hand: { geo: hname, variants, names: HAND_MATS }, env, contact, sizes: SIZES,
    items: ITEMS.map(it => ({ power: it.power, name: it.name, mass: it.mass, rest: it.rest, fric: it.fric, view: it.view || null, face_up: !!it.face_up,
      floor_mul: it.floor_mul ?? null, balls: !!it.balls, rolling: it.rolling ?? null, fixed_k: it.fixed_k ?? null })) };
}
