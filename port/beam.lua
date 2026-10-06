--[[
  beam.lua -- the port to Anchor: web/src/beam.js. PRISMATIC BEAM: a channelled beam from his index
  fingertip, one per snake in the fan of where he points, each a curve leaving along his finger
  (fx ribbon style 4 in pieces), burning into its snake, which fills with the light and bursts into
  warped streaks and a little gore; recoil on his arm (lich.kick / lich.press).
  Round 50: B.shot, the revolver (3+ snakes in one bout): one beam at a time, each from where his
  finger was when it fired, faster, with its own hard kick; powers.lua turns him to each in turn.
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local U = require('port.util')
local FX = require('port.fx')
local Vector3 = TM.Vector3
local smoothstep = U.smoothstep
local abs, sin, cos, atan2, exp, floor, min, max = math.abs, math.sin, math.cos, math.atan, math.exp, math.floor, math.min, math.max

local BE = {}
local SHOOT_V, DWELL, END, FILL, SHATTER_AT = 45, 0.16, 0.22, 0.22, 0.36
local W0, W1 = 0.012, 0.065
local PIECES = 10
BE.BEAM_LOOKS = { 'HIS COLOURS, STREAMING', 'HIS COLOURS, HELD', 'FULL RAINBOW, STREAMING' }
local NLOOKS = #BE.BEAM_LOOKS
local function jround(x) return floor(x + 0.5) end

local function opal(h, full, out)
  local s = FX.spectrum(h)
  local c = { s[1]*s[1]*(3 - 2*s[1]), s[2]*s[2]*(3 - 2*s[2]), s[3]*s[3]*(3 - 2*s[3]) }
  local g = full and 0 or 0.16
  for i = 1, 3 do c[i] = c[i]*(1 - g) + 0.5*g end
  local m = max((c[1] + c[2] + c[3])/3, 0.2)
  out[1] = c[1]/m; out[2] = c[2]/m; out[3] = c[3]/m
  return out
end
BE.opal = opal

function BE.create(ctx)
  local R, snakes, fx, rng, lich, warp, gore, get_L = ctx.R, ctx.snakes, ctx.fx, ctx.rng, ctx.lich, ctx.warp, ctx.gore, ctx.get_L
  local N = snakes.RINGS
  local light = T.PointLight.new(0xffffff, 0, 5, 2)
  local hand = T.PointLight.new(0xffffff, 0, 1.8, 2)
  R.world_scene:add(light); R.world_scene:add(hand)
  local look, ch, clock = 1, nil, 0
  local TIP, FD, V, P, C3 = Vector3.new(), Vector3.new(), Vector3.new(), Vector3.new(), { 1, 1, 1 }

  local function hue_at(p, x)
    local field0 = (TIP.x*0.45 + TIP.y*0.9 + TIP.z*0.3)*0.55 - clock*0.04
    if look == 1 then return (p.x*0.45 + p.y*0.9 + p.z*0.3)*0.55 - clock*0.04 end
    return field0 - (x - clock*2.4)*0.3
  end
  local function tint(p, x) return opal(hue_at(p, x), look == 2, C3) end
  local function spark(p, x, o)
    local c = tint(p, x)
    local q = { x = p.x, y = p.y, z = p.z, r = 0.5 + 2.2*c[1], g = 0.5 + 2.2*c[2], b = 0.5 + 2.2*c[3] }
    for k, v in pairs(o) do q[k] = v end
    return fx.mote(q)
  end

  local DIR, AX = Vector3.new(), Vector3.new()
  local function shatter(s)
    local pts = {}
    for i = 2, N - 3, 3 do pts[#pts + 1] = s.spine[i + 1]:clone() end
    for _ = 1, 20 do
      local i = rng.int(2, N - 3)
      local p = s.spine[i + 1]
      AX:sub_vectors(s.spine[max(0, i - 2) + 1], s.spine[min(N - 1, i + 2) + 1]):normalize()
      local dx = rng.spread(1)
      local dy = rng.float(-0.2, 1)
      local dz = rng.spread(1)
      DIR:set(dx, dy, dz):normalize()
      DIR:add_scaled_vector(AX, -DIR:dot(AX)*0.7):normalize()
      local speed = rng.float(6, 12)
      local life = rng.float(0.35, 0.65)
      local len = rng.float(0.5, 1.1)
      local curl = rng.spread(7)
      local jitter = rng.float(1.5, 3.5)
      local w = rng.float(0.1, 0.2)
      local amp = rng.float(7, 10)
      local chroma = rng.float(1.25, 1.6)
      warp.fling({ p = p, dir = DIR, speed = speed, life = life, len = len, curl = curl, jitter = jitter, w = w, amp = amp, chroma = chroma })
    end
    for _ = 1, 14 do
      local p = pts[rng.int(0, #pts - 1) + 1]
      local vx = rng.spread(1.6)
      local vy = rng.float(0.2, 1.4)
      local vz = rng.spread(1.6)
      local life = rng.float(0.45, 0.85)
      local s1 = rng.float(0.7, 1.1)
      local amp = rng.float(5, 6.5)
      local spin = rng.spread(6)
      warp.puff({ x = p.x, y = p.y + 0.05, z = p.z, vx = vx, vy = vy, vz = vz, drag = 2.5, rise = 0.2, life = life, s0 = 0.2, s1 = s1, amp = amp, spin = spin })
    end
    gore.spatter(pts)
  end
  local function pierce_fx(s, hit)
    local f
    f = {
      t = 0, sag = 0, hide = false,
      glow = function(i)
        local reach = smoothstep(0, FILL, f.t)*N
        local d = abs(i - hit)
        return d < reach and 1 - 0.4*smoothstep(reach*0.7, reach, d) or 0
      end,
      shift = function(i, out) local k = max(0, 1 - abs(i - hit)/6)*sin(f.t*60)*0.012; out[2] = out[2] + k end,
      tick = function(dt)
        f.t = f.t + dt
        f.sag = smoothstep(0, SHATTER_AT, f.t)*0.6
        if f.t >= SHATTER_AT and not f.hide then shatter(s); f.hide = true end
        if f.t >= SHATTER_AT + 0.05 then return 'done' end
      end,
    }
    return f
  end
  local function hit_ring() return rng.int(jround(N*0.12), jround(N*0.55)) end

  local function bite(p, first)
    fx.mote({ x = p.x, y = p.y, z = p.z, life = 0.08, s0 = 0.16, s1 = 0.06, r = 5, g = 5, b = 5, fin = 0.01 })
    local x = p:distance_to(TIP)
    for _ = 1, 14 do
      local xx = x + rng.spread(0.6)
      local vx = rng.spread(1.8)
      local vy = rng.float(0.8, 2.8)
      local vz = rng.spread(1.8)
      spark(p, xx, { vx = vx, vy = vy, vz = vz, grav = 8, drag = 0.5, life = rng.float(0.3, 0.6), s0 = 0.03, s1 = 0.012, fin = 0.01 })
    end
    if ch then ch.pop = 1; if first then lich.kick(ch.arm, 0.45) end end
  end
  local function at(b) return b.at or b.s.spine[b.ring + 1] end

  local function new_seg(from)
    local rb = {}
    for k = 1, PIECES do rb[k] = fx.ribbon(from, from, { held = true, style = 4, hue = look, w = 1.5, w0 = W1, w1 = W1, c = { 1, 1, 1 }, a = 1 }) end
    return { rb = rb, p0 = from:clone(), p1 = from:clone(), len = 0 }
  end
  local function release(sg) for _, b in ipairs(sg.rb) do fx.release(b) end end
  local Q0, Q1, CT = Vector3.new(), Vector3.new(), Vector3.new()
  local function bez(sg, u, out)
    local a, b, c = (1 - u)*(1 - u), 2*u*(1 - u), u*u
    return out:set(sg.p0.x*a + CT.x*b + sg.p1.x*c, sg.p0.y*a + CT.y*b + sg.p1.y*c, sg.p0.z*a + CT.z*b + sg.p1.z*c)
  end
  local function lay(sg, curved, w0, w1, a, ph0)
    local len = sg.p0:distance_to(sg.p1)
    CT:lerp_vectors(sg.p0, sg.p1, 0.5)
    if curved then CT:copy(sg.p0):add_scaled_vector(FD, min(0.4, 0.15*len)) end
    local x = 0
    bez(sg, 0, Q0)
    for k = 0, PIECES - 1 do
      local b = sg.rb[k + 1]
      local u1 = (k + 1)/PIECES
      bez(sg, u1*u1, Q1)
      b.p0:copy(Q0); b.p1:copy(Q1); b.x0 = x; b.ph0 = ph0
      b.w0 = w0; b.w1 = w1; b.a = a; b.hue = look
      b.pv = k > 0 and sg.rb[k].p0 or nil; b.nx = nil
      if k > 0 then sg.rb[k].nx = b.p1 end
      x = x + Q0:distance_to(Q1); Q0:copy(Q1)
    end
    sg.len = x
  end

  local FAN, FAN_URGENT, STAGGER_B, HOLD_B, FADE_B = 0.87, 1.1, 0.07, 0.16, 0.16
  local function yaw_to(p) local L = get_L(); return atan2(p.x - L.x, p.z - L.z) end
  local function off_yaw(a, b) return abs(atan2(sin(a - b), cos(a - b))) end
  local function beam_of(s, ring, delay) return { s = s, ring = ring, at = nil, head = TIP:clone(), phase = delay > 0 and 'wait' or 'shoot', pt = -delay, seg = nil, k = 1 } end

  local function update(t, dt)
    clock = t
    if not ch then light.intensity = 0; hand.intensity = 0; return end
    ch.t = ch.t + dt
    local live, kmax = 0, 0
    for _, b in ipairs(ch.beams) do
      if b.phase == 'wait' then b.pt = b.pt + dt; if b.pt >= 0 then b.phase = 'shoot'; b.head:copy(TIP); b.seg = new_seg(TIP) end end
      if b.phase == 'shoot' then
        local goal = at(b)
        local d = V:sub_vectors(goal, b.head):length()
        local step = (b.v or SHOOT_V)*dt
        if d <= step then
          b.head:copy(goal); b.at = goal:clone()
          if not b.s.fx or b.s.fx.placeholder then b.s.fx = pierce_fx(b.s, b.ring) end
          bite(goal, not ch.bit and not b.shot); ch.bit = true
          b.phase = 'burn'; b.pt = 0
        else b.head:add_scaled_vector(V, step/d) end
      elseif b.phase == 'burn' then
        b.pt = b.pt + dt
        if b.pt >= HOLD_B then b.phase = 'fade'; b.pt = 0 end
      elseif b.phase == 'fade' then
        b.pt = b.pt + dt
        if b.pt >= FADE_B then b.phase = 'gone'; if b.seg then release(b.seg) end; b.seg = nil end
      end
      b.k = b.phase == 'fade' and 1 - smoothstep(0, FADE_B, b.pt) or (b.phase == 'gone' and 0 or 1)
      if b.phase ~= 'gone' then live = live + 1; kmax = max(kmax, b.k) end
    end
    ch.k_on = smoothstep(0, 0.06, ch.t)
    ch.pop = max(0, ch.pop - dt*6)
    ch.kmax = kmax
    lich.press(ch.arm, ch.k_on*kmax)
    local fl = 0.8 + 0.2*sin(t*47)
    for _, b in ipairs(ch.beams) do
      if (b.phase == 'shoot' or b.phase == 'burn') and b.seg then
        local hx = b.head:distance_to(TIP)
        fx.mote({ x = b.head.x, y = b.head.y, z = b.head.z, life = 0.05, s0 = 0.12*fl, s1 = 0.1, r = 4, g = 4, b = 4, fin = 0.01 })
        local c = tint(b.head, hx)
        fx.mote({ x = b.head.x, y = b.head.y, z = b.head.z, life = 0.05, s0 = 0.26*fl, s1 = 0.22, r = 0.9*c[1], g = 0.9*c[2], b = 0.9*c[3], fin = 0.01 })
        if rng.next() < 0.7 then
          local xx = hx + rng.spread(0.5)
          local vx = rng.spread(2.0)
          local vy = rng.float(0.6, 2.4)
          local vz = rng.spread(2.0)
          spark(b.head, xx, { vx = vx, vy = vy, vz = vz, grav = 7, drag = 0.5, life = rng.float(0.25, 0.55), s0 = 0.028, s1 = 0.01 })
        end
      end
    end
    for _, b in ipairs(ch.beams) do
      local sg = b.seg
      if sg and not (sg.len < 0.3) and not (rng.next() > 0.8) then
        local r = sg.rb[rng.int(0, PIECES - 1) + 1]
        local e = rng.next()
        P:lerp_vectors(r.p0, r.p1, e)
        local xx = r.x0 + e*r.p0:distance_to(r.p1)
        local x = P.x + rng.spread(0.03)
        local z = P.z + rng.spread(0.03)
        local vx = rng.spread(0.6)
        local vy = rng.float(-0.5, 0.4)
        local vz = rng.spread(0.6)
        spark(P, xx, { x = x, z = z, vx = vx, vy = vy, vz = vz, grav = 2, drag = 1.5, life = rng.float(0.2, 0.4), s0 = 0.022, s1 = 0.008, a = b.k })
      end
    end
    local b0
    for _, b in ipairs(ch.beams) do if b.phase == 'shoot' or b.phase == 'burn' then b0 = b; break end end
    b0 = b0 or ch.beams[1]
    local c = tint(b0.head, b0.head:distance_to(TIP))
    light.color:set_rgb(0.55 + 0.45*c[1]/2, 0.55 + 0.45*c[2]/2, 0.55 + 0.45*c[3]/2)
    light.position:copy(b0.head); light.position.y = light.position.y + 0.2
    light.intensity = 1.6*kmax*ch.k_on*fl
    if live == 0 then
      lich.press(ch.arm, 0)
      ch = nil; light.intensity = 0; hand.intensity = 0
    end
  end

  local function after_pose(t)
    if not ch then return end
    lich.fingertip(ch.arm, TIP)
    lich.finger_dir(ch.arm, FD)
    TIP:add_scaled_vector(FD, 0.004)
    local flick = 1 + 0.12*sin(t*57) + 0.07*sin(t*83 + 1)
    local pop = 1 + 0.6*exp(-ch.t*18) + 0.35*ch.pop
    local ph0 = (TIP.x*0.45 + TIP.y*0.9 + TIP.z*0.3)*0.55 - t*0.04
    for _, b in ipairs(ch.beams) do
      local sg = b.seg
      if sg then
        sg.p0:copy(b.from or TIP)
        sg.p1:copy(b.phase == 'shoot' and b.head or at(b))
        local w = W1*ch.k_on*b.k*flick*pop
        lay(sg, not b.from, min(W0, w), w, b.k, ph0)
      end
    end
    local k = ch.kmax
    if k == nil then k = 1 end
    local c = tint(TIP, 0)
    fx.mote({ x = TIP.x, y = TIP.y, z = TIP.z, life = 0.04, s0 = 0.026*k*(0.9 + 0.3*ch.pop), s1 = 0.024, r = 4, g = 4, b = 4, fin = 0.01 })
    fx.mote({ x = TIP.x, y = TIP.y, z = TIP.z, life = 0.04, s0 = 0.038*k, s1 = 0.034, r = 0.35*c[1], g = 0.35*c[2], b = 0.35*c[3], fin = 0.01 })
    hand.position:copy(TIP):add_scaled_vector(FD, 0.15)
    hand.color:set_rgb(0.4 + 0.6*c[1]/2, 0.4 + 0.6*c[2]/2, 0.4 + 0.6*c[3]/2)
    hand.intensity = 0.05*ch.k_on*k*(0.9 + 0.1*flick)
  end

  local function free_unhit()
    for _, b in ipairs(ch.beams) do
      if (b.phase == 'wait' or b.phase == 'shoot') and b.s.fx and b.s.fx.placeholder then b.s.fx = nil end
    end
  end
  local function has_beam(s) for _, b in ipairs(ch.beams) do if b.s == s then return true end end; return false end

  local B = { name = 'BEAM', gesture = true, cooldown = 5.5, update = update, after_pose = after_pose, lights = { light = light, hand = hand } }
  function B.capacity(p) return 1 + jround((p - 1)*1.3) end
  function B.aim_ring() return jround(N*0.3) end
  function B.get_look() return look end
  function B.set_look(m) look = ((m % NLOOKS) + NLOOKS) % NLOOKS end
  function B.cast(targets, from, ring, arm)
    if arm == nil then arm = 1 end
    if ch then
      for _, b in ipairs(ch.beams) do if b.seg then release(b.seg) end end
      free_unhit(); lich.press(ch.arm, 0)
    end
    local a0 = yaw_to(targets[1].spine[20 + 1])
    local fan = {}
    for k, s in ipairs(targets) do
      if k == 1 or off_yaw(yaw_to(s.spine[20 + 1]), a0) < FAN then fan[#fan + 1] = { s = s, o = off_yaw(yaw_to(s.spine[20 + 1]), a0), k = k } end
    end
    table.sort(fan, function(p, q) if p.o ~= q.o then return p.o < q.o end; return p.k < q.k end)
    for k, e in ipairs(fan) do fan[k] = e.s end
    for _, s in ipairs(targets) do
      local inf = false
      for _, q in ipairs(fan) do if q == s then inf = true; break end end
      if not inf then s.claim = nil end
    end
    for _, s in ipairs(fan) do if snakes.free(s) then snakes.take(s, { placeholder = true, tick = function() end }) end end
    lich.fingertip(arm, TIP)
    local beams = {}
    ch = { t = 0, arm = arm, a0 = a0, pop = 0, k_on = 0, bit = false, kmax = 1, beams = beams }
    for k, s in ipairs(fan) do beams[k] = beam_of(s, k == 1 and ring or hit_ring(), (k - 1)*STAGGER_B) end
    ch.beams[1].seg = new_seg(TIP)
    lich.kick(arm, min(1.4, 1 + 0.12*(#fan - 1)))
    lich.finger_dir(arm, FD)
    for _ = 1, 8 do
      local x = rng.spread(1)
      local y = rng.spread(1)
      local z = rng.spread(1)
      V:set(x, y, z); V:add_scaled_vector(FD, -V:dot(FD)):set_length(rng.float(0.6, 1.4)):add_scaled_vector(FD, rng.float(-0.3, 0.4))
      spark(TIP, 0, { vx = V.x, vy = V.y, vz = V.z, grav = 3, drag = 2.5, life = rng.float(0.15, 0.3), s0 = 0.018, s1 = 0.006, fin = 0.01 })
    end
  end
  -- round 50: one revolver shot at s (powers.lua has turned him to it): a beam from where the finger is
  -- now (it stays there as he turns to the next), quicker than the cast's, and its own hard kick
  function B.shot(s, ring, arm)
    if arm == nil then arm = 1 end
    lich.fingertip(arm, TIP)
    lich.finger_dir(arm, FD)
    TIP:add_scaled_vector(FD, 0.004)
    if not ch then ch = { t = 0, arm = arm, a0 = yaw_to(s.spine[20 + 1]), pop = 0, k_on = 0, bit = false, kmax = 1, beams = {}, volley = true } end
    ch.volley = true
    if snakes.free(s) then snakes.take(s, { placeholder = true, tick = function() end }) end
    local b = beam_of(s, ring, 0)
    b.v = SHOOT_V*2.2; b.shot = true; b.from = TIP:clone(); b.seg = new_seg(TIP)
    ch.beams[#ch.beams + 1] = b
    ch.pop = 1
    lich.kick(arm, 1.25)
    for _ = 1, 14 do
      local x = rng.spread(1)
      local y = rng.spread(1)
      local z = rng.spread(1)
      V:set(x, y, z); V:add_scaled_vector(FD, -V:dot(FD)):set_length(rng.float(0.8, 1.8)):add_scaled_vector(FD, rng.float(-0.2, 0.9))
      spark(TIP, 0, { vx = V.x, vy = V.y, vz = V.z, grav = 3, drag = 2.5, life = rng.float(0.15, 0.32), s0 = 0.022, s1 = 0.006, fin = 0.01 })
    end
    fx.mote({ x = TIP.x, y = TIP.y, z = TIP.z, life = 0.07, s0 = 0.2, s1 = 0.05, r = 6, g = 6, b = 6, fin = 0.01 })
  end
  function B.chain() return ch and #ch.beams or 0 end
  function B.extend(more)
    if not ch then return false end
    local took = false
    for _, s in ipairs(more) do
      if not (not snakes.free(s) or has_beam(s) or off_yaw(yaw_to(s.spine[20 + 1]), ch.a0) > FAN_URGENT) then
        snakes.take(s, { placeholder = true, tick = function() end })
        local b = beam_of(s, hit_ring(), 0); b.seg = new_seg(TIP)
        ch.beams[#ch.beams + 1] = b; took = true
      end
    end
    return took
  end
  function B.cut()
    if not ch then return end
    free_unhit()
    for _, b in ipairs(ch.beams) do
      if b.phase ~= 'gone' then
        if b.phase == 'wait' or b.phase == 'shoot' then
          if b.seg then release(b.seg) end
          b.seg = nil; b.phase = 'gone'
        elseif b.phase == 'burn' then b.phase = 'fade'; b.pt = 0 end
      end
    end
  end
  function B.let_go() B.cut() end
  function B.busy() return ch ~= nil end
  function B.aim_point()
    if ch and ch.volley then return at(ch.beams[#ch.beams]) end
    return ch and at(ch.beams[1]) or nil
  end
  return B
end

return BE
