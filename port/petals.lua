--[[
  petals.lua -- round 51 (owner, 2026-10-06: "The prismatic death effect should remain the same but
  also prismatic glass petal-like particles should go up from the snake's body as it gets
  destroyed"). Thin cupped petals of glass that rise from a beamed snake's body, fluttering and
  turning as they go: faint most of the time, each flaring in its colours when it turns its face to
  the light (the glint moves with the turn, so the colour runs across the spectrum as it tumbles),
  fading out as they climb. One instanced mesh drawn additively with the leakage flakes' program
  (MeshBasic, double-sided, per-instance colour); its own rng (the powers' draws stay as they were).
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local MAT = require('port.three.materials')
local U = require('port.util')
local FX = require('port.fx')
local CAVE = require('port.cave')
local Vector3, Quaternion, Matrix4 = TM.Vector3, TM.Quaternion, TM.Matrix4
local smoothstep = U.smoothstep
local sin, cos, sqrt, abs, max, min, floor, pi = math.sin, math.cos, math.sqrt, math.abs, math.max, math.min, math.floor, math.pi

local PE = {}
local N = 420

-- a petal: a teardrop 1 long (y), 0.55 wide, cupped (its sides curl up in z), tip at y = 1
local function petal_geometry()
  local P, Nn, UV, I = {}, {}, {}, {}
  local ROWS, COLS = 6, 5
  local function width(v) return 0.55*sin(pi*(v^0.8))*(1 - 0.25*v) end
  for r = 0, ROWS do
    local v = r/ROWS
    local w = width(v)
    for c = 0, COLS do
      local u = c/COLS*2 - 1
      local x, y = u*w*0.5, v
      local z = 0.18*(u*u)*w + 0.06*sin(pi*v)
      P[#P + 1] = x; P[#P + 1] = y - 0.35; P[#P + 1] = z
      local nx, nz = -0.36*u*w, 1
      local l = sqrt(nx*nx + nz*nz)
      Nn[#Nn + 1] = nx/l; Nn[#Nn + 1] = 0; Nn[#Nn + 1] = nz/l
      UV[#UV + 1] = (u + 1)/2; UV[#UV + 1] = v
    end
  end
  for r = 0, ROWS - 1 do for c = 0, COLS - 1 do
    local a = r*(COLS + 1) + c
    local b, d, e = a + 1, a + COLS + 1, a + COLS + 2
    I[#I + 1] = a; I[#I + 1] = d; I[#I + 1] = b
    I[#I + 1] = b; I[#I + 1] = d; I[#I + 1] = e
  end end
  local g = T.BufferGeometry.new()
  g.name = 'petal'
  g:set_attribute('position', T.BufferAttribute.new(P, 3))
  g:set_attribute('normal', T.BufferAttribute.new(Nn, 3))
  g:set_attribute('uv', T.BufferAttribute.new(UV, 2))
  g:set_index(T.BufferAttribute.new(I, 1))
  return g
end

function PE.create(R, cave)
  local rng = U.make_rng(5311)
  local mat = MAT.MeshBasicMaterial.new({ name = 'leak.flakes', color = 0xffffff, side = MAT.DoubleSide, transparent = true,
    blending = MAT.AdditiveBlending, depth_write = false })
  mat.force_single_pass = true
  local mesh = T.InstancedMesh.new(petal_geometry(), mat, N)
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
  local M4, Q, Q2, AX, SV, PV, NRM, H = Matrix4.new(), Quaternion.new(), Quaternion.new(), Vector3.new(), Vector3.new(), Vector3.new(), Vector3.new(), Vector3.new()
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

  -- one petal at p, leaving the body (out: the way away from the body's axis there)
  local function spawn(p, ox, oz, k)
    local f = PP[nxt + 1]; nxt = (nxt + 1) % N
    k = k or 1
    f.life = rng.float(1.1, 1.8); f.max = f.life; f.t = 0      -- (round 52: a tad shorter; were 1.7-2.9 s)
    f.x = p.x + ox*0.04; f.y = p.y + rng.float(0.0, 0.05); f.z = p.z + oz*0.04
    local out = rng.float(0.06, 0.2)*k                          -- (round 52: more straight up; out 0.25-0.75, spread 0.25)
    f.vx = ox*out + rng.spread(0.08); f.vz = oz*out + rng.spread(0.08); f.vy = rng.float(0.9, 1.7)*k
    f.size = rng.float(0.13, 0.2)
    f.q = Quaternion.new():set_from_axis_angle(AX:set(rng.spread(1), rng.spread(1), rng.spread(1)):normalize(), rng.float(0, 6.28))
    f.w = Vector3.new(rng.spread(1), rng.spread(1), rng.spread(1)):normalize():multiply_scalar(rng.float(2.5, 6.5))
    f.hue = rng.next(); f.ph = rng.float(0, 6.28); f.fl = rng.float(1.4, 2.6); f.sway = rng.float(0.07, 0.16)
  end
  -- a body's petals: along its spine, from the rings it still has (count by how much of it there is)
  local function burst(spine, rings, n)
    n = n or 22
    for _ = 1, n do
      local i = rng.int(2, rings - 3)
      local a, b = spine[i], spine[i + 2]
      local tx, tz = b.x - a.x, b.z - a.z
      local tl = js_hypot(tx, tz); if tl < 1e-6 then tl = 1; tx = 1 end
      local side = rng.sign()
      local ox, oz = -tz/tl*side, tx/tl*side
      spawn(spine[i + 1], ox, oz, 1)
    end
  end
  -- a few lift off already while the light fills it (from the lit stretch round `hit`, `fill` of it)
  local function trickle(spine, rings, hit, fill, dt)
    if rng.next() > 12*dt then return end
    local reach = max(1, fill*rings)
    local i = max(1, min(rings - 2, hit + floor(rng.spread(reach))))
    spawn(spine[i + 1], rng.spread(1), rng.spread(1), 0.6)
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
        f.life = f.life - dt; f.t = f.t + dt
        local u = f.t/f.max
        -- rising like something light in warm air: lifted, held back by the air, swaying across
        f.vy = f.vy + (0.7 - f.vy*0.9)*dt*1.6
        local d = 1 - 1.4*dt
        f.vx = f.vx*d; f.vz = f.vz*d
        local sw = sin(f.t*f.fl*2*pi*0.5 + f.ph)*f.sway
        f.x = f.x + (f.vx + sw*cos(f.ph))*dt; f.y = f.y + f.vy*dt; f.z = f.z + (f.vz + sw*sin(f.ph))*dt
        -- tumbling, slowing a little
        local wl = f.w:length()
        if wl > 1e-4 then Q2:set_from_axis_angle(AX:copy(f.w):multiply_scalar(1/wl), wl*dt); f.q:premultiply(Q2) end
        f.w:multiply_scalar(1 - 0.25*dt)
        -- the glint: its face turned to the half-way between the light and the eye
        NRM:set(0, 0, 1):apply_quaternion(f.q)
        H:set(cx - f.x, cy - f.y, cz - f.z):normalize():add(SUN):normalize()
        local face = abs(NRM:dot(H))
        local lit = 0.35 + 0.65*in_sun(f.x, f.y, f.z)
        local glint = (face^8)*2.0*lit
        local base = 0.16 + 0.12*lit
        local fade = smoothstep(0, 0.12, u)*(1 - smoothstep(0.65, 1, u))
        local c = opal(f.hue + NRM.x*0.35 + NRM.y*0.25 + t*0.05)
        for q = 1, 3 do c[q] = 0.5*c[q] + 0.5 end           -- (glass: tinted, not dyed)
        local k = (base + glint)*fade
        local w = 0.35*glint*fade            -- (a flare runs toward white)
        ic[i*3 + 1], ic[i*3 + 2], ic[i*3 + 3] = c[1]*k + w, c[2]*k + w, c[3]*k + w
        local sc = f.size*(1 - 0.35*smoothstep(0.7, 1, u))
        M4:compose(PV:set(f.x, f.y, f.z), f.q, SV:set(sc, sc, sc))
        mesh:set_matrix_at(i, f.life > 0 and M4 or ZERO)
      end
    end
    if any or mesh.was_any then
      mesh.instance_matrix.needs_update = true; mesh.instance_color.needs_update = true
    end
    mesh.was_any = any
  end
  return { burst = burst, trickle = trickle, update = update, mesh = mesh }
end

return PE
