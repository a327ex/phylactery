-- (2026-10-18, Phylactery 20) the viewer's texts in the old pixel font and in the serif (names mixed / in capitals),
-- the question view (THROW) and the plain view (name only). OUT = a folder. Capture only: no recording.
record_stop()
local HUD = require('port.hud')
GAME.set_manual(true)
GAME.begin()
GAME.powers({ true, true, true, true, true, true })
GAME.step(400)
local n = 0
local function shot(name) engine_step(1); engine_snapshot(string.format('%s/%s.png', OUT, name), 2); n = n + 1 end
for _, v in ipairs({ { 'old', 'facet_fine', 'caps' }, { 'mixed', 'serif', 'mixed' }, { 'caps', 'serif', 'caps' } }) do
  HUD.set_font(v[2]); HUD.name_case = v[3]
  for _, i in ipairs({ 0, 3, 4 }) do
    GAME.ask(i); GAME.step(90); shot(string.format('%s_ask_%d', v[1], i))
    GAME.inspect_close(); GAME.step(40)
  end
  GAME.inspect(1); GAME.step(90); shot(v[1] .. '_view_1'); GAME.inspect_close(); GAME.step(40)
end
HUD.set_font('serif'); HUD.name_case = 'mixed'
GAME.set_manual(false)
return n .. ' frames'
