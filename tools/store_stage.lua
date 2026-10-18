--[[
  store_stage.lua -- stage one store-art composition in the game and read the finished frame back (Phylactery 20,
  2026-10-18; round 95's scratch staging made general). Capture only: it stops the recording first.

  Run in an agent instance (LICH_RENDER_SCALE=n for size, LICH_SEED=<n> so spasms and drops repeat):
    anchor drive eval . 'OUT="<folder>"; SPEC={...}; return dofile("tools/store_stage.lua")'
  Writes <OUT>/<SPEC.name>.rgba (+ _black / _lich layers with SPEC.layers): rgba8, GL rows bottom-up
  (rounds/95-finish-test/source/rgba2png.py turns them into PNGs).

  SPEC = {
    name = 'a02',
    pose = 'idle' | 'hurt',        hand = 0 (open, clawed) | 1 (pointing),  hold = ticks after the pose (180),
    bow = { neck = rad, head = rad, chest = rad },   -- an extra forward bend, laid over the pose (his head bowed)
    mask = 'held' (in front of his face, as in the game) | 'lift' (lift = m off the face) | 'none',
    mask_geo = 'identity/mask/avatar', -- his mask replaced by the burned mask's model built clean (tools/mask/build_clean.mjs)
    only = 'mask' | 'items',       -- nothing but his mask (cam at = 'mask') / the placed objects (cam at = 'item'): to fit them onto a painting
    lich = true | false,           -- false: he is not in the picture
    cave = true | false,           -- false: a flat field (field = {r, g, b} linear), the sun as a key light (key = {yaw, elevation})
    drop = { 0, 1, ... },          -- objects discarded from his hand (they land where they fall), in this order
    items = { { i = 5, at = 'halo', up = 0.3, scale = 1, rot = { x, y, z } } },   -- an object placed by hand (radians)
    cam = { at = 'chest' | 'head' | 'hand0' | 'hand1' | 'egg' | 'items' | {x, y, z}, yaw = deg (from the way he faces),
            dist, up, fov, look_up },
    layers = true,                 -- also the same instant on black, and without the mask
  }
]]
record_stop()
local G = GAME.G
local TM = require('port.three.math')
local Vector3, Quaternion, Color, Euler = TM.Vector3, TM.Quaternion, TM.Color, TM.Euler
local R, lich, M, cave, items = G.R, G.lich, G.lmask, G.cave, G.items
local S = SPEC
local P = R.params

GAME.set_manual(true)
GAME.hud(false)
if not STAGE_READY then                           -- (several compositions in one instance: idle ones, then hurt, then drops)
  GAME.begin()
  GAME.step(60*9)                                 -- his walk in and the hover settling
  STAGE_READY = true
end
GAME.hud(false)                                   -- (after the walk-in: it turns the HUD on)
if S.pose == 'hurt' then GAME.hand(S.hand or 0); GAME.hurt(1.0) end
for _, i in ipairs(S.drop or {}) do GAME.drop(i); GAME.step(50) end
GAME.step(S.hold or 180)
if S.move then                                     -- (him moving: sent dx, dz metres from where he is, caught after `ticks`)
  local st = GAME.state()
  GAME.step(S.move[3], { ['goto'] = { st.lich[1] + S.move[1], st.lich[3] + S.move[2] } })
end

-- (the store art's mask: the burned mask's own model built clean by tools/mask/build_clean.mjs, worn as his)
if S.mask_geo and not MASK_SWAPPED then
  local T3 = require('port.three.core')
  local g = T3.BufferGeometry.new()
  g.name = 'store.mask'
  for _, at in ipairs({ { 'position', 3 }, { 'normal', 3 }, { 'color', 3 }, { 'aMR', 2 } }) do
    g:set_attribute(at[1], T3.BufferAttribute.from_blob(assert(file_read_string(S.mask_geo .. '/mask.' .. at[1] .. '.f32')), at[2]))
  end
  local ia = T3.BufferAttribute.from_blob(assert(file_read_string(S.mask_geo .. '/mask.index.u32')), 1)
  ia.is_index = true
  g:set_index(ia)
  local bs = file_read_string(S.mask_geo .. '/mask.json'):match('"bs":%[([^%]]+)%]')
  local b = {}
  for v in bs:gmatch('[^,]+') do b[#b + 1] = tonumber(v) end
  g.bounding_sphere = { center = Vector3.new(b[1], b[2], b[3]), radius = b[4] }
  M.mesh.geometry = g
  M.mesh.frustum_culled = false
  M.mesh.scale:set_scalar(0.95)                    -- (lichmask builds its shell at 0.95 of the measures)
  MASK_SWAPPED = S.mask_geo
end
local cave_root = cave.egg.parent
local keep = {}
local function under(o, roots)
  while o do if roots[o] then return true end; o = o.parent end
  return false
end
if S.only == 'mask' then keep[M.mesh] = true                -- (his mask alone: to fit it onto a painting)
elseif S.only == 'dropped' then                             -- (the dropped objects alone, where they lie / were gathered)
  for _, i in ipairs(S.drop_kept or {}) do keep[items.W[i + 1].g] = true end
elseif S.only == 'items' then                               -- (the placed objects alone: S.items)
  for _, it in ipairs(S.items or {}) do keep[items.W[it.i + 1].g] = true end
elseif S.lich ~= false then keep[lich.root] = true; if S.mask ~= 'none' then keep[M.mesh] = true end end
if S.cave ~= false then keep[cave_root] = true end
if not S.objects_hidden then for _, i in ipairs(S.drop or {}) do keep[items.W[i + 1].g] = true end end
for _, it in ipairs(S.items or {}) do keep[items.W[it.i + 1].g] = true end

P.hud = 0                                          -- (the inventory's icons: the final pass's HUD strength)
local SUN
cave_root:traverse(function(o) if o.is_light and o.target and not SUN then SUN = o end end)
if S.exposure then P.exposure = S.exposure end            -- (the cave's darkness preset brightens: his mask alone wants less)
if S.cave == false then
  P.shafts.on = false
  P.fog.max = 0
  P.vignette = 0
  R.world_scene.background = Color.new(S.field[1], S.field[2], S.field[3])
end

local V = Vector3.new
local function wpos(node) node:update_world_matrix(true, false); return node:get_world_position(V()) end
local function target_of(at)
  if type(at) == 'table' then return V(at[1], at[2], at[3]) end
  if at == 'head' then return wpos(lich.nodes.head) end
  if at == 'item' then                                      -- (where the first of S.items is placed)
    local it = S.items[1]
    if it.at == 'halo' then local h = wpos(lich.nodes.head); return V(h.x + (it.dx or 0), h.y + (it.up or 0.3), h.z + (it.dz or 0)) end
    return V(it.at[1], it.at[2], it.at[3])
  end
  if at == 'mask' then M.snap(); M.mesh:update_world_matrix(true, false); return M.mesh:get_world_position(V()) end
  if at == 'hand0' or at == 'hand1' then return lich.fingertip(at == 'hand0' and 0 or 1) end
  if at == 'egg' then local e = wpos(cave.egg); e.y = e.y + 0.4; return e end
  if at == 'gather' then
    local g = S.gather
    local cx, cz
    if g.at == 'egg' then local e = wpos(cave.egg); cx, cz = e.x + (g.dx or 0), e.z + (g.dz or 0) else cx, cz = g.at[1], g.at[2] end
    return V(cx, cave.ground_y(cx, cz) + (g.h or 0.25), cz)
  end
  if at == 'items' then
    local c, n = V(), 0
    for _, i in ipairs(S.drop or {}) do c:add(items.W[i + 1].g.position); n = n + 1 end
    return c:multiply_scalar(1/math.max(1, n))
  end
  return wpos(lich.nodes.chest)
end

local function pose_over()
  -- his head bowed (an extra bend on top of the game's pose), then the mask put where the head would hold it
  local b = S.bow
  if b then
    for _, k in ipairs({ 'chest', 'neck', 'head' }) do
      if b[k] and b[k] ~= 0 then lich.nodes[k].quaternion:multiply(Quaternion.new():set_from_axis_angle(V(1, 0, 0), b[k])) end
    end
    lich.root:update_world_matrix(true, true)
  end
  if S.mask == 'lift' then
    local head = lich.nodes.head
    head:update_world_matrix(true, false)
    local p = V(0, 0.03 + (S.lift or 0.3)*0.35, 0.183 + (S.lift or 0.3)):apply_matrix4(head.matrix_world)
    M.mesh.position:copy(p)
  elseif S.mask ~= 'none' then
    M.snap()                                       -- held in front of his face, as the game holds it, no lag
  end
  -- the dropped objects gathered into a still life where they lie (each keeps its resting pose; moved over the
  -- floor, turned about the vertical): gather = { at = 'egg' | {x, z}, off = { [i] = { dx, dz, turn } } }
  if S.gather then
    local g = S.gather
    local cx, cz
    if g.at == 'egg' then local e = wpos(cave.egg); cx, cz = e.x + (g.dx or 0), e.z + (g.dz or 0) else cx, cz = g.at[1], g.at[2] end
    for i, o in pairs(g.off) do
      local w = items.W[i + 1]
      local nx, nz = cx + o[1], cz + o[2]
      if w.orbs then
        -- the orbs lie where each ball fell (the meshes in the world, their group at the origin): a small cluster here
        for k, m in ipairs(w.orbs) do
          local a, rr = k*2.4, 0.06 + 0.05*k
          local ox, oz = nx + math.cos(a)*rr, nz + math.sin(a)*rr
          m.position:set(ox, cave.ground_y(ox, oz) + (m.user_data.r or m.scale.x), oz)
        end
      else
        local p = w.g.position
        local lift = p.y - cave.ground_y(p.x, p.z)
        p:set(nx, cave.ground_y(nx, nz) + lift, nz)
        if o[3] then w.g.quaternion:premultiply(Quaternion.new():set_from_axis_angle(V(0, 1, 0), o[3])) end
      end
    end
  end
  for _, it in ipairs(S.items or {}) do
    local w = items.W[it.i + 1]
    w.g.visible = true
    if it.at == 'halo' then
      local h = wpos(lich.nodes.head)
      w.g.position:set(h.x + (it.dx or 0), h.y + (it.up or 0.3), h.z + (it.dz or 0))
    elseif type(it.at) == 'table' then
      w.g.position:set(it.at[1], it.at[2], it.at[3])
    end
    if it.rot then w.g.quaternion:set_from_euler(Euler.new(it.rot[1], it.rot[2], it.rot[3])) end
    if it.scale then w.g.scale:set_scalar(it.scale) end
  end
end

local function hide_rest()
  R.world_scene:traverse(function(o)
    if o.is_mesh or o.is_points then o.visible = under(o, keep) end
  end)
  R.warp_scene:traverse(function(o) if o.is_mesh or o.is_points then o.visible = false end end)
end

local c = S.cam
local tgt = target_of(c.at or 'chest')
local face = GAME.state().yaw
local a = (c.abs and 0 or face) + math.rad(c.yaw or 0)       -- (cam.abs: yaw in the world, not from his facing)
local eye = { tgt.x + math.sin(a)*c.dist, tgt.y + (c.up or 0), tgt.z + math.cos(a)*c.dist }
GAME.look(eye, { tgt.x, tgt.y + (c.look_up or 0), tgt.z }, c.fov or 40)
GAME.step(1)
pose_over()
hide_rest()
if S.cave == false and S.key and SUN then
  local ch = target_of('chest')
  local ka = math.atan(eye[1] - ch.x, eye[3] - ch.z) + math.rad(S.key[1])
  local el = math.rad(S.key[2])
  SUN.position:set(ch.x + math.sin(ka)*math.cos(el)*10, ch.y + math.sin(el)*10, ch.z + math.cos(ka)*math.cos(el)*10)
  SUN.target.position:copy(ch)
  SUN.target:update_world_matrix(true, false)
end

engine_step(1)                                     -- (a warm-up frame: the first after a new camera lags one frame)
local passes = { { '', S.field } }
if S.layers then passes[2] = { '_black', { 0, 0, 0 } }; passes[3] = { '_lich', { 0, 0, 0 }, true } end
for _, ps in ipairs(passes) do
  if ps[2] then R.world_scene.background = Color.new(ps[2][1], ps[2][2], ps[2][3]) end
  if ps[3] then M.mesh.visible = false end
  engine_step(1)
  local rt = R.out
  file_write_string(string.format('%s/%s%s.rgba', OUT, S.name, ps[1]), gpu_read(rt.gpu, 0, 0, R.W, R.H, 'rgba8'))
  M.mesh.visible = keep[M.mesh] == true
end
GAME.set_manual(false)
return S.name .. ' ' .. R.W .. 'x' .. R.H
