--[[
  lens.lua -- the port to Anchor: web/src/lens.js. LENS: a glass lens crystallizes in the shaft
  (transmissive glass), gathers the sunlight into a cone and a patch on the floor that tightens to
  a point beside the snake, then fires a fire laser that sweeps across it and cuts it (cut_fx);
  the glass dissolves into glints. No gesture; several lenses at once with fewer powers.
  Round 50: three or more in one cast (the bouts, powers.lua): one larger lens, and its burning point
  draws one long cut through them all, from beside the first through each in turn (cast_group).
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local MAT = require('port.three.materials')
local U = require('port.util')
local CAVE = require('port.cave')
local Vector2, Vector3 = TM.Vector2, TM.Vector3
local smoothstep = U.smoothstep
local sqrt, abs, sin, cos, exp, floor, ceil, min, max, pi = math.sqrt, math.abs, math.sin, math.cos, math.exp, math.floor, math.ceil, math.min, math.max, math.pi

local LE = {}
local FORM, CONVERGE, SPEED, SWEEP, LEAD, OFF, FADE, CUT_R = 0.4, 0.8, 3.0, 2.6, 0.35, 0.2, 0.45, 0.13
local LENS_R = 0.38
local LIGHTS_OFF = 0.15
local CUT_MIN, CUT_MAX = 1.0, 2.6
local GROUP_SPEED, GROUP_BIG, GROUP_TAIL = 5.0, 1.45, 0.7
LE.LENS_LOOKS = { 'FIRE LASER (TITAN, PHRIKE)', 'THE PRISMATIC BEAM, IN FIRE' }
local NLOOKS = #LE.LENS_LOOKS
local function jround(x) return floor(x + 0.5) end
local hyp = js_hypot

function LE.create(ctx)
  local R, snakes, fx, cave, rng = ctx.R, ctx.snakes, ctx.fx, ctx.cave, ctx.rng
  local N = snakes.RINGS
  local A = R.statics
  local S = CAVE.LAYOUT.sun_dir
  local sxz = Vector2.new(S.x/S.y, S.z/S.y)
  local function axis_at(h) return Vector3.new(sxz.x*h, h, sxz.y*h) end

  local geo = A.geometry('lens_glass')
  local function glass_mat()
    local m = MAT.MeshPhysicalMaterial.new({ name = 'lens.glass', color = 0xffffff, metalness = 0, roughness = 0.03, transmission = 1, thickness = 0.18, ior = 1.52,
      dispersion = 0.8, specular_intensity = 1, specular_color = 0xffffff, env_map_intensity = 0, depth_write = false })
    local UU = { uRim = { value = 0 } }
    m.user_data.U = UU
    m.custom = UU
    return m
  end
  local function shimmer_mat()
    return MAT.ShaderMaterial.new({ name = 'lens.shimmer', uniforms = { uA = { value = 0 }, uTime = { value = 0 } }, transparent = true, depth_write = false, blending = MAT.AdditiveBlending })
  end
  local SEG = 28
  local cone_mat = MAT.ShaderMaterial.new({ name = 'lens.cone', uniforms = { uA = { value = 1 } }, transparent = true, depth_write = false, blending = MAT.AdditiveBlending, side = MAT.DoubleSide })
  local patch_mat = MAT.ShaderMaterial.new({ name = 'lens.patch', uniforms = { uA = { value = 0 } }, transparent = true, depth_write = false, blending = MAT.AdditiveBlending })
  local function make_cone()
    local g = T.BufferGeometry.new()
    local at, aa = {}, {}
    for j = 0, SEG - 1 do at[j + 1] = 0; at[SEG + j + 1] = 1 end
    for k = 1, SEG*2 do aa[k] = 0 end
    g:set_attribute('position', T.float_attr(SEG*2, 3))
    g:set_attribute('aT', T.BufferAttribute.new(at, 1))
    g:set_attribute('aA', T.BufferAttribute.new(aa, 1))
    local idx = {}
    for j = 0, SEG - 1 do
      local a, b = j, (j + 1)%SEG
      local c, d = SEG + b, SEG + j
      local o = #idx
      idx[o + 1], idx[o + 2], idx[o + 3], idx[o + 4], idx[o + 5], idx[o + 6] = a, d, c, a, c, b
    end
    g:set_index(idx)
    local m = T.Mesh.new(g, cone_mat)
    m.frustum_culled = false; m.render_order = 11; m.visible = false
    R.world_scene:add(m)
    return m
  end
  local plane = A.geometry('plane_2_2')
  local function make_patch()
    local m = T.Mesh.new(plane, patch_mat:clone())
    m.rotation.x = -pi/2; m.frustum_culled = false; m.render_order = 11; m.visible = false
    R.world_scene:add(m)
    return m
  end

  local LENSES, LIGHTS = {}, {}
  for _ = 1, 5 do
    local m = T.Mesh.new(geo, glass_mat())
    m.cast_shadow = true; m.receive_shadow = false
    m.visible = false; m.frustum_culled = false; m.render_order = 13
    R.world_scene:add(m)
    local sh = T.Mesh.new(geo, shimmer_mat())
    sh.scale:set_scalar(1.02); sh.render_order = 14; sh.visible = false
    m:add(sh)
    LENSES[#LENSES + 1] = { m = m, sh = sh, cone = make_cone(), patch = make_patch(), on = false }
  end
  for _ = 1, 3 do
    local l = T.PointLight.new(0xffc27a, 0, 5, 2)
    R.world_scene:add(l)
    LIGHTS[#LIGHTS + 1] = { l = l, lens = nil }
  end
  local active = {}
  local look = 0
  local cuts, fired = {}, {}
  local stats = { done = 0, empty = 0 }              -- (lenses whose cut ended, and those that cut nothing)

  local function cut_fx(s, c)
    local tan = Vector3.new():sub_vectors(s.spine[max(0, c - 3) + 1], s.spine[min(N - 1, c + 3) + 1]); tan.y = 0; tan:normalize()
    local side = Vector3.new(-tan.z, 0, tan.x)
    local ph = rng.float(0, 6)
    local head = snakes.arc(c) < 0.6
    local f
    f = {
      t = 0, sag = 0,
      radk = function(i) local d = abs(i - c); return smoothstep(1.2, 3.2, d) end,
      shift = function(i, out)
        local sep = ((head and i < c) and 0.22 or 0.14)*(1 - exp(-f.t*7))
        local k = i < c and 1 or -0.6
        local tw = exp(-f.t*1.8)*sin(f.t*18 + i*0.25 + ph)*0.05*min(1, abs(i - c)/12)
        out[1] = out[1] + (tan.x*sep*k + side.x*tw); out[3] = out[3] + (tan.z*sep*k + side.z*tw)
        if head and i < c then out[1] = out[1] + side.x*0.08*(1 - exp(-f.t*4)); out[3] = out[3] + side.z*0.08*(1 - exp(-f.t*4)) end
        if f.t > 1.9 then out[2] = out[2] - 0.34*smoothstep(1.9, 3.1, f.t) end
      end,
      char = function(i) return exp(-abs(i - c)/2.5) end,
      ember = function(i) return exp(-abs(i - c)/2.0)*(1 - smoothstep(0.3, 1.8, f.t)) end,
      tick = function(dt)
        f.t = f.t + dt
        f.sag = smoothstep(0, head and 0.25 or 0.6, f.t)
        if f.t < 1.0 and rng.next() < 0.6 then
          local ci = c + (rng.next() < 0.5 and -3 or 3)
          local p = s.spine[ci + 1] or s.spine[c + 1]
          local x = p.x + rng.spread(0.03)
          local z = p.z + rng.spread(0.03)
          local vy = rng.float(0.4, 0.9)
          local vx = rng.spread(0.1)
          local vz = rng.spread(0.1)
          fx.mote({ x = x, y = p.y + 0.03, z = z, vy = vy, vx = vx, vz = vz, life = rng.float(0.2, 0.4), s0 = 0.08, s1 = 0.02, r = 3.0, g = 1.2, b = 0.25, a = 1 - f.t })
        end
        if f.t < 2.0 and rng.next() < 0.3 then
          local p = s.spine[c + 1]
          local vx = rng.spread(0.08)
          local vy = rng.float(0.3, 0.5)
          local vz = rng.spread(0.08)
          fx.puff({ x = p.x, y = p.y + 0.05, z = p.z, vx = vx, vy = vy, vz = vz, drag = 0.3, life = rng.float(1.2, 2.0), s0 = 0.12, s1 = 0.4, r = 0.012, g = 0.011, b = 0.01, a = 0.35 })
        end
        if f.t > 3.15 then return 'done' end
      end,
    }
    return f
  end

  local TAN, ACR = Vector3.new(), Vector3.new()
  local function frame_at(s, c)
    TAN:sub_vectors(s.spine[max(0, c - 3) + 1], s.spine[min(N - 1, c + 3) + 1]); TAN.y = 0; TAN:normalize()
    ACR:set(-TAN.z, 0, TAN.x)
    return s.spine[c + 1]
  end
  local function aim_ring() return max(1, jround(snakes.ring_at(max(0.05, rng.float(1.7, 2.3) - 0.18)))) end
  local unclaimed = function(s) return snakes.free(s) end
  local claim = function() end
  local function retarget(q)
    local best, bd = nil, 1e9
    for _, s in ipairs(snakes.S) do
      local taken = false
      for _, o in ipairs(active) do if o ~= q and o.s == s then taken = true; break end end
      if unclaimed(s) and not taken and not (hyp(s.x - snakes.egg.x, s.z - snakes.egg.z) > 7) then
        local d = hyp(s.spine[20 + 1].x - q.spot.x, s.spine[20 + 1].z - q.spot.z)
        if d < bd then bd = d; best = s end
      end
    end
    if best then q.s = best; q.ring = aim_ring(); claim(best); return true end
    q.fired = true; q.t = FORM + CONVERGE + q.dur + OFF + 1e-3
    return false
  end
  local function beside(q, out)
    if snakes.free(q.s) then local p = frame_at(q.s, q.ring); out:copy(p):add_scaled_vector(ACR, -LEAD*q.side) end
    out.y = cave.ground_y(out.x, out.z) + 0.02
    return out
  end
  local function spawn(s, k, quick, group)
    quick = quick or false
    local L
    for _, q in ipairs(LENSES) do if not q.on then L = q; break end end
    if not L then return nil end
    local ring = aim_ring()
    local h = rng.float(3.8, 6.0) + k*0.4
    local ox = rng.spread(0.8)
    local oz = rng.spread(0.8)
    local pos = axis_at(h):add(Vector3.new(ox, 0, oz))
    local light
    for _, x in ipairs(LIGHTS) do if not x.lens then light = x; break end end
    local q = { L = L, s = s, ring = ring, t = quick and FORM + CONVERGE - 0.12 or 0, t0q = quick, pos = pos, side = rng.sign(),
      spot = Vector3.new(), a = Vector3.new(), b = Vector3.new(), fired = false, core = nil, flare = 0, light = light, dur = SWEEP/SPEED,
      group = group, big = group and GROUP_BIG or 1 }
    if q.light then q.light.lens = q end
    beside(q, q.spot)
    L.on = true
    L.m.position:copy(pos); L.m.scale:set_scalar(0.001); L.m.visible = true; L.sh.visible = true
    active[#active + 1] = q
    return pos
  end

  -- round 50: the long cut's path: from beside the first, nearest-next through the rest (each at its own
  -- ring, followed while it crawls), then a little past the last
  local function group_path(q)
    local left = {}
    for _, s in ipairs(q.group) do if snakes.free(s) then left[#left + 1] = { s = s, ring = aim_ring() } end end
    local order, at = {}, q.a:clone()
    while #left > 0 do
      local bi, bd = 1, 1e9
      for i, e in ipairs(left) do local p = e.s.spine[e.ring + 1]; local d = hyp(p.x - at.x, p.z - at.z); if d < bd then bd = d; bi = i end end
      local e = table.remove(left, bi)
      order[#order + 1] = e
      at = e.s.spine[e.ring + 1]
    end
    return { nodes = order, start = q.a:clone(), len = 0 }
  end
  local TAIL = Vector3.new()
  local function path_at(q, f, out)
    local P = q.path
    local pts = { P.start }
    for _, e in ipairs(P.nodes) do
      if snakes.free(e.s) or not e.p then e.p = (e.p or Vector3.new()):copy(e.s.spine[e.ring + 1]) end
      pts[#pts + 1] = e.p
    end
    local n = #pts
    TAIL:sub_vectors(pts[n], pts[n - 1]); TAIL.y = 0
    if TAIL:length_sq() < 1e-6 then TAIL:set(1, 0, 0) end
    TAIL:normalize()
    pts[n + 1] = pts[n]:clone():add_scaled_vector(TAIL, GROUP_TAIL)
    local len = 0
    for i = 2, #pts do len = len + hyp(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z) end
    P.len = len
    local want = f*len
    for i = 2, #pts do
      local l = hyp(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z)
      if want <= l or i == #pts then return out:lerp_vectors(pts[i - 1], pts[i], l > 0 and min(1, want/l) or 1) end
      want = want - l
    end
    return out
  end

  -- (round 53: a snake another lens is on its way to: this lens's cut passes it by)
  local function aimed_by_other(s, q)
    for _, o in ipairs(active) do
      if o ~= q and (o.ncut or 0) == 0 then
        if o.s == s then return true end
        if o.group then for _, g in ipairs(o.group) do if g == s then return true end end end
      end
    end
    return false
  end

  local function update(t, dt)
    for ii = #active, 1, -1 do
      local q = active[ii]
      local i = ii - 1                              -- lens.js's index (the drift and flicker phases)
      q.t = q.t + dt
      -- (round 52: a lens on its way keeps its snake(s) until its cut has passed)
      if snakes.reclaim and q.t - FORM - CONVERGE <= q.dur then
        if q.s and snakes.free(q.s) then snakes.reclaim(q.s, 'LENS') end
        if q.path then for _, e in ipairs(q.path.nodes) do if snakes.free(e.s) then snakes.reclaim(e.s, 'LENS') end end
        elseif q.group then for _, g in ipairs(q.group) do if snakes.free(g) then snakes.reclaim(g, 'LENS') end end end
      end
      local L = q.L
      local m = L.m
      local UU = m.material.user_data.U
      local t_form, t_conv, sweep_t = q.t/FORM, (q.t - FORM)/CONVERGE, q.t - FORM - CONVERGE
      local gone = smoothstep(q.dur + OFF, q.dur + OFF + FADE, sweep_t)
      local grow = smoothstep(0, FORM, q.t)
      local size = LENS_R*grow*(1 - 0.4*gone)*q.big
      m.scale:set(size, size, size)
      m.visible = size > 0.004 and gone < 0.999
      L.sh.material.uniforms.uA.value = (grow*(1 - smoothstep(FORM, FORM + 0.4, q.t)) + gone*0.8 + 0.7*q.flare)*(1 - gone*gone)
      L.sh.material.uniforms.uTime.value = t
      q.flare = max(0, q.flare - dt/0.25)
      UU.uRim.value = (0.3 + 2.2*q.flare*q.flare)*grow*(1 - gone)
      m.position:copy(q.pos):add(Vector3.new(sin(t*0.9 + i)*0.04, sin(t*1.3 + i*2)*0.05, cos(t*0.8 + i)*0.04))
      local lp = m.position:clone()
      if not q.fired and not snakes.free(q.s) then
        local nx = nil
        if q.group then for _, s in ipairs(q.group) do if snakes.free(s) then nx = s; break end end end
        if nx then q.s = nx else retarget(q) end
      end
      local st = q.t - FORM - CONVERGE
      if st < 0 then beside(q, q.spot)
      elseif not q.fired or q.core or st <= q.dur + OFF then
        if not q.fired then
          q.fired = true
          q.a:copy(q.spot); beside(q, q.a)
          if q.group then
            q.path = group_path(q)
            if #q.path.nodes == 0 then q.path = nil end
          end
          if q.path then
            path_at(q, 0, q.b)
            q.dur = max(0.4, q.path.len/GROUP_SPEED)
          else
            local p = frame_at(q.s, q.ring)
            local dir = Vector3.new():sub_vectors(p, q.a); dir.y = 0; dir:normalize()
            q.b:copy(q.a):add_scaled_vector(dir, SWEEP)
          end
        end
        -- (round 53: a single lens's line keeps turning to pass through its snake while it crawls, until cut)
        if snakes.reclaim and not q.path and q.fired and q.s and snakes.free(q.s) and (q.ncut or 0) == 0 and sweep_t < q.dur then
          local tp = frame_at(q.s, q.ring)
          local dx, dz = tp.x - q.a.x, tp.z - q.a.z
          local dl = hyp(dx, dz)
          if dl > 1e-3 then q.b:set(q.a.x + dx/dl*max(SWEEP, dl + 0.5), q.b.y, q.a.z + dz/dl*max(SWEEP, dl + 0.5)) end
        end
        -- (round 52: its snake taken by another lens's cut before this one reached it: this one stops)
        if snakes.reclaim and not q.path and q.s and not snakes.free(q.s) and (q.ncut or 0) == 0 and sweep_t < q.dur and sweep_t > 0 then q.b:copy(q.spot); q.a:copy(q.spot); q.dur = sweep_t end
        local f = min(1, sweep_t/q.dur)
        if q.path then path_at(q, f, q.spot) else q.spot:lerp_vectors(q.a, q.b, f) end
        q.spot.y = cave.ground_y(q.spot.x, q.spot.z) + 0.02
      end
      m:look_at(q.spot); m:rotate_x(pi/2)
      local conv = t_conv < 0 and 0 or (t_conv >= 1 and 1 or t_conv)
      local on_c = t_conv >= 0 and sweep_t < LIGHTS_OFF
      L.cone.visible = on_c; L.patch.visible = on_c
      if on_c then
        local rf = 0.03 + 0.9*((1 - conv)^1.6)
        local bright = min(60, (LENS_R*LENS_R)/(rf*rf))
        local fadec = smoothstep(0, 0.2, t_conv)*(sweep_t > 0 and 1 - sweep_t/LIGHTS_OFF or 1)
        local nrm = Vector3.new():sub_vectors(q.spot, lp):normalize()
        local e1 = Vector3.new():cross_vectors(nrm, Vector3.new(0, 1, 0)); if e1:length_sq() < 1e-6 then e1:set(1, 0, 0) end; e1:normalize()
        local e2 = Vector3.new():cross_vectors(nrm, e1):normalize()
        local pa, aa = L.cone.geometry.attributes.position.array, L.cone.geometry.attributes.aA.array
        for j = 0, SEG - 1 do
          local th = j/SEG*6.2832
          local c, sn = cos(th), sin(th)
          local r0 = size*0.95
          pa[j*3 + 1] = lp.x + (e1.x*c + e2.x*sn)*r0; pa[j*3 + 2] = lp.y + (e1.y*c + e2.y*sn)*r0; pa[j*3 + 3] = lp.z + (e1.z*c + e2.z*sn)*r0
          pa[(SEG + j)*3 + 1] = q.spot.x + c*rf; pa[(SEG + j)*3 + 2] = q.spot.y + 0.01; pa[(SEG + j)*3 + 3] = q.spot.z + sn*rf
          aa[j + 1] = 0.05*fadec; aa[SEG + j + 1] = min(0.9, 0.05*sqrt(bright))*fadec
        end
        L.cone.geometry.attributes.position.needs_update = true; L.cone.geometry.attributes.aA.needs_update = true
        L.patch.position:set(q.spot.x, q.spot.y + 0.015, q.spot.z)
        L.patch.scale:set(rf*1.6, rf*1.6, 1)
        L.patch.material.uniforms.uA.value = min(9, 0.35*bright)*fadec
        if rng.next() < 0.6 then
          local w = rng.next()
          local p = lp:clone():lerp(q.spot, w)
          local rr = (size*0.95*(1 - w) + rf*w)*sqrt(rng.next())
          local th = rng.float(0, 6.28)
          p:add_scaled_vector(e1, cos(th)*rr):add_scaled_vector(e2, sin(th)*rr)
          local vx = rng.spread(0.05)
          local vy = rng.spread(0.05)
          local vz = rng.spread(0.05)
          fx.mote({ x = p.x, y = p.y, z = p.z, vx = vx, vy = vy, vz = vz, life = rng.float(0.2, 0.5), s0 = 0.015, s1 = 0.015, r = 1.4, g = 1.2, b = 0.9, fin = 0.3 })
        end
        if conv > 0.75 and rng.next() < 0.5 then
          local vx = rng.spread(0.05)
          local vy = rng.float(0.2, 0.45)
          local vz = rng.spread(0.05)
          fx.puff({ x = q.spot.x, y = q.spot.y + 0.03, z = q.spot.z, vx = vx, vy = vy, vz = vz, drag = 0.3, life = rng.float(0.8, 1.4), s0 = 0.05, s1 = 0.3, r = 0.02, g = 0.018, b = 0.016, a = 0.4 })
        end
        if conv > 0.6 then fx.mote({ x = q.spot.x, y = q.spot.y + 0.02, z = q.spot.z, life = 0.05, s0 = 0.06 + 0.1*conv, s1 = 0.06, r = 5, g = 4.4, b = 3, fin = 0.01 }) end
      end
      if sweep_t >= 0 and sweep_t <= q.dur + OFF then
        local k_off = sweep_t <= q.dur and 1 or 1 - (sweep_t - q.dur)/OFF
        local pop = 1 + 0.6*exp(-sweep_t*18)
        local flick = 1 + 0.12*sin(t*57 + i) + 0.07*sin(t*83 + i*3)
        if not q.core then
          q.core = fx.ribbon(lp, q.spot, { held = true, style = look == 0 and 2 or 3, w = 2, w0 = 0.1, w1 = 0.1 })
          fired[#fired + 1] = { lp = lp:to_array(), spot = q.spot:to_array(), quick = q.t0q, size = m.scale.x }
          q.flare = 1
          for _ = 1, 14 do
            local vx = rng.spread(1.6)
            local vy = rng.float(1.0, 3.0)
            local vz = rng.spread(1.6)
            fx.mote({ x = q.spot.x, y = q.spot.y + 0.03, z = q.spot.z, vx = vx, vy = vy, vz = vz, grav = 8, drag = 0.4, life = rng.float(0.3, 0.6), s0 = 0.03, s1 = 0.012, r = 4.5, g = 2.6, b = 0.8, fin = 0.01 })
          end
          fx.puff({ x = q.spot.x, y = q.spot.y + 0.05, z = q.spot.z, vy = 0.5, drag = 0.5, life = 1.2, s0 = 0.12, s1 = 0.5, r = 0.02, g = 0.018, b = 0.016, a = 0.45 })
        end
        local w = pop*flick*k_off
        q.core.p0:copy(lp); q.core.p1:copy(q.spot)
        if look == 0 then q.core.w0 = 0.22*w; q.core.w1 = 0.16*w else q.core.w0 = 0.03*w; q.core.w1 = 0.24*w end
        q.core.a = k_off; q.core.c = look == 0 and { 1, 1, 1 } or { 1.1, 1.0, 0.9 }
        for _ = 1, 2 do
          local e = rng.next()
          local p = lp:clone():lerp(q.spot, e)
          local x = p.x + rng.spread(0.04)
          local z = p.z + rng.spread(0.04)
          local vx = rng.spread(0.7)
          local vy = rng.float(-0.6, 0.4)
          local vz = rng.spread(0.7)
          local life = rng.float(0.2, 0.45)
          local hue = look == 1 and rng.next() or -1
          fx.mote({ x = x, y = p.y, z = z, vx = vx, vy = vy, vz = vz, grav = 2, drag = 1.5, life = life, s0 = 0.03, s1 = 0.012, r = 3.4, g = 1.5, b = 0.35, a = k_off, hue = hue, hr = 1 })
        end
        if sweep_t <= q.dur then
          local sp = q.spot
          fx.mote({ x = sp.x, y = sp.y + 0.06, z = sp.z, life = 0.06, s0 = 0.3*flick, s1 = 0.24, r = 5, g = 3.4, b = 1.4, fin = 0.01 })
          fx.mote({ x = sp.x, y = sp.y + 0.03, z = sp.z, life = 0.06, s0 = 0.12, s1 = 0.1, r = 6, g = 5.5, b = 4, fin = 0.01 })
          for _ = 1, 4 do
            local vx = rng.spread(2.2)
            local vy = rng.float(0.8, 2.6)
            local vz = rng.spread(2.2)
            local life = rng.float(0.3, 0.7)
            local hue = look == 1 and rng.next() or -1
            fx.mote({ x = sp.x, y = sp.y + 0.03, z = sp.z, vx = vx, vy = vy, vz = vz, grav = 7, drag = 0.5, life = life, s0 = 0.03, s1 = 0.012, r = 4, g = 2.2, b = 0.6, hue = hue, hr = 1 })
          end
          if rng.next() < 0.6 then
            local vy = rng.float(0.3, 0.6)
            local vx = rng.spread(0.1)
            local vz = rng.spread(0.1)
            fx.puff({ x = sp.x, y = sp.y + 0.05, z = sp.z, vy = vy, vx = vx, vz = vz, drag = 0.4, life = rng.float(1.0, 1.8), s0 = 0.1, s1 = 0.45, r = 0.014, g = 0.012, b = 0.011, a = 0.35 })
          end
          do
            local x = sp.x + rng.spread(0.02)
            local z = sp.z + rng.spread(0.02)
            fx.mote({ x = x, y = sp.y + 0.01, z = z, life = rng.float(1.4, 2.4), s0 = 0.06, s1 = 0.035, r = 1.4, g = 0.4, b = 0.07, a = 0.85, fin = 0.02 })
          end
          for _, s in ipairs(snakes.S) do
            if snakes.free(s) and not (snakes.held_by_other and s ~= q.s and (snakes.held_by_other(s, 'LENS') or aimed_by_other(s, q))) then
              local best, bi = 1e9, -1
              for j = 2, N - 3 do local d = hyp(s.spine[j + 1].x - sp.x, s.spine[j + 1].z - sp.z); if d < best then best = d; bi = j end end
              if best < CUT_R and snakes.arc(bi) <= CUT_MAX and snakes.arc(bi) >= CUT_MIN then
                s.claim = nil; snakes.take(s, cut_fx(s, max(3, bi))); cuts[#cuts + 1] = { arc = snakes.arc(bi), target = s == q.s }
                q.ncut = (q.ncut or 0) + 1
              end
            end
          end
        end
      end
      if q.light then
        local lit
        if sweep_t < 0 then lit = t_conv > 0 and 0.25 + 0.75*conv*conv or 0
        elseif sweep_t <= q.dur + OFF then lit = sweep_t <= q.dur and 1 or 1 - (sweep_t - q.dur)/OFF
        else lit = 0 end
        q.light.l.position:set(q.spot.x, q.spot.y + 0.3, q.spot.z)
        q.light.l.intensity = 2.2*lit*(0.85 + 0.15*sin(t*37))
      end
      if gone > 0 and gone < 1 and rng.next() < 0.5 then
        local x = lp.x + rng.spread(0.3)
        local y = lp.y + rng.spread(0.05)
        local z = lp.z + rng.spread(0.3)
        local vx = rng.spread(0.3)
        local vy = rng.float(-0.2, 0.3)
        local vz = rng.spread(0.3)
        local life = rng.float(0.3, 0.6)
        fx.mote({ x = x, y = y, z = z, vx = vx, vy = vy, vz = vz, life = life, s0 = 0.03, s1 = 0.01, r = 2, g = 2, b = 2.2, hue = rng.next(), hr = 1 })
      end
      if sweep_t > q.dur + OFF + FADE then
        L.on = false; m.visible = false; L.sh.visible = false; L.cone.visible = false; L.patch.visible = false
        if q.fired then
          stats.done = stats.done + 1
          if (q.ncut or 0) == 0 then
            stats.empty = stats.empty + 1
            local tg = q.s
            stats.why = stats.why or {}
            local d = tg and hyp(tg.spine[q.ring + 1].x - q.b.x, tg.spine[q.ring + 1].z - q.b.z) or -1
            stats.why[#stats.why + 1] = string.format('%s free %s by %s group %s quick %s ring-to-end %.2f', tostring(tg ~= nil), tostring(tg and snakes.free(tg)),
              tostring(tg and tg.fx and tg.fx.by or (tg and tg.burn and 'burn') or '-'), tostring(q.group ~= nil), tostring(q.t0q), d)
            if #stats.why > 30 then table.remove(stats.why, 1) end
          end
        end
        if q.core then fx.release(q.core) end
        if q.light then q.light.l.intensity = 0; q.light.lens = nil end
        table.remove(active, ii)
      end
    end
  end

  local P = { name = 'LENS', gesture = false, cooldown = 6.5, update = update, cuts = cuts, fired = fired, active = active, stats = stats }
  function P.capacity(p) return ceil(p/1.5) end
  function P.cast(targets, quick)
    local out = {}
    for k, s in ipairs(targets) do local p = spawn(s, k - 1, quick); if p then out[#out + 1] = p end end
    return out
  end
  -- round 52: a snake near the egg that a lens is already forming over: that lens fires now (as a quick
  -- one would) instead of a second lens being sent; true if one was found (forming, or already firing)
  function P.hurry(s)
    for _, q in ipairs(active) do
      if q.s == s or (q.group and (function() for _, g in ipairs(q.group) do if g == s then return true end end; return false end)()) then
        if not q.fired then q.t = max(q.t, FORM + CONVERGE - 0.12) end
        return true
      end
    end
    return false
  end
  function P.cast_group(targets)
    local p = spawn(targets[1], 0, false, targets)
    return p and { p } or {}
  end
  function P.busy_count() return #active end
  function P.get_look() return look end
  function P.set_look(v) look = ((v % NLOOKS) + NLOOKS) % NLOOKS end
  function P.free_lenses() local n = 0; for _, q in ipairs(LENSES) do if not q.on then n = n + 1 end end; return n end
  function P.use_claims(is_unclaimed, do_claim) unclaimed = is_unclaimed; claim = do_claim end
  return P
end

return LE
