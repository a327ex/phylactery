-- a scripted run in the final room: moves, a mouse goal, the ending; a digest every 2 s
record_stop()
local blocks = {}
local function dig() blocks[#blocks + 1] = dofile('tools/port_digest.lua') end
for k = 1, 10 do GAME.step(120, { keys = (k % 3 == 0) and 'wd' or ((k % 3 == 1) and 'a' or '') }); dig() end
GAME.step(60, { ['goto'] = { 3, 4 } }); dig()
GAME.remove_all()
for k = 1, 12 do GAME.step(150); dig() end
return table.concat(blocks, '\n=====\n')
