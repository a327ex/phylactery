-- a playthrough: him walked along the walk's centre line at the walk's pace (as a player holding
-- the mouse ahead of him), each inspect view put away after a second and a half; times recorded
record_stop()
local GG = G.game.G
local Wk = GG.walk
local pts = Wk.W.path.pts
local n = #pts//2
local log = {}
local t0 = GG.t
local last_col = 0
local insp_t = 0
for it = 1, 40000 do
  if GG.mode ~= 'walk' then log[#log + 1] = string.format('room at t=%.1f', GG.t - t0); break end
  if GG.inspect.S.active then
    insp_t = insp_t + 1/60
    if insp_t > 1.5 then GG.inspect.close(); insp_t = 0 end
    GAME.step(1)
  else
    local L = GG.mover.p
    local s = Wk.nav.s_at(L.x, L.z)
    local tunnel = s > Wk.W.path.total - 0.5
    local gx, gz
    if tunnel then gx, gz = 0, L.z + 4
    else
      local k = math.min(n - 1, math.floor(math.max(0, s) + 3.0))
      gx, gz = pts[k*2 + 1], pts[k*2 + 2]
    end
    GAME.step(6, { ['goto'] = { gx, gz } })
  end
  local c = 0; for i0 = 0, 5 do if Wk.collected[i0] then c = c + 1 end end
  if c ~= last_col then last_col = c; log[#log + 1] = string.format('object %d at t=%.1f s=%.1f', c, GG.t - t0, Wk.nav.s_at(GG.mover.p.x, GG.mover.p.z)) end
end
local st = GAME.state()
log[#log + 1] = string.format('end: mode %s t=%.1f lich %.1f %.1f %.1f powers %s', GG.mode, GG.t - t0, st.lich[1], st.lich[2], st.lich[3], table.concat(GG.powers.state().on, ','))
return table.concat(log, '\n')
