-- one still per fixed camera: him in its stretch
record_stop()
GAME.hud(false); G.game.G.walk.hold = true
local n = #G.game.G.walk.CAMS
local out = {}
for k = 1, n do
  local r = GAME.walk_zone(k)
  engine_step(1)
  engine_snapshot(string.format('scratch/walk_shots/z%02d.png', k))
  out[#out + 1] = k
end
GAME.hud(true)
return #out
