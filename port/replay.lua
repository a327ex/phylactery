--[[
  replay.lua -- the port to Anchor (2026-09-30): replays one frame captured from the three.js
  build (web/src/glcapture.js -> tools/glcap_to_lua.py) on the engine's gpu layer, with three.js's
  own programs, buffers, textures, targets, uniform values and state. If the frame it draws is
  three.js's frame, the gpu layer and the programs are proven; the Lua renderer is then checked
  by producing the same command stream itself.

  glcap_replay(dir) -> summary; writes <dir>/anchor_final_rgba8.bin and anchor_world_f32.bin
]]

local GL = {
  -- blend factors
  [0] = 'zero', [1] = 'one', [0x300] = 'src_color', [0x301] = 'one_minus_src_color', [0x302] = 'src_alpha',
  [0x303] = 'one_minus_src_alpha', [0x304] = 'dst_alpha', [0x305] = 'one_minus_dst_alpha', [0x306] = 'dst_color',
  [0x307] = 'one_minus_dst_color', [0x308] = 'src_alpha_saturate',
}
local EQ = { [0x8006] = 'add', [0x800A] = 'subtract', [0x800B] = 'reverse_subtract', [0x8007] = 'min', [0x8008] = 'max' }
local DEPTH = { [0x200] = 'never', [0x201] = 'less', [0x202] = 'equal', [0x203] = 'lequal', [0x204] = 'greater',
  [0x205] = 'notequal', [0x206] = 'gequal', [0x207] = 'always' }
local MODE = { [0] = 'points', [1] = 'lines', [2] = 'line_loop', [3] = 'line_strip', [4] = 'triangles', [5] = 'triangle_strip' }
local FILTER = { [9728] = 'nearest', [9729] = 'linear', [9984] = 'nearest_mipmap_nearest', [9985] = 'linear_mipmap_nearest',
  [9986] = 'nearest_mipmap_linear', [9987] = 'linear_mipmap_linear' }
local WRAP = { [33071] = 'clamp', [10497] = 'repeat', [33648] = 'mirror' }
local IFMT = { [32856] = 'rgba8', [35907] = 'srgba8', [34842] = 'rgba16f', [34836] = 'rgba32f', [33190] = 'depth24',
  [34843] = 'rgb16f', [33327] = 'rg16f', [33325] = 'r16f', [33326] = 'r32f', [33321] = 'r8' }
local COLOR_ATT, DEPTH_ATT = '36064', '36096'

