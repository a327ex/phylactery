--[[
  shards.lua -- round 69 (owner, 2026-10-11: "The only lens dissolve sound that's good is an ice break one, so let's
  change the dissolve effect visually to glass breaking"). When a lens is done it no longer dissolves into glints: it
  BREAKS. The lens is gone in one frame with a flash, and its glass flies apart as thin irregular shards that tumble
  and fall through the sun shaft, catching the light as they turn (the glint of round 51's petals: a face turned to
  half way between the sun and the eye flares in the lens's spectrum, brighter inside the shaft), hit the floor with a
  bounce or two, slide a little and lie there glinting until they fade.
  One instanced mesh drawn additively with the leakage flakes' program (MeshBasic, double-sided, per-instance colour),
  as the petals; its own rng (the powers' draws stay as they were). The game's flow only (lens.lua, ctx.varied):
  LICH_ROOM keeps the old dissolve, draw for draw.
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local MAT = require('port.three.materials')
local U = require('port.util')
local FX = require('port.fx')
local CAVE = require('port.cave')
local AU = require('port.audio')     -- (never draw from rng here)
local Vector3, Quaternion, Matrix4 = TM.Vector3, TM.Quaternion, TM.Matrix4
local smoothstep = U.smoothstep
local sin, cos, sqrt, abs, max, min, floor, pi = math.sin, math.cos, math.sqrt, math.abs, math.max, math.min, math.floor, math.pi

local SH = {}
local N = 240
-- the break: how many shards for a lens of radius 1 (a lens is ~0.38 m; a group's 1.45x that), how fast they part
-- (big = the few large pieces of the lens itself, a fraction of its radius; the rest are slivers)
SH.BREAK = { per_r = 70, big_n = 9, big = { 0.28, 0.5 }, out = { 0.5, 1.6 }, up = { -0.2, 0.9 }, spin = { 4, 14 },
  size = { 0.035, 0.09 }, gravity = 9.8, bounce = 0.32, slide = 0.55, lie = { 1.2, 2.2 }, fade = 0.5, tint = 0.25 }

-- a shard: a thin sliver of glass, flat in z, ~1 across; one shape bent a little along its length so it is not a
-- card; each one's own stretch and turn makes the variety
local function shard_geometry()
  local P = { 0.0, 0.62, 0.0,   -0.30, -0.18, 0.03,   0.12, -0.46, 0.0,   0.36, 0.04, -0.02 }
  local Nn = { 0, 0, 1,  0, 0, 1,  0, 0, 1,  0, 0, 1 }
  local UV = { 0.5, 1, 0, 0.3, 0.6, 0, 1, 0.5 }
  local I = { 0, 1, 2,  0, 2, 3 }
  local g = T.BufferGeometry.new()
  g.name = 'shard'
  g:set_attribute('position', T.BufferAttribute.new(P, 3))
  g:set_attribute('normal', T.BufferAttribute.new(Nn, 3))
  g:set_attribute('uv', T.BufferAttribute.new(UV, 2))
  g:set_index(T.BufferAttribute.new(I, 1))
  return g
end

function SH.create(R, cave, fx)
  local rng = U.run_rng(6917)
  local mat = MAT.MeshBasicMaterial.new({ name = 'leak.flakes', color = 0xffffff, side = MAT.DoubleSide, transparent = true,
    blending = MAT.AdditiveBlending, depth_write = false })
  mat.force_single_pass = true
  local mesh = T.InstancedMesh.new(shard_geometry(), mat, N)
  do
    local a = {}
    for k = 1, N*3 do a[k] = 0 end
    mesh.instance_color = T.BufferAttribute.new(a, 3); mesh.instance_color.instanced = true
  end
  mesh.frustum_culled = false
  mesh.render_order = 12
  R.world_scene:add(mesh)
  local ZERO = Matrix4.new():make_scale(0, 0, 0)
  local PP = {}
  for i = 0, N - 1 do PP[i + 1] = { life = 0 }; mesh:set_matrix_at(i, ZERO) end
  local nxt = 0
  local M4, Q2, AX, SV, PV, NRM, H = Matrix4.new(), Quaternion.new(), Vector3.new(), Vector3.new(), Vector3.new(), Vector3.new(), Vector3.new()
  local SUN = CAVE.LAYOUT.sun_dir:clone():normalize()
  local sxz = { SUN.x/SUN.y, SUN.z/SUN.y }
  local function in_sun(x, y, z) return 1 - smoothstep(1.55, 2.05, js_hypot(x - sxz[1]*y, z - sxz[2]*y)) end
  local OP = { 1, 1, 1 }
  local function opal(h)
    local s = FX.spectrum(h)
    local c = { s[1]*s[1]*(3 - 2*s[1]), s[2]*s[2]*(3 - 2*s[2]), s[3]*s[3]*(3 - 2*s[3]) }
    local m = max((c[1] + c[2] + c[3])/3, 0.2)
    OP[1] = c[1]/m; OP[2] = c[2]/m; OP[3] = c[3]/m
    return OP
  end
  local B = SH.BREAK

  -- a lens of radius r at p breaks (facing: its axis, the way it looked; warm = the fire laser's look)
  local function burst(p, r, facing, warm)
    AU.play('lens_dissolve', { pos = p })
    -- the flash: the glass lets go of the light it held, one white blink and glints thrown out
    fx.mote({ x = p.x, y = p.y, z = p.z, life = 0.12, s0 = 0.9*r/0.38, s1 = 0.2, r = 4, g = 3.8, b = warm and 3.0 or 4.2, fin = 0.01 })
    for _ = 1, 18 do
      local a = rng.float(0, 6.28)
      local sp = rng.float(0.4, 1.4)
      fx.mote({ x = p.x, y = p.y, z = p.z, vx = cos(a)*sp, vy = rng.float(-0.3, 0.6), vz = sin(a)*sp, drag = 2.5,
        life = rng.float(0.12, 0.3), s0 = 0.05, s1 = 0.01, r = 3.2, g = 3.0, b = warm and 2.2 or 3.4, fin = 0.01 })
    end
    -- the lens's plane: two directions across it
    local ax = facing and facing:clone():normalize() or Vector3.new(0, -1, 0)
    local e1 = Vector3.new():cross_vectors(ax, Vector3.new(0, 1, 0))
    if e1:length_sq() < 1e-6 then e1:set(1, 0, 0) end
    e1:normalize()
    local e2 = Vector3.new():cross_vectors(ax, e1):normalize()
    local n = max(12, floor(B.per_r*r + 0.5))
    for k = 1, n do
      local f = PP[nxt + 1]; nxt = (nxt + 1) % N
      -- where on the disc it was: out from the middle, the way it flies
      local a = rng.float(0, 6.28)
      local d = r*sqrt(rng.next())
      local ox, oy, oz = e1.x*cos(a) + e2.x*sin(a), e1.y*cos(a) + e2.y*sin(a), e1.z*cos(a) + e2.z*sin(a)
      f.x, f.y, f.z = p.x + ox*d, p.y + oy*d, p.z + oz*d
      local out = rng.float(B.out[1], B.out[2])*(0.35 + 0.65*d/max(r, 1e-3))
      if k <= B.big_n then f.size = r*rng.float(B.big[1], B.big[2]); out = out*0.6       -- (the big pieces part slower)
      else f.size = rng.float(B.size[1], B.size[2])*(0.6 + 0.8*r/0.38)^0.5 end
      f.sx, f.sy = rng.float(0.45, 1.0), rng.float(0.8, 1.6)            -- slivers, not squares
      f.vx = ox*out + ax.x*rng.spread(0.3)
      f.vy = oy*out + rng.float(B.up[1], B.up[2])
      f.vz = oz*out + ax.z*rng.spread(0.3)
      f.q = Quaternion.new():set_from_axis_angle(AX:set(rng.spread(1), rng.spread(1), rng.spread(1)):normalize(), rng.float(0, 6.28))
      f.w = Vector3.new(rng.spread(1), rng.spread(1), rng.spread(1)):normalize():multiply_scalar(rng.float(B.spin[1], B.spin[2]))
      f.hue = rng.next(); f.t = 0
      f.bounces, f.resting, f.rest_t = 0, false, 0
      f.lie = rng.float(B.lie[1], B.lie[2])
      f.life = 1
      f.warm = warm
    end
  end

  local function update(t, dt, cam)
    local ic = mesh.instance_color.array
    local cx, cy, cz = 0, 0, 0
    if cam then cx, cy, cz = cam.position.x, cam.position.y, cam.position.z end
    local any = false
    for i = 0, N - 1 do
      local f = PP[i + 1]
      if f.life > 0 then
        any = true
        f.t = f.t + dt
        if not f.resting then
          f.vy = f.vy - B.gravity*dt
          local d = 1 - 0.25*dt                          -- (thin glass: a little held back by the air)
          f.vx, f.vz = f.vx*d, f.vz*d
          f.x, f.y, f.z = f.x + f.vx*dt, f.y + f.vy*dt, f.z + f.vz*dt
          local wl = f.w:length()
          if wl > 1e-4 then Q2:set_from_axis_angle(AX:copy(f.w):multiply_scalar(1/wl), wl*dt); f.q:premultiply(Q2) end
          local gy = cave.ground_y(f.x, f.z) + 0.006
          if f.y <= gy then
            f.y = gy
            f.bounces = f.bounces + 1
            if f.bounces == 1 then AU.play('lens_shard_land', { pos = { f.x, f.y, f.z }, volume = min(1, 0.25 + abs(f.vy)/8), gap = 0.03 }) end
            if f.bounces >= 3 or abs(f.vy) < 0.8 then
              -- it settles: laid flat on the floor (its face up, its turn about the vertical kept), sliding to a stop
              f.resting = true; f.vy = 0
              NRM:set(0, 0, 1):apply_quaternion(f.q)
              local yaw = math.atan(NRM.x, NRM.z)
              f.q:set_from_axis_angle(AX:set(0, 1, 0), yaw + rng.float(0, 6.28))
              Q2:set_from_axis_angle(AX:set(1, 0, 0), -pi/2 + rng.spread(0.12)); f.q:multiply(Q2)
            else
              f.vy = -f.vy*B.bounce
              f.vx, f.vz = f.vx*B.slide, f.vz*B.slide
              f.w:multiply_scalar(0.6)
            end
          end
        else
          -- sliding to a stop on the stone
          local d = max(0, 1 - 6*dt)
          f.vx, f.vz = f.vx*d, f.vz*d
          f.x, f.z = f.x + f.vx*dt, f.z + f.vz*dt
          f.y = cave.ground_y(f.x, f.z) + 0.006
          f.rest_t = f.rest_t + dt
          if f.rest_t > f.lie + B.fade then f.life = 0 end
        end
        -- the glint: its face turned to the half-way between the light and the eye
        NRM:set(0, 0, 1):apply_quaternion(f.q)
        H:set(cx - f.x, cy - f.y, cz - f.z):normalize():add(SUN):normalize()
        local face = abs(NRM:dot(H))
        local lit = 0.3 + 0.7*in_sun(f.x, f.y, f.z)
        local glint = (face^10)*2.6*lit
        local base = 0.08 + 0.12*lit
        local fade = f.resting and (1 - smoothstep(f.lie, f.lie + B.fade, f.rest_t)) or 1
        local c = opal(f.hue + NRM.x*0.4 + NRM.y*0.3 + t*0.05)
        for q = 1, 3 do c[q] = B.tint*c[q] + (1 - B.tint) end   -- (clear glass: white, a hint of the spectrum in the glint)
        if f.warm then c[3] = c[3]*0.8 end
        local k = min(1.1, base + 0.9*glint)*fade             -- (held under the clip: round 53's white squares)
        ic[i*3 + 1], ic[i*3 + 2], ic[i*3 + 3] = c[1]*k, c[2]*k, c[3]*k
        local sc = f.size
        M4:compose(PV:set(f.x, f.y, f.z), f.q, SV:set(sc*f.sx, sc*f.sy, sc))
        mesh:set_matrix_at(i, f.life > 0 and M4 or ZERO)
      end
    end
    if any or mesh.was_any then
      mesh.instance_matrix.needs_update = true; mesh.instance_color.needs_update = true
    end
    mesh.was_any = any
  end
  return { burst = burst, update = update, mesh = mesh }
end

return SH
