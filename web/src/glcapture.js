// glcapture.js -- the port to Anchor (2026-09-30): a WebGL2 frame capture, active only with
// ?glcapture in the page's URL (tools/shoot.mjs --query '?glcapture'); otherwise it does nothing.
//
// From page load it keeps a copy of every buffer and texture upload (with the unpack state that
// shapes them), every framebuffer's attachments and every texture's parameters. GLCAP.frame()
// then records the GL commands of the next render(s): clears, draws (with the program, the bound
// framebuffer, the viewport, all fixed-function state, every uniform's value read back from GL,
// the texture on every sampler unit, every vertex attribute's buffer and layout), blits and
// mipmap builds. GLCAP.export(dir) writes it all through the harness (PUT /__out/...):
//   <dir>/frame.json          commands + resources (meta)
//   <dir>/buf/<id>.bin        buffer contents as uploaded
//   <dir>/tex/<id>.bin        level 0 of each uploaded texture, as GL received it (rows bottom-up
//                             when UNPACK_FLIP_Y was on)
// The Anchor side replays it (port/replay.lua) to prove the GPU layer draws what three.js drew.
const ON = typeof location !== 'undefined' && /glcapture/.test(location.search);
export const GLCAP = { on: ON };
if (ON) install();

function install() {
  const P = WebGL2RenderingContext.prototype;
  const G = WebGL2RenderingContext;
  const ids = new WeakMap(); let next = 1;
  const idof = (o) => { if (!o) return 0; let i = ids.get(o); if (!i) { i = next++; ids.set(o, i); } return i; };
  const objs = new Map();                  // id -> the GL object (programs, for mapping)
  const buffers = new Map();               // id -> Uint8Array
  const textures = new Map();              // id -> meta (+ data)
  const fbos = new Map();                  // id -> { attachments }
  const rbos = new Map();                  // id -> { ifmt, w, h, samples }
  const unpack = { flipY: false, premul: false };
  let rec = null;
  const O = {};
  for (const n of ['getParameter', 'getProgramParameter', 'getActiveUniform', 'getUniformLocation', 'getUniform', 'activeTexture',
    'getActiveAttrib', 'getAttribLocation', 'getVertexAttrib', 'getVertexAttribOffset']) O[n] = P[n];
  const wrap = (name, fn) => { const f = P[name]; O[name] = f; P[name] = function (...a) { return fn.call(this, f, a); }; };

  const bpc = (type) => (type === G.FLOAT || type === G.UNSIGNED_INT || type === G.INT ? 4 : type === G.HALF_FLOAT || type === G.UNSIGNED_SHORT || type === G.SHORT ? 2 : 1);
  const comps = (fmt) => (fmt === G.RGBA || fmt === G.RGBA_INTEGER ? 4 : fmt === G.RGB ? 3 : fmt === G.RG ? 2 : 1);
  const tex_binding = (gl, target) => {
    const q = target === G.TEXTURE_3D ? G.TEXTURE_BINDING_3D : target === G.TEXTURE_2D_ARRAY ? G.TEXTURE_BINDING_2D_ARRAY :
      (target === G.TEXTURE_CUBE_MAP || (target >= G.TEXTURE_CUBE_MAP_POSITIVE_X && target <= G.TEXTURE_CUBE_MAP_NEGATIVE_Z)) ? G.TEXTURE_BINDING_CUBE_MAP : G.TEXTURE_BINDING_2D;
    return O.getParameter.call(gl, q);
  };
  const tex_meta = (gl, target) => {
    const t = tex_binding(gl, target), id = idof(t);
    let m = textures.get(id);
    if (!m) { m = { id, target: target >= G.TEXTURE_CUBE_MAP_POSITIVE_X && target <= G.TEXTURE_CUBE_MAP_NEGATIVE_Z ? G.TEXTURE_CUBE_MAP : target, params: {}, data: null, faces: null }; textures.set(id, m); }
    return m;
  };
  // a TexImageSource's pixels as RGBA8, top row first
  const source_pixels = (src) => {
    const w = src.width || src.naturalWidth || src.videoWidth, h = src.height || src.naturalHeight || src.videoHeight;
    if (src.data && src.width && src.height && !(src instanceof HTMLCanvasElement)) return { w, h, px: new Uint8Array(src.data.buffer.slice(0)) };   // ImageData
    const c = document.createElement('canvas'); c.width = w; c.height = h;
    const g = c.getContext('2d'); g.drawImage(src, 0, 0);
    return { w, h, px: new Uint8Array(g.getImageData(0, 0, w, h).data.buffer) };
  };
  const flip_rows = (u8, w, h, rowbytes) => {
    const out = new Uint8Array(u8.length);
    for (let y = 0; y < h; y++) out.set(u8.subarray(y*rowbytes, (y + 1)*rowbytes), (h - 1 - y)*rowbytes);
    return out;
  };
  const view_bytes = (v, off_elems = 0, len_elems = 0) => {
    if (!v) return null;
    if (v instanceof ArrayBuffer) return new Uint8Array(v.slice(0));
    const bpe = v.BYTES_PER_ELEMENT || 1;
    const start = v.byteOffset + off_elems*bpe;
    const n = len_elems ? len_elems*bpe : v.byteLength - off_elems*bpe;
    return new Uint8Array(v.buffer.slice(start, start + n));
  };
  // store level-0 pixels (as GL receives them) into a texture's meta
  const store = (m, face, level, x, y, z, w, h, d, fmt, type, bytes, is_sub) => {
    if (level !== 0 || !bytes) return;
    const tb = comps(fmt)*bpc(type);
    m.fmt = fmt; m.type = type;
    if (m.target === G.TEXTURE_CUBE_MAP) { m.faces = m.faces || []; m.faces[face] = bytes; return; }
    if (!is_sub || (x === 0 && y === 0 && z === 0 && w === m.w && h === m.h && (d || 1) === (m.d || 1))) { m.data = bytes; return; }
    if (!m.data) m.data = new Uint8Array(m.w*m.h*(m.d || 1)*tb);
    for (let zz = 0; zz < (d || 1); zz++) for (let yy = 0; yy < h; yy++) {
      const src = (zz*h + yy)*w*tb, dst = (((z + zz)*m.h) + (y + yy))*m.w*tb + x*tb;
      m.data.set(bytes.subarray(src, src + w*tb), dst);
    }
  };
  const prep_view = (m, w, h, fmt, type, bytes) => (bytes && unpack.flipY && m.target !== G.TEXTURE_3D ? flip_rows(bytes, w, h, w*comps(fmt)*bpc(type)) : bytes);
  const prep_source = (src) => {
    let { w, h, px } = source_pixels(src);
    if (unpack.premul) for (let i = 0; i < px.length; i += 4) { const a = px[i + 3]/255; px[i] *= a; px[i + 1] *= a; px[i + 2] *= a; }
    if (unpack.flipY) px = flip_rows(px, w, h, w*4);
    return { w, h, px };
  };
  const face_of = (target) => (target >= G.TEXTURE_CUBE_MAP_POSITIVE_X && target <= G.TEXTURE_CUBE_MAP_NEGATIVE_Z ? target - G.TEXTURE_CUBE_MAP_POSITIVE_X : 0);

  wrap('pixelStorei', function (f, a) {
    if (a[0] === G.UNPACK_FLIP_Y_WEBGL) unpack.flipY = !!a[1];
    if (a[0] === G.UNPACK_PREMULTIPLY_ALPHA_WEBGL) unpack.premul = !!a[1];
    return f.apply(this, a);
  });
  wrap('bufferData', function (f, a) {
    const r = f.apply(this, a);
    const b = O.getParameter.call(this, a[0] === G.ELEMENT_ARRAY_BUFFER ? G.ELEMENT_ARRAY_BUFFER_BINDING : a[0] === G.ARRAY_BUFFER ? G.ARRAY_BUFFER_BINDING : 0);
    if (b) buffers.set(idof(b), typeof a[1] === 'number' ? new Uint8Array(a[1]) : view_bytes(a[1], a[3] || 0, a[4] || 0));
    return r;
  });
  wrap('bufferSubData', function (f, a) {
    const r = f.apply(this, a);
    const b = O.getParameter.call(this, a[0] === G.ELEMENT_ARRAY_BUFFER ? G.ELEMENT_ARRAY_BUFFER_BINDING : G.ARRAY_BUFFER_BINDING);
    const cur = b && buffers.get(idof(b));
    const src = view_bytes(a[2], a[3] || 0, a[4] || 0);
    if (cur && src) cur.set(src.subarray(0, Math.max(0, Math.min(src.length, cur.length - a[1]))), a[1]);
    return r;
  });
  wrap('texStorage2D', function (f, a) {
    const r = f.apply(this, a);
    const m = tex_meta(this, a[0]); m.levels = a[1]; m.ifmt = a[2]; m.w = a[3]; m.h = a[4]; m.d = 0; m.storage = true;
    return r;
  });
  wrap('texStorage3D', function (f, a) {
    const r = f.apply(this, a);
    const m = tex_meta(this, a[0]); m.levels = a[1]; m.ifmt = a[2]; m.w = a[3]; m.h = a[4]; m.d = a[5]; m.storage = true;
    return r;
  });
  wrap('texImage2D', function (f, a) {
    const r = f.apply(this, a);
    const m = tex_meta(this, a[0]);
    if (a.length >= 9) {                              // (target, level, ifmt, w, h, border, fmt, type, src, srcOffset?)
      if (a[1] === 0) { m.ifmt = a[2]; m.w = a[3]; m.h = a[4]; m.d = 0; }
      const src = a[8];
      if (src && typeof src === 'object' && !ArrayBuffer.isView(src)) { const s = prep_source(src); store(m, face_of(a[0]), a[1], 0, 0, 0, s.w, s.h, 0, G.RGBA, G.UNSIGNED_BYTE, s.px, false); }
      else if (src && typeof src === 'object') store(m, face_of(a[0]), a[1], 0, 0, 0, a[3], a[4], 0, a[6], a[7], prep_view(m, a[3], a[4], a[6], a[7], view_bytes(src, a[9] || 0)), false);
    } else {                                          // (target, level, ifmt, fmt, type, source)
      const s = prep_source(a[5]);
      if (a[1] === 0) { m.ifmt = a[2]; m.w = s.w; m.h = s.h; m.d = 0; }
      store(m, face_of(a[0]), a[1], 0, 0, 0, s.w, s.h, 0, a[3], a[4], s.px, false);
    }
    return r;
  });
  wrap('texSubImage2D', function (f, a) {
    const r = f.apply(this, a);
    const m = tex_meta(this, a[0]);
    if (a.length >= 9) {                              // (target, level, x, y, w, h, fmt, type, src, srcOffset?)
      const src = a[8];
      if (src && typeof src === 'object' && !ArrayBuffer.isView(src)) { const s = prep_source(src); store(m, face_of(a[0]), a[1], a[2], a[3], 0, s.w, s.h, 0, G.RGBA, G.UNSIGNED_BYTE, s.px, true); }
      else if (src && typeof src === 'object') store(m, face_of(a[0]), a[1], a[2], a[3], 0, a[4], a[5], 0, a[6], a[7], prep_view(m, a[4], a[5], a[6], a[7], view_bytes(src, a[9] || 0)), true);
    } else {                                          // (target, level, x, y, fmt, type, source)
      const s = prep_source(a[6]);
      store(m, face_of(a[0]), a[1], a[2], a[3], 0, s.w, s.h, 0, a[4], a[5], s.px, true);
    }
    return r;
  });
  wrap('texImage3D', function (f, a) {
    const r = f.apply(this, a);
    const m = tex_meta(this, a[0]);
    if (a[1] === 0) { m.ifmt = a[2]; m.w = a[3]; m.h = a[4]; m.d = a[5]; }
    if (a[9] && typeof a[9] === 'object') store(m, 0, a[1], 0, 0, 0, a[3], a[4], a[5], a[7], a[8], view_bytes(a[9], a[10] || 0), false);
    return r;
  });
  wrap('texSubImage3D', function (f, a) {
    const r = f.apply(this, a);
    const m = tex_meta(this, a[0]);
    if (a[10] && typeof a[10] === 'object') store(m, 0, a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], view_bytes(a[10], a[11] || 0), true);
    return r;
  });
  const param = function (f, a) { const r = f.apply(this, a); tex_meta(this, a[0]).params[a[1]] = a[2]; return r; };
  wrap('texParameteri', param);
  wrap('texParameterf', param);
  wrap('generateMipmap', function (f, a) {
    const r = f.apply(this, a);
    const m = tex_meta(this, a[0]); m.mip = true;
    if (rec) rec.push({ op: 'mipmap', tex: m.id });
    return r;
  });
  const fbo_meta = (gl, target) => {
    const b = O.getParameter.call(gl, target === G.READ_FRAMEBUFFER ? G.READ_FRAMEBUFFER_BINDING : G.DRAW_FRAMEBUFFER_BINDING);
    const id = idof(b);
    let m = fbos.get(id);
    if (!m) { m = { id, att: {} }; fbos.set(id, m); }
    return m;
  };
  wrap('framebufferTexture2D', function (f, a) {
    const r = f.apply(this, a);
    fbo_meta(this, a[0]).att[a[1]] = { kind: 'tex', id: idof(a[3]), face: face_of(a[2]), level: a[4] };
    return r;
  });
  wrap('framebufferTextureLayer', function (f, a) {
    const r = f.apply(this, a);
    fbo_meta(this, a[0]).att[a[1]] = { kind: 'tex', id: idof(a[2]), level: a[3], layer: a[4] };
    return r;
  });
  wrap('framebufferRenderbuffer', function (f, a) {
    const r = f.apply(this, a);
    fbo_meta(this, a[0]).att[a[1]] = { kind: 'rb', id: idof(a[3]) };
    return r;
  });
  wrap('renderbufferStorage', function (f, a) {
    const r = f.apply(this, a);
    rbos.set(idof(O.getParameter.call(this, G.RENDERBUFFER_BINDING)), { ifmt: a[1], w: a[2], h: a[3], samples: 0 });
    return r;
  });
  wrap('renderbufferStorageMultisample', function (f, a) {
    const r = f.apply(this, a);
    rbos.set(idof(O.getParameter.call(this, G.RENDERBUFFER_BINDING)), { ifmt: a[2], w: a[3], h: a[4], samples: a[1] });
    return r;
  });

  // ---- recording
  const state = (gl) => {
    const g = (q) => O.getParameter.call(gl, q);
    const s = {
      fbo: idof(g(G.DRAW_FRAMEBUFFER_BINDING)), viewport: Array.from(g(G.VIEWPORT)),
      scissor: g(G.SCISSOR_TEST) ? Array.from(g(G.SCISSOR_BOX)) : null,
      blend: g(G.BLEND), bsrc: g(G.BLEND_SRC_RGB), bdst: g(G.BLEND_DST_RGB), bsrca: g(G.BLEND_SRC_ALPHA), bdsta: g(G.BLEND_DST_ALPHA),
      beq: g(G.BLEND_EQUATION_RGB), beqa: g(G.BLEND_EQUATION_ALPHA),
      depth: g(G.DEPTH_TEST), dfunc: g(G.DEPTH_FUNC), dmask: g(G.DEPTH_WRITEMASK),
      cull: g(G.CULL_FACE), cullmode: g(G.CULL_FACE_MODE), front: g(G.FRONT_FACE), cmask: Array.from(g(G.COLOR_WRITEMASK)),
      poly: g(G.POLYGON_OFFSET_FILL) ? [g(G.POLYGON_OFFSET_FACTOR), g(G.POLYGON_OFFSET_UNITS)] : null,
      draw_buffers: g(G.DRAW_BUFFER0),
    };
    return s;
  };
  const uni_cache = new WeakMap();
  const uniforms_of = (gl, prog) => {
    let list = uni_cache.get(prog);
    if (!list) {
      list = [];
      const n = O.getProgramParameter.call(gl, prog, G.ACTIVE_UNIFORMS);
      for (let i = 0; i < n; i++) {
        const info = O.getActiveUniform.call(gl, prog, i);
        const base = info.name.replace(/\[0\]$/, '');
        for (let k = 0; k < info.size; k++) {
          const nm = info.size > 1 ? `${base}[${k}]` : info.name;
          const loc = O.getUniformLocation.call(gl, prog, nm);
          if (loc) list.push({ name: nm, loc, type: info.type });
        }
      }
      uni_cache.set(prog, list);
    }
    const out = {};
    for (const u of list) {
      let v = O.getUniform.call(gl, prog, u.loc);
      // JSON has no Infinity / NaN (three.js's attenuationDistance defaults to Infinity): tag them
      const fin = (x) => (typeof x === 'number' && !Number.isFinite(x) ? String(x) : x);
      if (v && typeof v === 'object' && 'length' in v) v = Array.from(v, fin);
      else v = fin(v);
      out[u.name] = v;
    }
    return { values: out, types: Object.fromEntries(list.map(u => [u.name, u.type])) };
  };
  const SAMPLERS = new Set([G.SAMPLER_2D, G.SAMPLER_3D, G.SAMPLER_CUBE, G.SAMPLER_2D_SHADOW, G.SAMPLER_2D_ARRAY, G.INT_SAMPLER_2D, G.UNSIGNED_INT_SAMPLER_2D]);
  const record_draw = (gl, kind, a) => {
    const prog = O.getParameter.call(gl, G.CURRENT_PROGRAM);
    const pid = idof(prog); objs.set(pid, prog);
    const u = uniforms_of(gl, prog);
    // the texture on each sampler's unit
    const units = {};
    const active = O.getParameter.call(gl, G.ACTIVE_TEXTURE);
    for (const [name, type] of Object.entries(u.types)) {
      if (!SAMPLERS.has(type)) continue;
      const unit = u.values[name];
      O.activeTexture.call(gl, G.TEXTURE0 + unit);
      const q = type === G.SAMPLER_3D ? G.TEXTURE_BINDING_3D : type === G.SAMPLER_CUBE ? G.TEXTURE_BINDING_CUBE_MAP : type === G.SAMPLER_2D_ARRAY ? G.TEXTURE_BINDING_2D_ARRAY : G.TEXTURE_BINDING_2D;
      units[name] = { unit, tex: idof(O.getParameter.call(gl, q)), type };
    }
    O.activeTexture.call(gl, active);
    // attributes
    const attrs = [];
    const na = O.getProgramParameter.call(gl, prog, G.ACTIVE_ATTRIBUTES);
    for (let i = 0; i < na; i++) {
      const info = O.getActiveAttrib.call(gl, prog, i);
      const loc = O.getAttribLocation.call(gl, prog, info.name);
      if (loc < 0) continue;
      const slots = info.type === G.FLOAT_MAT4 ? 4 : info.type === G.FLOAT_MAT3 ? 3 : info.type === G.FLOAT_MAT2 ? 2 : 1;
      for (let s = 0; s < slots; s++) {
        const l = loc + s;
        const on = O.getVertexAttrib.call(gl, l, G.VERTEX_ATTRIB_ARRAY_ENABLED);
        const e = { name: info.name, slot: s, loc: l, gltype: info.type, enabled: on };
        if (on) {
          e.buf = idof(O.getVertexAttrib.call(gl, l, G.VERTEX_ATTRIB_ARRAY_BUFFER_BINDING));
          e.size = O.getVertexAttrib.call(gl, l, G.VERTEX_ATTRIB_ARRAY_SIZE);
          e.type = O.getVertexAttrib.call(gl, l, G.VERTEX_ATTRIB_ARRAY_TYPE);
          e.norm = O.getVertexAttrib.call(gl, l, G.VERTEX_ATTRIB_ARRAY_NORMALIZED);
          e.stride = O.getVertexAttrib.call(gl, l, G.VERTEX_ATTRIB_ARRAY_STRIDE);
          e.offset = O.getVertexAttribOffset.call(gl, l, G.VERTEX_ATTRIB_ARRAY_POINTER);
          e.divisor = O.getVertexAttrib.call(gl, l, G.VERTEX_ATTRIB_ARRAY_DIVISOR);
          e.int = O.getVertexAttrib.call(gl, l, G.VERTEX_ATTRIB_ARRAY_INTEGER);
        } else e.value = Array.from(O.getVertexAttrib.call(gl, l, G.CURRENT_VERTEX_ATTRIB));
        attrs.push(e);
      }
    }
    const d = { op: 'draw', kind, prog: pid, state: state(gl), uniforms: u.values, utypes: u.types, units, attrs };
    if (kind === 'arrays') { d.mode = a[0]; d.first = a[1]; d.count = a[2]; d.instances = a[3] || 0; }
    else { d.mode = a[0]; d.count = a[1]; d.itype = a[2]; d.offset = a[3]; d.instances = a[4] || 0; d.ibuf = idof(O.getParameter.call(gl, G.ELEMENT_ARRAY_BUFFER_BINDING)); }
    rec.push(d);
  };
  wrap('drawArrays', function (f, a) { if (rec) record_draw(this, 'arrays', a); return f.apply(this, a); });
  wrap('drawElements', function (f, a) { if (rec) record_draw(this, 'elements', a); return f.apply(this, a); });
  wrap('drawArraysInstanced', function (f, a) { if (rec) record_draw(this, 'arrays', a); return f.apply(this, a); });
  wrap('drawElementsInstanced', function (f, a) { if (rec) record_draw(this, 'elements', a); return f.apply(this, a); });
  wrap('clear', function (f, a) {
    if (rec) {
      const g = (q) => O.getParameter.call(this, q);
      rec.push({ op: 'clear', mask: a[0], color: Array.from(g(G.COLOR_CLEAR_VALUE)), depth: g(G.DEPTH_CLEAR_VALUE), state: state(this) });
    }
    return f.apply(this, a);
  });
  wrap('blitFramebuffer', function (f, a) {
    if (rec) rec.push({ op: 'blit', read: idof(O.getParameter.call(this, G.READ_FRAMEBUFFER_BINDING)), draw: idof(O.getParameter.call(this, G.DRAW_FRAMEBUFFER_BINDING)), src: a.slice(0, 4), dst: a.slice(4, 8), mask: a[8], filter: a[9] });
    return f.apply(this, a);
  });
  wrap('clearBufferfv', function (f, a) {
    if (rec) rec.push({ op: 'clearbuffer', buffer: a[0], index: a[1], value: Array.from(a[2]), state: state(this) });
    return f.apply(this, a);
  });

  GLCAP.frame = () => { rec = []; return true; };
  GLCAP.stop = () => { const r = rec; rec = null; return r ? r.length : 0; };
  // write the recording and every resource it touches; `programs` maps a WebGLProgram to three.js's id
  GLCAP.export = async (dir, commands, program_ids) => {
    const put = (name, body) => fetch(`/__out/${dir}/${name}`, { method: 'PUT', body });
    const used_buf = new Set(), used_tex = new Set(), used_fbo = new Set(), used_rb = new Set();
    for (const c of commands) {
      if (c.state) used_fbo.add(c.state.fbo);
      if (c.op === 'blit') { used_fbo.add(c.read); used_fbo.add(c.draw); }
      if (c.op === 'mipmap') used_tex.add(c.tex);
      if (c.op !== 'draw') continue;
      for (const a of c.attrs) if (a.enabled) used_buf.add(a.buf);
      if (c.ibuf) used_buf.add(c.ibuf);
      for (const u of Object.values(c.units)) if (u.tex) used_tex.add(u.tex);
    }
    for (const id of used_fbo) { const m = fbos.get(id); if (!m) continue; for (const at of Object.values(m.att)) { if (at.kind === 'tex') used_tex.add(at.id); else used_rb.add(at.id); } }
    const tex_meta_out = {};
    for (const id of used_tex) {
      const m = textures.get(id);
      if (!m) { tex_meta_out[id] = { missing: true }; continue; }
      const { data, faces, ...meta } = m;
      meta.has_data = !!data; meta.has_faces = !!faces;
      tex_meta_out[id] = meta;
      if (data) await put(`tex/${id}.bin`, data);
      if (faces) for (let f = 0; f < 6; f++) if (faces[f]) await put(`tex/${id}_f${f}.bin`, faces[f]);
    }
    const buf_meta = {};
    for (const id of used_buf) { const b = buffers.get(id); buf_meta[id] = { bytes: b ? b.length : -1 }; if (b) await put(`buf/${id}.bin`, b); }
    const fbo_out = {}; for (const id of used_fbo) fbo_out[id] = fbos.get(id) || { att: {} };
    const rb_out = {}; for (const id of used_rb) rb_out[id] = rbos.get(id);
    const prog_out = {}; for (const [id, o] of objs) prog_out[id] = program_ids.get(o) ?? null;
    await put('frame.json', JSON.stringify({ commands, textures: tex_meta_out, buffers: buf_meta, fbos: fbo_out, rbos: rb_out, programs: prog_out }));
    return { commands: commands.length, textures: used_tex.size, buffers: used_buf.size, fbos: used_fbo.size };
  };
  GLCAP.last = null;
  GLCAP.capture = async (dir, render_fn) => {
    rec = [];
    render_fn();
    const commands = rec; rec = null;
    return commands;
  };
  GLCAP.idof = idof;
}
