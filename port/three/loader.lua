--[[
  three/loader.lua -- the port to Anchor: what the three.js build exported (assets/port/<group>.lua +
  assets/port/<group>/), as three objects: geometry(name) -> BufferGeometry (static attributes kept
  as their float32 bytes), texture(name) -> Texture (on the GPU, sampled as three.js sampled it).
]]
local T = require('port.three.core')
local LD = {}

local function read(path) local s = file_read_string(path); assert(s, 'port asset missing: ' .. path); return s end

function LD.group(name)
  local m = require('assets.port.' .. name)
  local G = { manifest = m, geometries = {}, textures = {} }
  function G.geometry(gname)
    if G.geometries[gname] then return G.geometries[gname] end
    local meta = assert(m.geometries[gname], 'no geometry ' .. gname .. ' in ' .. name)
    local g = T.BufferGeometry.new()
    g.name = gname
    for _, attr in ipairs(meta.order) do
      local a = meta.attrs[attr]
      g:set_attribute(attr, T.BufferAttribute.from_blob(read(m.dir .. '/geo/' .. gname .. '.' .. attr .. '.f32'), a.size))
    end
    if meta.index then
      local ia = T.BufferAttribute.from_blob(read(m.dir .. '/geo/' .. gname .. '.index.u32'), 1)
      ia.is_index = true
      g:set_index(ia)
    end
    local bs = meta.bs
    if bs then g.bounding_sphere = { center = require('port.three.math').Vector3.new(bs[1], bs[2], bs[3]), radius = bs[4] } end
    if meta.draw_range and meta.draw_range[2] >= 0 then g:set_draw_range(meta.draw_range[1], meta.draw_range[2]) end
    for _, gr in ipairs(meta.groups or {}) do g:add_group(gr[1], gr[2], gr[3]) end
    G.geometries[gname] = g
    return g
  end
  -- an attribute file beside a geometry's own (e.g. the hand's colour variants: <geo>.color_1.f32)
  function G.attribute(gname, attr, size)
    return T.BufferAttribute.from_blob(read(m.dir .. '/geo/' .. gname .. '.' .. attr .. '.f32'), size)
  end
  function G.texture(tname)
    if G.textures[tname] then return G.textures[tname] end
    local meta = assert(m.textures[tname], 'no texture ' .. tname .. ' in ' .. name)
    local gpu
    if meta.kind == 'rgba8' then
      gpu = gpu_texture(meta.w, meta.h, { format = meta.srgb and 'srgba8' or 'rgba8', min = meta.min, mag = meta.mag,
        wrap_s = meta.wrap_s, wrap_t = meta.wrap_t, anisotropy = meta.anisotropy, data = read(m.dir .. '/tex/' .. tname .. '.rgba') })
    elseif meta.kind == 'cube_f32' or meta.kind == 'cube_rgba8' then
      -- a cube render target, read back face by face (half floats, exact in rgba16f)
      local faces = {}
      local ext = meta.kind == 'cube_f32' and '.f32' or '.rgba'
      for k = 0, 5 do faces[k + 1] = read(m.dir .. '/tex/' .. tname .. '.face' .. k .. ext) end
      gpu = gpu_texture_cube(meta.w, { format = meta.kind == 'cube_f32' and 'rgba16f' or 'rgba8', min = meta.min, mag = meta.mag, faces = faces })
    elseif meta.kind == 'f32_3d' then
      gpu = gpu_texture_3d(meta.w, meta.h, meta.d, { format = 'rgba32f', min = meta.min, mag = meta.mag,
        wrap_s = meta.wrap_s, wrap_t = meta.wrap_t, wrap_r = meta.wrap_r, data = read(m.dir .. '/tex/' .. tname .. '.f32') })
    elseif meta.kind == 'f32' then
      gpu = gpu_texture(meta.w, meta.h, { format = meta.half and 'rgba16f' or 'rgba32f', min = meta.min, mag = meta.mag,
        wrap_s = meta.wrap_s, wrap_t = meta.wrap_t, data = read(m.dir .. '/tex/' .. tname .. '.f32') })
    end
    local t = T.Texture.new(gpu, meta.w, meta.h)
    t.name = tname
    if meta.kind == 'cube_f32' or meta.kind == 'cube_rgba8' then t.is_cube_render_target = true end
    t.color_space = meta.srgb and 'srgb' or 'linear'
    if meta.offset then t.offset:set(meta.offset[1], meta.offset[2]); t.repeat_:set(meta['repeat'][1], meta['repeat'][2]) end
    G.textures[tname] = t
    return t
  end
  return G
end

return LD
