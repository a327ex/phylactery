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
  2026-10-15, session 17 (owner: "Game seems to be stuttering whenever some events happen"): that pacing ran a whole
  cycle in ONE step. While the collector is stopped Lua keeps counting what is allocated as its debt, so the first step
  after the wait paid for everything since the last cycle: 18 steps in a 78 s run, 3 of them 21-30 ms on the desktop
  (more on the web), sooner after a burst of allocation (gore, a group attack), so they fell on the busy moments.
  Measured over the same run (scratch/s17/gc_mode_probe.lua, steps over 30 ms / p99.9): this pacing 12 / 31.5 ms, the
  debt dropped at the wait's end 17 / 34.2, Lua 5.4's generational collector 15 / 32.8, its automatic incremental
  collector with its defaults 7 / 26-28 ms (and a smaller heap). With round 64's garbage gone (232 -> 40 KB a frame)
  Lua's own pacing is the best of them: AUTO = true hands the collector back to it; tick() then does nothing.
  2026-10-16, Phylactery 19 (owner: "Sometimes it drops to like 30 fps"): Lua's own pacing still ended a cycle in one
  frame now and then (the ending: 32-44 ms natively, the heap dropping 75 MB at once; none with the collector stopped):
  an allocation burst (geometry built in a tick) raises its debt, and the next step pays it all. SMOOTH: the collector
  stopped, and each tick ONE basic step (collectgarbage('step', 0): a fixed amount of work, never the debt piled up
  since; 'step' with n > 0 pays that too, which is what sank round 64's and session 17's pacing). Measured: a cycle is
  ~37 basic steps at ~80 MB, 0.3 ms each natively, the slowest 2.3 ms; so a cycle takes ~0.6 s of ticks at ~0.3 ms a
  tick. Between cycles nothing, until the heap is s_pause times what the last left plus s_slack MB; past s_runaway
  times it, s_catch steps a tick.
]]
local GP = { k = 4, grow = 1.5, slack = 8, runaway = 2.5, catch_up = 4, AUTO = false,
  SMOOTH = true, s_pause = 1.6, s_slack = 16, s_steps = 1, s_catch = 3, s_runaway = 2.5 }

local live_kb, last_kb, waiting = nil, nil, false
function GP.start()
  if GP.AUTO then collectgarbage('incremental', 200, 100, 13); collectgarbage('restart'); return end
  if GP.SMOOTH then
    collectgarbage('collect')
    collectgarbage('incremental', 200, 100, 13)       -- (a basic step's size)
    collectgarbage('stop')
    live_kb = collectgarbage('count'); last_kb = live_kb; waiting = true
    return
  end
  collectgarbage('collect')
  collectgarbage('incremental', 100, 100, 10)
  collectgarbage('stop')
  live_kb = collectgarbage('count'); last_kb = live_kb; waiting = true
end

-- On the site (2026-10-09) the game shares the site's Lua: the collector is the site's too. While the game is off
-- screen or gone its ticks stop, so the automatic collector comes back, as the site runs it (Lua 5.4's defaults);
-- back on screen, the game paces it again. (main.lua: game_hosted_visible / game_hosted_stop.)
function GP.pause()
  if GP.AUTO or not live_kb then return end
  live_kb = nil
  collectgarbage('incremental', 200, 100, 13)
  collectgarbage('restart')
end
function GP.resume()
  if GP.AUTO or live_kb then return end
  if not GP.SMOOTH then collectgarbage('incremental', 100, 100, 10) end
  collectgarbage('stop')
  live_kb = collectgarbage('count'); last_kb = live_kb; waiting = false
end

function GP.tick()
  if not live_kb then return end
  if GP.SMOOTH then
    local kb = collectgarbage('count')
    if waiting then
      if kb < live_kb*GP.s_pause + GP.s_slack*1024 then return end
      waiting = false
    end
    local n = (kb > live_kb*GP.s_runaway + GP.s_slack*1024) and GP.s_catch or GP.s_steps
    for _ = 1, n do
      if collectgarbage('step', 0) then live_kb = collectgarbage('count'); waiting = true; break end
    end
    return
  end
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
