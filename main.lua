--[[
  lich-survivors — an Anchor 3 game.

  Scaffolded by `anchor new`. Read Anchor/engine/docs/SURFACE.md first: how a
  game is run, driven, recorded and reloaded.

  THIS FILE HOLDS DEFINITIONS ONLY, so saving it re-runs them in the live
  globals — functions rebind, constants go live, and the state boot.lua made
  survives. One-time work (layers, fonts, binds, state) belongs in boot.lua,
  which the init table names below and which never reloads.

  Run it with run.bat (the owner's). Drive it with:
    anchor drive start .
    anchor drive eval  . 'engine_step(60) return box_x'
    anchor drive stop  .
]]

require('anchor')({
  width  = 480,
  height = 270,
  scale  = 2,
  title  = 'lich-survivors',
  filter = 'rough',
  boot   = {'boot.lua'},
})

-- Definitions: a saved colour or constant is live on the next frame.
COL_BG  = color(26, 26, 26)
COL_BOX = color(230, 165, 80)

BOX_SIZE  = 32
BOX_SPEED = 120        -- pixels per second

function update(dt)
  sync_engine_globals()
  if input_pressed('quit') then engine_quit() end
  box_x = (box_x + BOX_SPEED*dt) % (width + BOX_SIZE)
  process_destroy_queue()
end

function draw()
  -- rectangles and text draw from the TOP-LEFT; images and circles centre on (x, y)
  layer_rectangle(game_layer, 0, 0, width, height, COL_BG())
  layer_rectangle(game_layer, box_x - BOX_SIZE, math.floor((height - BOX_SIZE)/2),
                  BOX_SIZE, BOX_SIZE, COL_BOX())
  layer_render(game_layer)
  layer_draw(game_layer)
end

require('boot')   -- LAST line: one-time work, after every definition exists
