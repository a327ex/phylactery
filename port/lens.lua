--[[
  lens.lua -- the port to Anchor: web/src/lens.js. LENS: a glass lens crystallizes in the shaft
  (transmissive glass), gathers the sunlight into a cone and a patch on the floor that tightens to
  a point beside the snake, then fires a fire laser that sweeps across it and cuts it (cut_fx);
  the glass dissolves into glints (round 69: in the game's flow it BREAKS instead, port/shards.lua; LICH_ROOM keeps
  the dissolve). No gesture; several lenses at once with fewer powers.
  Round 50: three or more in one cast (the bouts, powers.lua): one larger lens, and its burning point
  draws one long cut through them all, from beside the first through each in turn (cast_group).
  2026-10-15, THE FAMILIAR (the game's flow; LICH_ROOM keeps a lens per cast): a lens, once formed, stays. After its cut
  it floats in the shaft, resting its gaze on the egg; given its next snake it glides a little and turns to it, gathers
  the light and cuts again, until its shots or its life are spent or nothing comes for a while, and then it breaks.
  powers.lua decides when it shoots and how many there may be.
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local MAT = require('port.three.materials')
local U = require('port.util')
local CAVE = require('port.cave')
local AU = require('port.audio')     -- 2026-10-10: the sounds (never draw from rng here)
local Vector2, Vector3 = TM.Vector2, TM.Vector3
local smoothstep = U.smoothstep
local sqrt, abs, sin, cos, exp, floor, ceil, min, max, pi = math.sqrt, math.abs, math.sin, math.cos, math.exp, math.floor, math.ceil, math.min, math.max, math.pi

local LE = {}
LE.STAGGER = 0.25     -- (2026-10-12) at least this long between two lenses starting (the game's flow)
local FORM, CONVERGE, SPEED, SWEEP, LEAD, OFF, FADE, CUT_R = 0.4, 0.8, 3.0, 2.6, 0.35, 0.2, 0.45, 0.13
local LENS_R = 0.38
local LIGHTS_OFF = 0.15
local CUT_MIN, CUT_MAX = 1.0, 2.6
local GROUP_SPEED, GROUP_BIG, GROUP_TAIL = 5.0, 1.45, 0.7
LE.LENS_LOOKS = { 'FIRE LASER (TITAN, PHRIKE)', 'THE PRISMATIC BEAM, IN FIRE' }
-- (2026-10-15) what the familiar darts about (Q, testing): its place in the shaft leaning to him, or him
LE.FOLLOWS = { 'ITS PLACE IN THE SHAFT, LEANING TO HIM', "HIM, LIKE EMOJIAN'S GUN" }
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
  -- round 69 (owner, 2026-10-11): a lens that is done breaks like glass (the game's flow; LICH_ROOM keeps the dissolve)
  local shards = ctx.varied and require('port.shards').create(R, cave, fx) or nil
  -- 2026-10-12 (owner: "multiple attack lens can't spawn at exactly the same time, at least a 0.25s or so delay between
  -- them, otherwise the attack sound gets repeated"): in the game's flow a lens starts STAGGER s after the last one
  -- started, at the soonest (casts of several, and casts close together). Its snake, ring and place are chosen at the
  -- cast as before; it waits (q.wait_t: unseen, silent, its snake kept), then starts as if spawned then. LICH_ROOM:
  -- all at once, as before.
  local stagger = ctx.varied and LE.STAGGER or 0
  local clock, last_start = 0, -1e9
  local active = {}
  local look = 0
  local cuts, fired = {}, {}
  local stats = { done = 0, empty = 0 }              -- (lenses whose cut ended, and those that cut nothing)
  -- 2026-10-15 (owner: "the lens should be more like a familiar that is destroyed and created less often. It should
  -- stay above and float and change angles as it targets snakes instead of being created/destroyed for each individual
  -- attack. But it shouldn't stay forever nor attack every snake unless the setup requires it when its the only weapon
  -- or one of the few left"): in the game's flow a lens is a FAMILIAR. It lives max_shots shots or life s, and breaks
  -- after IDLE_MAX s with nothing to do; when the lens is the only attack or one of two (`strong`, set by powers.lua)
  -- only the idle time ends it, and there may be more than one. A cast beyond them (the guarantee's rush) still makes a
  -- lens that breaks after its cut. Once the last one breaks another forms only after a while. Its own draws (frng)
  -- leave the lens rng's order as it was.
  local familiar = ctx.varied or false
  local frng = familiar and U.run_rng(7331) or nil
  local fam_max, fam_strong = 1, false
  local TURN, IDLE_MAX, IDLE_MAX_STRONG = 0.4, 5.0, 6.0
  local resummon_at = -1e9
  local EGG_LOOK = Vector3.new(snakes.egg.x, cave.ground_y(snakes.egg.x, snakes.egg.z), snakes.egg.z)
  local function fam_count() local n = 0; for _, q in ipairs(active) do if q.fam and not q.leaving then n = n + 1 end end; return n end
  local function idle_fam() for _, q in ipairs(active) do if q.fam and q.idle and not q.leaving then return q end end; return nil end
  local function new_place(q)                       -- where it floats for its next cut: in the shaft, near where it was
    local h = frng.float(3.8, 5.6)
    q.pos_to = axis_at(h):add(Vector3.new(frng.spread(0.9), 0, frng.spread(0.9)))
  end
  -- (2026-10-15, owner: "The lens following behavior should also be more loose, and it should lightly be affected by
  -- the player, so maybe the lens lightly, very lightly follow the player") its gaze rides a soft spring (it lags and
  -- overshoots a little: LOOK_W rad/s, under-damped), and its place leans toward the lich by PULL of his offset from it
  -- across the floor, at most PULL_MAX m (how it moves there: emojian's arrive, FOLLOW below)
  local LOOK_W, LOOK_W_AIM, LOOK_Z, PULL, PULL_MAX = 2.6, 7.0, 0.6, 0.12, 1.0
  local get_L = ctx.get_L
  local WANT = Vector3.new()
  local function spring(p, v, to, w, z, dt)
    local ax, ay, az = w*w*(to.x - p.x) - 2*z*w*v.x, w*w*(to.y - p.y) - 2*z*w*v.y, w*w*(to.z - p.z) - 2*z*w*v.z
    v.x, v.y, v.z = v.x + ax*dt, v.y + ay*dt, v.z + az*dt
    p.x, p.y, p.z = p.x + v.x*dt, p.y + v.y*dt, p.z + v.z*dt
  end
  -- (same day, owner: "There is a game called emojunky where I had a gun emoji follow the player as a familiar, perhaps
  -- it was another game ... make the lens be more like that instead in terms of its movement") it was emojian (2022,
  -- Z:\2022-2023\code\emojian\automata.lua: its automatons, "like Isaac's familiars that follow you around and
  -- shoot"): every 0.4-1.2 s the gun took a new spot near the player (35 px either side, 25-75 px above; the gun 18 px)
  -- and ARRIVED there: straight at it at up to 150 px/s under a capped force, slowing only within 25 px of it, so it
  -- darts and settles, darts and settles. The lens does the same about what it follows (FOLLOW: across m either side,
  -- up m above, max_v m/s (max_v_him after him), max_a m/s^2, slowing within slow_r). What it follows (LE.FOLLOWS, Q):
  -- its place in the shaft leaning to him (PULL, the default), or him, above_lich m over his root, as the gun followed
  -- the player. (Same day, owner: "When firing the lens stop moving, this stop has to be realistic and not abrupt, but
  -- it has to stop seeking new positions and so on") from the moment it starts gathering the light until its cut is
  -- over (`hold`) it seeks nothing and comes to rest, its speed dying away as under drag (brake /s), never braking
  -- harder than it accelerates (max_a): from 3 m/s near still in ~0.6 s, from 4.5 in ~0.75 s, so it is still by the
  -- fire (0.8 s of gathering); its hover's bob eases down to bob_hold of itself.
  local FOLLOW = { every = { 0.4, 1.2 }, across = 1.0, up = { 0.0, 1.1 }, max_v = 3.0, max_v_him = 4.5, max_a = 14.0, slow_r = 0.7, above_lich = 2.6,
                   brake = 6.0, bob_hold = 0.15 }
  local follow = 0
  local function drift(q, dt, hold)
    local v = q.posv
    if hold then
      -- (dying away as under drag, but never braking harder than it can push: max_a)
      local vl = sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
      local dv = min(vl*min(1, FOLLOW.brake*dt), FOLLOW.max_a*dt)
      local k = vl > 0 and (vl - dv)/vl or 0
      v.x, v.y, v.z = v.x*k, v.y*k, v.z*k
      if vl - dv < 0.01 then v.x, v.y, v.z = 0, 0, 0 end
      q.pos.x, q.pos.y, q.pos.z = q.pos.x + v.x*dt, q.pos.y + v.y*dt, q.pos.z + v.z*dt
      return
    end
    q.off_t = (q.off_t or 0) - dt
    if q.off_t <= 0 or not q.off then
      q.off_t = frng.float(FOLLOW.every[1], FOLLOW.every[2])
      q.off = q.off or Vector3.new()
      q.off:set(frng.spread(FOLLOW.across), frng.float(FOLLOW.up[1], FOLLOW.up[2]), frng.spread(FOLLOW.across))
    end
    local Lp = get_L and get_L()
    if follow == 1 and Lp then WANT:set(Lp.x, Lp.y + FOLLOW.above_lich, Lp.z)
    else
      WANT:copy(q.pos_to)
      if Lp then
        local dx, dz = (Lp.x - q.pos_to.x)*PULL, (Lp.z - q.pos_to.z)*PULL
        local d = hyp(dx, dz)
        if d > PULL_MAX then dx, dz = dx*PULL_MAX/d, dz*PULL_MAX/d end
        WANT.x, WANT.z = WANT.x + dx, WANT.z + dz
      end
    end
    WANT:add(q.off)
    -- arrive: the speed it wants (full, or less within slow_r), the change toward it capped, the speed capped
    local dx, dy, dz = WANT.x - q.pos.x, WANT.y - q.pos.y, WANT.z - q.pos.z
    local d = sqrt(dx*dx + dy*dy + dz*dz)
    local vmax = follow == 1 and FOLLOW.max_v_him or FOLLOW.max_v   -- (after him: faster than his 2.6 m/s, as the gun was than the player)
    local want = d < FOLLOW.slow_r and vmax*d/FOLLOW.slow_r or vmax
    local wx, wy, wz = 0, 0, 0
    if d > 1e-6 then wx, wy, wz = dx/d*want, dy/d*want, dz/d*want end
    local sx, sy, sz = wx - v.x, wy - v.y, wz - v.z
    local sl, cap = sqrt(sx*sx + sy*sy + sz*sz), FOLLOW.max_a*dt
    if sl > cap then sx, sy, sz = sx*cap/sl, sy*cap/sl, sz*cap/sl end
    v.x, v.y, v.z = v.x + sx, v.y + sy, v.z + sz
    local vl = sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
    if vl > vmax and vl > 0 then v.x, v.y, v.z = v.x*vmax/vl, v.y*vmax/vl, v.z*vmax/vl end
    q.pos.x, q.pos.y, q.pos.z = q.pos.x + v.x*dt, q.pos.y + v.y*dt, q.pos.z + v.z*dt
  end

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
    if q.fam then q.settle_now = true; return false end           -- (a familiar: back to floating, no shot spent)
    q.fired = true; q.t = FORM + CONVERGE + q.dur + OFF + 1e-3
    return false
  end
  local function beside(q, out)
    if snakes.free(q.s) then local p = frame_at(q.s, q.ring); out:copy(p):add_scaled_vector(ACR, -LEAD*q.side) end
    out.y = cave.ground_y(out.x, out.z) + 0.02
    return out
  end
  local function spawn(s, k, quick, group, fam)
    quick = quick or false
    local wait = 0
    if stagger > 0 then
      local start = math.max(clock, last_start + stagger)
      wait, last_start = start - clock, start
    end
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
    if fam then
      q.fam = true; q.age = 0; q.shots = 0; q.idle_t = 0; q.cd = 0
      q.max_shots = frng.int(3, 5); q.life = frng.float(9, 14); q.ph = frng.float(0, 6.28)
      q.look = q.spot:clone(); q.pos_to = pos:clone(); q.bigv = q.big
      q.posv = Vector3.new(); q.lookv = Vector3.new()
    end
    L.on = true
    if wait > 0 then q.wait_t = wait                                  -- (it sounds and shows as it starts: update)
    else AU.play('lens_form', { pos = pos }) end
    L.m.position:copy(pos); L.m.scale:set_scalar(0.001); L.m.visible = wait <= 0; L.sh.visible = true
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

  -- (2026-10-16, owner: "attack lens fire will often go through a snake, but because the snake isn't the targeted one, it
  -- doesn't die, which feels unrealistic. If the laser goes through a snake it should die and other abilities should take
  -- that into account and target other snakes from the get go") the game's flow only (snakes.reclaim: LICH_ROOM keeps the
  -- old rule): every free snake near the line its fire will sweep is this lens's from the moment it starts gathering the
  -- light (a claim renewed each tick, so the other attacks choose others), and its cut takes every snake it passes over.
  -- Before the fire the line is the one the fire will take from where things are now (beside(), toward the target's
  -- frame, SWEEP long); then what is left of it (the spot to its end, or the rest of a group's path). No rng draws.
  local CLAIM_R = CUT_R + 0.12
  local LA, LB, LP = Vector3.new(), Vector3.new(), {}
  for k = 1, 9 do LP[k] = Vector3.new() end
  local function seg_d(px, pz, ax, az, bx, bz)
    local dx, dz = bx - ax, bz - az
    local l2 = dx*dx + dz*dz
    local u = l2 > 1e-9 and max(0, min(1, ((px - ax)*dx + (pz - az)*dz)/l2)) or 0
    return hyp(px - (ax + dx*u), pz - (az + dz*u))
  end
  local function line_of(q)
    local pts, n = LP, 0
    if not q.fired then
      if q.group or not q.s or not snakes.free(q.s) then return nil, 0 end
      beside(q, LA)
      local p = frame_at(q.s, q.ring)
      local dx, dz = p.x - LA.x, p.z - LA.z
      local dl = hyp(dx, dz)
      if dl < 1e-3 then return nil, 0 end
      LB:set(LA.x + dx/dl*max(SWEEP, dl + 0.5), 0, LA.z + dz/dl*max(SWEEP, dl + 0.5))
      pts[1]:copy(LA); pts[2]:copy(LB); n = 2
    elseif q.path then
      local f0 = min(1, max(0, q.t - FORM - CONVERGE)/q.dur)
      for k = 0, 8 do n = n + 1; path_at(q, f0 + (1 - f0)*k/8, pts[n]) end
    else
      pts[1]:copy(q.spot); pts[2]:copy(q.b); n = 2
    end
    return pts, n
  end
  local function claim_line(q)
    local pts, n = line_of(q)
    if not pts then return end
    for _, s in ipairs(snakes.S) do
      if snakes.free(s) and s ~= q.s then
        local hit = false
        for j = 2, N - 3, 2 do
          local p = s.spine[j + 1]
          for k = 2, n do if seg_d(p.x, p.z, pts[k - 1].x, pts[k - 1].z, pts[k].x, pts[k].z) < CLAIM_R then hit = true; break end end
          if hit then break end
        end
        if hit then snakes.reclaim(s, 'LENS') end
      end
    end
  end

  -- a shot's tally (once): its cut done, and whether it cut nothing
  local function count_shot(q)
    if q.counted or not q.fired then return end
    q.counted = true
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
  -- the familiar: its cut over (or none to make), it floats waiting; its time up, it breaks where it is (round 69)
  local function settle(q, no_shot)
    if not no_shot then count_shot(q); q.shots = q.shots + 1 end
    if q.charge then q.charge.stop(); q.charge = nil end
    if q.core then fx.release(q.core); q.core = nil end
    if q.snd then q.snd.stop(); q.snd = nil end
    if q.light then q.light.l.intensity = 0 end
    q.L.cone.visible = false; q.L.patch.visible = false
    q.idle = true; q.idle_t = 0; q.cd = frng.float(1.2, 2.4)
    q.fired = false; q.s = nil; q.group = nil; q.path = nil; q.ncut = 0; q.big = 1; q.flare = 0; q.settle_now = nil
  end
  local function leave(q)
    if q.charge then q.charge.stop(); q.charge = nil end
    q.idle = false; q.leaving = true; q.fired = true; q.counted = true; q.focus_snd = true
    q.s = nil; q.group = nil; q.path = nil
    q.t = FORM + CONVERGE + q.dur + OFF + 1e-4
    if q.light then q.light.l.intensity = 0 end
    if fam_count() == 0 then resummon_at = clock + (fam_strong and 0 or frng.float(4.0, 7.0)) end
  end
  -- its next snake (or several: one long cut): it glides a little, turns to it, gathers the light, cuts
  local function shoot(q, s, quick, group)
    q.idle = false; q.idle_t = 0
    q.s = s; q.group = group; q.ring = aim_ring(); q.side = rng.sign()
    q.dur = SWEEP/SPEED; q.fired = false; q.core = nil; q.ncut = 0; q.path = nil; q.focus_snd = nil; q.counted = nil
    q.big = group and GROUP_BIG or 1
    q.t0q = quick or false
    q.t = quick and FORM + CONVERGE - 0.12 or FORM - TURN
    new_place(q)
    beside(q, q.spot)
    if not q.light then for _, x in ipairs(LIGHTS) do if not x.lens then q.light = x; x.lens = q; break end end end
    return q.pos_to:clone()
  end
  -- it floats, resting its gaze on the egg
  local IDLE_BOB = Vector3.new()
  local function float_idle(q, t, dt)
    local L, m = q.L, q.L.m
    drift(q, dt)
    q.bobk = (q.bobk or 1) + (1 - (q.bobk or 1))*(1 - exp(-dt*3))
    IDLE_BOB:set(sin(t*0.9 + q.ph)*0.06*q.bobk, sin(t*1.3 + q.ph*2)*0.08*q.bobk, cos(t*0.8 + q.ph)*0.06*q.bobk)
    m.position:copy(q.pos):add(IDLE_BOB)
    spring(q.look, q.lookv, EGG_LOOK, LOOK_W*0.6, LOOK_Z, dt)
    m:look_at(q.look); m:rotate_x(pi/2)
    q.bigv = q.bigv + (1 - q.bigv)*(1 - exp(-dt*4))
    local size = LENS_R*q.bigv
    m.scale:set(size, size, size); m.visible = true; L.sh.visible = true
    L.sh.material.uniforms.uA.value = 0; L.sh.material.uniforms.uTime.value = t
    m.material.user_data.U.uRim.value = 0.3
    L.cone.visible = false; L.patch.visible = false
    if q.light then q.light.l.intensity = 0 end
  end

  local function update(t, dt)
    clock = t
    if shards then shards.update(t, dt, R.world_camera) end
    for ii = #active, 1, -1 do
      local q = active[ii]
      local i = ii - 1                              -- lens.js's index (the drift and flicker phases)
      -- (a staggered lens waits its turn, unseen and silent, keeping its snake(s); then it starts, quick if hurried)
      if q.wait_t then
        q.wait_t = q.wait_t - dt
        if q.wait_t > 0 then
          if snakes.reclaim then
            if q.s and snakes.free(q.s) then snakes.reclaim(q.s, 'LENS') end
            if q.group then for _, g in ipairs(q.group) do if snakes.free(g) then snakes.reclaim(g, 'LENS') end end end
          end
          q.L.m.visible = false
          goto next_lens
        end
        q.wait_t = nil
        if q.hurried then q.t = max(q.t, FORM + CONVERGE - 0.12); q.hurried = nil end
        AU.play('lens_form', { pos = q.pos })
      end
      q.t = q.t + dt
      if q.fam then
        q.age = q.age + dt
        if q.t >= FORM + 0.4 then q.formed = true end
        if q.settle_now then settle(q, true) end
        -- its cut over: it floats on, or (its shots or its life spent) it breaks
        if q.fired and not q.leaving and q.t - FORM - CONVERGE > q.dur + OFF then
          settle(q)
          if q.dismissed or (not fam_strong and (q.shots >= q.max_shots or q.age >= q.life)) then leave(q) end
        end
        if q.idle then
          q.idle_t = q.idle_t + dt
          if q.dismissed or q.idle_t > (fam_strong and IDLE_MAX_STRONG or IDLE_MAX) or (not fam_strong and q.age >= q.life) then leave(q)
          else float_idle(q, t, dt); goto next_lens end
        end
        if not q.leaving then drift(q, dt, q.t >= FORM) end
      end
      -- (round 52: a lens on its way keeps its snake(s) until its cut has passed)
      if snakes.reclaim and q.t - FORM - CONVERGE <= q.dur then
        if q.s and snakes.free(q.s) then snakes.reclaim(q.s, 'LENS') end
        if q.path then for _, e in ipairs(q.path.nodes) do if snakes.free(e.s) then snakes.reclaim(e.s, 'LENS') end end
        elseif q.group then for _, g in ipairs(q.group) do if snakes.free(g) then snakes.reclaim(g, 'LENS') end end end
      end
      -- (2026-10-16) and every snake on the line its fire will sweep, from when it starts gathering the light
      if snakes.reclaim and q.t >= FORM and q.t - FORM - CONVERGE <= q.dur then claim_line(q) end
      local L = q.L
      local m = L.m
      local UU = m.material.user_data.U
      local t_form, t_conv, sweep_t = q.t/FORM, (q.t - FORM)/CONVERGE, q.t - FORM - CONVERGE
      local gone = smoothstep(q.dur + OFF, q.dur + OFF + FADE, sweep_t)
      local grow = q.formed and 1 or smoothstep(0, FORM, q.t)
      if q.fam then q.bigv = q.bigv + (q.big - q.bigv)*(1 - exp(-dt*4)) end
      local size = LENS_R*grow*(1 - 0.4*gone)*(q.fam and q.bigv or q.big)
      m.scale:set(size, size, size)
      m.visible = size > 0.004 and gone < 0.999
      L.sh.material.uniforms.uA.value = ((q.formed and 0.45 or 1)*grow*(1 - smoothstep(FORM, FORM + 0.4, q.t)) + gone*0.8 + 0.7*q.flare)*(1 - gone*gone)
      L.sh.material.uniforms.uTime.value = t
      q.flare = max(0, q.flare - dt/0.25)
      UU.uRim.value = (0.3 + 2.2*q.flare*q.flare)*grow*(1 - gone)
      local ph = q.fam and q.ph or i
      if q.fam then
        local hold = q.t >= FORM and not q.leaving
        q.bobk = (q.bobk or 1) + ((hold and FOLLOW.bob_hold or 0.7) - (q.bobk or 1))*(1 - exp(-dt*4))
        IDLE_BOB:set(sin(t*0.9 + ph)*0.06*q.bobk, sin(t*1.3 + ph*2)*0.08*q.bobk, cos(t*0.8 + ph)*0.06*q.bobk)
        m.position:copy(q.pos):add(IDLE_BOB)
      else m.position:copy(q.pos):add(Vector3.new(sin(t*0.9 + ph)*0.04, sin(t*1.3 + ph*2)*0.05, cos(t*0.8 + ph)*0.04)) end
      local lp = m.position:clone()
      -- round 69: done, it breaks: gone in one frame, its glass in shards (facing the spot it burned, as it looked)
      if shards and gone > 0 and not q.broke then
        q.broke = true
        shards.burst(lp, LENS_R*(q.fam and q.bigv or q.big), Vector3.new():sub_vectors(q.spot, lp), look == 0)
      end
      if q.broke then m.visible = false end
      if not q.fired and not snakes.free(q.s) then
        local nx = nil
        if q.group then for _, s in ipairs(q.group) do if snakes.free(s) then nx = s; break end end end
        if nx then q.s = nx else retarget(q) end
        if q.settle_now then settle(q, true); float_idle(q, t, dt); goto next_lens end
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
      if q.fam then                                  -- (the familiar turns to its snake, then holds on it)
        spring(q.look, q.lookv, q.spot, t_conv >= 0 and LOOK_W_AIM or LOOK_W, LOOK_Z, dt)
        m:look_at(q.look)
      else m:look_at(q.spot) end
      m:rotate_x(pi/2)
      local conv = t_conv < 0 and 0 or (t_conv >= 1 and 1 or t_conv)
      local on_c = t_conv >= 0 and sweep_t < LIGHTS_OFF
      -- (2026-10-11, owner: lens_focus -> lens_charge, "right after the lens forms, while the attack is building up": from the
      -- lens itself now, not the spot on the floor where its light gathers)
      -- (2026-10-15, owner: "I need a lens_charge event that happens when the lens starts focusing and ends right before it
      -- fires") a loop from the lens from the moment it starts gathering the light, stopped as the fire comes: its FADE
      -- OUT (the editor) set to end at the fire. Not for a lens hurried to fire within 0.1 s
      if t_conv >= 0 and not q.focus_snd then
        q.focus_snd = true
        if sweep_t < -0.1 then q.charge = AU.loop('lens_charge', { pos = lp }) end
      end
      if q.charge then
        if sweep_t >= -AU.get('lens_charge', 'fade') then q.charge.stop(); q.charge = nil
        else q.charge.set_pos(lp) end
      end
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
        if q.snd then q.snd.set_pos(q.spot) end
        if not q.core then
          q.snd = AU.loop('lens_fire', { pos = q.spot, max = 2 })
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
          -- (2026-10-16: in the game's flow the fire takes every free snake it passes over, whoever else had chosen it,
          -- cut where it is crossed, kept inside the cuttable stretch; LICH_ROOM keeps round 52/53's rule)
          local pierce = snakes.reclaim ~= nil
          for _, s in ipairs(snakes.S) do
            if snakes.free(s) and (pierce or not (snakes.held_by_other and s ~= q.s and (snakes.held_by_other(s, 'LENS') or aimed_by_other(s, q)))) then
              local best, bi = 1e9, -1
              for j = 2, N - 3 do local d = hyp(s.spine[j + 1].x - sp.x, s.spine[j + 1].z - sp.z); if d < best then best = d; bi = j end end
              if pierce and best < CUT_R then
                while bi > 3 and snakes.arc(bi) > CUT_MAX do bi = bi - 1 end
                while bi < N - 4 and snakes.arc(bi) < CUT_MIN do bi = bi + 1 end
              end
              if best < CUT_R and snakes.arc(bi) <= CUT_MAX and snakes.arc(bi) >= CUT_MIN then
                s.claim = nil; snakes.take(s, cut_fx(s, max(3, bi))); cuts[#cuts + 1] = { arc = snakes.arc(bi), target = s == q.s }
                AU.play('lens_cut', { pos = s.spine[bi + 1], gap = 0.05 })
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
      if q.snd and sweep_t > q.dur + OFF then q.snd.stop(); q.snd = nil end
      if not shards and gone > 0 and not q.gone_snd then q.gone_snd = true; AU.play('lens_dissolve', { pos = lp }) end
      if not shards and gone > 0 and gone < 1 and rng.next() < 0.5 then     -- (the dissolve's glints: LICH_ROOM only now)
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
        count_shot(q)
        if q.core then fx.release(q.core) end
        if q.snd then q.snd.stop(); q.snd = nil end
        if q.charge then q.charge.stop(); q.charge = nil end
        if q.light then q.light.l.intensity = 0; q.light.lens = nil end
        table.remove(active, ii)
      end
      ::next_lens::
    end
  end

  local P = { name = 'LENS', gesture = false, cooldown = 6.5, update = update, cuts = cuts, fired = fired, active = active, stats = stats }
  function P.capacity(p) return ceil(p/1.5) end
  function P.cast(targets, quick)
    local out = {}
    for k, s in ipairs(targets) do
      local p
      if familiar then
        local f = idle_fam()
        if f then p = shoot(f, s, quick)
        elseif fam_count() < fam_max and clock >= resummon_at then p = spawn(s, k - 1, quick, nil, true)
        elseif quick then p = spawn(s, k - 1, quick) end           -- (the guarantee's rush: a lens gone after its cut)
      else p = spawn(s, k - 1, quick) end
      if p then out[#out + 1] = p end
    end
    return out
  end
  -- round 52: a snake near the egg that a lens is already forming over: that lens fires now (as a quick
  -- one would) instead of a second lens being sent; true if one was found (forming, or already firing)
  function P.hurry(s)
    for _, q in ipairs(active) do
      if q.s == s or (q.group and (function() for _, g in ipairs(q.group) do if g == s then return true end end; return false end)()) then
        if q.wait_t then q.hurried = true                        -- (still waiting its turn: quick as it starts)
        elseif not q.fired then q.t = max(q.t, FORM + CONVERGE - 0.12) end
        return true
      end
    end
    return false
  end
  function P.cast_group(targets)
    local p
    if familiar then
      local f = idle_fam()
      if f then p = shoot(f, targets[1], false, targets)
      elseif fam_count() < fam_max and clock >= resummon_at then p = spawn(targets[1], 0, false, targets, true) end
    else p = spawn(targets[1], 0, false, targets) end
    return p and { p } or {}
  end
  -- (the familiars, for powers.lua) how many snakes a cast now could be given (an idle one each, or new ones formed);
  -- one idle (its idle_t: how long it has rested, cd: how long it rests between cuts of its own); how many there may be
  -- and whether the lens is all (or nearly all) he has; whether any lens is at work (forming, turning, gathering,
  -- cutting); resting: none, and none to be formed yet
  function P.slots()
    if not familiar then return P.free_lenses() end
    local n = 0
    for _, q in ipairs(active) do if q.fam and q.idle and not q.leaving then n = n + 1 end end
    if clock >= resummon_at then n = n + min(max(0, fam_max - fam_count()), P.free_lenses()) end
    return n
  end
  function P.idle_familiar() return idle_fam() end
  function P.set_familiars(n, strong) fam_max = max(1, n); fam_strong = strong and true or false end
  function P.working() for _, q in ipairs(active) do if not q.idle and not q.leaving then return true end end; return false end
  function P.familiars() return fam_count() end
  function P.get_follow() return follow end
  function P.set_follow(v) local n = #LE.FOLLOWS; follow = ((v % n) + n) % n end
  -- the lens taken from him: its familiars break (one cutting finishes its cut first)
  function P.dismiss() for _, q in ipairs(active) do if q.fam and not q.leaving then q.dismissed = true end end end
  function P.resting() return familiar and fam_count() == 0 and clock < resummon_at end
  function P.busy_count() return #active end
  function P.get_look() return look end
  function P.set_look(v) look = ((v % NLOOKS) + NLOOKS) % NLOOKS end
  function P.free_lenses() local n = 0; for _, q in ipairs(LENSES) do if not q.on then n = n + 1 end end; return n end
  function P.use_claims(is_unclaimed, do_claim) unclaimed = is_unclaimed; claim = do_claim end
  return P
end

return LE
