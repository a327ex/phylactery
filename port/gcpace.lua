--[[
  gcpace.lua -- round 64 (owner, 2026-10-08: "Game is noticeably slowing down when snakes gore explode from lift").
  Lua's own pacing let a whole cycle's garbage (50-70 MB of small tables) be freed in one or two frames: a 40-90 ms
  frame every few seconds, more often as the gore made garbage. Now the automatic collector is off and the game runs
  it itself, a little every tick: steps of 1 KB of work until `budget` s are spent or a cycle ends (a new one starts
  the next tick: pause 100). If the heap runs away from what the last cycle left (`grow` times it plus `slack` MB) the
  tick's budget goes to `catch_up`. Measured (round 64): the collector's share of a frame 0.5-1.6 ms, the heap 70-108
  MB, no frame long because of it.
]]
local GP = { budget = 0.0005, catch_up = 0.003, grow = 1.5, slack = 24 }

local live_kb = nil
function GP.start()
  collectgarbage('collect')
  collectgarbage('incremental', 100, 100, 10)
  collectgarbage('stop')
  live_kb = collectgarbage('count')
end

-- On the site (2026-10-09) the game shares the site's Lua: the collector is the site's too. While the game is off
-- screen or gone its ticks stop, so the automatic collector comes back, as the site runs it (Lua 5.4's defaults);
-- back on screen, the game paces it again. (main.lua: game_hosted_visible / game_hosted_stop.)
function GP.pause()
  if not live_kb then return end
  live_kb = nil
  collectgarbage('incremental', 200, 100, 13)
  collectgarbage('restart')
end
function GP.resume()
  if live_kb then return end
  collectgarbage('incremental', 100, 100, 10)
  collectgarbage('stop')
  live_kb = collectgarbage('count')
end

function GP.tick()
  if not live_kb then return end
  local t0 = perf_time()
  local kb = collectgarbage('count')
  local budget = (kb > live_kb*GP.grow + GP.slack*1024) and GP.catch_up or GP.budget
  repeat
    if collectgarbage('step', 0) then live_kb = collectgarbage('count'); break end
  until perf_time() - t0 > budget
end

return GP
