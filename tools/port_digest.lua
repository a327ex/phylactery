-- port_digest.lua -- the port to Anchor: the same digest as tools/port_digest.js, from the Anchor
-- build (anchor drive eval . 'return dofile("tools/port_digest.lua")'). See ANCHOR_PORT.md.
local g = G.game.G
local function f(v) if math.abs(v) < 1e-300 then return '0' end; return string.format('%.15g', v) end
local function fs(...) local t = {}; for i, v in ipairs({ ... }) do t[i] = f(v) end; return table.concat(t, ' ') end
local out = {}
out[#out + 1] = 't ' .. g.tick
local L = g.mover.p
out[#out + 1] = 'L ' .. fs(L.x, L.y, L.z, g.mover.yaw())
for _, s in ipairs(g.snakes.S) do
  local sp = s.spine
  out[#out + 1] = 's ' .. fs(s.x, s.z, s.dir, s.leak, s.delay, s.sink) .. ' ' .. (s.fx and 'fx' or '-') .. (s.burn and 'b' or '-') .. (s.coil and s.coil.phase or '-') .. ' ' ..
    fs(sp[1].x, sp[1].y, sp[1].z, sp[41].x, sp[41].y, sp[41].z, sp[72].x, sp[72].y, sp[72].z)
end
local st = g.powers.state()
local names = { 'FIRE', 'LIFT', 'ROCK', 'LEAKAGE', 'BEAM', 'LENS' }
local u = {}
for _, n in ipairs(names) do u[#u + 1] = '"' .. n .. '":' .. st.uses[n] end
out[#out + 1] = 'p ' .. st.phase .. ' ' .. tostring(st.ab) .. ' {' .. table.concat(u, ',') .. '}'
local e = g.END
out[#out + 1] = 'e ' .. fs(e.w, e.level, e.grips)
local hp = g.lich.head_pos and nil
local head = g.lich.nodes.head
head:update_world_matrix(true, false)
local TM = require('port.three.math')
local p = head:get_world_position(TM.Vector3.new())
out[#out + 1] = 'h ' .. fs(p.x, p.y, p.z)
local its = GAME.items()
local parts = {}
for _, w in ipairs(its) do
  if w.balls then local p = { '"' .. w.state .. '"' }; for _, b in ipairs(w.balls) do p[#p+1] = f(b[1]); p[#p+1] = f(b[2]); p[#p+1] = f(b[3]) end; parts[#parts+1] = '[' .. table.concat(p, ',') .. ']'
  else parts[#parts+1] = '["' .. w.state .. '",' .. f(w.x) .. ',' .. f(w.y) .. ',' .. f(w.z) .. ']' end
end
out[#out + 1] = 'i [' .. table.concat(parts, ',') .. ']'
return table.concat(out, '\n')
