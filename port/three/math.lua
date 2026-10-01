--[[
  three/math.lua -- the port to Anchor (2026-09-30): three.js r170's math, the subset the game
  uses, with its formulas kept exactly (the port must draw what three.js draws). Method names are
  three.js's in snake_case (addScaledVector -> add_scaled_vector). Matrices store `elements`
  1..16 column-major, as three.js stores 0..15.
]]

local sqrt, sin, cos, atan2, asin, acos, abs, floor, min, max, huge =
  math.sqrt, math.sin, math.cos, math.atan, math.asin, math.acos, math.abs, math.floor, math.min, math.max, math.huge

local M = {}
local clamp = function(x, a, b) return x < a and a or (x > b and b or x) end
M.clamp = clamp
M.lerp = function(a, b, t) return a + (b - a)*t end
M.smoothstep = function(x, a, b) if x <= a then return 0 end if x >= b then return 1 end x = (x - a)/(b - a); return x*x*(3 - 2*x) end
M.deg2rad = math.pi/180
M.rad2deg = 180/math.pi

-- ---------------------------------------------------------------------------- Vector2
local Vector2 = {}; Vector2.__index = Vector2
M.Vector2 = Vector2
function Vector2.new(x, y) return setmetatable({ x = x or 0, y = y or 0, is_vector2 = true }, Vector2) end
function Vector2:set(x, y) self.x, self.y = x, y; return self end
function Vector2:copy(v) self.x, self.y = v.x, v.y; return self end
function Vector2:clone() return Vector2.new(self.x, self.y) end
function Vector2:add(v) self.x, self.y = self.x + v.x, self.y + v.y; return self end
function Vector2:sub(v) self.x, self.y = self.x - v.x, self.y - v.y; return self end
function Vector2:multiply_scalar(s) self.x, self.y = self.x*s, self.y*s; return self end
function Vector2:length() return sqrt(self.x*self.x + self.y*self.y) end
function Vector2:normalize() local l = self:length(); if l == 0 then l = 1 end; return self:multiply_scalar(1/l) end
function Vector2:dot(v) return self.x*v.x + self.y*v.y end
function Vector2:to_array(a, o) a = a or {}; o = o or 0; a[o + 1], a[o + 2] = self.x, self.y; return a end
function Vector2:from_array(a, o) o = o or 0; self.x, self.y = a[o + 1], a[o + 2]; return self end

-- ---------------------------------------------------------------------------- Vector3
local Vector3 = {}; Vector3.__index = Vector3
M.Vector3 = Vector3
function Vector3.new(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, Vector3) end
local V3 = Vector3.new
function Vector3:set(x, y, z) self.x, self.y, self.z = x, y, z; return self end
function Vector3:set_scalar(s) self.x, self.y, self.z = s, s, s; return self end
function Vector3:copy(v) self.x, self.y, self.z = v.x, v.y, v.z; return self end
function Vector3:clone() return V3(self.x, self.y, self.z) end
function Vector3:add(v) self.x, self.y, self.z = self.x + v.x, self.y + v.y, self.z + v.z; return self end
function Vector3:add_scalar(s) self.x, self.y, self.z = self.x + s, self.y + s, self.z + s; return self end
function Vector3:add_vectors(a, b) self.x, self.y, self.z = a.x + b.x, a.y + b.y, a.z + b.z; return self end
function Vector3:add_scaled_vector(v, s) self.x, self.y, self.z = self.x + v.x*s, self.y + v.y*s, self.z + v.z*s; return self end
function Vector3:sub(v) self.x, self.y, self.z = self.x - v.x, self.y - v.y, self.z - v.z; return self end
function Vector3:sub_vectors(a, b) self.x, self.y, self.z = a.x - b.x, a.y - b.y, a.z - b.z; return self end
function Vector3:multiply(v) self.x, self.y, self.z = self.x*v.x, self.y*v.y, self.z*v.z; return self end
function Vector3:multiply_scalar(s) self.x, self.y, self.z = self.x*s, self.y*s, self.z*s; return self end
function Vector3:divide_scalar(s) return self:multiply_scalar(1/s) end
function Vector3:negate() self.x, self.y, self.z = -self.x, -self.y, -self.z; return self end
function Vector3:dot(v) return self.x*v.x + self.y*v.y + self.z*v.z end
function Vector3:length_sq() return self.x*self.x + self.y*self.y + self.z*self.z end
function Vector3:length() return sqrt(self.x*self.x + self.y*self.y + self.z*self.z) end
function Vector3:normalize() local l = self:length(); if l == 0 then l = 1 end; return self:multiply_scalar(1/l) end
function Vector3:set_length(l) return self:normalize():multiply_scalar(l) end
function Vector3:distance_to(v) local dx, dy, dz = self.x - v.x, self.y - v.y, self.z - v.z; return sqrt(dx*dx + dy*dy + dz*dz) end
function Vector3:distance_to_squared(v) local dx, dy, dz = self.x - v.x, self.y - v.y, self.z - v.z; return dx*dx + dy*dy + dz*dz end
function Vector3:lerp(v, t) self.x, self.y, self.z = self.x + (v.x - self.x)*t, self.y + (v.y - self.y)*t, self.z + (v.z - self.z)*t; return self end
function Vector3:lerp_vectors(a, b, t) self.x, self.y, self.z = a.x + (b.x - a.x)*t, a.y + (b.y - a.y)*t, a.z + (b.z - a.z)*t; return self end
function Vector3:cross(v) return self:cross_vectors(self, v) end
function Vector3:cross_vectors(a, b)
  local ax, ay, az, bx, by, bz = a.x, a.y, a.z, b.x, b.y, b.z
  self.x, self.y, self.z = ay*bz - az*by, az*bx - ax*bz, ax*by - ay*bx
  return self
