--[[
  Lich Survivors -- the Anchor build (the port from three.js, started 2026-09-30).

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
  title  = 'Lich Survivors',
  filter = 'rough',
  boot   = {'boot.lua'},
})

-- input, then the game's 60 Hz ticks (the engine updates at 120 Hz)
function update(dt)
  sync_engine_globals()
  G.game.input_update()
  G.game.frame(dt)
  G.render_acc = G.render_acc + dt
  process_destroy_queue()
end

function draw()
  local dt = G.game.G.render_dt or G.render_acc
  G.game.G.render_dt = nil
  G.render_acc = 0
  G.game.render(dt)
  if G.trace_path then port_trace_flush() end
  G.R.present(G.screen_layer)
  layer_render(G.screen_layer)
  layer_draw(G.screen_layer)
end

require('boot')   -- LAST line: one-time work, after every definition exists
