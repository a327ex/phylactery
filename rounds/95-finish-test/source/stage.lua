-- (2026-10-18, Phylactery 20) round 95's staging: the A02 composition (Queen Bee "Kirei": one figure arched back on a
-- flat field, something leaving the head). The lich in his hurt pose, everything but him and his mask hidden, the field
-- a flat colour, the mask lifted off his face along its own axis, a free camera; the finished frame read back from the
-- GPU (run with LICH_RENDER_SCALE for size). Capture only: record_stop() first.
-- Globals set by the eval: OUT (folder), SHOTS = { {name, yaw, dist, up, fov, look_up, tick}, ... }, LIFT (m off the
-- face), FIELD = {r,g,b} (linear), SCALE (the render scale it was started with)
record_stop()
local G = GAME.G
local TM = require('port.three.math')
local Vector3, Quaternion, Color = TM.Vector3, TM.Quaternion, TM.Color
local R, lich, M = G.R, G.lich, G.lmask

GAME.set_manual(true)
GAME.begin()
GAME.step(60*9)                 -- his walk in (~6 s) and the hover settling
GAME.hand(0)                    -- OPEN, CLAWED (the image)
GAME.hurt(1.0)                  -- the hurt pose at full strength (the ending's, without snakes)
GAME.hud(false)
GAME.step(HOLD or 180)          -- the arch develops (its level eases in over ~1 s)

-- the field: no cave, no shaft, no fog, no vignette
local P = R.params
P.shafts.on = false
P.fog.max = 0
P.vignette = 0
R.world_scene.background = Color.new(FIELD[1], FIELD[2], FIELD[3])

local function under(o, root)
  while o do if o == root then return true end; o = o.parent end
  return false
end
local function stage()
  R.world_scene:traverse(function(o)
    if (o.is_mesh or o.is_points) then o.visible = under(o, lich.root) or o == M.mesh end
  end)
  if R.warp_scene then R.warp_scene:traverse(function(o) if o.is_mesh or o.is_points then o.visible = false end end) end
  -- the mask lifted off the face, along the face's own axis (the head's +z), turned a little
  local head = lich.nodes.head
  head:update_world_matrix(true, false)
  local p = Vector3.new(0, 0.03 + LIFT*0.35, 0.183 + LIFT):apply_matrix4(head.matrix_world)
  local tp, tq, ts = Vector3.new(), Quaternion.new(), Vector3.new()
  head.matrix_world:decompose(tp, tq, ts)
  M.mesh.position:copy(p)
  if EYE then
    -- its face turned toward the camera (MASK_TURN of the way from the face's own axis), so it reads as a mask
    local fwd = Vector3.new(0, 0, 1):apply_quaternion(tq)
    local to = Vector3.new(EYE[1] - p.x, EYE[2] - p.y, EYE[3] - p.z):normalize()
    local dir = fwd:clone():lerp(to, MASK_TURN or 0.7):normalize()
    M.mesh.quaternion:set_from_unit_vectors(Vector3.new(0, 0, 1), dir)
  else
    M.mesh.quaternion:copy(tq)
  end
  -- the key light: the sun moved to the camera's side, high (KEY = { yaw from the camera, elevation }, degrees)
  if KEY and SUN then
    local c = lich.nodes.chest:get_world_position(Vector3.new())
    local a = math.atan(EYE[1] - c.x, EYE[3] - c.z) + math.rad(KEY[1])
    local el = math.rad(KEY[2])
    SUN.position:set(c.x + math.sin(a)*math.cos(el)*10, c.y + math.sin(el)*10, c.z + math.cos(a)*math.cos(el)*10)
    SUN.target.position:copy(c)
    SUN.target:update_world_matrix(true, false)
  end
end
R.world_scene:traverse(function(o) if o.is_light and o.target and not SUN then SUN = o end end)

local function camera(yaw_deg, dist, up, fov, look_up)
  -- around his chest: yaw measured from the way he faces
  local c = lich.nodes.chest
  c:update_world_matrix(true, false)
  local cp = c:get_world_position(Vector3.new())
  local face = GAME.state().yaw
  local a = face + math.rad(yaw_deg)
  local eye = { cp.x + math.sin(a)*dist, cp.y + up, cp.z + math.cos(a)*dist }
  EYE = eye
  GAME.look(eye, { cp.x, cp.y + look_up, cp.z }, fov)
end

local done = {}
local t0 = 0
for _, s in ipairs(SHOTS) do
  local name, yaw, dist, up, fov, look_up, ticks = s[1], s[2], s[3], s[4], s[5], s[6], s[7]
  if ticks and ticks > 0 then GAME.step(ticks) end
  camera(yaw, dist, up, fov, look_up)
  GAME.step(1)
  stage()
  -- the frame on the field, then (LAYERS) the same instant on black: everything, and the lich without his mask, for
  -- masks in the finishing passes
  local passes = { { '', FIELD, true } }
  if LAYERS then passes[2] = { '_black', { 0, 0, 0 }, true }; passes[3] = { '_lich', { 0, 0, 0 }, false } end
  for _, ps in ipairs(passes) do
    R.world_scene.background = Color.new(ps[2][1], ps[2][2], ps[2][3])
    M.mesh.visible = ps[3]
    engine_step(1)
    local rt = R.out
    file_write_string(string.format('%s/%s%s.rgba', OUT, name, ps[1]), gpu_read(rt.gpu or rt.texture.gpu, 0, 0, R.W, R.H, 'rgba8'))
  end
  M.mesh.visible = true
  done[#done + 1] = name .. ' ' .. R.W .. 'x' .. R.H
end
GAME.set_manual(false)
return table.concat(done, ', ')