end
function Vector3:equals(v) return self.x == v.x and self.y == v.y and self.z == v.z end
function Vector3:min(v) self.x, self.y, self.z = min(self.x, v.x), min(self.y, v.y), min(self.z, v.z); return self end
function Vector3:max(v) self.x, self.y, self.z = max(self.x, v.x), max(self.y, v.y), max(self.z, v.z); return self end
function Vector3:apply_matrix3(m)
  local x, y, z, e = self.x, self.y, self.z, m.elements
  self.x = e[1]*x + e[4]*y + e[7]*z
  self.y = e[2]*x + e[5]*y + e[8]*z
  self.z = e[3]*x + e[6]*y + e[9]*z
  return self
end
function Vector3:apply_normal_matrix(m) return self:apply_matrix3(m):normalize() end
function Vector3:apply_matrix4(m)
  local x, y, z, e = self.x, self.y, self.z, m.elements
  local w = 1/(e[4]*x + e[8]*y + e[12]*z + e[16])
  self.x = (e[1]*x + e[5]*y + e[9]*z + e[13])*w
  self.y = (e[2]*x + e[6]*y + e[10]*z + e[14])*w
  self.z = (e[3]*x + e[7]*y + e[11]*z + e[15])*w
  return self
end
function Vector3:apply_quaternion(q)
  local vx, vy, vz = self.x, self.y, self.z
  local qx, qy, qz, qw = q._x, q._y, q._z, q._w
  local tx = 2*(qy*vz - qz*vy)
  local ty = 2*(qz*vx - qx*vz)
  local tz = 2*(qx*vy - qy*vx)
  self.x = vx + qw*tx + qy*tz - qz*ty
  self.y = vy + qw*ty + qz*tx - qx*tz
  self.z = vz + qw*tz + qx*ty - qy*tx
  return self
end
function Vector3:apply_axis_angle(axis, angle) return self:apply_quaternion(M.Quaternion.new():set_from_axis_angle(axis, angle)) end
function Vector3:apply_euler(e) return self:apply_quaternion(M.Quaternion.new():set_from_euler(e)) end
function Vector3:transform_direction(m)
  local x, y, z, e = self.x, self.y, self.z, m.elements
  self.x = e[1]*x + e[5]*y + e[9]*z
  self.y = e[2]*x + e[6]*y + e[10]*z
  self.z = e[3]*x + e[7]*y + e[11]*z
  return self:normalize()
end
function Vector3:set_from_matrix_position(m) local e = m.elements; self.x, self.y, self.z = e[13], e[14], e[15]; return self end
function Vector3:set_from_matrix_scale(m)
  local e = m.elements
  local sx = sqrt(e[1]*e[1] + e[2]*e[2] + e[3]*e[3])
  local sy = sqrt(e[5]*e[5] + e[6]*e[6] + e[7]*e[7])
  local sz = sqrt(e[9]*e[9] + e[10]*e[10] + e[11]*e[11])
  self.x, self.y, self.z = sx, sy, sz
  return self
end
function Vector3:set_from_matrix_column(m, i) local e = m.elements; local o = i*4; self.x, self.y, self.z = e[o + 1], e[o + 2], e[o + 3]; return self end
function Vector3:project(camera) return self:apply_matrix4(camera.matrix_world_inverse):apply_matrix4(camera.projection_matrix) end
function Vector3:unproject(camera) return self:apply_matrix4(camera.projection_matrix_inverse):apply_matrix4(camera.matrix_world) end
function Vector3:angle_to(v)
  local d = sqrt(self:length_sq()*v:length_sq())
  if d == 0 then return math.pi/2 end
  return acos(clamp(self:dot(v)/d, -1, 1))
end
function Vector3:project_on_plane(n) local d = self:dot(n)/n:length_sq(); return self:add_scaled_vector(n, -d) end
function Vector3:to_array(a, o) a = a or {}; o = o or 0; a[o + 1], a[o + 2], a[o + 3] = self.x, self.y, self.z; return a end
function Vector3:from_array(a, o) o = o or 0; self.x, self.y, self.z = a[o + 1], a[o + 2], a[o + 3]; return self end
function Vector3:set_from_spherical_coords(radius, phi, theta)
  local s = sin(phi)*radius
  self.x, self.y, self.z = s*sin(theta), cos(phi)*radius, s*cos(theta)
  return self
end

-- ---------------------------------------------------------------------------- Vector4
local Vector4 = {}; Vector4.__index = Vector4
M.Vector4 = Vector4
function Vector4.new(x, y, z, w) return setmetatable({ x = x or 0, y = y or 0, z = z or 0, w = w == nil and 1 or w }, Vector4) end
function Vector4:set(x, y, z, w) self.x, self.y, self.z, self.w = x, y, z, w; return self end
function Vector4:copy(v) self.x, self.y, self.z, self.w = v.x, v.y, v.z, v.w; return self end
function Vector4:from_array(a, o) o = o or 0; self.x, self.y, self.z, self.w = a[o + 1], a[o + 2], a[o + 3], a[o + 4]; return self end

