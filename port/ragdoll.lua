--[[
  ragdoll.lua -- round 59 (owner, 2026-10-07: "When the lich falls, his body should collide properly with the ground,
  like a dead rag doll, one arm reaching towards the egg"). A verlet rag doll taken from his pose as he dies: points at
  his joints (pelvis, chest, neck, skull, each arm's shoulder / elbow / wrist / fingertip, each leg's hip / knee / ankle /
  toe), sticks between them at the lengths they have then (the hips and the ribcage braced stiff, the spine, the head,
  the hands and the feet looser), knees and elbows kept from bending the wrong way, the cave's floor (ground_y) and the
  egg (a sphere) pushing them out with friction. Each tick his bones are set from the points: every node's frame from
  its own points (its bone, and a sideways reference), times the turn it had against that frame when he died, so the
  bones keep their twist; the body takes the pelvis's place, the rest their parents'. The fingers, thumbs and jaw keep
  what the pose gives them. The reaching arm is kept straight and drawn toward the egg.
]]
local TM = require('port.three.math')
local AU = require('port.audio')     -- 2026-10-10: the sounds
local Vector3, Quaternion, Matrix4 = TM.Vector3, TM.Quaternion, TM.Matrix4
local sqrt, max, min = math.sqrt, math.max, math.min

local RG = {}
RG.G = 9.8
RG.SUB, RG.ITER = 2, 10
RG.DAMP = 0.996                 -- of the velocity each substep (in the air)
RG.FRICTION = 0.45              -- of the sideways velocity kept at each contact
-- the slump (ragdoll.create): a straight knee's hip-ankle length times `knee`, the chest to the knees times `hip`, the
-- pelvis to the skull times `spine`, the free arm's shoulder-wrist times `elbow`; all as soft as `k`
RG.SLUMP = { knee = 0.86, hip = 0.9, spine = 0.95, elbow = 0.8, k = 0.06 }
RG.REACH_T = 1.4                -- (opts.reach_from: how long the reach takes to turn to reach_to)

-- opts: ground_y(x, z), egg = { x, y, z, r }, reach = arm index (1 or 2) or nil, reach_to = { x, y, z } (a point to
-- reach toward), reach_from = { x, y, z } (where it reaches at first, nil: reach_to from the start), push = { x, y, z } (m/s on the upper body as he goes), turn = { x, y, z } (m/s on the camera-side
-- shoulder, to turn him as he falls)
function RG.create(lich, opts)
  local N = lich.nodes
  local arms, legs = N.arms, N.legs
  local V = Vector3.new()
  local P, idx = {}, {}
  local function add(name, node, ox, oy, oz, r)
    node:update_world_matrix(true, false)
    V:set(ox or 0, oy or 0, oz or 0):apply_matrix4(node.matrix_world)
    P[#P + 1] = { x = V.x, y = V.y, z = V.z, ox = V.x, oy = V.y, oz = V.z, r = r, name = name }
    idx[name] = #P
  end
  add('pelvis', N.pelvis, 0, 0, 0, 0.1)
  add('chest', N.chest, 0, 0, 0, 0.11)
  add('neck', N.neck, 0, 0, 0, 0.06)
  add('head', N.head, 0, 0.09, 0.02, 0.09)
  for k, a in ipairs(arms) do
    add('sh' .. k, a.sh, 0, 0, 0, 0.05); add('el' .. k, a.el, 0, 0, 0, 0.035); add('wr' .. k, a.wr, 0, 0, 0, 0.03)
    add('tip' .. k, a.fingers[2].tip, 0, 0, 0, 0.015)
  end
  for k, l in ipairs(legs) do
    add('hip' .. k, l.hip, 0, 0, 0, 0.07); add('kn' .. k, l.kn, 0, 0, 0, 0.045); add('an' .. k, l.an, 0, 0, 0, 0.04)
    add('toe' .. k, l.an, 0, -0.06, 0.12, 0.025)
  end
  local function p(n) return P[idx[n]] end
  local function dist(a, b) local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z; return sqrt(dx*dx + dy*dy + dz*dz) end
  local C = {}
  local function stick(a, b, k) local A, B = p(a), p(b); C[#C + 1] = { A, B, dist(A, B), k or 1 } end
  -- the hips and the ribcage, braced
  local hips = { 'pelvis', 'hip1', 'hip2', 'chest' }
  for i = 1, #hips do for j = i + 1, #hips do stick(hips[i], hips[j], 1) end end
  local cage = { 'chest', 'neck', 'sh1', 'sh2' }
  for i = 1, #cage do for j = i + 1, #cage do stick(cage[i], cage[j], 1) end end
  -- the spine bends a little
  stick('pelvis', 'neck', 0.35); stick('pelvis', 'sh1', 0.3); stick('pelvis', 'sh2', 0.3); stick('hip1', 'sh1', 0.2); stick('hip2', 'sh2', 0.2)
  -- the head
  stick('neck', 'head', 1); stick('chest', 'head', 0.4)
  -- arms and legs
  for k = 1, 2 do
    stick('sh' .. k, 'el' .. k, 1); stick('el' .. k, 'wr' .. k, 1); stick('wr' .. k, 'tip' .. k, 1); stick('el' .. k, 'tip' .. k, 0.5)
    stick('hip' .. k, 'kn' .. k, 1); stick('kn' .. k, 'an' .. k, 1); stick('an' .. k, 'toe' .. k, 1); stick('kn' .. k, 'toe' .. k, 0.6)
  end
  -- the slump: a body without hold still folds a little (soft, under gravity and the floor): the knees and hips bend,
  -- the free arm's elbow, the spine curls (as fractions of the straight lengths)
  local function slump(a, b, f, k) local A, B = p(a), p(b); C[#C + 1] = { A, B, dist(A, B)*f, k } end
  for k = 1, 2 do
    local L1 = dist(p('hip' .. k), p('kn' .. k)) + dist(p('kn' .. k), p('an' .. k))
    C[#C + 1] = { p('hip' .. k), p('an' .. k), L1*RG.SLUMP.knee, RG.SLUMP.k }
    slump('chest', 'kn' .. k, RG.SLUMP.hip, RG.SLUMP.k)
  end
  slump('pelvis', 'head', RG.SLUMP.spine, RG.SLUMP.k)
  -- the reaching arm: straight; the other bent
  local R = opts.reach
  local reach_len
  for k = 1, 2 do
    if k ~= R then
      local L1 = dist(p('sh' .. k), p('el' .. k)) + dist(p('el' .. k), p('wr' .. k))
      C[#C + 1] = { p('sh' .. k), p('wr' .. k), L1*RG.SLUMP.elbow, RG.SLUMP.k }
    end
  end
  if R then
    local s, e, w, t = p('sh' .. R), p('el' .. R), p('wr' .. R), p('tip' .. R)
    local L1 = dist(s, e) + dist(e, w)
    C[#C + 1] = { s, w, L1, 0.6 }
    reach_len = L1 + dist(w, t)
  end
  -- the push as he goes (in m/s: the previous position set back by it)
  local h0 = 1/60/RG.SUB
  local function give(n, vx, vy, vz) local q = p(n); q.ox = q.x - vx*h0; q.oy = q.y - vy*h0; q.oz = q.z - vz*h0 end
  if opts.push then for _, n in ipairs({ 'chest', 'neck', 'head', 'sh1', 'sh2' }) do give(n, opts.push[1], opts.push[2], opts.push[3]) end end
  if opts.turn then local q = p(opts.turn_side or 'sh1'); q.ox = q.ox - opts.turn[1]*h0; q.oy = q.oy - opts.turn[2]*h0; q.oz = q.oz - opts.turn[3]*h0 end

  local ground, egg = opts.ground_y, opts.egg
  local function collide(q)
    local g = ground(q.x, q.z) + q.r
    if q.y < g then
      -- (2026-10-10: each part of him sounds the first time it meets the floor, as hard as it came down)
      if not q.landed then q.landed = true; AU.play('lich_thud', { pos = { q.x, g, q.z }, volume = math.max(0.15, math.min(1, (q.oy - q.y)*40)), gap = 0.07 }) end
      q.y = g
      local f = RG.FRICTION
      q.ox = q.x - (q.x - q.ox)*f; q.oz = q.z - (q.z - q.oz)*f
      if q.oy < q.y then q.oy = q.y - (q.y - q.oy)*0.2 end
    end
    if egg then
      local dx, dy, dz = q.x - egg.x, q.y - egg.y, q.z - egg.z
      local d = sqrt(dx*dx + dy*dy + dz*dz)
      local m = egg.r + q.r
      if d < m and d > 1e-6 then local k = m/d; q.x = egg.x + dx*k; q.y = egg.y + dy*k; q.z = egg.z + dz*k end
    end
  end
  -- knees forward of the hip-ankle line, elbows behind the shoulder-wrist line (the torso's front)
  local function front()
    local L, Rr, pl, ch = p('hip2'), p('hip1'), p('pelvis'), p('chest')
    local xx, xy, xz = L.x - Rr.x, L.y - Rr.y, L.z - Rr.z
    local yx, yy, yz = ch.x - pl.x, ch.y - pl.y, ch.z - pl.z
    local zx, zy, zz = xy*yz - xz*yy, xz*yx - xx*yz, xx*yy - xy*yx
    local l = sqrt(zx*zx + zy*zy + zz*zz); if l < 1e-6 then return 0, 0, 0 end
    return zx/l, zy/l, zz/l
  end
  local function hinge(a, j, b, fx, fy, fz, sign)
    local A, J, B = p(a), p(j), p(b)
    local mx, my, mz = (A.x + B.x)/2, (A.y + B.y)/2, (A.z + B.z)/2
    local d = ((J.x - mx)*fx + (J.y - my)*fy + (J.z - mz)*fz)*sign
    if d < 0.01 then local k = (0.01 - d)*sign*0.5; J.x = J.x + fx*k; J.y = J.y + fy*k; J.z = J.z + fz*k end
  end

  local rag = { P = P, t = 0 }
  function rag.step(dt)
    rag.t = rag.t + dt
    local h = dt/RG.SUB
    for _ = 1, RG.SUB do
      local damp = RG.DAMP
      for _, q in ipairs(P) do
        local vx, vy, vz = (q.x - q.ox)*damp, (q.y - q.oy)*damp, (q.z - q.oz)*damp
        q.ox, q.oy, q.oz = q.x, q.y, q.z
        q.x, q.y, q.z = q.x + vx, q.y + vy - RG.G*h*h, q.z + vz
      end
      if R then
        -- drawn toward the egg: the wrist and fingertip toward where a straight arm would reach, the shoulder back by as
        -- much (a muscle, not a hand from outside: round 59b found the old one-sided pull dragging his whole body across
        -- the floor to the egg); strong as he falls, holding after
        local s = p('sh' .. R)
        -- (2026-10-16: reach_from, where his hand was when he died; the point it reaches for slides from there to reach_to
        -- over RG.REACH_T s. His last gesture leaves the arm pointing down at the floor, and pulled at once toward the egg
        -- it swung up against the floor's friction and threw him 1.5-3.5 m across it, up to 26 m/s)
        local rt = opts.reach_to
        local rf = opts.reach_from
        local rx, ry, rz = rt[1], rt[2], rt[3]
        if rf then
          local u = min(1, rag.t/RG.REACH_T)
          u = u*u*(3 - 2*u)
          rx, ry, rz = rf[1] + (rx - rf[1])*u, rf[2] + (ry - rf[2])*u, rf[3] + (rz - rf[3])*u
        end
        local tx, ty, tz = rx - s.x, ry - s.y, rz - s.z
        local l = sqrt(tx*tx + ty*ty + tz*tz)
        local fk = 1 - 0.7*min(1, max(0, (rag.t - 1.0)/1.0))
        if l > 1e-6 then
          tx, ty, tz = tx/l, ty/l, tz/l
          for _, e in ipairs({ { 'tip' .. R, reach_len, 0.05 }, { 'wr' .. R, reach_len*0.86, 0.03 } }) do
            local q = p(e[1])
            local k = e[3]*fk
            local dx, dy, dz = (s.x + tx*e[2] - q.x)*k, (s.y + ty*e[2] - q.y)*k, (s.z + tz*e[2] - q.z)*k
            q.x, q.y, q.z = q.x + dx*0.5, q.y + dy*0.5, q.z + dz*0.5
            s.x, s.y, s.z = s.x - dx*0.5, s.y - dy*0.5, s.z - dz*0.5
          end
        end
      end
      for _ = 1, RG.ITER do
        for _, c in ipairs(C) do
          local A, B, rest, k = c[1], c[2], c[3], c[4]
          local dx, dy, dz = B.x - A.x, B.y - A.y, B.z - A.z
          local d = sqrt(dx*dx + dy*dy + dz*dz)
          if d > 1e-9 then
            local m = (d - rest)/d*0.5*k
            A.x = A.x + dx*m; A.y = A.y + dy*m; A.z = A.z + dz*m
            B.x = B.x - dx*m; B.y = B.y - dy*m; B.z = B.z - dz*m
          end
        end
        local fx, fy, fz = front()
        for k = 1, 2 do
          hinge('hip' .. k, 'kn' .. k, 'an' .. k, fx, fy, fz, 1)
          if k ~= R then hinge('sh' .. k, 'el' .. k, 'wr' .. k, fx, fy, fz, -1) end
        end
        for _, q in ipairs(P) do collide(q) end
      end
    end
  end

  -- each node's frame from its points: `ax` from a to b (its bone), `ref` a sideways direction
  local M4, Qb, Qi = Matrix4.new(), Quaternion.new(), Quaternion.new()
  local function frame(out, ax, ay, az, rx, ry, rz)
    local l = sqrt(ax*ax + ay*ay + az*az)
    ax, ay, az = ax/l, ay/l, az/l
    local d = rx*ax + ry*ay + rz*az
    local xx, xy, xz = rx - d*ax, ry - d*ay, rz - d*az
    local xl = sqrt(xx*xx + xy*xy + xz*xz)
    if xl < 1e-6 then xx, xy, xz = 1, 0, 0; xl = 1 end
    xx, xy, xz = xx/xl, xy/xl, xz/xl
    local zx, zy, zz = xy*az - xz*ay, xz*ax - xx*az, xx*ay - xy*ax
    M4:set(xx, ax, zx, 0, xy, ay, zy, 0, xz, az, zz, 0, 0, 0, 0, 1)
    return out:set_from_rotation_matrix(M4)
  end
  local function seg(a, b) local A, B = p(a), p(b); return B.x - A.x, B.y - A.y, B.z - A.z end
  -- name, node, its parent's entry (nil: the body), its bone (a, b), its sideways reference (a, b)
  local DEF = {
    { 'pelvis', N.pelvis, nil, 'pelvis', 'chest', 'hip1', 'hip2' },
    { 'spine', N.spine, 'pelvis', 'pelvis', 'chest', 'sh1', 'sh2' },
    { 'chest', N.chest, 'spine', 'chest', 'neck', 'sh1', 'sh2' },
    { 'neck', N.neck, 'chest', 'neck', 'head', 'sh1', 'sh2' },
    { 'head', N.head, 'neck', 'neck', 'head', 'sh1', 'sh2' },
  }
  for k, a in ipairs(arms) do
    DEF[#DEF + 1] = { 'sh' .. k, a.sh, 'chest', 'sh' .. k, 'el' .. k, 'sh1', 'sh2' }
    DEF[#DEF + 1] = { 'el' .. k, a.el, 'sh' .. k, 'el' .. k, 'wr' .. k, 'sh1', 'sh2' }
    DEF[#DEF + 1] = { 'wr' .. k, a.wr, 'el' .. k, 'wr' .. k, 'tip' .. k, 'sh1', 'sh2' }
  end
  for k, l in ipairs(legs) do
    DEF[#DEF + 1] = { 'hip' .. k, l.hip, 'pelvis', 'hip' .. k, 'kn' .. k, 'hip1', 'hip2' }
    DEF[#DEF + 1] = { 'kn' .. k, l.kn, 'hip' .. k, 'kn' .. k, 'an' .. k, 'hip1', 'hip2' }
    DEF[#DEF + 1] = { 'an' .. k, l.an, 'kn' .. k, 'an' .. k, 'toe' .. k, 'hip1', 'hip2' }
  end
  -- the turn of each node against its frame, as he dies
  local OFF, QW = {}, {}
  for _, d in ipairs(DEF) do
    local ax, ay, az = seg(d[4], d[5])
    local rx, ry, rz = seg(d[7], d[6])
    frame(Qb, ax, ay, az, rx, ry, rz)
    d[2]:update_world_matrix(true, false)
    local qn = Quaternion.new(); d[2]:get_world_quaternion(qn)
    OFF[d[1]] = Quaternion.new():copy(Qb):invert():multiply(qn)
    QW[d[1]] = Quaternion.new()
  end
  local body, root = lich.body, lich.root
  local RQ, BP = Quaternion.new(), Vector3.new()
  function rag.apply()
    for _, d in ipairs(DEF) do
      local ax, ay, az = seg(d[4], d[5])
      local rx, ry, rz = seg(d[7], d[6])
      frame(Qb, ax, ay, az, rx, ry, rz)
      QW[d[1]]:copy(Qb):multiply(OFF[d[1]])
    end
    -- the body where the pelvis is (the pelvis node sits at the body's origin, unturned)
    root:update_world_matrix(true, false)
    root:get_world_quaternion(RQ)
    RQ:invert()
    local pl = p('pelvis')
    BP:set(pl.x, pl.y, pl.z)
    root:world_to_local(BP)
    body.position:copy(BP)
    body.quaternion:copy(RQ):multiply(QW.pelvis)
    N.pelvis.quaternion:set(0, 0, 0, 1)
    for _, d in ipairs(DEF) do
      if d[3] then d[2].quaternion:copy(Qi:copy(QW[d[3]]):invert():multiply(QW[d[1]])) end
    end
  end
  return rag
end

return RG