function glcap_replay(dir)
  local F = load(file_read_string(dir .. '/frame.lua'))()
  local S = { prog = {}, tex = {}, tgt = {}, mesh = {}, buf = {} }
  local function bin(path) local s = file_read_string(path); assert(s, 'missing ' .. path); return s end
  -- programs, by the capture's id -> three.js program id -> its GLSL
  for gid, tid in pairs(F.programs) do
    local vs = bin(dir .. '/programs/' .. tid .. '_vs.glsl')
    local fs = bin(dir .. '/programs/' .. tid .. '_fs.glsl')
    S.prog[tonumber(gid)] = gpu_program(vs, fs, 'three_' .. tid)
  end
  -- targets (each framebuffer) and the textures attached to them
  local function tex_opts(m)
    local p = m.params or {}
    return { format = IFMT[m.ifmt] or 'rgba8', min = FILTER[p['10241']] or 'nearest', mag = FILTER[p['10240']] or 'nearest',
      wrap_s = WRAP[p['10242']] or 'clamp', wrap_t = WRAP[p['10243']] or 'clamp', wrap_r = WRAP[p['32882']] or 'clamp' }
  end
  for fid, fb in pairs(F.fbos) do
    local id = tonumber(fid)
    local c, d = fb.att[COLOR_ATT], fb.att[DEPTH_ATT]
    if id == 0 then
      S.tgt[0] = gpu_target(640, 360, { color = 'rgba8', depth = 'buffer' })
    elseif c and c.kind == 'rb' then
      local rb = F.rbos[tostring(c.id)]
      S.tgt[id] = gpu_target(rb.w, rb.h, { samples = rb.samples, color = IFMT[rb.ifmt] or 'rgba16f', depth = d ~= nil })
    elseif c then
      local m = F.textures[tostring(c.id)]
      local o = tex_opts(m)
      local t = gpu_target(m.w, m.h, { color = o.format, min = o.min, mag = o.mag, wrap = o.wrap_s,
        depth = d and (d.kind == 'tex' and 'texture' or 'buffer') or false })
      S.tgt[id] = t
      S.tex[c.id] = gpu_target_color(t)
      if d and d.kind == 'tex' then S.tex[d.id] = gpu_target_depth(t) end
    end
  end
  -- uploaded textures
  local n_tex = 0
  for tid, m in pairs(F.textures) do
    local id = tonumber(tid)
    if not S.tex[id] and m.has_data then
      local o = tex_opts(m)
      o.data = bin(dir .. '/tex/' .. tid .. '.bin')
      if (m.d or 0) > 0 then S.tex[id] = gpu_texture_3d(m.w, m.h, m.d, o)
      else S.tex[id] = gpu_texture(m.w, m.h, o) end
      n_tex = n_tex + 1
    end
  end
  -- meshes: one per distinct set of buffers a draw reads
  local function buffer(id)
    if not S.buf[id] then S.buf[id] = bin(dir .. '/buf/' .. id .. '.bin') end
    return S.buf[id]
  end
  local function mesh_for(d)
    local key = {}
    for _, a in ipairs(d.attrs) do if a.enabled and a.slot == 0 then key[#key + 1] = a.name .. '=' .. a.buf .. '/' .. a.divisor end end
    key[#key + 1] = 'i' .. tostring(d.ibuf or 0)
    local k = table.concat(key, ',')
    if S.mesh[k] then return S.mesh[k] end
    local m = gpu_mesh()
    for _, a in ipairs(d.attrs) do
      if a.enabled and a.slot == 0 then
        assert(a.type == 5126 and (a.offset == 0) and (a.stride == 0 or a.stride == a.size*4 or a.gltype == 35676),
          'attribute layout the replay does not handle: ' .. a.name)
        local comps = a.gltype == 35676 and 16 or a.size        -- FLOAT_MAT4
        gpu_mesh_attr(m, a.name, comps, buffer(a.buf), a.divisor)
      end
    end
    if d.ibuf and d.ibuf ~= 0 then gpu_mesh_index(m, buffer(d.ibuf), d.itype == 5123 and 16 or 32) end
    S.mesh[k] = m
    return m
  end
  -- run
  local counts = { draw = 0, clear = 0, blit = 0, mipmap = 0, skipped = 0 }
  local function bind(st)
    local t = S.tgt[st.fbo]
    gpu_bind(t)
    local v = st.viewport
    gpu_viewport(v[1], v[2], v[3], v[4])
  end
  for _, c in ipairs(F.commands) do
    if c.op == 'clear' then
      bind(c.state)
      local color = (c.mask & 0x4000) ~= 0
      local depth = (c.mask & 0x100) ~= 0
      if color then gpu_clear(c.color[1], c.color[2], c.color[3], c.color[4], depth and c.depth or false)
      elseif depth then gpu_clear(nil, nil, nil, nil, c.depth) end
      counts.clear = counts.clear + 1
    elseif c.op == 'blit' then
      gpu_blit(S.tgt[c.read], S.tgt[c.draw], c.filter == 9729 and 'linear' or 'nearest')
      counts.blit = counts.blit + 1
    elseif c.op == 'mipmap' then
      if S.tex[c.tex] then gpu_texture_mipmaps(S.tex[c.tex]) end
      counts.mipmap = counts.mipmap + 1
    elseif c.op == 'draw' then
      local p = S.prog[c.prog]
      bind(c.state)
      for name, v in pairs(c.uniforms) do
        local u = c.units[name]
        if u then gpu_set(p, name, u.tex ~= 0 and S.tex[u.tex] or nil)
        else gpu_set(p, name, v) end
      end
      local st = c.state
      local o = { mode = MODE[c.mode], instances = c.instances, color_write = st.cmask[1],
        depth_test = st.depth, depth_write = st.dmask, depth_func = DEPTH[st.dfunc],
        cull = st.cull and (st.cullmode == 0x404 and 'front' or 'back') or 'none', front = st.front == 0x900 and 'cw' or 'ccw' }
      if st.blend then
        o.blend = true
        o.blend_src, o.blend_dst, o.blend_src_alpha, o.blend_dst_alpha = GL[st.bsrc], GL[st.bdst], GL[st.bsrca], GL[st.bdsta]
        o.blend_eq, o.blend_eq_alpha = EQ[st.beq], EQ[st.beqa]
      end
      if st.poly then o.polygon_offset = st.poly end
      if c.kind == 'arrays' then o.first, o.count = c.first, c.count
      else o.first, o.count = c.offset//(c.itype == 5123 and 2 or 4), c.count end
      gpu_draw(p, mesh_for(c), o)
      counts.draw = counts.draw + 1
    end
  end
  -- what it drew: the final frame (the 8-bit target three.js reads back as rt_final) and the world
  local final_id, world_id
  for fid, fb in pairs(F.fbos) do
    local c = fb.att[COLOR_ATT]
    if c and c.kind == 'tex' then
      local m = F.textures[tostring(c.id)]
      if m.ifmt == 32856 and m.w == 640 and m.h == 360 and (m.params or {})['10241'] == 9729 then final_id = tonumber(fid) end
      if m.ifmt == 34842 and m.w == 640 and m.h == 360 and fb.att[DEPTH_ATT] and fb.att[DEPTH_ATT].kind == 'tex' then world_id = tonumber(fid) end
    end
  end
  if final_id then file_write_string(dir .. '/anchor_final_rgba8.bin', gpu_read(S.tgt[final_id], 0, 0, 640, 360, 'rgba8')) end
  if world_id then file_write_string(dir .. '/anchor_world_f32.bin', gpu_read(S.tgt[world_id], 0, 0, 640, 360, 'float')) end
  gpu_end()
  GLCAP_LAST = S              -- (debugging: the replay's resources)
  counts.textures = n_tex
  counts.final = final_id
  counts.world = world_id
  return counts
end
