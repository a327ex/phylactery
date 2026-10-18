--[[
  store_t01.lua -- his T01 (the Orphic egg): one serpent coiled round the egg (Phylactery 20, 2026-10-18). Capture only.
  Run the instance with LICH_START=ENDING (every power given up, the snakes gathering on the egg).

    anchor drive eval . 'OUT="<folder>"; T01={ after = {20, 60, 120}, yaw = 0, dist = 1.6, up = 0.5, fov = 38, look_up = 0.35 }; return dofile("tools/store_t01.lua")'

  Steps until the first snake has coiled (snakes.coiled), then reads frames `after` ticks later, the camera on the egg
  (yaw in the world). Writes <OUT>/t01_a<after>.rgba (GL rows bottom-up).
]]
record_stop()
local G = GAME.G
local R = G.R
GAME.set_manual(true)
GAME.hud(false)
R.params.hud = 0
local A = T01 or {}
local n = 0
while #G.snakes.coiled < (A.coiled or 1) and n < 60*60 do GAME.step(5); n = n + 5 end
assert(#G.snakes.coiled >= (A.coiled or 1), 'no snake coiled within a minute')
local egg = G.cave.egg
egg:update_world_matrix(true, false)
local e = egg:get_world_position(require('port.three.math').Vector3.new())
local done, t = {}, 0
for _, at in ipairs(A.after or { 20, 60, 120 }) do
  GAME.step(at - t); t = at
  local a = math.rad(A.yaw or 0)
  local eye = { e.x + math.sin(a)*(A.dist or 1.6), e.y + (A.up or 0.5), e.z + math.cos(a)*(A.dist or 1.6) }
  GAME.look(eye, { e.x, e.y + (A.look_up or 0.35), e.z }, A.fov or 38)
  GAME.step(1)
  engine_step(1); engine_step(1)
  file_write_string(string.format('%s/t01_a%d.rgba', OUT, at), gpu_read(R.out.gpu, 0, 0, R.W, R.H, 'rgba8'))
  done[#done + 1] = at .. ':' .. #G.snakes.coiled
end
GAME.set_manual(false)
return 't01 after/coiled ' .. table.concat(done, ',') .. ' (' .. n .. ' ticks to the first coil)'