-- ---------------------------------------------------------------------------- Quaternion
-- Like three.js, a quaternion tells its owner (an Object3D's Euler) when it changes.
local Quaternion = {}
M.Quaternion = Quaternion
local qget = { x = '_x', y = '_y', z = '_z', w = '_w' }
Quaternion.__index = function(t, k) local f = qget[k]; if f then return rawget(t, f) end; return Quaternion[k] end
Quaternion.__newindex = function(t, k, v) local f = qget[k]; if f then rawset(t, f, v); local cb = rawget(t, '_cb'); if cb then cb() end else rawset(t, k, v) end end
function Quaternion.new(x, y, z, w) return setmetatable({ _x = x or 0, _y = y or 0, _z = z or 0, _w = w == nil and 1 or w }, Quaternion) end
local function qchanged(q) local cb = rawget(q, '_cb'); if cb then cb() end; return q end
function Quaternion:on_change(cb) rawset(self, '_cb', cb); return self end
function Quaternion:set(x, y, z, w) rawset(self, '_x', x); rawset(self, '_y', y); rawset(self, '_z', z); rawset(self, '_w', w); return qchanged(self) end
function Quaternion:clone() return Quaternion.new(self._x, self._y, self._z, self._w) end
function Quaternion:copy(q) rawset(self, '_x', q._x); rawset(self, '_y', q._y); rawset(self, '_z', q._z); rawset(self, '_w', q._w); return qchanged(self) end
function Quaternion:identity() return self:set(0, 0, 0, 1) end
function Quaternion:set_from_euler(e, update)
  local x, y, z, order = e._x, e._y, e._z, e._order
  local c1, c2, c3 = cos(x/2), cos(y/2), cos(z/2)
  local s1, s2, s3 = sin(x/2), sin(y/2), sin(z/2)
  local qx, qy, qz, qw
  if order == 'XYZ' then
    qx = s1*c2*c3 + c1*s2*s3; qy = c1*s2*c3 - s1*c2*s3; qz = c1*c2*s3 + s1*s2*c3; qw = c1*c2*c3 - s1*s2*s3
  elseif order == 'YXZ' then
    qx = s1*c2*c3 + c1*s2*s3; qy = c1*s2*c3 - s1*c2*s3; qz = c1*c2*s3 - s1*s2*c3; qw = c1*c2*c3 + s1*s2*s3
  elseif order == 'ZXY' then
    qx = s1*c2*c3 - c1*s2*s3; qy = c1*s2*c3 + s1*c2*s3; qz = c1*c2*s3 + s1*s2*c3; qw = c1*c2*c3 - s1*s2*s3
  elseif order == 'ZYX' then
    qx = s1*c2*c3 - c1*s2*s3; qy = c1*s2*c3 + s1*c2*s3; qz = c1*c2*s3 - s1*s2*c3; qw = c1*c2*c3 + s1*s2*s3
  elseif order == 'YZX' then
    qx = s1*c2*c3 + c1*s2*s3; qy = c1*s2*c3 + s1*c2*s3; qz = c1*c2*s3 - s1*s2*c3; qw = c1*c2*c3 - s1*s2*s3
  else -- XZY
    qx = s1*c2*c3 - c1*s2*s3; qy = c1*s2*c3 - s1*c2*s3; qz = c1*c2*s3 + s1*s2*c3; qw = c1*c2*c3 + s1*s2*s3
  end
  rawset(self, '_x', qx); rawset(self, '_y', qy); rawset(self, '_z', qz); rawset(self, '_w', qw)
  if update ~= false then qchanged(self) end
  return self
end
function Quaternion:set_from_axis_angle(axis, angle)
  local h = angle/2; local s = sin(h)
  return self:set(axis.x*s, axis.y*s, axis.z*s, cos(h))
end
function Quaternion:set_from_rotation_matrix(m)
  local te = m.elements
  local m11, m12, m13 = te[1], te[5], te[9]
  local m21, m22, m23 = te[2], te[6], te[10]
  local m31, m32, m33 = te[3], te[7], te[11]
  local trace = m11 + m22 + m33
  local x, y, z, w
  if trace > 0 then
    local s = 0.5/sqrt(trace + 1.0)
    w = 0.25/s; x = (m32 - m23)*s; y = (m13 - m31)*s; z = (m21 - m12)*s
  elseif m11 > m22 and m11 > m33 then
    local s = 2.0*sqrt(1.0 + m11 - m22 - m33)
    w = (m32 - m23)/s; x = 0.25*s; y = (m12 + m21)/s; z = (m13 + m31)/s
  elseif m22 > m33 then
    local s = 2.0*sqrt(1.0 + m22 - m11 - m33)
    w = (m13 - m31)/s; x = (m12 + m21)/s; y = 0.25*s; z = (m23 + m32)/s
  else
    local s = 2.0*sqrt(1.0 + m33 - m11 - m22)
    w = (m21 - m12)/s; x = (m13 + m31)/s; y = (m23 + m32)/s; z = 0.25*s
  end
  return self:set(x, y, z, w)
end
function Quaternion:set_from_unit_vectors(from, to)
  local r = from:dot(to) + 1
  local x, y, z, w
  if r < 1e-8 then
    r = 0
    if abs(from.x) > abs(from.z) then x, y, z, w = -from.y, from.x, 0, r
    else x, y, z, w = 0, -from.z, from.y, r end
  else
    x = from.y*to.z - from.z*to.y
    y = from.z*to.x - from.x*to.z
    z = from.x*to.y - from.y*to.x
    w = r
  end
  rawset(self, '_x', x); rawset(self, '_y', y); rawset(self, '_z', z); rawset(self, '_w', w)
  return self:normalize()
end
function Quaternion:angle_to(q) return 2*acos(abs(clamp(self:dot(q), -1, 1))) end
function Quaternion:invert() return self:conjugate() end
function Quaternion:conjugate() rawset(self, '_x', -self._x); rawset(self, '_y', -self._y); rawset(self, '_z', -self._z); return qchanged(self) end
function Quaternion:dot(v) return self._x*v._x + self._y*v._y + self._z*v._z + self._w*v._w end
function Quaternion:length() return sqrt(self._x*self._x + self._y*self._y + self._z*self._z + self._w*self._w) end
function Quaternion:normalize()
  local l = self:length()
  if l == 0 then rawset(self, '_x', 0); rawset(self, '_y', 0); rawset(self, '_z', 0); rawset(self, '_w', 1)
  else l = 1/l; rawset(self, '_x', self._x*l); rawset(self, '_y', self._y*l); rawset(self, '_z', self._z*l); rawset(self, '_w', self._w*l) end
  return qchanged(self)
end
function Quaternion:multiply(q) return self:multiply_quaternions(self, q) end
function Quaternion:premultiply(q) return self:multiply_quaternions(q, self) end
function Quaternion:multiply_quaternions(a, b)
  local qax, qay, qaz, qaw = a._x, a._y, a._z, a._w
  local qbx, qby, qbz, qbw = b._x, b._y, b._z, b._w
  rawset(self, '_x', qax*qbw + qaw*qbx + qay*qbz - qaz*qby)
  rawset(self, '_y', qay*qbw + qaw*qby + qaz*qbx - qax*qbz)
  rawset(self, '_z', qaz*qbw + qaw*qbz + qax*qby - qay*qbx)
  rawset(self, '_w', qaw*qbw - qax*qbx - qay*qby - qaz*qbz)
  return qchanged(self)
end
function Quaternion:slerp(qb, t)
  if t == 0 then return self end
  if t == 1 then return self:copy(qb) end
  local x, y, z, w = self._x, self._y, self._z, self._w
  local cos_half = w*qb._w + x*qb._x + y*qb._y + z*qb._z
  if cos_half < 0 then
    rawset(self, '_w', -qb._w); rawset(self, '_x', -qb._x); rawset(self, '_y', -qb._y); rawset(self, '_z', -qb._z)
    cos_half = -cos_half
  else
    rawset(self, '_w', qb._w); rawset(self, '_x', qb._x); rawset(self, '_y', qb._y); rawset(self, '_z', qb._z)
  end
  if cos_half >= 1.0 then
    rawset(self, '_w', w); rawset(self, '_x', x); rawset(self, '_y', y); rawset(self, '_z', z)
    return self
  end
  local sq = 1.0 - cos_half*cos_half
  if sq <= 2.220446049250313e-16 then
    local s = 1 - t
    rawset(self, '_w', s*w + t*self._w); rawset(self, '_x', s*x + t*self._x); rawset(self, '_y', s*y + t*self._y); rawset(self, '_z', s*z + t*self._z)
    self:normalize()
    return self
  end
  local sin_half = sqrt(sq)
  local half = atan2(sin_half, cos_half)
  local ra, rb = sin((1 - t)*half)/sin_half, sin(t*half)/sin_half
  rawset(self, '_w', w*ra + self._w*rb); rawset(self, '_x', x*ra + self._x*rb); rawset(self, '_y', y*ra + self._y*rb); rawset(self, '_z', z*ra + self._z*rb)
  return qchanged(self)
end
function Quaternion:slerp_quaternions(a, b, t) return self:copy(a):slerp(b, t) end
function Quaternion:equals(q) return q._x == self._x and q._y == self._y and q._z == self._z and q._w == self._w end
function Quaternion:to_array(a, o) a = a or {}; o = o or 0; a[o + 1], a[o + 2], a[o + 3], a[o + 4] = self._x, self._y, self._z, self._w; return a end
function Quaternion:from_array(a, o) o = o or 0; return self:set(a[o + 1], a[o + 2], a[o + 3], a[o + 4]) end

-- ---------------------------------------------------------------------------- Euler
local Euler = {}
M.Euler = Euler
local eget = { x = '_x', y = '_y', z = '_z', order = '_order' }
Euler.__index = function(t, k) local f = eget[k]; if f then return rawget(t, f) end; return Euler[k] end
Euler.__newindex = function(t, k, v) local f = eget[k]; if f then rawset(t, f, v); local cb = rawget(t, '_cb'); if cb then cb() end else rawset(t, k, v) end end
function Euler.new(x, y, z, order) return setmetatable({ _x = x or 0, _y = y or 0, _z = z or 0, _order = order or 'XYZ' }, Euler) end
local function echanged(e) local cb = rawget(e, '_cb'); if cb then cb() end; return e end
function Euler:on_change(cb) rawset(self, '_cb', cb); return self end
function Euler:set(x, y, z, order) rawset(self, '_x', x); rawset(self, '_y', y); rawset(self, '_z', z); if order then rawset(self, '_order', order) end; return echanged(self) end
function Euler:copy(e) rawset(self, '_x', e._x); rawset(self, '_y', e._y); rawset(self, '_z', e._z); rawset(self, '_order', e._order); return echanged(self) end
function Euler:clone() return Euler.new(self._x, self._y, self._z, self._order) end
function Euler:set_from_rotation_matrix(m, order, update)
  local te = m.elements
  local m11, m12, m13 = te[1], te[5], te[9]
  local m21, m22, m23 = te[2], te[6], te[10]
  local m31, m32, m33 = te[3], te[7], te[11]
  order = order or self._order
  local x, y, z
  if order == 'XYZ' then
    y = asin(clamp(m13, -1, 1))
    if abs(m13) < 0.9999999 then x = atan2(-m23, m33); z = atan2(-m12, m11) else x = atan2(m32, m22); z = 0 end
  elseif order == 'YXZ' then
    x = asin(-clamp(m23, -1, 1))
    if abs(m23) < 0.9999999 then y = atan2(m13, m33); z = atan2(m21, m22) else y = atan2(-m31, m11); z = 0 end
  elseif order == 'ZXY' then
    x = asin(clamp(m32, -1, 1))
    if abs(m32) < 0.9999999 then y = atan2(-m31, m33); z = atan2(-m12, m22) else y = 0; z = atan2(m21, m11) end
  elseif order == 'ZYX' then
    y = asin(-clamp(m31, -1, 1))
    if abs(m31) < 0.9999999 then x = atan2(m32, m33); z = atan2(m21, m11) else x = 0; z = atan2(-m12, m22) end
  elseif order == 'YZX' then
    z = asin(clamp(m21, -1, 1))
    if abs(m21) < 0.9999999 then x = atan2(-m23, m22); y = atan2(-m31, m11) else x = 0; y = atan2(m13, m33) end
  else -- XZY
    z = asin(-clamp(m12, -1, 1))
    if abs(m12) < 0.9999999 then x = atan2(m32, m22); y = atan2(m13, m11) else x = atan2(-m23, m33); y = 0 end
  end
  rawset(self, '_x', x); rawset(self, '_y', y); rawset(self, '_z', z); rawset(self, '_order', order)
  if update ~= false then echanged(self) end
  return self
end
local _em = nil
function Euler:set_from_quaternion(q, order, update)
  _em = _em or M.Matrix4.new()
  _em:make_rotation_from_quaternion(q)
  return self:set_from_rotation_matrix(_em, order, update)
end

-- ---------------------------------------------------------------------------- Matrix3
local Matrix3 = {}; Matrix3.__index = Matrix3
M.Matrix3 = Matrix3
function Matrix3.new() return setmetatable({ elements = { 1, 0, 0, 0, 1, 0, 0, 0, 1 } }, Matrix3) end
function Matrix3:set(n11, n12, n13, n21, n22, n23, n31, n32, n33)
  local te = self.elements
  te[1], te[2], te[3] = n11, n21, n31
  te[4], te[5], te[6] = n12, n22, n32
  te[7], te[8], te[9] = n13, n23, n33
  return self
end
function Matrix3:identity() return self:set(1, 0, 0, 0, 1, 0, 0, 0, 1) end
function Matrix3:copy(m) local a, b = self.elements, m.elements; for i = 1, 9 do a[i] = b[i] end; return self end
function Matrix3:clone() return Matrix3.new():copy(self) end
function Matrix3:set_from_matrix4(m)
  local me = m.elements
  return self:set(me[1], me[5], me[9], me[2], me[6], me[10], me[3], me[7], me[11])
end
function Matrix3:determinant()
  local te = self.elements
  local a, b, c, d, e, f, g, h, i = te[1], te[2], te[3], te[4], te[5], te[6], te[7], te[8], te[9]
  return a*e*i - a*f*h - b*d*i + b*f*g + c*d*h - c*e*g
end
function Matrix3:invert()
  local te = self.elements
  local n11, n21, n31 = te[1], te[2], te[3]
  local n12, n22, n32 = te[4], te[5], te[6]
  local n13, n23, n33 = te[7], te[8], te[9]
  local t11 = n33*n22 - n32*n23
  local t12 = n32*n13 - n33*n12
  local t13 = n23*n12 - n22*n13
  local det = n11*t11 + n21*t12 + n31*t13
  if det == 0 then return self:set(0, 0, 0, 0, 0, 0, 0, 0, 0) end
  local di = 1/det
  te[1] = t11*di
  te[2] = (n31*n23 - n33*n21)*di
  te[3] = (n32*n21 - n31*n22)*di
  te[4] = t12*di
  te[5] = (n33*n11 - n31*n13)*di
  te[6] = (n31*n12 - n32*n11)*di
  te[7] = t13*di
  te[8] = (n21*n13 - n23*n11)*di
  te[9] = (n22*n11 - n21*n12)*di
  return self
end
function Matrix3:transpose()
  local m = self.elements
  m[2], m[4] = m[4], m[2]
  m[3], m[7] = m[7], m[3]
  m[6], m[8] = m[8], m[6]
  return self
end
function Matrix3:get_normal_matrix(m4) return self:set_from_matrix4(m4):invert():transpose() end
function Matrix3:multiply_scalar(s) local m = self.elements; for k = 1, 9 do m[k] = m[k]*s end; return self end
function Matrix3:set_uv_transform(tx, ty, sx, sy, rotation, cx, cy)
  local c, s = cos(rotation), sin(rotation)
  return self:set(sx*c, sx*s, -sx*(c*cx + s*cy) + cx + tx,
                  -sy*s, sy*c, -sy*(-s*cx + c*cy) + cy + ty,
                  0, 0, 1)
end

-- ---------------------------------------------------------------------------- Matrix4
local Matrix4 = {}; Matrix4.__index = Matrix4
M.Matrix4 = Matrix4
function Matrix4.new() return setmetatable({ elements = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 } }, Matrix4) end
function Matrix4:set(n11, n12, n13, n14, n21, n22, n23, n24, n31, n32, n33, n34, n41, n42, n43, n44)
  local te = self.elements
  te[1], te[5], te[9], te[13] = n11, n12, n13, n14
  te[2], te[6], te[10], te[14] = n21, n22, n23, n24
  te[3], te[7], te[11], te[15] = n31, n32, n33, n34
  te[4], te[8], te[12], te[16] = n41, n42, n43, n44
  return self
