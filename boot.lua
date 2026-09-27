--[[
  boot.lua — ONE-TIME WORK: the layers, the binds, and the state main.lua's
  definitions read and write. main.lua names this file in its init table
  (`boot = {'boot.lua'}`) and requires it as its last line, so it runs once
  and NEVER reloads: saving any other file re-runs its definitions in the
  globals while everything created here survives.
]]

game_layer = layer_new('game')

bind('quit', 'key:escape')

-- state the definition files read and write
box_x = 0
