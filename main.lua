--[[
  Phylactery (named Lich Survivors until 2026-10-15) -- the Anchor build (the port from three.js, started 2026-09-30).

  The three.js build (web/) is the reference; this one must draw and play exactly as it does
  (ANCHOR_PORT.md section 5). Rendering runs three.js's own compiled programs on the engine's gpu
  layer through a small three.js in Lua (port/three/); the game's modules are ports of web/src/
  (port/*.lua), with the heavy static content (the sculpted skeleton and objects, the cave and its
  light bake, textures, environment maps) exported from the three.js build (assets/port/).

  THIS FILE HOLDS DEFINITIONS ONLY (it reloads on save); boot.lua does the one-time work.
  Drive it with:  anchor drive start .   anchor drive eval . 'engine_step(60)'   anchor drive stop .
  GAME (port/game.lua) is the harness, as window.GAME in the three.js build.
  Runs record like any Anchor game (the gpu layer records since APR v13, 2026-10-01).
]]

require('anchor')({
  width  = 640,
  height = 360,
  scale  = 2,
  title  = 'Phylactery',
  filter = 'rough',
  boot   = {'boot.lua'},
})

-- input, then the game's 60 Hz ticks (the engine updates at 120 Hz)
function update(dt)
  local PROF = require('port.prof')
  local t0 = PROF.on and perf_time()   -- (2026-10-15: the benchmark's totals, port/bench.lua)
  sync_engine_globals()
  G.game.input_update()
  G.game.frame(dt)
  G.render_acc = G.render_acc + dt
  process_destroy_queue()
  if t0 then PROF.add('UPDATE (all)', t0) end
end

function draw()
  local PROF = require('port.prof')
  local B = require('port.bench')
  if B.on then B.frame(GAME) end         -- (2026-10-15: the benchmark's schedule and report, port/bench.lua)
  -- 2026-10-15 (owner: "Performance is an issue on the web version it seems"): the world is drawn at most once per
  -- game tick (60 a second), or 60 times a second while the game stands still (the sound tool, the viewer), or when a
  -- harness steps it (render_dt): a frame between two ticks is the same picture, and drawing it costs ~6 ms on the
  -- web. (The engine caps drawing at 60 Hz by default and the site keeps that cap while a game is live, so on a
  -- 165 Hz screen this is a safety net; it also drops the frames where the 60 Hz draw and the 60 Hz tick drift
  -- apart.) Between, the last frame's layers are shown again (layer_draw without layer_render keeps a layer's
  -- texture as it was).
  local g = G.game.G
  if g.tick == G.drawn_tick and not g.render_dt and G.render_acc < 1/60 - 1e-6 then
    layer_draw(G.screen_layer)
    layer_draw(G.ui_layer)
    return
  end
  G.drawn_tick = g.tick
  local t0 = PROF.on and perf_time()
  local dt = G.game.G.render_dt or G.render_acc
  G.game.G.render_dt = nil
  G.render_acc = 0
  G.game.render(dt)
  if G.trace_path then port_trace_flush() end
  local t1 = PROF.on and perf_time()
  G.R.present(G.screen_layer)
  layer_render(G.screen_layer)
  layer_draw(G.screen_layer)
  layer_render(G.ui_layer)          -- the icons at full resolution, over everything (round 49)
  layer_draw(G.ui_layer)
  if t1 then PROF.add('present', t1); PROF.add('DRAW (all)', t0) end
end

-- On a327ex.com (the site's game host, GAME_HOSTED): the host stops ticking the game while it is off screen and
-- drops it when another game takes the slot; the garbage collector (paced by the game, round 64) goes back to the
-- site's own pacing then, or the site's garbage would pile up with nothing collecting it.
function game_hosted_visible(on)
  if on then require('port.gcpace').resume() else require('port.gcpace').pause() end
  require('port.audio').mute(not on)      -- (its sounds go quiet with it, loops kept)
end
function game_hosted_stop() require('port.gcpace').pause(); require('port.audio').stop_all() end

require('boot')   -- LAST line: one-time work, after every definition exists