end
function Matrix4:identity() return self:set(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) end
function Matrix4:copy(m) local a, b = self.elements, m.elements; for i = 1, 16 do a[i] = b[i] end; return self end
function Matrix4:clone() return Matrix4.new():copy(self) end
function Matrix4:from_array(a, o) o = o or 0; local te = self.elements; for i = 1, 16 do te[i] = a[o + i] end; return self end
function Matrix4:to_array(a, o) a = a or {}; o = o or 0; local te = self.elements; for i = 1, 16 do a[o + i] = te[i] end; return a end
function Matrix4:copy_position(m) local te, me = self.elements, m.elements; te[13], te[14], te[15] = me[13], me[14], me[15]; return self end
function Matrix4:set_position(x, y, z)
  local te = self.elements
  if type(x) == 'table' then te[13], te[14], te[15] = x.x, x.y, x.z else te[13], te[14], te[15] = x, y, z end
  return self
end
function Matrix4:multiply(m) return self:multiply_matrices(self, m) end
function Matrix4:premultiply(m) return self:multiply_matrices(m, self) end
function Matrix4:multiply_matrices(a, b)
  local ae, be, te = a.elements, b.elements, self.elements
  local a11, a12, a13, a14 = ae[1], ae[5], ae[9], ae[13]
  local a21, a22, a23, a24 = ae[2], ae[6], ae[10], ae[14]
  local a31, a32, a33, a34 = ae[3], ae[7], ae[11], ae[15]
  local a41, a42, a43, a44 = ae[4], ae[8], ae[12], ae[16]
  local b11, b12, b13, b14 = be[1], be[5], be[9], be[13]
  local b21, b22, b23, b24 = be[2], be[6], be[10], be[14]
  local b31, b32, b33, b34 = be[3], be[7], be[11], be[15]
  local b41, b42, b43, b44 = be[4], be[8], be[12], be[16]
  te[1] = a11*b11 + a12*b21 + a13*b31 + a14*b41
  te[5] = a11*b12 + a12*b22 + a13*b32 + a14*b42
  te[9] = a11*b13 + a12*b23 + a13*b33 + a14*b43
  te[13] = a11*b14 + a12*b24 + a13*b34 + a14*b44
  te[2] = a21*b11 + a22*b21 + a23*b31 + a24*b41
  te[6] = a21*b12 + a22*b22 + a23*b32 + a24*b42
  te[10] = a21*b13 + a22*b23 + a23*b33 + a24*b43
  te[14] = a21*b14 + a22*b24 + a23*b34 + a24*b44
  te[3] = a31*b11 + a32*b21 + a33*b31 + a34*b41
  te[7] = a31*b12 + a32*b22 + a33*b32 + a34*b42
  te[11] = a31*b13 + a32*b23 + a33*b33 + a34*b43
  te[15] = a31*b14 + a32*b24 + a33*b34 + a34*b44
  te[4] = a41*b11 + a42*b21 + a43*b31 + a44*b41
  te[8] = a41*b12 + a42*b22 + a43*b32 + a44*b42
  te[12] = a41*b13 + a42*b23 + a43*b33 + a44*b43
  te[16] = a41*b14 + a42*b24 + a43*b34 + a44*b44
  return self
