-- (2026-10-18) the viewer with the serif on the object's title only. OUT = a folder. Capture only.
record_stop()
GAME.set_manual(true)
GAME.begin()
GAME.powers({ true, true, true, true, true, true })
GAME.step(400)
local n = 0
local function shot(name) engine_step(1); engine_snapshot(string.format('%s/%s.png', OUT, name), 2); n = n + 1 end
for _, i in ipairs({ 0, 3, 4 }) do GAME.ask(i); GAME.step(90); shot('ask_' .. i); GAME.inspect_close(); GAME.step(40) end
GAME.inspect(1); GAME.step(90); shot('view_1'); GAME.inspect_close(); GAME.step(40)
GAME.set_manual(false)
return n .. ' frames, font now ' .. require('port.hud').font_name
