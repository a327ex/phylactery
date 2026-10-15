--[[
  prof.lua -- the game's own section profiler (2026-10-15, owner: "Performance is an issue on the web version it
  seems, so you should find an easy way to test that and fix it generally"). Off unless a benchmark turns it on
  (port/bench.lua): every timed section is `local t0 = PROF.on and perf_time()` ... `if t0 then PROF.add(name, t0) end`,
  so it costs a boolean test when off. It sums seconds per section and counts the frames drawn and the ticks run;
  report() gives milliseconds per drawn frame (and per tick for the tick's sections), heaviest first.
  PROF.fine = true (set it from a driver) adds the finer sections: inside each draw (three/renderer.lua d.*: program,
  mesh uploads, uniforms, state, the GL call; ~<object>.<attribute>: each buffer sent again, '#floats_up' the floats
  sent a frame, '#draws' / '#mat_refresh' counts), and the snakes' (s.build, s.trail, s.direct, '#builds').
]]
local PROF = { on = false, t = {}, frames = 0, ticks = 0, kind = {} }
local clock = perf_time

function PROF.add(name, t0, per_tick)
  local d = clock() - t0
  PROF.t[name] = (PROF.t[name] or 0) + d
  if per_tick then PROF.kind[name] = 'tick' end
end
-- a section ended where the next begins: lap(name, t0) adds since t0 and returns now (nil when off)
function PROF.lap(name, t0, per_tick)
  if not t0 then return nil end
  local now = clock()
  PROF.t[name] = (PROF.t[name] or 0) + (now - t0)
  if per_tick then PROF.kind[name] = 'tick' end
  return now
end
function PROF.reset() PROF.t = {}; PROF.frames = 0; PROF.ticks = 0; PROF.kind = {} end
function PROF.frame() PROF.frames = PROF.frames + 1 end
function PROF.tick() PROF.ticks = PROF.ticks + 1 end

-- { {name, ms per frame, ms per tick or nil}, ... } heaviest first
function PROF.rows()
  local out = {}
  local f = math.max(1, PROF.frames)
  for name, s in pairs(PROF.t) do
    out[#out + 1] = { name = name, ms = s*1000/f, per_tick = PROF.kind[name] == 'tick' and s*1000/math.max(1, PROF.ticks) or nil }
  end
  table.sort(out, function(a, b) if a.ms ~= b.ms then return a.ms > b.ms end; return a.name < b.name end)
  return out
end
function PROF.report()
  local lines = { string.format('%d frames, %d ticks (%.2f ticks a frame)', PROF.frames, PROF.ticks, PROF.ticks/math.max(1, PROF.frames)) }
  for _, r in ipairs(PROF.rows()) do
    lines[#lines + 1] = string.format('  %-18s %7.3f ms/frame%s', r.name, r.ms, r.per_tick and string.format('  (%.3f ms/tick)', r.per_tick) or '')
  end
  return table.concat(lines, '\n')
end

return PROF
