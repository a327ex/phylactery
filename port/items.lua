--[[
  items.lua -- the port to Anchor: web/src/items.js. The six powers as objects: each power the
  player removes drops from the lich's nearer hand onto clear floor beside him (round 31), growing
  to its size as it flies, a rigid body (body.lua) until it lies still; the orbs are a handful of
  balls. The objects are the three.js build's (assets/port/items.lua: the cave's instances, the
  inspect view's, the hand's two materials, the environments; the bodies' contact points and boxes
  per floor size, as make_body computes them).
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local U = require('port.util')
local LD = require('port.three.loader')
local OB = require('port.objects')
local BO = require('port.body')
local CAVE = require('port.cave')
local Vector2, Vector3, Quaternion, Euler, Matrix4 = TM.Vector2, TM.Vector3, TM.Quaternion, TM.Euler, TM.Matrix4
local smoothstep = U.smoothstep
local sqrt, abs, sin, cos, atan2, floor, min, max, pi = math.sqrt, math.abs, math.sin, math.cos, math.atan, math.floor, math.min, math.max, math.pi

local IT = {}
IT.SIZES = { { name = 'X3 (LENS X1.8)', k = 3 }, { name = 'X4 (LENS X1.8)', k = 4 }, { name = 'X1.8 (ROUND 30)', k = 1.8 } }
IT.HAND_MATS = { 'BRONZE', 'BONE' }
local SIZES = IT.SIZES

local assets
local function A() assets = assets or LD.group('items'); return assets end
IT.assets = A
-- the objects in powers.ALL's order (keys 5-0): FIRE, LIFT, ROCK, LEAKAGE, PRISMATIC BEAM, LENS
IT.ITEMS = {}
do
  local X = A().manifest.items
  for i, it in ipairs(X.items) do
    IT.ITEMS[i] = { power = it.power, name = it.name, mass = it.mass, rest = it.rest, fric = it.fric, view = it.view, face_up = it.face_up,
      floor_mul = it.floor_mul, balls = it.balls, rolling = it.rolling, fixed_k = it.fixed_k, build = true }
  end
end
IT.X = function() return A().manifest.items end
-- round 53 (owner, 2026-10-07: "The orbs should all be of similar size, closer to the smaller ones now"):
-- the five orbs' radii in the model (were 0.05, 0.036, 0.042, 0.028, 0.032), for the world and the viewer
IT.ORB_SIZES = { 0.031, 0.029, 0.032, 0.028, 0.030 }
-- round 48 (owner, 2026-10-05): their titles
do
  local TITLES = { 'BURNED MASK', 'THE HAND', 'LODESTONE', 'PSYONIAN ORBS', 'PRISMATIC GEM', 'ATTACK LENS' }
  for i, t in ipairs(TITLES) do IT.ITEMS[i].name = t end
end

-- the hand's geometry wears one of its two materials (item_hand.js set_hand_material: the
-- geometry is shared, so the cave's hand and the inspect view's change together)
local hand_variants
function IT.set_hand_material(i)
  local AA = A()
  local X = AA.manifest.items
  local g = AA.geometry(X.hand.geo)
  if not hand_variants then
    hand_variants = {}
    for _, k in ipairs(X.hand.variants) do hand_variants[k + 1] = { color = AA.attribute(X.hand.geo, 'color_' .. k, 3), aMR = AA.attribute(X.hand.geo, 'aMR_' .. k, 2) } end
  end
  local v = hand_variants[i + 1]
  if g.attributes.color ~= v.color then
    g.attributes.color = v.color; g.attributes.aMR = v.aMR
    v.color.needs_update = true; v.aMR.needs_update = true
    g.gpu_dirty = true
  end
end

