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
  end
end

function IT.create(ctx)
  local R, cave, fx, warp, nav, lich, mover, get_L, glance = ctx.R, ctx.cave, ctx.fx, ctx.warp, ctx.nav, ctx.lich, ctx.mover, ctx.get_L, ctx.glance
  local AA = A()
  local X = AA.manifest.items
  local rng = U.make_rng(71)
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
    if i == 4 then for _, ix in ipairs(X.world[i].orbs) do local m = g.children[ix + 1]; IT.trace_hook(m, m.material, sun, true) end end
    return g
  end
  local W = {}
  for i, it in ipairs(IT.ITEMS) do
    if i == 2 then IT.set_hand_material(opts.hand_mat) end
    local w = { it = it, i = i - 1, g = make_world(i), body = nil, state = 'away', t = 0, scale = 1, r0 = X.world[i].r0 }
    w.make = function() return make_world(i) end
    if it.balls then
      w.orbs = {}
      for _, ix in ipairs(X.world[i].orbs) do local m = w.g.children[ix + 1]; m.user_data.r = m.user_data.r or m.scale.x; w.orbs[#w.orbs + 1] = m end
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
              if o.bodies then ox, oz = o.land.x, o.land.y else ox, oz = o.g.position.x, o.g.position.z end
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
  local function take(i)
    local w = W[i + 1]
    if not w or w.state == 'away' then return end
    w.state = 'leaving'; w.t = 0
    if w.body then w.body.asleep = true end
    if w.bodies then for _, b in ipairs(w.bodies) do b.asleep = true end end
    for _ = 1, 5 do
      local x = w.g.position.x + rng.spread(0.12)
      local z = w.g.position.z + rng.spread(0.12)
      warp.puff({ x = x, y = w.g.position.y + 0.1, z = z, vy = 0.6, drag = 1.5, life = 0.5, s0 = 0.15, s1 = 0.4, amp = 3, spin = rng.spread(3) })
    end
  end

  local function update_balls(w, dt)
    local O = w.orbs
    local k = kf(w)
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
        if w.it.balls then update_balls(w, dt)
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
  return { W = W, opts = opts, drop = drop, take = take, update = update, set_hand_mat = set_hand_mat, set_size = set_size, state = state }
end

return IT
