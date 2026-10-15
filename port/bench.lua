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

-- (2026-10-15, session 17) the benchmark as the site hosts the game: a file bench_site beside bench_on (tools/webbench,
-- WEBBENCH_SITE=1) makes the boot a hosted one (GAME_HOSTED) with the site's packs emulated: the sounds 3 s after the
-- boot starts, the objects and the viewer 8 s after (game_host.lua "Packs"). What the boot costs then is what a
-- visitor waits for once the boot pack is in.
function B.host_emulation()
  if not B.active() then return end
  local f = io.open('bench_site', 'r')
  if not f then return end
  f:close()
  GAME_HOSTED = true
  local t0 = perf_time()
  local at = { ambient = 0.5, sounds = 3, items = 8 }
  function game_pack_ready(name) return perf_time() - t0 >= (at[name] or 0) end
  function game_file_ready(path)
    if path:find('^assets/sfx/') then return game_pack_ready('sounds') end
    if path:find('^assets/port/items/') then return game_pack_ready('items') end
    return true
  end
  print('BENCH as the site hosts it (packs emulated)')
end
-- (session 17) the audio device's callbacks (engine audio_stats: on the web the mix runs on the main thread, and a
-- callback late by more than a block replays the one before), per phase; bench_plain = plain voices, no FX voices
local function aud_line(label)
  if not audio_stats then return 'BENCH audio ' .. label .. ': no audio_stats in this engine' end
  local a = audio_stats(true)
  if a.path == 'worklet' or a.path == 'script' then   -- (Phylactery 19) the engine's own web output: pumps into a queue
    return string.format('BENCH audio %s: %s output, %d pumps, lead %.0f ms; gaps heard %d (%.1f ms); least queued %.1f ms; worst pump gap %.1f ms; mix %.2f ms avg, %.2f max; voices max %d (FX %d)',
      label, a.path, a.callbacks, a.period_ms, a.gaps, a.gap_ms, a.queue_ms_min, a.gap_ms_max, a.cb_ms_avg, a.cb_ms_max, a.voices_max, a.fx_max)
  end
  return string.format('BENCH audio %s: %d callbacks of %.1f ms; late %d, very late (a block replayed) %d, worst gap %.1f ms; mix %.2f ms avg, %.2f max, over half a block %d; voices max %d (FX %d)%s',
    label, a.callbacks, a.period_ms, a.late, a.very_late, a.gap_ms_max, a.cb_ms_avg, a.cb_ms_max, a.over_budget, a.voices_max, a.fx_max,
    B.aud_ev and #B.aud_ev > 0 and ('; very late at ' .. table.concat(B.aud_ev, ' ')) or '')
end
B.aud_line = aud_line
function B.audio_switches()
  if not B.active() then return end
  local f = io.open('bench_plain', 'r')
  if f then f:close(); require('port.audio').PLAIN = true; print('BENCH plain voices (no FX voices)') end
  -- (Phylactery 19) bench_soundlog: every play the game asks of the engine, with the main thread's clock (perf_time:
  -- performance.now on the web), as SNDLOG lines; tools/webbench/start_jitter.py sets them against when the engine
  -- mixed (the tap's chunk times) to see how far each sound's start moved
  f = io.open('bench_soundlog', 'r')
  if f then
    f:close()
    local id, n = {}, 0
    local function key(s) local k = id[s]; if not k then n = n + 1; k = n; id[s] = k end; return k end
    for _, fn in ipairs({ 'sound_play_fx', 'sound_play_handle', 'sound_play' }) do
      local orig = _G[fn]
      if orig then
        _G[fn] = function(s, ...)
          print(string.format('SNDLOG %.3f %d', perf_time()*1000, key(s)))
          return orig(s, ...)
        end
      end
    end
    print('BENCH sound log on')
  end
end

local t, wi, last, started = 0, 1, nil, false
local frames = {}
local function pct(sorted, p) if #sorted == 0 then return 0 end; return sorted[math.max(1, math.min(#sorted, math.floor(#sorted*p + 0.5)))] end

-- every drawn frame (main.lua draw), with the game's harness API
function B.frame(GAME)
  if not B.on or B.done then return end
  local now = perf_time()
  if not B.first_frame then              -- (2026-10-15, session 17: the first drawn frame, after the boot's own work)
    B.first_frame = true
    if BOOT_END then print(string.format('BENCH first frame drawn %.0f ms after the boot', (now - BOOT_END)*1000)) end
  end
  local dt = last and (now - last) or 0
  last = now
  -- (session 17) the frames before the measured span: the first ones (the first frame's compiles) and the worst (the
  -- hosted boot's programs, compiled one a frame)
  if t < WARM then
    B.early = B.early or {}
    if #B.early < 6 then B.early[#B.early + 1] = string.format('%.0f', dt*1000) end
    if dt*1000 > (B.early_worst or 0) then B.early_worst, B.early_worst_t = dt*1000, t end
    B.early_long = (B.early_long or 0) + ((dt > 0.05) and 1 or 0)
    B.early_n = (B.early_n or 0) + 1
  elseif not B.early_said then
    B.early_said = true
    print(string.format('BENCH early frames: the first %s ms; the worst %.0f ms at %.1f s; %d of %d over 50 ms', table.concat(B.early or {}, ', '),
      B.early_worst or 0, B.early_worst_t or 0, B.early_long or 0, B.early_n or 0))
  end
  t = t + math.min(dt, 0.25)
  if audio_stats and started then
    local vl = audio_stats().very_late
    if vl > (B.aud_vl or 0) then B.aud_ev = B.aud_ev or {}; B.aud_ev[#B.aud_ev + 1] = string.format('%.1f', t) end
    B.aud_vl = vl
  end
  -- (session 17) the frames over 50 ms, when; and with bench_ending (tools/webbench WEBBENCH_ENDING=1) the ending
  -- played after the measured span: every power given up, the coil, his death, the hatch
  if dt > 0.05 and started then B.spikes = B.spikes or {}; B.spikes[#B.spikes + 1] = string.format('%.0f@%.1f', dt*1000, t) end
  if B.ending then
    local q = GAME.seq()
    if q.dead and not B.ending.dead then B.ending.dead = t end
    if (B.ending.dead and t >= B.ending.dead + 12) or t >= B.ending.t0 + 70 then
      print(string.format('BENCH ending: gave up at %.1f s, died at %s s; frames over 50 ms after giving up (ms@s, d = dead): %s',
        B.ending.t0, B.ending.dead and string.format('%.1f', B.ending.dead) or 'never', table.concat(B.ending.spikes, ' ')))
      print(aud_line('ending'))
      print('BENCH DONE')
      B.done = true
    elseif dt > 0.05 then
      B.ending.spikes[#B.ending.spikes + 1] = string.format('%.0f@%.1f%s', dt*1000, t, q.dead and 'd' or '')
    end
    return
  end
  if not started then
    started = true
    GAME.begin()
    GAME.powers({ true, true, true, true, true, true })
  end
  while WAVES[wi] and t >= WAVES[wi][1] do GAME.wave(WAVES[wi][2]); wi = wi + 1 end
  if t >= WARM and not PROF.on then PROF.reset(); PROF.on = true; frames = {}; if audio_stats then audio_stats(true); B.aud_vl = 0; B.aud_ev = {} end end
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
    lines[#lines + 1] = 'BENCH frames over 50 ms (ms@s): ' .. table.concat(B.spikes or {}, ' ')
    lines[#lines + 1] = aud_line('fight'); B.aud_vl = 0; B.aud_ev = {}
    local f = io.open('bench_ending', 'r')
    if f then
      f:close()
      B.ending = { t0 = t, spikes = {} }
      GAME.remove_all()
    else
      lines[#lines + 1] = 'BENCH DONE'
      B.done = true
    end
    B.result = table.concat(lines, '\n')
    for _, l in ipairs(lines) do print(l) end
  end
end

return B
