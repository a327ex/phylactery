--[[
  store_a24.lua -- his A24 (Dark Side of the Moon): a snake as the centre piece, struck by the prismatic beam coming
  from his finger at the frame's edge (Phylactery 20, 2026-10-18). Capture only.

    anchor drive eval . 'OUT="<folder>"; A24={ ticks = {12, 20, 28}, side = 1, dist = 1.4, up = 0.35, fov = 42, toward = 0.3 }; return dofile("tools/store_a24.lua")'

  One snake is sent and, once it is within reach, the beam (power 4) is forced at it; frames are read back `ticks` after
  the cast. The camera stands square to the line finger -> snake (side = 1 or -1), `dist` from the snake, `up` above it,
  looking at the snake moved `toward` of the way to the finger, so the finger sits at the frame's edge.
  Writes <OUT>/a24_t<ticks>.rgba (GL rows bottom-up).
]]
record_stop()
local G = GAME.G
local TM = require('port.three.math')
local V = TM.Vector3.new
local R, lich = G.R, G.lich
GAME.set_manual(true)
if not STAGE_READY then GAME.begin(); GAME.step(60*9); STAGE_READY = true end
GAME.hud(false)
R.params.hud = 0
local A = A24 or {}

local function lich_xz() local st = GAME.state(); return st.lich[1], st.lich[3] end
local function live()
  local out = {}
  for _, s in ipairs(G.snakes.S) do if not s.pooled and (s.dying or -1) < 0 then out[#out + 1] = s end end
  return out
end
GAME.wave('ONE')
local target
for _ = 1, 120 do                                   -- up to 20 s for one to come within reach
  GAME.step(10)
  local lx, lz = lich_xz()
  for _, s in ipairs(live()) do
    local d = math.sqrt((s.x - lx)^2 + (s.z - lz)^2)
    if d < (A.reach or 2.6) and d > 1.2 then target = s break end
  end
  if target then break end
end
assert(target, 'no snake came within reach')
GAME.force(4, target.x, target.z)

local done, t = {}, 0
for _, tk in ipairs(A.ticks or { 12, 20, 28 }) do
  GAME.step(tk - t); t = tk
  local k = A.arm or 1
  local f = lich.fingertip(k)
  local sx, sz = target.x, target.z
  local sy = (G.cave.ground_y and G.cave.ground_y(sx, sz) or 0) + (A.lift or 0.12)
  local dx, dz = f.x - sx, f.z - sz
  local len = math.sqrt(dx*dx + dz*dz)
  local px, pz = -dz/len*(A.side or 1), dx/len*(A.side or 1)
  local tw = A.toward or 0.3
  local lx, ly, lz = sx + (f.x - sx)*tw, sy + (f.y - sy)*tw, sz + (f.z - sz)*tw
  local eye = { lx + px*(A.dist or 1.4), sy + (A.up or 0.35), lz + pz*(A.dist or 1.4) }
  GAME.look(eye, { lx, ly, lz }, A.fov or 42)
  GAME.step(1)
  engine_step(1); engine_step(1)
  file_write_string(string.format('%s/a24_t%d.rgba', OUT, tk), gpu_read(R.out.gpu, 0, 0, R.W, R.H, 'rgba8'))
  done[#done + 1] = tk
end
GAME.set_manual(false)
return 'a24 at ticks ' .. table.concat(done, ',') .. ' ' .. R.W .. 'x' .. R.H