-- the traced stones' per-draw uniforms (item_gem.js / item_orbs.js onBeforeRender): the eye in the
-- object's frame, the object's rotation, the sun
function IT.trace_hook(mesh, mat, sun, scale_from_world)
  local inv, cam, sc = Matrix4.new(), Vector3.new(), Vector3.new()
  mesh.on_before_render = function(self, renderer, camera)
    local UU = mat.user_data.U
    if scale_from_world then self:update_matrix_world() end
    inv:copy(self.matrix_world):invert()
    UU.uCamO.value:copy(cam:set_from_matrix_position(camera.matrix_world):apply_matrix4(inv))
    local k = sc:set_from_matrix_scale(self.matrix_world).x
    UU.uToWorld.value:set_from_matrix4(self.matrix_world):multiply_scalar(1/k)
    if sun then UU.uSunDir.value:copy(sun.dir); UU.uSunCol.value:copy(sun.col) end
    -- (round 45: the orbs' markings: which ball this is, and the finish)
    if UU.uMark then UU.uMark.value = self.user_data.mark or 0; UU.uMarkStyle.value = require('port.orbmarks').style end
  end
end

function IT.create(ctx)
  local R, cave, fx, warp, nav, lich, mover, get_L, glance = ctx.R, ctx.cave, ctx.fx, ctx.warp, ctx.nav, ctx.lich, ctx.mover, ctx.get_L, ctx.glance
  local AA = A()
  local X = AA.manifest.items
  local rng = U.run_rng(71)
  local opts = { size = 0, hand_mat = 1 }                     -- round 31 (owner): the hand in BONE
  local function kf(w) return w.it.fixed_k or SIZES[opts.size + 1].k*(w.it.floor_mul or 1) end
  local S = CAVE.LAYOUT.sun_dir
  local sxz = Vector2.new(S.x/S.y, S.z/S.y)
  local sun = { dir = S:clone(), col = Vector3.new(1, 0.9, 0.72):multiply_scalar(22) }
  local egg = { x = CAVE.LAYOUT.egg.x, z = CAVE.LAYOUT.egg.z, r = 0.42, top = cave.ground_y(0, 0) + 0.8 }
  local function floor_y(x, z) return cave.ground_y(x, z) end
  local function in_sun(p) return 1 - smoothstep(1.55, 2.05, js_hypot(p.x - sxz.x*p.y, p.z - sxz.y*p.y)) end
  local function dust(p, v)
    local gy = floor_y(p.x, p.z)
    local n = min(7, floor(v*3 + 0.5))
    local k = 0.06 + 0.5*in_sun(p)
    for _ = 1, n do
      local a = rng.float(0, 6.28)
      local vx = cos(a)*rng.float(0.2, 0.6)*v*0.35
      local vy = rng.float(0.08, 0.3)
      local vz = sin(a)*rng.float(0.2, 0.6)*v*0.35
      fx.puff({ x = p.x + cos(a)*0.08, y = gy + 0.03, z = p.z + sin(a)*0.08, vx = vx, vy = vy, vz = vz, drag = 2.4, life = rng.float(0.5, 0.9), s0 = 0.05, s1 = 0.14,
        r = 0.9*k, g = 0.72*k, b = 0.5*k, a = 0.2 })
    end
  end

  -- the cave's instances (as made at the start: lit by the cave's bounce light, its shadow flags)
  local function make_world(i)
    local B = OB.builder(AA, X.mats, { gi = cave.GU })
    local g = B.node(X.world[i].node)
    g:traverse(function(o) if o.is_mesh then o.cast_shadow = not o.user_data.no_shadow; o.receive_shadow = true end end)
    -- the traced stones (the gem: one mesh; the orbs: each sphere)
    if i == 5 then local m = g.children[1]; IT.trace_hook(m, m.material, sun, false) end
    if i == 4 then for k, ix in ipairs(X.world[i].orbs) do local m = g.children[ix + 1]; m.user_data.mark = k - 1; IT.trace_hook(m, m.material, sun, true) end end
    return g
  end
  local W = {}
  for i, it in ipairs(IT.ITEMS) do
    if i == 2 then IT.set_hand_material(opts.hand_mat) end
    local w = { it = it, i = i - 1, g = make_world(i), body = nil, state = 'away', t = 0, scale = 1, r0 = X.world[i].r0 }
    w.make = function() return make_world(i) end
    if it.balls then
      w.orbs = {}
      for k, ix in ipairs(X.world[i].orbs) do
        local m = w.g.children[ix + 1]
        m.user_data.r = m.user_data.r or m.scale.x
        if ctx.varied and IT.ORB_SIZES[k] then m.user_data.r = IT.ORB_SIZES[k]; m.scale:set_scalar(m.user_data.r) end
        w.orbs[#w.orbs + 1] = m
      end
    end
    w.g.visible = false
    R.world_scene:add(w.g)
    W[i] = w
  end

  local function make_body(w)
    local c = X.contact[w.i + 1][opts.size + 1]
    local pts = {}
    for k, q in ipairs(c.pts) do pts[k] = Vector3.new(q[1], q[2], q[3]) end
    local sz = c.sz
    local b = BO.create({ points = pts, mass = w.it.mass, inertia = BO.box_inertia(w.it.mass, sz[1], sz[2], sz[3]), restitution = w.it.rest, friction = w.it.fric,
      rolling = w.it.rolling or 0.8, floor = floor_y, egg = egg })
    b.on_hit = function(v) dust(b.x, v) end
    return b
  end

  local function lying_r(w) return kf(w)*w.r0*0.9 end
  local side = 1
  local function spot(w, r)
    local L, yaw = get_L(), mover.yaw()
    local fwd = Vector2.new(sin(yaw), cos(yaw))
    side = -side
    local base = atan2(fwd.y, fwd.x) + side*(pi*0.42)
    local best, bs = nil, math.huge
    for da = 0, 170, 10 do
      local sgs = da ~= 0 and { 1, -1 } or { 1 }
      for _, sg in ipairs(sgs) do
        local d = 0.55 + r
        while d <= 1.9 + r do
          local a = base + sg*side*da*pi/180
          local x, z = L.x + cos(a)*d, L.z + sin(a)*d
          local bad = 0
          local dz = -r
          while dz <= r do
            local dx = -r
            while dx <= r do
              if not (dx*dx + dz*dz > r*r) then
                local px, pz = x + dx, z + dz
                if nav.is_blocked(px, pz) or nav.rock_top(px, pz) > floor_y(px, pz) + 0.02 then bad = bad + 1 end
              end
              dx = dx + 0.1
            end
            dz = dz + 0.1
          end
          if js_hypot(x - egg.x, z - egg.z) < egg.r + r + 0.1 then bad = bad + 50 end
          for _, o in ipairs(W) do
            if o ~= w and (o.state == 'lying' or o.state == 'falling' or o.state == 'forming') then
              local ox, oz
              if o.bodies and o.land then ox, oz = o.land.x, o.land.y
              elseif o.bodies then
                -- (round 51: orbs let go from where they hovered have no landing spot: where they are now)
                ox, oz = 0, 0
                for _, b in ipairs(o.bodies) do ox = ox + b.x.x; oz = oz + b.x.z end
                ox, oz = ox/#o.bodies, oz/#o.bodies
              else ox, oz = o.g.position.x, o.g.position.z end
              if js_hypot(x - ox, z - oz) < r + lying_r(o) + 0.08 then bad = bad + 50 end
            end
          end
          local score = bad*10 + da*0.01 + abs(d - ((w.it.balls and 0.7 or 0.95) + r))*0.8
          if score < bs then bs = score; best = Vector2.new(x, z) end
          d = d + 0.15
        end
      end
    end
    return best
  end
  local tmp = Vector3.new()
  local function from_hand(to)
    local a, b = lich.fingertip(0, Vector3.new()), lich.fingertip(1, Vector3.new())
    local k = a:distance_to_squared(tmp:set(to.x, a.y, to.y)) < b:distance_to_squared(tmp:set(to.x, b.y, to.y)) and 0 or 1
    return { k = k, p = k == 0 and a or b }
  end
  local function toss(p, x, y, z, t) return Vector3.new((x - p.x)/t, (y - p.y + 0.5*9.81*t*t)/t, (z - p.z)/t) end

  local function drop_balls(w, to, from)
    local k = kf(w)
    w.land = to:clone()
    w.bodies = {}
    for j0, m in ipairs(w.orbs) do
      local j = j0 - 1
      local r = m.user_data.r*k
      local b = BO.create({ sphere = r, mass = w.it.mass, inertia = Vector3.new(1, 1, 1):multiply_scalar(0.4*w.it.mass*r*r), restitution = 0.22, friction = w.it.fric,
        rolling = 2.5, rr = 0.26, floor = floor_y, egg = egg })
      local a, spread = j*2.4, 0.06*k
      local ox = rng.spread(0.05)
      local oz = rng.spread(0.05)
      b.x:copy(from):add(Vector3.new(ox, j*0.03, oz))
      local tx, tz = to.x + cos(a)*spread, to.y + sin(a)*spread
      b.v:copy(toss(b.x, tx, floor_y(tx, tz) + r, tz, 0.72 + j*0.04))
      b.on_hit = function(v) if v > 1.2 then dust(b.x, v*0.5) end end
      w.bodies[j0] = b
    end
    w.body = w.bodies[1]
  end
  -- round 51 (owner, 2026-10-06: "The orbs should be visible around the player, hovering around him in
  -- unpredictable patterns, thrown away by just having some force applied to them in the direction"):
  -- (ctx.varied) while the leakage is his its orbs hover round him, each wandering on its own: an
  -- angle that drifts, slows, stops and turns back, a breathing radius and height, now and then a
  -- swerve; a soft spring, so they trail him when he moves; off him, the egg, the floor and each
  -- other. THROW pushes each the way he faces (a little spread) and they fly, fall and roll as
  -- bodies; taken back, they rise to him again.
  local varied = ctx.varied or false
  local orng = U.run_rng(733)
  local HOV_R, HOV_Y = 0.62, 0.1
  -- round 52 (owner, 2026-10-06: "the orbs could rotate around the lich more, like electrons around atoms,
  -- except with a bit more varied patterns"): each circles his chest on an orbit of its own, a tilted
  -- ellipse (its plane 30-70 degrees off level), once every 1.6-2.6 s, the plane turning slowly about the
  -- upright; now and then one changes: a new tilt, the other way round, faster or slower, wider or
  -- tighter (eased, never a jump). A firm spring keeps the circling crisp; they still keep off him,
  -- the egg, the floor and each other.
  local ORB_C = 0.28
  local YAX = Vector3.new(0, 1, 0)
  local QO = Quaternion.new()
  local function ORB_PLANE()
    local tilt, az = orng.float(0.52, 1.22), orng.float(0, 6.28)     -- (30-70 degrees: the orbits cross)
    return Vector3.new(sin(tilt)*cos(az), cos(tilt), sin(tilt)*sin(az))
  end
  local NP = Vector3.new()
  local TG, A3, DV, QS = Vector3.new(), Vector3.new(), Vector3.new(), Quaternion.new()
  local function ball_body(w, j, r)
    local b = BO.create({ sphere = r, mass = w.it.mass, inertia = Vector3.new(1, 1, 1):multiply_scalar(0.4*w.it.mass*r*r), restitution = 0.22, friction = w.it.fric,
      rolling = 2.5, rr = 0.26, floor = floor_y, egg = egg })
    b.on_hit = function(v) if v > 1.2 then dust(b.x, v*0.5) end end
    return b
  end
  local function hold_orbs(w)
    local L = get_L()
    w.hov = w.hov or {}
    local n = #w.orbs
    for j, m in ipairs(w.orbs) do
      local h = w.hov[j] or {}
      local b = w.bodies and w.bodies[j]
      if b then h.p = b.x:clone(); h.v = Vector3.new(orng.spread(0.4), orng.float(1.4, 2.2), orng.spread(0.4))
      else
        local a = (j - 1)*6.2832/n + orng.spread(0.4)
        h.p = Vector3.new(L.x + sin(a)*HOV_R, L.y + HOV_Y + orng.spread(0.2), L.z + cos(a)*HOV_R); h.v = Vector3.new()
      end
      -- (round 52: an orbit of its own: its plane's normal, its turn, its size, how round it is)
      h.n = ORB_PLANE(); h.n_to = h.n:clone()
      h.phi = orng.float(0, 6.28)
      h.om = orng.sign()*orng.float(2.4, 4.0); h.om_to = h.om
      h.r = orng.float(0.85, 1.15); h.r_to = h.r          -- (round 53: wider; were 0.5-0.72)
      h.b = orng.float(0.65, 1.0)
      h.prec, h.pw = orng.float(0, 6.28), orng.spread(0.5)
      h.ev = orng.float(2.0, 6.0)
      h.q = h.q or Quaternion.new()
      h.ax = Vector3.new(orng.spread(1), orng.spread(1), orng.spread(1)):normalize()
      h.spin = orng.float(0.5, 1.4)
      w.hov[j] = h
    end
    w.bodies = nil; w.body = nil
    w.state = 'held'; w.t = 0; w.g.visible = true
    w.g.position:set(0, 0, 0); w.g.quaternion:identity(); w.g.scale:set_scalar(1)
    w.thrown = false; w.armed = false; w.lie_n = 0
  end
  local function update_held(w, dt, t)
    local L = get_L()
    local k = kf(w)
    w.scale = min(1, (w.scale or 0) + dt/0.4)
    local O, Hh = w.orbs, w.hov
    for j, m in ipairs(O) do
      local h = Hh[j]
      local rb = m.user_data.r*k
      -- its orbit now (each change eased in)
      h.ev = h.ev - dt
      if h.ev <= 0 then
        h.ev = orng.float(3.0, 8.0)
        local e = orng.next()
        if e < 0.4 then h.n_to = ORB_PLANE()
        elseif e < 0.62 then h.om_to = -h.om_to
        elseif e < 0.82 then h.om_to = (h.om_to < 0 and -1 or 1)*orng.float(2.2, 4.2)
        else h.r_to = orng.float(0.8, 1.2); h.b = orng.float(0.6, 1.0) end
      end
      h.om = h.om + (h.om_to - h.om)*min(1, dt*1.4)
      h.r = h.r + (h.r_to - h.r)*min(1, dt*0.9)
      h.n:lerp(h.n_to, min(1, dt*0.8)):normalize()
      h.prec = h.prec + h.pw*dt
      h.phi = h.phi + h.om*dt
      local cp, sp = cos(h.prec), sin(h.prec)
      NP:set(h.n.x*cp - h.n.z*sp, h.n.y, h.n.x*sp + h.n.z*cp):normalize()
      QO:set_from_unit_vectors(YAX, NP)
      TG:set(cos(h.phi)*h.r, 0, sin(h.phi)*h.r*h.b):apply_quaternion(QO)
      TG.x = TG.x + L.x; TG.y = TG.y + L.y + ORB_C; TG.z = TG.z + L.z
      local wn = 6.2832*2.4
      A3:sub_vectors(TG, h.p):multiply_scalar(wn*wn):add_scaled_vector(h.v, -2*0.8*wn)
      for q = 1, #O do
        if q ~= j then
          local o = Hh[q]
          local dx, dy, dz = h.p.x - o.p.x, h.p.y - o.p.y, h.p.z - o.p.z
          local d = sqrt(dx*dx + dy*dy + dz*dz)
          local mn = (rb + O[q].user_data.r*k)*1.9
          if d < mn and d > 1e-4 then local f = (mn - d)/mn*320; A3.x = A3.x + dx/d*f; A3.y = A3.y + dy/d*f; A3.z = A3.z + dz/d*f end
        end
      end
      h.v:add_scaled_vector(A3, dt)
      h.p:add_scaled_vector(h.v, dt)
      -- never inside him (a column round him), the egg or the floor
      local dx, dz = h.p.x - L.x, h.p.z - L.z
      local dh = js_hypot(dx, dz)
      local inner = 0.34 + rb
      if dh < inner and h.p.y < L.y + 0.75 and h.p.y > L.y - 1.35 then
        if dh < 1e-4 then dx, dz, dh = 1, 0, 1 end
        h.p.x = L.x + dx/dh*inner; h.p.z = L.z + dz/dh*inner
        local vr = (h.v.x*dx + h.v.z*dz)/dh
        if vr < 0 then h.v.x = h.v.x - dx/dh*vr; h.v.z = h.v.z - dz/dh*vr end
      end
      local ey = egg.top - 0.4
      local ex, eyy, ez = h.p.x - egg.x, h.p.y - ey, h.p.z - egg.z
      local de = sqrt(ex*ex + eyy*eyy + ez*ez)
      local er = egg.r + rb + 0.04
      if de < er and de > 1e-4 then
        h.p.x = egg.x + ex/de*er; h.p.y = ey + eyy/de*er; h.p.z = egg.z + ez/de*er
        local vn = (h.v.x*ex + h.v.y*eyy + h.v.z*ez)/de
        if vn < 0 then h.v.x = h.v.x - ex/de*vn; h.v.y = h.v.y - eyy/de*vn; h.v.z = h.v.z - ez/de*vn end
      end
      local fy = floor_y(h.p.x, h.p.z) + rb + 0.05
      if h.p.y < fy then h.p.y = fy; if h.v.y < 0 then h.v.y = 0 end end
      QS:set_from_axis_angle(h.ax, h.spin*dt); h.q:premultiply(QS)
      m.position:copy(h.p); m.quaternion:copy(h.q)
      m.scale:set_scalar(max(1e-4, rb*w.scale))
      m.material.user_data.U.uLit.value = in_sun(h.p)
    end
  end
  -- from where they hover, as bodies: each pushed the way he faces (THROW), or tossed down beside him (a drop)
  local function release_orbs(w, push_yaw, to)
    local k = kf(w)
    w.bodies = {}
    for j, m in ipairs(w.orbs) do
      local h = w.hov[j]
      local r = m.user_data.r*k
      local b = ball_body(w, j, r)
      b.x:copy(h.p)
      if push_yaw then
        local a = push_yaw + orng.spread(0.3)
        local sp = orng.float(3.4, 5.4)
        b.v:set(sin(a)*sp + h.v.x*0.3, orng.float(0.9, 2.0), cos(a)*sp + h.v.z*0.3)
        b.w:set(orng.spread(8), orng.spread(8), orng.spread(8))
        for _ = 1, 3 do
          warp.puff({ x = h.p.x, y = h.p.y, z = h.p.z, vx = sin(a)*orng.float(0.5, 1.4), vy = orng.spread(0.3), vz = cos(a)*orng.float(0.5, 1.4),
            drag = 2.5, life = orng.float(0.3, 0.5), s0 = 0.08, s1 = 0.3, amp = 3.2, spin = orng.spread(4) })
        end
      else
        local a, spread = (j - 1)*2.4, 0.06*k
        local tx, tz = to.x + cos(a)*spread, to.y + sin(a)*spread
        b.v:copy(toss(b.x, tx, floor_y(tx, tz) + r, tz, 0.55 + (j - 1)*0.04))
      end
      w.bodies[j] = b
    end
    w.body = w.bodies[1]
    w.state = 'falling'; w.t = 0; w.scale = 1
  end
  local function collide_balls(w)
    local Bs, O = w.bodies, w.orbs
    local k = kf(w)
    for i = 1, #Bs do for j = i + 1, #Bs do
      local a, b = Bs[i], Bs[j]
      local d = a.x:distance_to(b.x)
      local mn = (O[i].user_data.r + O[j].user_data.r)*k
      if not (d >= mn or d < 1e-6) then
        local n = Vector3.new():sub_vectors(b.x, a.x):multiply_scalar(1/d)
        a.x:add_scaled_vector(n, -(mn - d)*0.5); b.x:add_scaled_vector(n, (mn - d)*0.5)
        local vn = Vector3.new():sub_vectors(b.v, a.v):dot(n)
        if vn < 0 then local j2 = -(1 + 0.4)*vn*0.5; a.v:add_scaled_vector(n, -j2); b.v:add_scaled_vector(n, j2); a.wake(); b.wake() end
      end
    end end
  end

  local function drop(i)
    local w = W[i + 1]
    if not w then return false end
    local r = lying_r(w)
    local to = spot(w, r)
    local h = from_hand(to)
    local from = h.p:clone():add(Vector3.new(to.x - h.p.x, 0, to.y - h.p.z):normalize():multiply_scalar(0.12))
    lich.kick(h.k, 0.45)
    if glance then glance(Vector3.new(to.x, floor_y(to.x, to.y), to.y)) end
    for _ = 1, 5 do
      local x = from.x + rng.spread(0.06)
      local y = from.y + rng.spread(0.06)
      local z = from.z + rng.spread(0.06)
      local vx = rng.spread(0.3)
      local vy = rng.spread(0.2)
      local vz = rng.spread(0.3)
      warp.puff({ x = x, y = y, z = z, vx = vx, vy = vy, vz = vz, drag = 2.5, life = rng.float(0.3, 0.45), s0 = 0.1, s1 = 0.3, amp = 3.2, spin = rng.spread(4) })
    end
    if w.it.balls and w.state == 'held' then release_orbs(w, nil, to); return true end
    if w.it.balls then
      drop_balls(w, to, from)
      w.state = 'forming'; w.t = 0; w.g.visible = true
      w.g.position:set(0, 0, 0); w.g.quaternion:identity(); w.g.scale:set_scalar(1)
      return true
    end
    w.body = make_body(w)
    w.land = to:clone()
    w.body.x:copy(from)
    local Tt = 0.5 + 0.12*js_hypot(to.x - from.x, to.y - from.z)
    w.body.v:copy(toss(from, to.x, floor_y(to.x, to.y) + r*0.7, to.y, Tt))
    if w.it.face_up then
      local ex = -pi/2 + rng.spread(0.35)
      local ey = rng.float(0, 6.28)
      local ez = rng.spread(0.35)
      w.body.q:set_from_euler(Euler.new(ex, ey, ez, 'YXZ'))
      local wx = rng.spread(1)
      local wy = rng.spread(1.5)
      local wz = rng.spread(1)
      w.body.w:set(wx, wy, wz)
    else
      local ex = rng.spread(1.2)
      local ey = rng.float(0, 6.28)
      local ez = rng.spread(1.2)
      w.body.q:set_from_euler(Euler.new(ex, ey, ez))
      local wx = rng.spread(3)
      local wy = rng.spread(2)
      local wz = rng.spread(3)
      w.body.w:set(wx, wy, wz)
    end
    w.state = 'forming'; w.t = 0
    w.g.visible = true
    return true
  end
  -- round 48: THROW: from his nearer hand, the way he faces, as far as the floor stays clear (up to
  -- 6.5 m; never onto the egg), on a high arc; it lands and rolls as a dropped one does. A thrown one
  -- is his again when he walks back to it (near()), once he has been away from it.
  local function throw(i, yaw)
    local w = W[i + 1]
    if not w then return false end
    if w.it.balls and w.state == 'held' then
      local L = get_L()
      local h = from_hand(Vector2.new(L.x + sin(yaw), L.z + cos(yaw)))
      lich.kick(h.k, 0.9)
      release_orbs(w, yaw)
      w.thrown = true; w.armed = false; w.lie_n = 0
      return true
    end
    local r = lying_r(w)
    local L = get_L()
    local fx_, fz_ = sin(yaw), cos(yaw)
    local d, tx, tz = 6.5, L.x, L.z
    while d > 1.2 do
      tx, tz = L.x + fx_*d, L.z + fz_*d
      if not nav.is_blocked(tx, tz) and js_hypot(tx - egg.x, tz - egg.z) > egg.r + r + 0.35 then break end
      d = d - 0.25
    end
    local to = Vector2.new(tx, tz)
    local h = from_hand(to)
    local from = h.p:clone():add(Vector3.new(to.x - h.p.x, 0, to.y - h.p.z):normalize():multiply_scalar(0.12))
    lich.kick(h.k, 1.1)
    if glance then glance(Vector3.new(to.x, floor_y(to.x, to.y), to.y)) end
    for _ = 1, 7 do
      warp.puff({ x = from.x + rng.spread(0.06), y = from.y + rng.spread(0.06), z = from.z + rng.spread(0.06), vx = fx_*rng.float(0.4, 1.2), vy = rng.spread(0.3), vz = fz_*rng.float(0.4, 1.2),
        drag = 2.5, life = rng.float(0.3, 0.5), s0 = 0.1, s1 = 0.35, amp = 3.2, spin = rng.spread(4) })
    end
    local Tt = 0.7 + 0.07*d
    if w.it.balls then
      drop_balls(w, to, from)
      -- (the balls on the same arc: a longer flight)
      for j, b in ipairs(w.bodies) do
        local a, spread = (j - 1)*2.4, 0.12*kf(w)
        local bx, bz = to.x + cos(a)*spread, to.y + sin(a)*spread
        local rb = w.orbs[j].user_data.r*kf(w)
        b.v:copy(toss(b.x, bx, floor_y(bx, bz) + rb, bz, Tt + (j - 1)*0.04))
      end
      w.g.position:set(0, 0, 0); w.g.quaternion:identity(); w.g.scale:set_scalar(1)
    else
      w.body = make_body(w)
      w.land = to:clone()
      w.body.x:copy(from)
      w.body.v:copy(toss(from, to.x, floor_y(to.x, to.y) + r*0.7, to.y, Tt))
      local ex = rng.spread(1.2)
      local ey = rng.float(0, 6.28)
      local ez = rng.spread(1.2)
      w.body.q:set_from_euler(Euler.new(ex, ey, ez))
      w.body.w:set(rng.spread(5), rng.spread(4), rng.spread(5))
    end
    w.state = 'forming'; w.t = 0
    w.g.visible = true
    w.thrown = true; w.armed = false; w.lie_n = 0
    return true
  end
  -- the thrown one he has come back to (lying, him within ~1 m), if any; it can be taken back once it
  -- has been 1.8 m from him at some moment since the throw, or has lain still 2.5 s (so a throw against
  -- a wall at his feet does not come straight back)
  local function near(L)
    for _, w in ipairs(W) do
      if w.thrown and w.state ~= 'away' then
        local px, pz
        if w.bodies then
          px, pz = 0, 0
          for _, b in ipairs(w.bodies) do px = px + b.x.x; pz = pz + b.x.z end
          px, pz = px/#w.bodies, pz/#w.bodies
        else px, pz = w.g.position.x, w.g.position.z end
        local dd = js_hypot(L.x - px, L.z - pz)
        if dd > 1.8 then w.armed = true end
        if w.state == 'lying' then
          w.lie_n = (w.lie_n or 0) + 1
          if w.lie_n > 150 then w.armed = true end
          if w.armed and dd < 1.05 + lying_r(w)*0.5 then w.thrown = false; w.armed = false; w.lie_n = 0; return w.i end
        end
      end
    end
    return nil
  end
  local function take(i)
    local w = W[i + 1]
    if not w or w.state == 'away' then return end
    if varied and w.it.balls then
      for _, b in ipairs(w.bodies or {}) do
        warp.puff({ x = b.x.x, y = b.x.y + 0.05, z = b.x.z, vy = 0.6, drag = 1.5, life = 0.5, s0 = 0.12, s1 = 0.35, amp = 3, spin = orng.spread(3) })
      end
      hold_orbs(w)
      return
    end
    w.thrown = false
    w.state = 'leaving'; w.t = 0
    if w.body then w.body.asleep = true end
    if w.bodies then for _, b in ipairs(w.bodies) do b.asleep = true end end
    for _ = 1, 5 do
      local x = w.g.position.x + rng.spread(0.12)
      local z = w.g.position.z + rng.spread(0.12)
      warp.puff({ x = x, y = w.g.position.y + 0.1, z = z, vy = 0.6, drag = 1.5, life = 0.5, s0 = 0.15, s1 = 0.4, amp = 3, spin = rng.spread(3) })
    end
  end

  local function update_balls(w, dt, t)
    if w.state == 'held' then update_held(w, dt, t); return end
    local O = w.orbs
    local k = kf(w)
    if varied and w.state == 'falling' then
      -- (thrown ones stay out of the rocks and in the room camera's frame: nav's walls)
      for j, b in ipairs(w.bodies) do nav.resolve(b.x, b.v, O[j].user_data.r*k) end
    end
    if w.state == 'forming' then
      w.scale = smoothstep(0, 0.3, w.t)
      for _, b in ipairs(w.bodies) do b.step(dt) end
      collide_balls(w)
      if w.t > 0.3 then w.state = 'falling' end
    elseif w.state == 'falling' then
      for _, b in ipairs(w.bodies) do b.step(dt) end
      collide_balls(w)
      local all = true
      for _, b in ipairs(w.bodies) do if not b.asleep then all = false; break end end
      if all then w.state = 'lying' end
    elseif w.state == 'leaving' then
      for _, b in ipairs(w.bodies) do b.x.y = b.x.y + dt*0.9*smoothstep(0, 0.3, w.t) end
      w.scale = 1 - smoothstep(0.1, 0.45, w.t)
      if w.t > 0.45 then w.state = 'away'; w.g.visible = false end
    end
    for j, m in ipairs(O) do
      local b = w.bodies[j]
      m.position:copy(b.x); m.quaternion:copy(b.q)
      m.scale:set_scalar(max(1e-4, m.user_data.r*k*w.scale))
      m.material.user_data.U.uLit.value = in_sun(b.x)
    end
  end

  local function update(t, dt)
    for _, w in ipairs(W) do
      if w.state ~= 'away' then
        w.t = w.t + dt
        if w.it.balls then update_balls(w, dt, t)
        else
          local skip = false
          if w.state == 'forming' then
            w.scale = 0.08 + 0.92*smoothstep(0, 0.3, w.t)
            w.body.step(dt)
            if w.t > 0.3 then w.state = 'falling' end
          elseif w.state == 'falling' then
            w.body.step(dt)
            if w.body.asleep then w.state = 'lying' end
          elseif w.state == 'leaving' then
            w.g.position.y = w.g.position.y + dt*0.9*smoothstep(0, 0.3, w.t)
            w.scale = 1 - smoothstep(0.1, 0.45, w.t)
            w.g.scale:set_scalar(max(1e-3, w.scale)*kf(w))
            if w.t > 0.45 then w.state = 'away'; w.g.visible = false end
            skip = true
          end
          if not skip then
            w.g.position:copy(w.body.x)
            w.g.quaternion:copy(w.body.q)
            w.g.scale:set_scalar(max(1e-3, w.scale)*kf(w))
          end
        end
      end
    end
    local gw = W[5]
    if gw and gw.g.visible then
      local m = gw.g.children[1]
      m.material.user_data.U.uLit.value = in_sun(gw.g.position)
    end
  end

  local function rebuild(i)
    local w = W[i + 1]
    local vis, pos, q = w.g.visible, w.g.position:clone(), w.g.quaternion:clone()
    R.world_scene:remove(w.g)
    w.g = w.make(); w.g.visible = vis; w.g.position:copy(pos); w.g.quaternion:copy(q)
    R.world_scene:add(w.g)
    if w.state ~= 'away' then
      local old = w.body
      w.body = make_body(w); w.body.x:copy(old.x); w.body.q:copy(old.q); w.body.x.y = w.body.x.y + 0.05; w.state = 'falling'
    end
  end
  local function set_hand_mat(c)
    local n = #IT.HAND_MATS
    opts.hand_mat = ((c % n) + n) % n
    IT.set_hand_material(opts.hand_mat)
    rebuild(1)
    return IT.HAND_MATS[opts.hand_mat + 1]
  end
  local function set_size(i)
    local n = #SIZES
    opts.size = ((i % n) + n) % n
    local lying = {}
    for _, w in ipairs(W) do if w.state ~= 'away' then lying[#lying + 1] = w end end
    for _, w in ipairs(lying) do w.state = 'away'; w.g.visible = false end
    for _, w in ipairs(lying) do drop(w.i); for _ = 1, 40 do update(0, 1/60) end end
    return SIZES[opts.size + 1].name
  end
  local function state()
    local out = {}
    for k, w in ipairs(W) do
      if w.bodies then
        local balls = {}
        for j, b in ipairs(w.bodies) do balls[j] = { b.x.x, b.x.y, b.x.z, b.asleep and 1 or 0 } end
        out[k] = { state = w.state, balls = balls }
      else
        out[k] = { state = w.state, x = w.g.position.x, y = w.g.position.y, z = w.g.position.z, asleep = (w.body and w.body.asleep) and true or false }
      end
    end
    return out
  end
  if varied then for _, w in ipairs(W) do if w.it.balls then hold_orbs(w) end end end
  return { W = W, opts = opts, drop = drop, throw = throw, near = near, take = take, update = update, set_hand_mat = set_hand_mat, set_size = set_size, state = state }
end

return IT
