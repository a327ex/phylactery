--[[
  gcpace.lua -- round 64 (owner, 2026-10-08: "Game is noticeably slowing down when snakes gore explode from lift").
  Lua's own pacing let a whole cycle's garbage (50-70 MB of small tables) be freed in one or two frames: a 40-90 ms
  frame every few seconds, more often as the gore made garbage. So the automatic collector is off and the game runs it
  itself, a little every tick.
  2026-10-15 (owner: "Performance is an issue on the web version it seems ... fix it generally"): round 64 stepped
  until 0.5 ms had passed every tick and began a new cycle the moment one ended, so it marked the whole live heap
  (~80 MB, mostly the meshes' tables) over and over: its full budget every tick (0.52 ms natively, ~0.95 on the web,
  where the clock ticks in whole milliseconds and a 0.5 ms budget runs to the next one). Now a cycle's work is paced
  by what the game allocates, as Lua's own pacing is, and spread over the ticks as round 64 wanted: each tick a step
  of `k` times the KB allocated since the last tick; when a cycle ends, a pause until the heap has grown by `grow`
  times what the cycle left (plus `slack` MB), with no work at all meanwhile. Far from that (the heap past `runaway`
  times it), steps of `catch_up` times as much.
]]
local GP = { k = 4, grow = 1.5, slack = 8, runaway = 2.5, catch_up = 4 }

local live_kb, last_kb, waiting = nil, nil, false
function GP.start()
  collectgarbage('collect')
  collectgarbage('incremental', 100, 100, 10)
  collectgarbage('stop')
  live_kb = collectgarbage('count'); last_kb = live_kb; waiting = true
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
  live_kb = collectgarbage('count'); last_kb = live_kb; waiting = false
end

function GP.tick()
  if not live_kb then return end
  local kb = collectgarbage('count')
  local grown = kb - last_kb
  if waiting then
    if kb < live_kb*GP.grow + GP.slack*1024 then last_kb = kb; return end
    waiting = false
  end
  if grown < 1 then grown = 1 end
  local n = grown*GP.k*((kb > live_kb*GP.runaway + GP.slack*1024) and GP.catch_up or 1)
  if collectgarbage('step', math.floor(n + 0.5)) then
    live_kb = collectgarbage('count'); waiting = true
  end
  last_kb = collectgarbage('count')
end

return GP