end
function Matrix4:multiply_scalar(s) local te = self.elements; for i = 1, 16 do te[i] = te[i]*s end; return self end
function Matrix4:determinant()
  local te = self.elements
  local n11, n12, n13, n14 = te[1], te[5], te[9], te[13]
  local n21, n22, n23, n24 = te[2], te[6], te[10], te[14]
  local n31, n32, n33, n34 = te[3], te[7], te[11], te[15]
  local n41, n42, n43, n44 = te[4], te[8], te[12], te[16]
  return n41*(n14*n23*n32 - n13*n24*n32 - n14*n22*n33 + n12*n24*n33 + n13*n22*n34 - n12*n23*n34)
       + n42*(n11*n23*n34 - n11*n24*n33 + n14*n21*n33 - n13*n21*n34 + n13*n24*n31 - n14*n23*n31)
       + n43*(n11*n24*n32 - n11*n22*n34 - n14*n21*n32 + n12*n21*n34 + n14*n22*n31 - n12*n24*n31)
       + n44*(-n13*n22*n31 - n11*n23*n32 + n11*n22*n33 + n13*n21*n32 - n12*n21*n33 + n12*n23*n31)
end
function Matrix4:transpose()
  local te = self.elements
  te[2], te[5] = te[5], te[2]; te[3], te[9] = te[9], te[3]; te[7], te[10] = te[10], te[7]
  te[4], te[13] = te[13], te[4]; te[8], te[14] = te[14], te[8]; te[12], te[15] = te[15], te[12]
  return self
