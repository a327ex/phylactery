--[[
  bench.lua -- the performance benchmark (2026-10-15, owner: "Performance is an issue on the web version it seems, so
  you should find an easy way to test that and fix it generally"). One fixed scenario, the same on the desktop and in
  a browser: a fixed seed, his walk in, all six powers, a fixed schedule of waves (a pack, a spread, a stream, a pair,
  again), the game's own camera; after WARM s the section profiler (port/prof.lua) runs for SPAN s; then it prints
  BENCH lines (frame times from one drawn frame to the next, wall clock: on the web that is the browser's frame pacing,
  GPU waits included; and the sections' ms per frame) and BENCH DONE.
  On: LICH_BENCH in the environment (desktop: `LICH_BENCH=1 anchor drive start .`, then step), or a file `bench_on`
  beside main.lua (the web harness, tools/webbench/, writes it into the page's file system before the game starts).
  BENCH.done / BENCH.result hold the result for a driver that reads it instead of the console.
]]
local PROF = require('port.prof')
local B = { on = false, done = false, result = nil }
local SEED = 424242
local WARM, SPAN = 8.0, 30.0
local WAVES = { { 7.5, 'PACK' }, { 13.5, 'SPREAD' }, { 19.5, 'STREAM' }, { 25.5, 'PAIR' }, { 29.5, 'PACK' }, { 34.5, 'SPREAD' } }

function B.active()
  if B.checked then return B.on end
  B.checked = true
  local env = os.getenv and os.getenv('LICH_BENCH')
  if env and env ~= '' and env ~= '0' then B.on = true end
  if not B.on then
    local f = io.open('bench_on', 'r')
    if f then f:close(); B.on = true end
  end
  return B.on
end
function B.seed() return SEED end

local t, wi, last, started = 0, 1, nil, false
local frames = {}
local function pct(sorted, p) if #sorted == 0 then return 0 end; return sorted[math.max(1, math.min(#sorted, math.floor(#sorted*p + 0.5)))] end

-- every drawn frame (main.lua draw), with the game's harness API
function B.frame(GAME)
  if not B.on or B.done then return end
  local now = perf_time()
  local dt = last and (now - last) or 0
  last = now
  t = t + math.min(dt, 0.25)
  if not started then
    started = true
    GAME.begin()
    GAME.powers({ true, true, true, true, true, true })
  end
  while WAVES[wi] and t >= WAVES[wi][1] do GAME.wave(WAVES[wi][2]); wi = wi + 1 end
  if t >= WARM and not PROF.on then PROF.reset(); PROF.on = true; frames = {} end
  if PROF.on and dt > 0 then
    frames[#frames + 1] = dt*1000
    local kb = collectgarbage('count')
    B.heap_lo = math.min(B.heap_lo or kb, kb); B.heap_hi = math.max(B.heap_hi or kb, kb)
    if dt*1000 > (B.worst or 0) then B.worst = dt*1000; B.worst_t = t end
    -- the last frame's own Lua time (update + draw) and whether the lens's second world render ran in it: a frame
    -- much longer than its Lua waited on something else (the GPU, the browser)
    local cpu = ((PROF.t['UPDATE (all)'] or 0) + (PROF.t['DRAW (all)'] or 0))*1000
    local tr = (PROF.t['r3.transmission'] or 0)*1000
    local fc, ft = cpu - (B.last_cpu or cpu), tr - (B.last_tr or tr)
    B.last_cpu, B.last_tr = cpu, tr
    local long = dt*1000 > 25
    local k = (long and 'long' or 'ok') .. (ft > 0.3 and '+lens' or '')
    B.cls = B.cls or {}
    local c = B.cls[k] or { n = 0, cpu = 0, dt = 0 }
    c.n, c.cpu, c.dt = c.n + 1, c.cpu + fc, c.dt + dt*1000
    B.cls[k] = c
  end
  if t >= WARM + SPAN then
    PROF.on = false
    local s = {}
    for i, v in ipairs(frames) do s[i] = v end
    table.sort(s)
    local sum = 0
    for _, v in ipairs(frames) do sum = sum + v end
    local mean = sum/math.max(1, #frames)
    local lines = {
      string.format('BENCH %s  frames %d in %.1f s: %.1f fps; frame ms mean %.2f, p50 %.2f, p90 %.2f, p99 %.2f, max %.2f',
        platform or '?', #frames, SPAN, #frames/SPAN, mean, pct(s, 0.5), pct(s, 0.9), pct(s, 0.99), s[#s] or 0),
    }
    lines[#lines + 1] = string.format('BENCH heap %.0f..%.0f MB; the worst frame %.1f ms at %.1f s', (B.heap_lo or 0)/1024, (B.heap_hi or 0)/1024,
      B.worst or 0, B.worst_t or 0)
    lines[#lines + 1] = string.format('BENCH the game\'s Lua busy %.0f%% of the time (%.0f ms a second); the world drawn %d times (%.1f a second)',
      ((PROF.t['UPDATE (all)'] or 0) + (PROF.t['DRAW (all)'] or 0))/SPAN*100, ((PROF.t['UPDATE (all)'] or 0) + (PROF.t['DRAW (all)'] or 0))/SPAN*1000,
      PROF.frames, PROF.frames/SPAN)
    for _, k in ipairs({ 'ok', 'ok+lens', 'long', 'long+lens' }) do
      local c = B.cls and B.cls[k]
      if c then lines[#lines + 1] = string.format('BENCH frames %-9s %5d: %.1f ms each, of it Lua %.1f', k, c.n, c.dt/c.n, c.cpu/c.n) end
    end
    for line in PROF.report():gmatch('[^\n]+') do lines[#lines + 1] = 'BENCH ' .. line end
    lines[#lines + 1] = 'BENCH DONE'
    B.result = table.concat(lines, '\n')
    B.done = true
    for _, l in ipairs(lines) do print(l) end
  end
end

return B
