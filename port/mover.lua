--[[
  mover.lua -- the port to Anchor: web/src/mover.js. The lich's body through the room: he eases
  into motion, drifts out of it, turns to face where he is sent (or, with `face`, what he points
  at), rides over stones, is stopped by rock, the egg and the room camera's edges; each tick he
  hands lich.pose() what his pelvis felt. Round 63: mover.free = nothing stops him (his walk in
  from out of the frame, where the grid is all edge).
]]
local TM = require('port.three.math')
local Vector2, Vector3 = TM.Vector2, TM.Vector3
local sqrt, sin, cos, exp, atan2, min, max = math.sqrt, math.sin, math.cos, math.exp, math.atan, math.min, math.max

local MV = {}
MV.MOVE = {
  speed = 2.6,
  acc = 7.0, tau_acc = 0.3,
  dec = 5.0, tau_dec = 0.38,
  jerk = 11,
  radius = 0.34,
  turn_f = 0.8, turn_z = 0.85, turn_amax = 22, turn_vmax = 5.5,
  turn_f_point = 2.0, turn_amax_point = 45, turn_vmax_point = 8,
  bob = 0.05,
}
local MOVE = MV.MOVE
local function clamp(x, a, b) return x < a and a or (x > b and b or x) end
local function wrap(a) return atan2(sin(a), cos(a)) end

function MV.create(nav, lich, start, yaw0)
  local p = start:clone()
  local v = Vector3.new()
  local push = Vector2.new()
  local vy, yaw, yaw_v, yaw_a, want_yaw = 0, yaw0, 0, 0, yaw0
  local face = { on = false, yaw = 0, half = 1.31 }
  local prev_p, prev_vel, vel, acc = p:clone(), Vector3.new(), Vector3.new(), Vector3.new()
  local motion = { a = { 0, 0, 0 }, v = { 0, 0, 0 }, push = { 0, 0 }, yaw_a = 0, yaw_v = 0, look = 0 }
  local function height_at(t) return nav.floor(p.x, p.z) + lich.hover_h + MOVE.bob*sin(t*1.1) + 0.015*sin(t*0.63 + 1.0) end
  p.y = height_at(0)
  prev_p:copy(p)

  local mover = { p = p, v = v, motion = motion, face = face }
  function mover.tick(t, dt, want)
    local wl = js_hypot(want.x, want.z)
    local pushing = wl > 0.01
    local tau = pushing and MOVE.tau_acc or MOVE.tau_dec
    local amax = pushing and MOVE.acc or MOVE.dec
    local cx, cz = (want.x - v.x)/tau, (want.z - v.z)/tau
    local cl = js_hypot(cx, cz)
    if cl > amax then cx = cx*(amax/cl); cz = cz*(amax/cl) end
    local k = 1 - exp(-MOVE.jerk*dt)
    push.x = push.x + (cx - push.x)*k; push.y = push.y + (cz - push.y)*k
    v.x = v.x + push.x*dt; v.z = v.z + push.y*dt
    if not pushing and js_hypot(v.x, v.z) < 0.02 and js_hypot(push.x, push.y) < 0.05 then v.x = 0; v.z = 0; push:set(0, 0) end
    p.x = p.x + v.x*dt; p.z = p.z + v.z*dt
    if not mover.free and nav.resolve(p, v, MOVE.radius) then
      local s = js_hypot(v.x, v.z)
      local ps = js_hypot(push.x, push.y)
      if s > 1e-4 and ps > 1e-4 then local along = (push.x*v.x + push.y*v.z)/s; push:set(v.x/s*along, v.z/s*along) end
    end
    local wv = 6.2832*1.0
    vy = vy + (wv*wv*(height_at(t) - p.y) - 2*0.65*wv*vy)*dt
    p.y = p.y + vy*dt
    if pushing then want_yaw = atan2(want.x, want.z) end
    if face.on then
      local rel = wrap(face.yaw - want_yaw)
      if math.abs(rel) > face.half then want_yaw = wrap(face.yaw - (rel > 0 and 1 or (rel < 0 and -1 or 0))*face.half) end
    end
    local wy = 6.2832*(face.on and MOVE.turn_f_point or MOVE.turn_f)
    local tam = face.on and MOVE.turn_amax_point or MOVE.turn_amax
    local tvm = face.on and MOVE.turn_vmax_point or MOVE.turn_vmax
    -- (round 50: face.boost, a snappier turn while he fires in turn or sweeps; nil = as before)
    if face.on and face.boost then wy = wy*face.boost; tam = tam*face.boost*face.boost; tvm = tvm*face.boost end
    yaw_a = clamp(wy*wy*wrap(want_yaw - yaw) - 2*MOVE.turn_z*wy*yaw_v, -tam, tam)
    yaw_v = clamp(yaw_v + yaw_a*dt, -tvm, tvm)
    yaw = wrap(yaw + yaw_v*dt)
    vel:sub_vectors(p, prev_p):divide_scalar(dt)
    acc:sub_vectors(vel, prev_vel):divide_scalar(dt)
    if acc:length() > 20 then acc:set_length(20) end
    prev_p:copy(p); prev_vel:copy(vel)
    local sy, cy = sin(yaw), cos(yaw)
    motion.a[1] = acc.x*cy - acc.z*sy; motion.a[2] = acc.y; motion.a[3] = acc.x*sy + acc.z*cy
    motion.v[1] = vel.x*cy - vel.z*sy; motion.v[2] = vel.y; motion.v[3] = vel.x*sy + vel.z*cy
    local qx = ((want.x - vel.x)*cy - (want.z - vel.z)*sy)/MOVE.speed
    local qz = ((want.x - vel.x)*sy + (want.z - vel.z)*cy)/MOVE.speed
    local ql = js_hypot(qx, qz)
    if ql > 1 then qx = qx/ql; qz = qz/ql end
    motion.push[1] = qx; motion.push[2] = qz
    motion.yaw_a = yaw_a; motion.yaw_v = yaw_v
    motion.look = pushing and wrap(want_yaw - yaw) or 0
    lich.root.position:copy(p)
    lich.root.rotation.y = yaw
  end
  function mover.yaw() return yaw end
  function mover.speed() return js_hypot(v.x, v.z) end
  function mover.place(x, z, y_)
    if y_ == nil then y_ = yaw end
    p.x = x; p.z = z; v:set(0, 0, 0); push:set(0, 0); yaw = y_; want_yaw = y_; yaw_v = 0
    p.y = height_at(0); vy = 0; prev_p:copy(p); prev_vel:set(0, 0, 0)
    lich.root.position:copy(p); lich.root.rotation.y = yaw
  end
  return mover
end

return MV
