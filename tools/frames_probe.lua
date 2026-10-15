-- (2026-10-15, round 81) the same scenario stepped by hand (deterministic: LICH_SEED fixed, waves at fixed ticks, the lens forced
-- out) and the frame drawn at fixed ticks -> OUT/tNNNN.png, to compare the renders before and after a change
record_stop()
GAME.set_manual(true)
GAME.begin()
GAME.powers({ true, true, true, true, true, true })
local waves = { [420] = 'PACK', [780] = 'SPREAD', [1140] = 'STREAM', [1500] = 'PAIR', [1740] = 'PACK' }
local shots = { [600] = true, [700] = true, [900] = true, [1000] = true, [1200] = true, [1300] = true, [1500] = true, [1650] = true, [1800] = true, [1950] = true }
local n = 0
for tick = 1, 2000 do
  if waves[tick] then GAME.wave(waves[tick]) end
  GAME.step(1)
  if shots[tick] then
    engine_step(1)                       -- (one engine frame: the game is manual, so it only draws)
    engine_snapshot(string.format('%s/t%04d.png', OUT, tick), 2)
    n = n + 1
  end
end
GAME.set_manual(false)
return n .. ' frames'
