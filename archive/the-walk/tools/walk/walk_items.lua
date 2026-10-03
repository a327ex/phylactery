-- each object up close (three sides), and its stretch's camera with him at the stretch's start
record_stop()
GAME.hud(false)
local Wk = G.game.G.walk
Wk.hold = true
for i = 1, 6 do
  local it = Wk.W.items[i]
  local zk
  for k, c in ipairs(Wk.CAMS) do if c.item == i - 1 then zk = k end end
  GAME.walk_zone(zk)
  local x, y, z = it.at[1], it.at[2], it.at[3]
  for v = 1, 3 do
    local a = ({ 0.6, 2.4, 4.3 })[v]
    local d = 2.2
    GAME.look({ x + math.cos(a)*d, y + 0.7, z + math.sin(a)*d }, { x, y - 0.05, z }, 45)
    GAME.step(1); engine_step(1)
    engine_snapshot(string.format('scratch/walk_items/i%d_%d.png', i, v))
  end
  GAME.look()
  -- the hero shot: him a few metres before the object
  local c = Wk.CAMS[zk]
  local best, bx, bz = 1e9, x, z
  for r = 2.5, 5, 0.25 do for q = 0, 31 do
    local px, pz = x + math.cos(q/32*6.283)*r, z + math.sin(q/32*6.283)*r
    local s = Wk.nav.s_at(px, pz)
    if Wk.nav.dist(px, pz) > 0.5 and s < it.s - 1.5 and s > c.s0 then local dd = math.abs(s - (it.s - 3)); if dd < best then best = dd; bx, bz = px, pz end end
  end end
  GAME.place(bx, bz, math.atan(x - bx, z - bz))
  GAME.step(2); engine_step(1)
  engine_snapshot(string.format('scratch/walk_items/i%d_4.png', i))
end
GAME.hud(true)
return 'ok'