end
function Matrix4:invert()
  local te = self.elements
  local n11, n21, n31, n41 = te[1], te[2], te[3], te[4]
  local n12, n22, n32, n42 = te[5], te[6], te[7], te[8]
  local n13, n23, n33, n43 = te[9], te[10], te[11], te[12]
  local n14, n24, n34, n44 = te[13], te[14], te[15], te[16]
  local t11 = n23*n34*n42 - n24*n33*n42 + n24*n32*n43 - n22*n34*n43 - n23*n32*n44 + n22*n33*n44
  local t12 = n14*n33*n42 - n13*n34*n42 - n14*n32*n43 + n12*n34*n43 + n13*n32*n44 - n12*n33*n44
  local t13 = n13*n24*n42 - n14*n23*n42 + n14*n22*n43 - n12*n24*n43 - n13*n22*n44 + n12*n23*n44
  local t14 = n14*n23*n32 - n13*n24*n32 - n14*n22*n33 + n12*n24*n33 + n13*n22*n34 - n12*n23*n34
  local det = n11*t11 + n21*t12 + n31*t13 + n41*t14
  if det == 0 then return self:set(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) end
  local di = 1/det
  te[1] = t11*di
  te[2] = (n24*n33*n41 - n23*n34*n41 - n24*n31*n43 + n21*n34*n43 + n23*n31*n44 - n21*n33*n44)*di
  te[3] = (n22*n34*n41 - n24*n32*n41 + n24*n31*n42 - n21*n34*n42 - n22*n31*n44 + n21*n32*n44)*di
  te[4] = (n23*n32*n41 - n22*n33*n41 - n23*n31*n42 + n21*n33*n42 + n22*n31*n43 - n21*n32*n43)*di
  te[5] = t12*di
  te[6] = (n13*n34*n41 - n14*n33*n41 + n14*n31*n43 - n11*n34*n43 - n13*n31*n44 + n11*n33*n44)*di
  te[7] = (n14*n32*n41 - n12*n34*n41 - n14*n31*n42 + n11*n34*n42 + n12*n31*n44 - n11*n32*n44)*di
  te[8] = (n12*n33*n41 - n13*n32*n41 + n13*n31*n42 - n11*n33*n42 - n12*n31*n43 + n11*n32*n43)*di
  te[9] = t13*di
  te[10] = (n14*n23*n41 - n13*n24*n41 - n14*n21*n43 + n11*n24*n43 + n13*n21*n44 - n11*n23*n44)*di
  te[11] = (n12*n24*n41 - n14*n22*n41 + n14*n21*n42 - n11*n24*n42 - n12*n21*n44 + n11*n22*n44)*di
  te[12] = (n13*n22*n41 - n12*n23*n41 - n13*n21*n42 + n11*n23*n42 + n12*n21*n43 - n11*n22*n43)*di
  te[13] = t14*di
  te[14] = (n13*n24*n31 - n14*n23*n31 + n14*n21*n33 - n11*n24*n33 - n13*n21*n34 + n11*n23*n34)*di
  te[15] = (n14*n22*n31 - n12*n24*n31 - n14*n21*n32 + n11*n24*n32 + n12*n21*n34 - n11*n22*n34)*di
  te[16] = (n12*n23*n31 - n13*n22*n31 + n13*n21*n32 - n11*n23*n32 - n12*n21*n33 + n11*n22*n33)*di
  return self
