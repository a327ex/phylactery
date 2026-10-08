--[[
  lichmask.lua -- round 45 (owner, 2026-10-04: "I also want the lich itself to have a mask on his
  face. It should be like Shun's mask except with no eyes nor mouth markings, just a flat white
  mask"). The avatar's mask as item_mask.js measured it (round 30: the outline, a round brow over
  the measured jaw lines to a pointed chin; the face's gentle curve, the faint ridge of a nose,
  the eyes' slight hollows, the cheeks), before any slit, gash or fire: a smooth white shell on the
  skull's face, its rim rolled back. Built here at load (a polar grid out to the outline), worn by
  the head node, drawn with the burned mask's own material ('item.mask', so its compiled program)
  in white.
]]
local T = require('port.three.core')
local OB = require('port.objects')
local ITM = require('port.items')
local sqrt, exp, abs, cos, sin, max, min, pi = math.sqrt, math.exp, math.abs, math.cos, math.sin, math.max, math.min, math.pi

local LM = {}

-- item_mask.js's measures (metres; E = 13.8 cm between the eyes' outer ends)
local EY = 0.022
local JAW = { { 0, 0.093 }, { 0.0245, 0.0855 }, { 0.042, 0.0695 }, { 0.06, 0.059 }, { 0.068, 0.0555 }, { 0.085, 0.0365 }, { 0.098, 0.017 }, { 0.106, 0.0 } }
local function jaw(dy)
  if dy <= 0 then return JAW[1][2] end
  if dy >= JAW[#JAW][1] then return 0 end
  local i = 1
  while JAW[i + 1][1] < dy do i = i + 1 end
  local p0, p1, p2, p3 = JAW[max(1, i - 1)][2], JAW[i][2], JAW[i + 1][2], JAW[min(#JAW, i + 2)][2]
  local t = (dy - JAW[i][1])/(JAW[i + 1][1] - JAW[i][1])
  return 0.5*((2*p1) + (-p0 + p2)*t + (2*p0 - 5*p1 + 4*p2 - p3)*t*t + (-p0 + 3*p1 - 3*p2 + p3)*t*t*t)
end
local function outline(x, y)
  if y >= EY then return (sqrt((x/0.093)^2 + ((y - EY)/0.09)^2) - 1)*0.09 end
  local dy = EY - y
  if dy > 0.106 then return sqrt(x*x + (dy - 0.106)^2) end
  return (abs(x) - jaw(dy))*0.85
end
local function sstep(a, b, x) local t = max(0, min(1, (x - a)/(b - a))); return t*t*(3 - 2*t) end
local function face(x, y)
  local v = y - 0.01
  local z = -(x*x)/(2*0.105) - (v*v)/(2*0.3)
  z = z + 0.008*exp(-((x/0.0105)^2))*sstep(EY + 0.012, EY - 0.01, y)*sstep(EY - 0.046, EY - 0.03, y)
  z = z - 0.0035*exp(-(((abs(x) - 0.046)/0.026)^2 + ((y - EY)/0.018)^2))
  z = z + 0.0026*exp(-(((abs(x) - 0.048)/0.028)^2 + ((y - EY + 0.036)/0.024)^2))
  z = z + 0.0016*exp(-((x/0.026)^2 + ((y - EY + 0.064)/0.013)^2))
  return z
end

LM.LOOKS = {
  { name = 'WHITE', color = { 0.80, 0.79, 0.76 }, rough = 0.55 },
  { name = 'WHITE, MATTE', color = { 0.78, 0.77, 0.74 }, rough = 0.85 },
  { name = 'NONE', color = nil },
}

-- the shell's geometry in the mask's own frame (x right, y up, z out of the face; z = 0 at the
-- nose's line)
local function build_geometry(s)
  local NA, NR, TH = 112, 22, 0.0055
  local cx, cy = 0, EY - 0.012
  local Rr = {}
  for a = 0, NA - 1 do
    local th = a/NA*2*pi
    local dx, dy = cos(th), sin(th)
    local lo, hi = 0, 0.2
    for _ = 1, 40 do local m = (lo + hi)/2; if outline(cx + dx*m, cy + dy*m) < 0 then lo = m else hi = m end end
    Rr[a] = lo
  end
  local P, N, C, MR, I = {}, {}, {}, {}, {}
  local nv = 0
  local function zf(x, y, u) return face(x, y) - 0.0024*sstep(0.86, 1.0, u)^2 end
  local function add(x, y, z, nx, ny, nz)
    P[#P + 1] = x*s; P[#P + 1] = y*s; P[#P + 1] = z*s
    local l = sqrt(nx*nx + ny*ny + nz*nz)
    N[#N + 1] = nx/l; N[#N + 1] = ny/l; N[#N + 1] = nz/l
    nv = nv + 1
    return nv - 1
  end
  local function us(k) local u = k/NR; return 1 - (1 - u)^1.6 end      -- (rings denser toward the rim)
  -- front and back surfaces, ring by ring
  local front, back = {}, {}
  for k = 0, NR do
    front[k], back[k] = {}, {}
    local u = us(k)
    for a = 0, NA - 1 do
      local th = a/NA*2*pi
      local x, y = cx + cos(th)*Rr[a]*u, cy + sin(th)*Rr[a]*u
      local e = 2e-4
      local z = zf(x, y, u)
      local gx = (zf(x + e, y, u) - zf(x - e, y, u))/(2*e)
      local gy = (zf(x, y + e, u) - zf(x, y - e, u))/(2*e)
      local nx, ny, nz = -gx, -gy, 1
      local l = sqrt(nx*nx + ny*ny + 1)
      front[k][a] = add(x, y, z, nx, ny, nz)
      back[k][a] = add(x - nx/l*TH, y - ny/l*TH, z - nz/l*TH, -nx, -ny, -nz)
      if k == 0 then break end
    end
  end
  local function tri(a, b, c) I[#I + 1] = a; I[#I + 1] = b; I[#I + 1] = c end
  for a = 0, NA - 1 do
    local b = (a + 1) % NA
    tri(front[0][0], front[1][a], front[1][b])
    tri(back[0][0], back[1][b], back[1][a])
    for k = 1, NR - 1 do
      tri(front[k][a], front[k + 1][a], front[k + 1][b]); tri(front[k][a], front[k + 1][b], front[k][b])
      tri(back[k][a], back[k + 1][b], back[k + 1][a]); tri(back[k][a], back[k][b], back[k + 1][b])
    end
  end
  -- the rim: its own vertices, facing outward
  for a = 0, NA - 1 do
    local b = (a + 1) % NA
    local function rim(i, j)
      local fi, bi = front[NR][i], back[NR][i]
      local th = i/NA*2*pi
      local ox, oy = cos(th), sin(th)
      local f = add(P[fi*3 + 1]/s, P[fi*3 + 2]/s, P[fi*3 + 3]/s, ox, oy, 0.15)
      local bk = add(P[bi*3 + 1]/s, P[bi*3 + 2]/s, P[bi*3 + 3]/s, ox, oy, -0.15)
      return f, bk
    end
    local f0, b0 = rim(a)
    local f1, b1 = rim(b)
    tri(f0, b0, b1); tri(f0, b1, f1)
  end
  for i = 1, nv do C[#C + 1] = 1; C[#C + 1] = 1; C[#C + 1] = 1; MR[#MR + 1] = 0; MR[#MR + 1] = 0.55 end
  local g = T.BufferGeometry.new()
  g.name = 'lich.mask'
  g:set_attribute('position', T.BufferAttribute.new(P, 3))
  g:set_attribute('normal', T.BufferAttribute.new(N, 3))
  g:set_attribute('color', T.BufferAttribute.new(C, 3))
  g:set_attribute('aMR', T.BufferAttribute.new(MR, 2))
  g:set_index(T.BufferAttribute.new(I, 1))
  return g, C, MR
end

-- round 47 (owner, 2026-10-05: "His mask has to be a bit in front of him, not glued to his face,
-- like it's maintained by telekinesis. So it also lags his vertical movement by a bit."): held in
-- front of the skull's face (its eyes' line on the skull's, y 0.03 in the head's frame, 7 cm out),
-- not worn: each tick it follows where the head would hold it, sideways and in turn closely, up
-- and down late (a softer spring), with a slow drift of its own.
local Vector3, Quaternion, Matrix4 = require('port.three.math').Vector3, require('port.three.math').Quaternion, require('port.three.math').Matrix4
LM.HOLD = { y = 0.03 - EY*0.95, z = 0.183 }
LM.SPRING = { xz = 400, y = 34, turn = 16 }       -- (stiffness, 1/s^2; turning as a rate)
-- round 50 fix (owner, 2026-10-06: "The mask is going behind the liches face"): measured in his
-- fastest turns, the lag carried it 17 cm back into the skull and 15 cm aside, its facing 0.85 rad
-- behind. Sideways and in turn it now follows closer, and the lag is bounded in the head's own frame:
-- never more than `back` nearer the face, `side` to a side, `up`/`down` off its height (the vertical
-- lag he asked for kept), its facing never more than `turn` rad behind.
LM.BOUND = { back = 0.022, side = 0.025, up = 0.03, down = 0.045, turn = 0.25 }
function LM.create(lich, GU, R)
  local A = ITM.assets()
  local X = A.manifest.items
  local B = OB.builder(A, X.mats, { gi = GU })
  local mat = B.material(0)                              -- 'item.mask' (world): the burned mask's
  local S = 0.95
  local g, C, MR = build_geometry(S)
  local m = T.Mesh.new(g, mat)
  m.name = 'lich.mask'
  m.cast_shadow = true; m.receive_shadow = true
  R.world_scene:add(m)
  local head = lich.nodes.head
  local tp, tq, ts = Vector3.new(), Quaternion.new(), Vector3.new()
  local hold = Vector3.new()
  local INV, LP = Matrix4.new(), Vector3.new()
  local M = { mesh = m, look = 0, p = nil, v = Vector3.new(), t = 0 }
  local function target()
    head:update_world_matrix(true, false)
    hold:set(0, LM.HOLD.y, LM.HOLD.z):apply_matrix4(head.matrix_world)
    head.matrix_world:decompose(tp, tq, ts)
    return hold, tq
  end
  -- where it is held, at once (a start, a jump)
  function M.snap()
    local p, q = target()
    M.p = p:clone(); M.v:set(0, 0, 0)
    m.position:copy(M.p); m.quaternion:copy(q)
  end
  -- round 58 (the ending, owner: "mask also drops and stops floating in front of him"): from where it is held it
  -- falls, bounces a little and lies on the floor face up, still (ground_y: the cave's floor)
  local LIE, FACE, UPV = Quaternion.new(), Vector3.new(), Vector3.new(0, 1, 0)
  function M.drop(ground_y)
    if M.dropped then return end
    if not M.p then M.snap() end
    M.dropped = { g = ground_y }
    FACE:set(0, 0, 1):apply_quaternion(m.quaternion)
    LIE:set_from_unit_vectors(FACE, UPV):multiply(m.quaternion)
    M.v:add(Vector3.new(0, 0.6, 0))
  end
  local function fall(dt)
    local P, V = M.p, M.v
    V.y = V.y - 9.8*dt
    P.x = P.x + V.x*dt; P.y = P.y + V.y*dt; P.z = P.z + V.z*dt
    local fl = M.dropped.g(P.x, P.z) + 0.015
    local near = P.y - fl < 0.06
    if P.y < fl then
      P.y = fl
      if V.y < -0.7 then V.y = -V.y*0.3 else V.y = 0 end
      V.x = V.x*0.6; V.z = V.z*0.6
    end
    m.position:copy(P)
    m.quaternion:slerp(LIE, 1 - math.exp(-(near and 9 or 3)*dt))
  end
  function M.tick(dt)
    if M.dropped then fall(dt); return end
    local p, q = target()
    if not M.p then M.snap(); return end
    M.t = M.t + dt
    local P, V, K = M.p, M.v, LM.SPRING
    -- critically damped springs: x and z close, y late
    local function axis(c, k)
      local d = 2*math.sqrt(k)
      V[c] = V[c] + ((p[c] - P[c])*k - V[c]*d)*dt
      P[c] = P[c] + V[c]*dt
    end
    axis('x', K.xz); axis('y', K.y); axis('z', K.xz)
    -- the bounds, in the head's frame (head.matrix_world is current: target() updated it)
    local B, H = LM.BOUND, LM.HOLD
    INV:copy(head.matrix_world):invert()
    LP:copy(P):apply_matrix4(INV)
    local out = false
    if LP.z < H.z - B.back then LP.z = H.z - B.back; out = true end
    if LP.x > B.side then LP.x = B.side; out = true elseif LP.x < -B.side then LP.x = -B.side; out = true end
    if LP.y > H.y + B.up then LP.y = H.y + B.up; out = true elseif LP.y < H.y - B.down then LP.y = H.y - B.down; out = true end
    if out then
      LP:apply_matrix4(head.matrix_world)
      V:add_scaled_vector(LP:clone():sub(P), 1/dt*0.5)          -- (carried along with the bound)
      P:copy(LP)
    end
    m.position:set(P.x, P.y + math.sin(M.t*1.3)*0.004, P.z)
    m.quaternion:slerp(q, 1 - math.exp(-K.turn*dt))
    local a = m.quaternion:angle_to(q)
    if a > B.turn then m.quaternion:slerp(q, 1 - B.turn/a) end
  end
  function M.set_look(i)
    M.look = ((i % #LM.LOOKS) + #LM.LOOKS) % #LM.LOOKS
    local L = LM.LOOKS[M.look + 1]
    m.visible = L.color ~= nil
    if L.color then
      for k = 1, #C, 3 do C[k], C[k + 1], C[k + 2] = L.color[1], L.color[2], L.color[3] end
      for k = 2, #MR, 2 do MR[k] = L.rough end
      g.attributes.color.needs_update = true; g.attributes.aMR.needs_update = true
    end
    return L.name
  end
  M.set_look(0)
  return M
end

return LM
