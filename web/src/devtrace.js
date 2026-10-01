// devtrace.js -- the port to Anchor (2026-09-30): what three.js actually draws, read from the
// running renderer, so the Anchor build can be made to draw the same. Test-only; nothing in the
// game calls it (window.GAME.trace_* in main.js).
//   programs(): every compiled program: id, name, cacheKey, the final GLSL three.js built
//   draws(on): record every draw call of the next render(s): pass (render target), object,
//     material type/name, program id, geometry (vertex count, attributes, index), state
//     (blending, depth test/write, side, transparent), instance count, and every uniform value
//     the program uses, read back from GL after the draw
export function create_devtrace(R) {
  const renderer = R.renderer, gl = renderer.getContext();
  const props = renderer.properties;
  let rec = null;
  const names = new Map();                     // target -> name
  for (const [k, t] of Object.entries(R.targets || {})) names.set(t, k);

  function programs() {
    return renderer.info.programs.map(p => {
      const sh = gl.getAttachedShaders(p.program) || [];
      const src = sh.map(s => ({ type: gl.getShaderParameter(s, gl.SHADER_TYPE) === gl.VERTEX_SHADER ? 'vs' : 'fs', src: gl.getShaderSource(s) }));
      return { id: p.id, name: p.name, cacheKey: p.cacheKey, usedTimes: p.usedTimes, vs: (src.find(x => x.type === 'vs') || {}).src, fs: (src.find(x => x.type === 'fs') || {}).src };
    });
  }

  // uniform values of the bound program, read back from GL
  function uniform_values(glp) {
    const out = {};
    const n = gl.getProgramParameter(glp, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < n; i++) {
      const info = gl.getActiveUniform(glp, i);
      const base = info.name.replace(/\[0\]$/, '');
      const count = info.size;
      for (let k = 0; k < count; k++) {
        const nm = count > 1 ? `${base}[${k}]` : info.name;
        const loc = gl.getUniformLocation(glp, nm);
        if (!loc) continue;
        let v = gl.getUniform(glp, loc);
        if (v && typeof v === 'object' && 'length' in v) v = Array.from(v).map(x => (typeof x === 'number' ? +x.toFixed(6) : x));
        else if (typeof v === 'number') v = +v.toFixed(6);
        out[nm] = v;
      }
    }
    return out;
  }

  const orig = renderer.renderBufferDirect.bind(renderer);
  renderer.renderBufferDirect = function (camera, scene, geometry, material, object, group) {
    const r = orig(camera, scene, geometry, material, object, group);
    if (rec) {
      const mp = props.get(material), prog = mp.currentProgram;
      const tgt = renderer.getRenderTarget();
      const attrs = Object.fromEntries(Object.entries(geometry.attributes).map(([k, a]) => [k, [a.itemSize, a.count, a.isInstancedBufferAttribute ? 'inst' : '']]));
      const d = {
        pass: !scene ? 'shadow' : tgt ? (names.get(tgt) || (tgt.isWebGLCubeRenderTarget ? 'cube' : `rt${tgt.width}x${tgt.height}`)) : 'canvas',
        object: object.name || object.type, obj_type: object.type, parent: object.parent ? (object.parent.name || object.parent.type) : null,
        material: material.type, mat_name: material.name || '', program: prog ? prog.id : null, program_name: prog ? prog.name : null,
        verts: geometry.index ? geometry.index.count : (geometry.attributes.position ? geometry.attributes.position.count : 0), indexed: !!geometry.index,
        draw_range: [geometry.drawRange.start, geometry.drawRange.count], group: group ? [group.start, group.count] : null,
        instances: object.isInstancedMesh ? object.count : (geometry.isInstancedBufferGeometry ? geometry.instanceCount : 1),
        attrs, blending: material.blending, blend: [material.blendSrc, material.blendDst, material.blendEquation], depthTest: material.depthTest, depthWrite: material.depthWrite,
        side: material.side, transparent: material.transparent, colorWrite: material.colorWrite, visible: object.visible,
      };
      if (rec.uniforms && prog) d.uniforms = uniform_values(prog.program);
      rec.list.push(d);
    }
    return r;
  };

  return {
    programs,
    // start recording draws; uniforms = also read every uniform (slow, big)
    start(uniforms = false) { rec = { list: [], uniforms }; return true; },
    stop() { const l = rec ? rec.list : []; rec = null; return l; },
    info() { return { calls: renderer.info.render.calls, triangles: renderer.info.render.triangles, programs: renderer.info.programs.length, geometries: renderer.info.memory.geometries, textures: renderer.info.memory.textures }; },
  };
}

// the port to Anchor: which compiled program each draw used, keyed the way the Anchor renderer
// looks programs up (port/three/renderer.lua): material.name|scene.name|side|instanced, and for
// the shadow pass depth|side|instanced. Collect over a whole session (every power, the inspect
// view, the ending), then program_map() -> { keys: key -> cacheKey, programs: cacheKey -> {vs, fs},
// conflicts: keys seen with more than one program, unnamed: materials without a name }
export function create_program_map(R) {
  const renderer = R.renderer, gl = renderer.getContext(), props = renderer.properties;
  const keys = new Map(), progs = new Map(), conflicts = new Map(), unnamed = new Map();
  const orig = renderer.renderBufferDirect.bind(renderer);
  renderer.renderBufferDirect = function (camera, scene, geometry, material, object, group) {
    const r = orig(camera, scene, geometry, material, object, group);
    const prog = props.get(material).currentProgram;
    if (!prog) return r;
    const inst = object.isInstancedMesh ? 'i' : '-';
    const key = !scene ? `depth|${material.side}|${inst}` : `${material.name || ('?' + material.type)}|${scene.name || '?'}|${material.side}|${inst}`;
    if (!material.name && scene) unnamed.set(key, (object.name || object.type) + ' in ' + (scene.name || '?'));
    const ck = prog.cacheKey;
    if (!progs.has(ck)) {
      const sh = gl.getAttachedShaders(prog.program) || [];
      const src = {};
      for (const s of sh) src[gl.getShaderParameter(s, gl.SHADER_TYPE) === gl.VERTEX_SHADER ? 'vs' : 'fs'] = gl.getShaderSource(s);
      progs.set(ck, src);
    }
    if (keys.has(key) && keys.get(key) !== ck) { if (!conflicts.has(key)) conflicts.set(key, new Set([keys.get(key)])); conflicts.get(key).add(ck); }
    keys.set(key, ck);
    return r;
  };
  return {
    result: () => ({ keys: Object.fromEntries(keys), programs: Object.fromEntries(progs),
      conflicts: Object.fromEntries([...conflicts].map(([k, v]) => [k, [...v]])), unnamed: Object.fromEntries(unnamed) }),
  };
}