end
function Matrix4:compose(position, quaternion, scale)
  local te = self.elements
  local x, y, z, w = quaternion._x, quaternion._y, quaternion._z, quaternion._w
  local x2, y2, z2 = x + x, y + y, z + z
  local xx, xy, xz = x*x2, x*y2, x*z2
  local yy, yz, zz = y*y2, y*z2, z*z2
  local wx, wy, wz = w*x2, w*y2, w*z2
  local sx, sy, sz = scale.x, scale.y, scale.z
  te[1] = (1 - (yy + zz))*sx; te[2] = (xy + wz)*sx; te[3] = (xz - wy)*sx; te[4] = 0
  te[5] = (xy - wz)*sy; te[6] = (1 - (xx + zz))*sy; te[7] = (yz + wx)*sy; te[8] = 0
  te[9] = (xz + wy)*sz; te[10] = (yz - wx)*sz; te[11] = (1 - (xx + yy))*sz; te[12] = 0
  te[13] = position.x; te[14] = position.y; te[15] = position.z; te[16] = 1
  return self
end
local _zero, _one = V3(0, 0, 0), V3(1, 1, 1)
function Matrix4:make_rotation_from_quaternion(q) return self:compose(_zero, q, _one) end
function Matrix4:make_rotation_from_euler(e) return self:make_rotation_from_quaternion(Quaternion.new():set_from_euler(e, false)) end
function Matrix4:decompose(position, quaternion, scale)
  local te = self.elements
  local sx = sqrt(te[1]*te[1] + te[2]*te[2] + te[3]*te[3])
  local sy = sqrt(te[5]*te[5] + te[6]*te[6] + te[7]*te[7])
  local sz = sqrt(te[9]*te[9] + te[10]*te[10] + te[11]*te[11])
  if self:determinant() < 0 then sx = -sx end
  position.x, position.y, position.z = te[13], te[14], te[15]
  local m = Matrix4.new():copy(self)
  local me = m.elements
  local isx, isy, isz = 1/sx, 1/sy, 1/sz
  me[1], me[2], me[3] = me[1]*isx, me[2]*isx, me[3]*isx
  me[5], me[6], me[7] = me[5]*isy, me[6]*isy, me[7]*isy
  me[9], me[10], me[11] = me[9]*isz, me[10]*isz, me[11]*isz
  quaternion:set_from_rotation_matrix(m)
  scale.x, scale.y, scale.z = sx, sy, sz
  return self
end
function Matrix4:make_translation(x, y, z) return self:set(1, 0, 0, x, 0, 1, 0, y, 0, 0, 1, z, 0, 0, 0, 1) end
function Matrix4:make_scale(x, y, z) return self:set(x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0, 0, 0, 0, 1) end
function Matrix4:make_rotation_axis(axis, angle)
  local c, s = cos(angle), sin(angle)
  local t = 1 - c
  local x, y, z = axis.x, axis.y, axis.z
  local tx, ty = t*x, t*y
  return self:set(tx*x + c, tx*y - s*z, tx*z + s*y, 0,
                  tx*y + s*z, ty*y + c, ty*z - s*x, 0,
                  tx*z - s*y, ty*z + s*x, t*z*z + c, 0,
                  0, 0, 0, 1)
end
function Matrix4:make_rotation_x(t) local c, s = cos(t), sin(t); return self:set(1, 0, 0, 0, 0, c, -s, 0, 0, s, c, 0, 0, 0, 0, 1) end
function Matrix4:make_rotation_y(t) local c, s = cos(t), sin(t); return self:set(c, 0, s, 0, 0, 1, 0, 0, -s, 0, c, 0, 0, 0, 0, 1) end
function Matrix4:make_rotation_z(t) local c, s = cos(t), sin(t); return self:set(c, -s, 0, 0, s, c, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) end
function Matrix4:extract_rotation(m)
  local te, me = self.elements, m.elements
  local v = V3()
  local sx = 1/v:set_from_matrix_column(m, 0):length()
  local sy = 1/v:set_from_matrix_column(m, 1):length()
  local sz = 1/v:set_from_matrix_column(m, 2):length()
  te[1], te[2], te[3], te[4] = me[1]*sx, me[2]*sx, me[3]*sx, 0
  te[5], te[6], te[7], te[8] = me[5]*sy, me[6]*sy, me[7]*sy, 0
  te[9], te[10], te[11], te[12] = me[9]*sz, me[10]*sz, me[11]*sz, 0
  te[13], te[14], te[15], te[16] = 0, 0, 0, 1
  return self
end
-- lookAt(eye, target, up): the rotation part only, as three.js
function Matrix4:look_at(eye, target, up)
  local te = self.elements
  local zx, zy, zz = eye.x - target.x, eye.y - target.y, eye.z - target.z
  local l = zx*zx + zy*zy + zz*zz
  if l == 0 then zz = 1; l = 1 end
  l = sqrt(l); zx, zy, zz = zx/l, zy/l, zz/l
  local xx, xy, xz = up.y*zz - up.z*zy, up.z*zx - up.x*zz, up.x*zy - up.y*zx
  l = xx*xx + xy*xy + xz*xz
  if l == 0 then
    if abs(up.z) == 1 then zx = zx + 0.0001 else zz = zz + 0.0001 end
    l = sqrt(zx*zx + zy*zy + zz*zz); zx, zy, zz = zx/l, zy/l, zz/l
    xx, xy, xz = up.y*zz - up.z*zy, up.z*zx - up.x*zz, up.x*zy - up.y*zx
    l = xx*xx + xy*xy + xz*xz
  end
  l = sqrt(l); xx, xy, xz = xx/l, xy/l, xz/l
  local yx, yy, yz = zy*xz - zz*xy, zz*xx - zx*xz, zx*xy - zy*xx
  te[1], te[5], te[9] = xx, yx, zx
  te[2], te[6], te[10] = xy, yy, zy
  te[3], te[7], te[11] = xz, yz, zz
  return self
