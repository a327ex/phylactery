--[[
  body.lua -- the port to Anchor: web/src/body.js. A small rigid body that drops onto the cave
  floor (a power's object, let go beside the lich): a cloud of contact points on its surface (or
  one sphere) against the floor's height field, plus the egg as a round wall; sequential impulses
  with restitution and Coulomb friction, rolling resistance, and sleep once it lies still.
  (A point's floor height is looked up once per pass and reused, as the same call would return it.)
]]
local TM = require('port.three.math')
local Vector3, Quaternion, Matrix3, Matrix4 = TM.Vector3, TM.Quaternion, TM.Matrix3, TM.Matrix4
local abs, exp, min, max, sqrt = math.abs, math.exp, math.min, math.max, math.sqrt

local BO = {}
local SUB = 4
local G = 9.81

function BO.create(opts)
  local b = { x = Vector3.new(), v = Vector3.new(), q = Quaternion.new(), w = Vector3.new(), asleep = false, still = 0, contact = false, landed = 0, on_hit = nil }
  local m = opts.mass or 1
  local im = 1/m
  local Ib = opts.inertia or Vector3.new(0.01, 0.01, 0.01)
  local Ibi = Vector3.new(1/Ib.x, 1/Ib.y, 1/Ib.z)
  local e = opts.restitution or 0.25
  local mu = opts.friction or 0.6
  local roll = opts.rolling or 0.5
  local rr = opts.rr or 0
  local pts, rad = opts.points, opts.sphere or 0
  local floor_f = opts.floor
  local R, Rt, m4 = Matrix3.new(), Matrix3.new(), Matrix4.new()
  local anchor = { x = Vector3.new(1e9, 0, 0), q = Quaternion.new() }
  local r, p, n, vp, t, tmp, tmp2 = Vector3.new(), Vector3.new(), Vector3.new(), Vector3.new(), Vector3.new(), Vector3.new(), Vector3.new()

  local function Iinv(a, out)
    out:copy(a):apply_matrix3(Rt)
    out:set(out.x*Ibi.x, out.y*Ibi.y, out.z*Ibi.z)
    return out:apply_matrix3(R)
  end
  local function floor_n(x, z, out)
    local h = 0.03
    return out:set(floor_f(x - h, z) - floor_f(x + h, z), 2*h, floor_f(x, z - h) - floor_f(x, z + h)):normalize()
  end
  local function contact(pw, nn, depth, strength)
    r:sub_vectors(pw, b.x)
    vp:cross_vectors(b.w, r):add(b.v)
    local vn = vp:dot(nn)
    b.x:add_scaled_vector(nn, depth*0.6*strength)
    if vn >= 0 then return 0 end
    tmp:cross_vectors(r, nn); Iinv(tmp, tmp2); tmp:cross_vectors(tmp2, r)
    local kn = im + nn:dot(tmp)
    local ee = -vn > 0.5 and e or 0
    local jn = -(1 + ee)*vn/kn*strength
    b.v:add_scaled_vector(nn, jn*im)
    tmp:cross_vectors(r, nn):multiply_scalar(jn); Iinv(tmp, tmp2); b.w:add(tmp2)
    vp:cross_vectors(b.w, r):add(b.v)
    t:copy(vp):add_scaled_vector(nn, -vp:dot(nn))
    local vt = t:length()
    if vt > 1e-5 then
      t:multiply_scalar(1/vt)
      tmp:cross_vectors(r, t); Iinv(tmp, tmp2); tmp:cross_vectors(tmp2, r)
      local kt = im + t:dot(tmp)
      local jt = min(vt/kt, mu*jn)
      b.v:add_scaled_vector(t, -jt*im)
      tmp:cross_vectors(r, t):multiply_scalar(-jt); Iinv(tmp, tmp2); b.w:add(tmp2)
    end
    return -vn
  end

  local NP = pts and #pts or 0
  local PX, PY, PZ, FY = {}, {}, {}, {}
  local wq = Quaternion.new()
  function b.step(dt)
    if b.asleep then return end
    local h = dt/SUB
    local touched = false
    for _ = 1, SUB do
      b.v.y = b.v.y - G*h
      b.x:add_scaled_vector(b.v, h)
      -- q += 0.5 w q h
      wq:set(b.w.x*h*0.5, b.w.y*h*0.5, b.w.z*h*0.5, 0):multiply(b.q)
      b.q:set(b.q.x + wq.x, b.q.y + wq.y, b.q.z + wq.z, b.q.w + wq.w):normalize()
      m4:make_rotation_from_quaternion(b.q); R:set_from_matrix4(m4); Rt:copy(R):transpose()
      b.contact = false
      local hit = 0
      for _ = 1, 2 do
        if rad ~= 0 then
          local fy = floor_f(b.x.x, b.x.z)
          floor_n(b.x.x, b.x.z, n)
          local d = fy + rad/max(n.y, 0.5) - b.x.y
          if d > 0 then p:copy(b.x):add_scaled_vector(n, -rad); hit = max(hit, contact(p, n, d*n.y, 1)); b.contact = true end
        else
          -- the deepest points carry the contact; all touching points share it
          local cnt = 0
          for k = 1, NP do
            p:copy(pts[k]):apply_matrix3(R):add(b.x)
            PX[k], PY[k], PZ[k] = p.x, p.y, p.z
            local fy = floor_f(p.x, p.z)
            FY[k] = fy
            if p.y < fy then cnt = cnt + 1 end
          end
          for k = 1, NP do
            -- (the same point and the same floor as the count above: b.x moves only after this loop's contacts... so recompute)
            p:copy(pts[k]):apply_matrix3(R):add(b.x)
            local fy
            if p.x == PX[k] and p.z == PZ[k] then fy = FY[k] else fy = floor_f(p.x, p.z) end
            if not (p.y >= fy) then
              floor_n(p.x, p.z, n)
              hit = max(hit, contact(p, n, (fy - p.y)*n.y, 1/max(1, cnt*0.5)))
              b.contact = true
            end
          end
        end
        local eg = opts.egg
        if eg then
          local function wall(qx, qy, qz)
            local dx, dz = qx - eg.x, qz - eg.z
            local dd = js_hypot(dx, dz)
            local rr2 = eg.r + rad
            if dd < rr2 and qy < eg.top and dd > 1e-4 then
              n:set(dx/dd, 0, dz/dd)
              p:set(qx, qy, qz):add_scaled_vector(n, -rad)
              contact(p, n, rr2 - dd, 1)
            end
          end
          if rad ~= 0 then wall(b.x.x, b.x.y, b.x.z)
          else
            -- (body.js lists every point first, then walls them: the list is taken before any wall contact)
            local L = {}
            for k = 1, NP do local q = pts[k]:clone():apply_matrix3(R):add(b.x); L[k] = q end
            for k = 1, NP do wall(L[k].x, L[k].y, L[k].z) end
          end
        end
      end
      if b.contact then
        local k = exp(-((b.w:length() < 0.5 and b.v:length() < 0.08) and 8 or roll)*h)
        b.w:multiply_scalar(k)
        b.v.x = b.v.x*exp(-0.4*h); b.v.z = b.v.z*exp(-0.4*h)
        if rr > 0 then
          local hv, dv = js_hypot(b.v.x, b.v.z), rr*G*h
          local s = hv > dv and (hv - dv)/hv or 0
          b.v.x = b.v.x*s; b.v.z = b.v.z*s; b.w:multiply_scalar(s > 0 and max(s, 0.9) or 0.5)
        end
      end
      if hit > 0.4 and b.on_hit then b.on_hit(hit) end
      touched = touched or b.contact
    end
    b.contact = touched
    if b.contact then b.landed = b.landed + dt end
    if not b.contact or b.x:distance_to(anchor.x) > 0.004 or b.q:angle_to(anchor.q) > 0.03 then anchor.x:copy(b.x); anchor.q:copy(b.q); b.still = 0
    else b.still = b.still + dt end
    if b.still > 0.5 then b.asleep = true; b.v:set(0, 0, 0); b.w:set(0, 0, 0) end
  end
  function b.wake() b.asleep = false; b.still = 0 end
  return b
end

function BO.box_inertia(m, w, h, d) return Vector3.new(m*(h*h + d*d)/12, m*(w*w + d*d)/12, m*(w*w + h*h)/12) end

return BO