end
function Matrix4:make_perspective(left, right, top, bottom, near, far)
  local te = self.elements
  local x = 2*near/(right - left)
  local y = 2*near/(top - bottom)
  local a = (right + left)/(right - left)
  local b = (top + bottom)/(top - bottom)
  local c = -(far + near)/(far - near)
  local d = -2*far*near/(far - near)
  te[1], te[5], te[9], te[13] = x, 0, a, 0
  te[2], te[6], te[10], te[14] = 0, y, b, 0
  te[3], te[7], te[11], te[15] = 0, 0, c, d
  te[4], te[8], te[12], te[16] = 0, 0, -1, 0
  return self
end
function Matrix4:make_orthographic(left, right, top, bottom, near, far)
  local te = self.elements
  local w, h, p = 1.0/(right - left), 1.0/(top - bottom), 1.0/(far - near)
  local x, y, z = (right + left)*w, (top + bottom)*h, (far + near)*p
  te[1], te[5], te[9], te[13] = 2*w, 0, 0, -x
  te[2], te[6], te[10], te[14] = 0, 2*h, 0, -y
  te[3], te[7], te[11], te[15] = 0, 0, -2*p, -z
  te[4], te[8], te[12], te[16] = 0, 0, 0, 1
  return self
end
function Matrix4:get_max_scale_on_axis()
  local te = self.elements
  local sx = te[1]*te[1] + te[2]*te[2] + te[3]*te[3]
  local sy = te[5]*te[5] + te[6]*te[6] + te[7]*te[7]
  local sz = te[9]*te[9] + te[10]*te[10] + te[11]*te[11]
  return sqrt(max(sx, sy, sz))
end
function Matrix4:equals(m) local a, b = self.elements, m.elements; for i = 1, 16 do if a[i] ~= b[i] then return false end end; return true end

-- ---------------------------------------------------------------------------- Color
-- three.js keeps colours in linear sRGB (ColorManagement enabled): set_hex / set_style decode sRGB.
local Color = {}; Color.__index = Color
M.Color = Color
local function srgb_to_linear(c) return c < 0.04045 and c*0.0773993808 or ((c*0.9478672986 + 0.0521327014)^2.4) end
local function linear_to_srgb(c) return c < 0.0031308 and c*12.92 or (1.055*(c^0.41666) - 0.055) end
M.srgb_to_linear, M.linear_to_srgb = srgb_to_linear, linear_to_srgb
function Color.new(r, g, b)
  local c = setmetatable({ r = 1, g = 1, b = 1, is_color = true }, Color)
  if g == nil and r ~= nil then
    if type(r) == 'number' then c:set_hex(r) elseif type(r) == 'table' then c:copy(r) end
  elseif r ~= nil then c.r, c.g, c.b = r, g, b end
  return c
end
function Color:set_hex(hex)
  hex = floor(hex)
  self.r = srgb_to_linear(((hex >> 16) & 255)/255)
  self.g = srgb_to_linear(((hex >> 8) & 255)/255)
  self.b = srgb_to_linear((hex & 255)/255)
  return self
end
function Color:set(r, g, b)
  if g == nil then if type(r) == 'number' then return self:set_hex(r) else return self:copy(r) end end
  self.r, self.g, self.b = r, g, b; return self
end
function Color:set_rgb(r, g, b) self.r, self.g, self.b = r, g, b; return self end
function Color:set_scalar(s) self.r, self.g, self.b = s, s, s; return self end
function Color:copy(c) self.r, self.g, self.b = c.r, c.g, c.b; return self end
function Color:clone() return Color.new(self.r, self.g, self.b) end
function Color:multiply_scalar(s) self.r, self.g, self.b = self.r*s, self.g*s, self.b*s; return self end
function Color:multiply(c) self.r, self.g, self.b = self.r*c.r, self.g*c.g, self.b*c.b; return self end
function Color:add(c) self.r, self.g, self.b = self.r + c.r, self.g + c.g, self.b + c.b; return self end
function Color:lerp(c, t) self.r, self.g, self.b = self.r + (c.r - self.r)*t, self.g + (c.g - self.g)*t, self.b + (c.b - self.b)*t; return self end
function Color:lerp_colors(a, b, t) self.r, self.g, self.b = a.r + (b.r - a.r)*t, a.g + (b.g - a.g)*t, a.b + (b.b - a.b)*t; return self end
function Color:get_hex()
  local r, g, b = clamp(linear_to_srgb(self.r), 0, 1), clamp(linear_to_srgb(self.g), 0, 1), clamp(linear_to_srgb(self.b), 0, 1)
  return (floor(r*255 + 0.5) << 16) | (floor(g*255 + 0.5) << 8) | floor(b*255 + 0.5)
end
-- HSL in sRGB (three.js's setHSL works in the sRGB space, then converts to the working space)
local function hue2rgb(p, q, t)
  if t < 0 then t = t + 1 end
  if t > 1 then t = t - 1 end
  if t < 1/6 then return p + (q - p)*6*t end
  if t < 1/2 then return q end
  if t < 2/3 then return p + (q - p)*6*(2/3 - t) end
  return p
end
function Color:set_hsl(h, s, l)
  h = ((h % 1) + 1) % 1
  s = clamp(s, 0, 1); l = clamp(l, 0, 1)
  local r, g, b
  if s == 0 then r, g, b = l, l, l
  else
    local p = l <= 0.5 and l*(1 + s) or l + s - l*s
    local q = 2*l - p
    r, g, b = hue2rgb(q, p, h + 1/3), hue2rgb(q, p, h), hue2rgb(q, p, h - 1/3)
  end
  self.r, self.g, self.b = srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b)
  return self
end
function Color:to_array(a, o) a = a or {}; o = o or 0; a[o + 1], a[o + 2], a[o + 3] = self.r, self.g, self.b; return a end
function Color:from_array(a, o) o = o or 0; self.r, self.g, self.b = a[o + 1], a[o + 2], a[o + 3]; return self end

return M
