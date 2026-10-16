--[[
  lich.lua -- the port to Anchor: web/src/lich.js (and gem.js's material, skeleton.js's rig).
  The lich: a realistic human skeleton (the bones exported from the three.js build,
  assets/port/lich.lua), all bones, floating, prismatic gem bone. Every part floats on a spring
  around the lich 07 pose; recoil (the beam), the curl (the lift's pull), the hurt layer (the
  ending). A line-by-line translation: the same springs, the same order, the same constants.
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local MAT = require('port.three.materials')
local LD = require('port.three.loader')
local U = require('port.util')
local AU = require('port.audio')     -- 2026-10-10: the sounds
local SND_P = TM.Vector3.new()
local Vector3, Quaternion, Matrix4 = TM.Vector3, TM.Quaternion, TM.Matrix4
local sin, cos, abs, exp, min, max, asin, acos, atan2, sqrt = math.sin, math.cos, math.abs, math.exp, math.min, math.max, math.asin, math.acos, math.atan, math.sqrt

local L = {}

-- skeleton.js: parent-relative joint offsets, and the fingers
L.RIG = {
  spine = { 0, 0.10, -0.062 }, chest = { 0, 0.18, 0.0 }, neck = { 0, 0.285, 0.004 }, head = { 0, 0.118, 0.014 },
  jaw = { 0, 0.004, 0.008 }, shoulder = { 0.172, 0.248, -0.006 }, elbow = { 0, -0.305, 0 }, wrist = { 0, -0.262, 0.004 },
  hip = { 0.088, 0, 0 }, knee = { -0.03, -0.44, 0.004 }, ankle = { 0, -0.405, -0.004 },
}
L.FINGERS = {
  { z = 0.018, meta = 0.064, ph = { 0.04, 0.024, 0.018 } },
  { z = 0.005, meta = 0.062, ph = { 0.044, 0.027, 0.019 } },
  { z = -0.008, meta = 0.058, ph = { 0.041, 0.026, 0.018 } },
  { z = -0.02, meta = 0.052, ph = { 0.033, 0.019, 0.016 } },
}
-- gem.js
L.GEM_LEVELS = {
  { name = 'SOLID', fire = 4.0, inner = 0.6, irid = 0.32 },
  { name = 'STRONG (ROUND 3)', fire = 6.0, inner = 0.95, irid = 0.9 },
  { name = 'SUBTLE', fire = 1.6, inner = 0.35, irid = 0.35 },
}
L.PATTERNS = { 'FINE (ROUND 7)', 'SOFT', 'PER BONE', 'GLINTS ONLY' }

local function clamp(x, a, b) return x < a and a or (x > b and b or x) end
local function smoothstep01(x) return x <= 0 and 0 or (x >= 1 and 1 or x*x*(3 - 2*x)) end
local function mix(a, b, t) return a + (b - a)*t end
local function wrapi(i, n) return ((i % n) + n) % n end

-- opts.GU = the cave's GI uniforms (gi_dynamic)
function L.create(R, opts)
  opts = opts or {}
  local A = LD.group('lich')
  local X = A.manifest.lich
  local xm = X.material
  -- gem_material({ flat = false, roughness = 0.44, color = 0xecdab2 }) + gi_dynamic
  local mat = MAT.MeshPhysicalMaterial.new({ name = 'lich.gem', metalness = 0, ior = xm.ior, specular_intensity = xm.specular_intensity,
    iridescence = xm.iridescence, iridescence_ior = xm.iridescence_ior, iridescence_thickness_range = { xm.iridescence_thickness_range[1], xm.iridescence_thickness_range[2] },
    flat_shading = xm.flat, roughness = xm.roughness })
  mat.color:set_rgb(xm.color[1], xm.color[2], xm.color[3])
  local GU = { uGemTime = { value = 0 }, uFire = { value = 1.6 }, uInner = { value = 0.16 }, uGlow = { value = 0 }, uGemDebug = { value = 0 },
    uPrismLo = { value = 0.02 }, uPrismHi = { value = 1.0 }, uLitDim = { value = 0.36 }, uPattern = { value = 1 }, uLift = { value = 0 } }
  mat.custom = {}
  for k, v in pairs(GU) do mat.custom[k] = v end
  if opts.GU then for _, k in ipairs({ 'uGIUp', 'uGIDown', 'uGIMin', 'uGIMax', 'uGIScale' }) do mat.custom[k] = opts.GU[k] end end
  local function set_level(l) GU.uFire.value = l.fire; GU.uInner.value = l.inner; mat.iridescence = l.irid end
  local tris = 0

  local root = T.Group.new()
  local body = T.Group.new()
  root:add(body)
  local function node(parent, p, s)
    p = p or { 0, 0, 0 }; s = s or 1
    local g = T.Group.new()
    g.position:set(p[1]*s, p[2], p[3])
    parent:add(g)
    return g
  end
  local function skin(n, key)
    local gname = X.geo[key]
    if not gname then return end
    local g = A.geometry(gname)
    local m = T.Mesh.new(g, mat)
    m.cast_shadow = true; m.receive_shadow = true
    n:add(m)
    tris = tris + (g.index and g.index.count or g.attributes.position.count)/3
  end

  local RIG, FINGERS = L.RIG, L.FINGERS
  local pelvis = node(body); skin(pelvis, 'pelvis')
  local spine = node(pelvis, RIG.spine); skin(spine, 'spine')
  local chest = node(spine, RIG.chest); skin(chest, 'chest')
  local neck = node(chest, RIG.neck); skin(neck, 'neck')
  local head = node(neck, RIG.head); skin(head, 'head')
  local jaw = node(head, RIG.jaw); skin(jaw, 'jaw')
  local arms, legs = {}, {}
  for _, s in ipairs({ -1, 1 }) do
    local S = s > 0 and 'L' or 'R'
    local sh = node(chest, RIG.shoulder, s); skin(sh, 'upper' .. S)
    local el = node(sh, RIG.elbow); skin(el, 'fore' .. S)
    local wr = node(el, RIG.wrist); skin(wr, 'hand' .. S)
    local fingers = {}
    for i, f in ipairs(FINGERS) do
      local segs = {}
      local parent = node(wr, { 0, -0.028 - f.meta, f.z })
      for j, len in ipairs(f.ph) do
        skin(parent, 'finger' .. S .. (i - 1) .. '_' .. (j - 1))
        segs[#segs + 1] = parent
        parent = node(parent, { 0, -len, 0 })
      end
      segs.tip = parent
      fingers[i] = segs
    end
    local thumb = {}
    local tp = node(wr, { s*0.012, -0.055, 0.046 })
    for j, len in ipairs({ 0.034, 0.026 }) do
      skin(tp, 'thumb' .. S .. '_' .. (j - 1))
      thumb[#thumb + 1] = tp
      tp = node(tp, { 0, -len, 0 })
    end
    arms[#arms + 1] = { s = s, sh = sh, el = el, wr = wr, fingers = fingers, thumb = thumb }
    local hip = node(pelvis, RIG.hip, s); skin(hip, 'thigh' .. S)
    local kn = node(hip, RIG.knee, s); skin(kn, 'knee' .. S); skin(kn, 'shin' .. S)
    local an = node(kn, RIG.ankle); skin(an, 'foot' .. S)
    legs[#legs + 1] = { s = s, hip = hip, kn = kn, an = an }
  end

  R.world_scene:add(root)
  local light = T.PointLight.new(0xffffff, 0, 0.1, 2)          -- kept at zero, never added (as in lich.js)

  local GLOWS = {
    { name = 'FOLLOWS THE LIGHT', lift = 0, glow = 0.0015 },
    { name = 'A LITTLE BRIGHTER', lift = 0.7, glow = 0.004 },
    { name = 'DIMMER', lift = -0.35, glow = 0 },
  }
  local glow = 0
  local function set_glow(i) glow = wrapi(i, #GLOWS); GU.uGlow.value = GLOWS[glow + 1].glow; GU.uLift.value = GLOWS[glow + 1].lift or 0 end
  set_glow(0)
  local MODES = {}
  for i, l in ipairs(L.GEM_LEVELS) do MODES[i] = 'GEM, ' .. l.name end
  local mode = 2
  set_level(L.GEM_LEVELS[mode + 1])

  local JUICE = {
    { name = 'FLOATY', gain = 1.0, freq = 1.0, damp = 1.0 },
    { name = 'LOOSE', gain = 1.6, freq = 0.8, damp = 0.72 },
    { name = 'LIGHT', gain = 0.55, freq = 1.25, damp = 1.4 },
    { name = 'OFF: ROUND 4, RIGID', gain = 0, freq = 1.0, damp = 1.0 },
  }
  local juice = 0
  local ARM_REST = { { p = -0.12, e = -1.25, w = -0.25, curl = 0.55 }, { p = -0.72, e = -0.42, w = -0.35, curl = 0.32 } }
  local ARM_TRAIL = { p = 0.36, e = -0.3, w = 0.3, curl = 0.2 }
  local trail = 0
  local function SP(x) return { x = x or 0, v = 0, a = 0 } end
  local S = {
    bp = SP(), br = SP(), py = SP(), cp = SP(), cr = SP(), cy = SP(), hp = SP(), hr = SP(), hy = SP(), jw = SP(), fo = SP(),
    legs = { { p = SP(), r = SP(), k = SP(), an = SP(), tw = SP() }, { p = SP(), r = SP(), k = SP(), an = SP(), tw = SP() } },
    arms = {},
  }
  for i, r in ipairs(ARM_REST) do S.arms[i] = { p = SP(r.p), r = SP(), t = SP(), e = SP(r.e), w = SP(r.w), f = SP() } end
  local RC = {}
  for i = 1, 2 do RC[i] = { p = SP(), e = SP(), w = SP(), kick = 0, press = 0, curl_t = 9, fist = 0 } end
  local CURL = { up = 0.1, hold = 0.35, down = 0.8, elbow = 0.8, shoulder = 0.18 }
  local RECOILS = { { name = 'HEAVY', gain = 1.7 }, { name = 'MEDIUM', gain = 1 }, { name = 'LIGHT', gain = 0.5 }, { name = 'OFF', gain = 0 } }
  local recoil = 0
  local HURT = { w = 0, level = 0, hand = 0, drop = SP(), clench = SP(), legs = SP() }
  local HANDS = { 'OPEN, CLAWED (THE IMAGE)', 'POINTING (HIS CASTING HAND)' }
  local CLAW = { 0.12, 0.62, 0.7 }
  local fq, dz = 1, 1
  local function spring(s, target, f, z, force, dt)
    local w = 6.2832*f*fq
    local zz = min(1.2, z*dz)
    s.a = w*w*(target - s.x) - 2*zz*w*s.v + force
    s.v = s.v + s.a*dt; s.x = s.x + s.v*dt
  end
  local function air(t, k, f, amp)
    local w = 6.2832*f*fq
    return w*w*amp*(sin(t*0.71 + k*1.37)*0.55 + sin(t*1.29 + k*2.71)*0.3 + sin(t*2.17 + k*0.53)*0.15)
  end
  local INV, TV, TIP = Matrix4.new(), Vector3.new(), Vector3.new()
  local AQ = { e = Quaternion.new(), c = Quaternion.new(), r = Quaternion.new(), i = Quaternion.new(), t = Quaternion.new() }
  local AV = { b = Vector3.new(), t = Vector3.new(), f = Vector3.new(), d = Vector3.new(), ax = Vector3.new(), up = Vector3.new(0, 1, 0) }
  local NO_MOTION = { a = { 0, 0, 0 }, v = { 0, 0, 0 }, push = { 0, 0 }, yaw_a = 0, yaw_v = 0, look = 0, gaze = 0, gaze_p = 0, gaze_w = 0 }
  local hit_rng = U.run_rng(97)

  local lich = {
    root = root, body = body, mat = mat, light = light, MODES = MODES, tris = tris,
    nodes = { pelvis = pelvis, spine = spine, chest = chest, neck = neck, head = head, jaw = jaw, arms = arms, legs = legs },
    JUICE = JUICE, springs = S, GLOWS = GLOWS, PATTERNS = L.PATTERNS, rc = RC, hurt = HURT, HANDS = HANDS, RECOILS = RECOILS,
    hover_h = 1.28, recoil_gain = 1,
  }
  function lich.get_pattern() return GU.uPattern.value end
  function lich.set_pattern(i) GU.uPattern.value = wrapi(i, #L.PATTERNS) end
  function lich.get_glow() return glow end
  function lich.set_glow(i) set_glow(i) end
  function lich.get_mode() return mode end
  function lich.set_mode(m) mode = wrapi(m, #MODES); set_level(L.GEM_LEVELS[mode + 1]) end
  function lich.get_juice() return juice end
  function lich.set_juice(j) juice = wrapi(j, #JUICE) end
  function lich.get_recoil() return recoil end
  function lich.set_recoil(i) recoil = wrapi(i, #RECOILS) end

  function lich.pose(t, dt, m)
    dt = dt or 1/60
    m = m or NO_MOTION
    local J = JUICE[juice + 1]
    local g = J.gain
    local gt = min(1, g)
    fq = J.freq; dz = J.damp
    local ax, ay, az = m.a[1], m.a[2], m.a[3]
    local vx, vz = m.v[1], m.v[3]
    local px, pz = m.push[1], m.push[2]
    local ya = m.yaw_a
    local speed = js_hypot(vx, vz)
    local still = 1 - clamp(speed/0.6, 0, 1)
    local fwd = clamp(vz/2.6, 0, 1)
    local side = clamp(vx/2.6, -1, 1)
    local hw, lv = HURT.w, HURT.level
    local function H(normal, hurt) if hw > 0 then return mix(normal, hurt, hw) end; return normal end
    local wr1 = sin(t*0.83)*0.6 + sin(t*1.61 + 1.3)*0.4
    local wr2 = sin(t*0.71 + 2.1)*0.55 + sin(t*1.93 + 0.4)*0.45
    local wr3 = sin(t*0.57 + 4.0)*0.6 + sin(t*1.37 + 2.6)*0.4
    local shk = hw*(0.01 + 0.035*lv)
    local function trem(k) return shk*(sin(t*47.1 + k*1.7)*0.5 + sin(t*61.3 + k*2.9)*0.3 + sin(t*83.7 + k*0.7)*0.2) end
    spring(HURT.drop, 0, 1.6, 0.45, 0, dt)
    spring(HURT.clench, 0, 3.0, 0.5, 0, dt)
    for k = 1, 2 do
      local rc = RC[k]
      if rc.kick ~= 0 then
        local s = arms[k].s
        S.cy.v = S.cy.v + s*1.6*rc.kick; S.cp.v = S.cp.v - 0.9*rc.kick; S.hp.v = S.hp.v - 1.6*rc.kick
        rc.p.v = rc.p.v - 2.6*rc.kick; rc.e.v = rc.e.v - 4.5*rc.kick; rc.w.v = rc.w.v + 5.0*rc.kick
        rc.kick = 0
      end
      rc.curl_t = rc.curl_t + dt
      local cw = smoothstep01(rc.curl_t/CURL.up)*(1 - smoothstep01((rc.curl_t - CURL.hold)/(CURL.down - CURL.hold)))
      rc.fist = cw
      local on = cw > 0.01
      spring(rc.p, -0.03*rc.press + CURL.shoulder*cw, on and 3.0 or 2.2, 0.5, 0, dt)
      spring(rc.e, -0.06*rc.press - CURL.elbow*cw, on and 4.2 or 2.6, 0.5, 0, dt)
      spring(rc.w, 0.035*rc.press, 3.2, 0.45, 0, dt)
    end

    local idle_glance = sin(t*0.33)*0.1*still
    local gz = m.gaze_w or 0
    spring(S.hp, H(mix(clamp((0.26*pz - 0.2*(S.bp.x + S.cp.x))*g, -0.12, 0.3), clamp((m.gaze_p or 0) - 0.27, -0.7, 0.55), gz), -(0.42 + 0.2*lv) + 0.08*wr1), 2.4, 0.6, air(t, 5, 2.4, 0.03*g), dt)
    spring(S.hr, H(clamp((-0.22*px - 0.2*(S.br.x + S.cr.x))*g, -0.25, 0.25), 0.3 + 0.12*wr2), 2.4, 0.6, air(t, 6, 2.4, 0.025*g), dt)
    local gc = clamp((m.gaze or 0)*0.3, -0.35, 0.35)
    spring(S.hy, H(mix(clamp(m.look*0.5, -0.5, 0.5)*g + idle_glance, clamp((m.gaze or 0) - gc, -1.1, 1.1), gz), -0.24 + 0.14*wr3), 2.2, 0.75, air(t, 8, 2.2, 0.025*g), dt)
    spring(S.cp, H(clamp((0.24*pz + 0.05*fwd)*g, -0.1, 0.3), -(0.28 + 0.14*lv) + 0.05*wr2), 1.6, 0.6, air(t, 3, 1.6, 0.02*g), dt)
    spring(S.cr, H(clamp(-0.2*px*g, -0.22, 0.22), 0.2 + 0.1*wr1), 1.6, 0.6, air(t, 4, 1.6, 0.018*g), dt)
    spring(S.cy, H(mix(clamp(m.look*0.4*g, -0.45, 0.45), gc, gz), -0.32 + 0.1*wr3), 1.6, 0.7, air(t, 9, 1.6, 0.02*g), dt)
    spring(S.bp, H(clamp((0.03*vz + 0.02*az)*g, -0.2, 0.24), -(0.1 + 0.08*lv) + 0.03*wr1), 0.9, 0.75, air(t, 1, 0.9, 0.012*g), dt)
    spring(S.br, H(clamp(-0.035*ax*g, -0.24, 0.24), 0.08 + 0.07*wr2), 0.9, 0.75, air(t, 2, 0.9, 0.012*g), dt)
    spring(S.py, 0, 1.1, 0.45, -ya*0.05*g, dt)
    spring(S.jw, 0, 2.3, 0.22, (ay*8 + az*3.5)*g + air(t, 7, 2.3, 0.015*g), dt)
    -- (2026-10-16, the ending's down-stroke, owner: "his body/torso needs to react with it as well, he needs to put all
    -- his force into it"): m.force, his whole body behind the blow (game.lua GEST): below 0 he draws himself up and back
    -- (the wind-up), 1 thrown forward and down over the arm he brings down, his knees giving, the other arm flung back.
    -- A fast spring that overshoots a little (the blow's follow-through); nil = 0 (never set outside the ending)
    spring(S.fo, m.force or 0, 3.4, 0.42, 0, dt)
    local fo = S.fo.x
    local fd = max(0, fo)
    local JAW0 = H(0.07 + max(0, sin(t*0.45))*0.04, 0.26 + 0.1*lv + 0.04*wr3)
    if JAW0 + S.jw.x < 0.0 then S.jw.x = -JAW0; if S.jw.v < 0 then S.jw.v = -S.jw.v*0.3 end end
    if JAW0 + S.jw.x > 0.42 then S.jw.x = 0.42 - JAW0; if S.jw.v > 0 then S.jw.v = 0 end end

    local pull = 14*fq*fq
    for k0 = 0, 1 do
      local Lg, O = S.legs[k0 + 1], S.legs[2 - k0]
      local df = k0 == 1 and 1.08 or 0.93
      local dd = k0 == 1 and 0.9 or 1.1
      local sd = k0 == 1 and 31 or 10
      local tt = t*(k0 == 1 and 1.14 or 0.87)
      spring(Lg.p, clamp(0.045*vz*g, -0.1, 0.18), 0.75*df, 0.3*dd, (az*0.75 - ay*0.4)*g + (O.p.x - Lg.p.x)*pull + air(tt, sd, 0.75, 0.07*g), dt)
      spring(Lg.r, clamp(-0.04*vx*g, -0.16, 0.16), 0.7*df, 0.3*dd, (-ax*0.8 + ya*0.08)*g + (O.r.x - Lg.r.x)*pull + air(tt, sd + 2, 0.7, 0.05*g), dt)
      spring(Lg.k, 0, 1.2*df, 0.3, (az*0.7 - Lg.p.a*0.4)*g + air(tt, sd + 4, 1.2, 0.08*g), dt)
      spring(Lg.an, 0, 1.7*df, 0.3, (az*0.4 - Lg.k.a*0.3)*g + air(tt, sd + 6, 1.7, 0.09*g), dt)
      spring(Lg.tw, 0, 0.9*df, 0.4, air(tt, sd + 8, 0.9, 0.1*g) - ya*0.03*g, dt)
    end
    spring(HURT.legs, 0, 1.3, 0.4, 0, dt)
    local r0, r1 = S.legs[1].r.x, S.legs[2].r.x
    if r0 - r1 > 0.03 then local c = (r0 + r1)/2; r0 = c + 0.015; r1 = c - 0.015 end
    for _, l in ipairs(legs) do
      local k = l.s > 0 and 1 or 0
      local Lg = S.legs[k + 1]
      local stagger = l.s > 0 and 0.07 or 0
      l.hip.rotation:set(clamp(H(0.1 + stagger, -0.34 - 0.1*lv + (k == 1 and -0.12 or 0.06) + 0.05*wr2*(k == 1 and 1 or -1)) + Lg.p.x + HURT.legs.x - 0.32*fd, -0.9, 0.9),
        clamp(Lg.tw.x, -0.2, 0.2), H(-0.02*l.s, 0.05*l.s) + clamp(k == 1 and r1 or r0, -0.4, 0.4))
      l.kn.rotation:set(clamp(H(0.2 + stagger*0.5, 0.62 + 0.2*lv + (k == 1 and 0.3 or 0)) + Lg.k.x - 0.6*HURT.legs.x + 0.5*fd, 0.03, 1.5), 0, 0.015*l.s)
      l.an.rotation:set(clamp(H(1.0, 1.22) + Lg.an.x, 0.55, 1.45), 0, 0)
    end

    trail = trail + (fwd*gt - trail)*(1 - exp(-dt/(fwd*gt > trail and 0.35 or 0.9)))
    for k0 = 0, 1 do
      local Ar = arms[k0 + 1]
      local Q, s, R0 = S.arms[k0 + 1], Ar.s, ARM_REST[k0 + 1]
      local df = k0 == 1 and 1.12 or 0.9
      local sd = 40 + k0*17
      local tt = t*(k0 == 1 and 1.21 or 0.79)
      local pt = (m.point and m.point.arm == k0) and m.point.w or 0
      -- (2026-10-16, the ending's gesture: m.point.f, how much faster than usual the arm follows its aim; nil = as before)
      local pf = (pt > 0 and m.point.f) or 1
      local aim_p, aim_r = 0, 0
      if pt > 0 then
        chest:update_world_matrix(true, false)
        INV:copy(chest.matrix_world):invert()
        TV:set(m.point.x, m.point.y, m.point.z):apply_matrix4(INV):sub(Ar.sh.position):normalize()
        aim_r = asin(clamp(TV.x, -1, 1)); aim_p = atan2(-TV.z, -TV.y)
        aim_r = s*max(-0.45, s*aim_r)
        aim_p = clamp(aim_p, -2.4, 0.9)
      end
      local base_r = (s < 0 and 0.12 or 0.22)*s
      local drive = (az*0.85 + ay*sin(-Q.p.x) + (S.cp.a + S.bp.a)*0.5 - s*(S.cy.a + ya)*0.3)*(1 - pt)
      local hang = k0 == 0 and hw or 0
      spring(Q.p, H(mix(mix(R0.p, ARM_TRAIL.p, trail), aim_p, pt), hang ~= 0 and 0.3 + 0.1*wr1 or aim_p + 0.16*lv*pt), mix(0.55*df, 2.3*pf, pt), mix(0.34, 0.75, pt), drive*g + air(tt, sd, 0.55, 0.1*g*(1 - pt)), dt)
      spring(Q.r, H(mix((-0.25*side + s*0.1*fwd)*gt, aim_r - base_r, pt), hang ~= 0 and s*(0.42 + 0.08*wr2) or aim_r - base_r), mix(0.6*df, 2.3*pf, pt), mix(0.3, 0.75, pt), (-ax + (S.cr.a + S.br.a)*0.4)*g*(1 - pt) + air(tt, sd + 3, 0.6, 0.07*g*(1 - pt)), dt)
      spring(Q.t, 0, 0.7*df, 0.4, air(tt, sd + 5, 0.7, 0.12*g*(1 - pt)), dt)
      spring(Q.e, H(mix(mix(R0.e, ARM_TRAIL.e, trail), -0.1, pt), hang ~= 0 and -0.5 - 0.1*wr3 or -0.12 - 0.38*lv*pt), mix(1.0*df, 2.6*pf, pt), mix(0.3, 0.75, pt), (az*0.8 - Q.p.a*0.35)*g*(1 - pt) + air(tt, sd + 7, 1.0, 0.1*g*(1 - pt)), dt)
      spring(Q.w, H(mix(mix(R0.w, ARM_TRAIL.w, trail), 0.05, pt), hang ~= 0 and 0.6 or 0.05), mix(1.5*df, 3.0, pt), mix(0.3, 0.75, pt), (az*0.5 - Q.e.a*0.3)*g*(1 - pt) + air(tt, sd + 9, 1.5, 0.08*g*(1 - pt)), dt)
      spring(Q.f, (ARM_TRAIL.curl - R0.curl)*trail, 2.0*df, 0.3, (az*0.6 - Q.w.a*0.2)*g + air(tt, sd + 11, 2.0, 0.06*g), dt)
      local roll = s*max(mix(-0.08, -0.45, pt), s*Q.r.x)
      local rc = RC[k0 + 1]
      local tr = rc.press*sin(t*31 + k0*2)*0.012 + trem(k0*3)*1.4
      local fling = (m.point and m.point.arm ~= k0) and 0.6*fd or 0       -- (the other arm flung back with the blow)
      rc.sh = clamp(Q.p.x + rc.p.x + tr + fling, -2.4, 1.0); rc.el = clamp(Q.e.x + rc.e.x + trem(k0*3 + 1)*1.6, -1.9, -0.05)
      Ar.sh.rotation:set(clamp(Q.p.x, -2.4, 1.0), clamp(Q.t.x, -0.35, 0.35), base_r + roll)
      Ar.el.rotation:set(clamp(Q.e.x, -1.9, -0.05), 0, 0)
      Ar.wr.rotation:set(clamp(Q.w.x, -0.9, 0.7), -s*(s < 0 and 0.9 or 1.25), 0)
      local curl = R0.curl + clamp(Q.f.x, -0.3, 0.4)
      local fw = rc.fist
      local claw = hw*((k0 == 0 or HURT.hand == 0) and 1 or 0)
      for i0, segs in ipairs(Ar.fingers) do
        local i = i0 - 1
        local c = mix(mix(curl, i == 0 and -0.1 or 1.05, pt), 1.3, fw)
        for j0, n in ipairs(segs) do
          local j = j0 - 1
          local normal = c + j*(i == 0 and 0.12*(1 - pt) or 0.12 + 0.25*pt) + i*0.03 + sin(t*1.3 + i)*0.03
          local hurt = CLAW[j + 1] + 0.08*i*(j > 0 and 1 or 0) + HURT.clench.x*(0.5 + 0.3*j) + trem(10 + i*3 + j)*4
          n.rotation:set(j == 0 and -claw*(FINGERS[i0].z/0.02)*0.2 or 0, 0, -s*mix(normal, hurt, claw))
        end
      end
      Ar.thumb[1].rotation:set(0.5 + 0.35*fw - 0.3*((k0 == 0 or HURT.hand == 0) and hw or 0), 0, -s*(0.35 + 0.35*fw))
      Ar.thumb[2].rotation:set(0, 0, -s*(0.3 + 0.5*fw))
    end

    body.position.y = (hw ~= 0 and (-hw*(0.07 + 0.2*lv) + HURT.drop.x + hw*0.025*wr2) or 0) - 0.09*fd + 0.035*max(0, -fo)
    body.rotation:set(0.1 + S.bp.x + 0.2*fo, 0, S.br.x)
    pelvis.rotation:set(0, S.py.x, 0)
    spine.rotation:set(0.04 + S.cp.x*0.5 + 0.6*fo, -S.py.x*0.75 + S.cy.x*0.45, S.cr.x*0.5)
    chest.rotation:set(0.03 + S.cp.x*0.5 + 0.4*fo, S.cy.x*0.55, S.cr.x*0.5)
    neck.rotation:set(0.04 + S.hp.x*0.3 + 0.15*fo, S.hy.x*0.3, S.hr.x*0.3)
    head.rotation:set(-0.02 + S.hp.x*0.7 + trem(20) + 0.3*fo, S.hy.x*0.7 + trem(21)*0.7, S.hr.x*0.7)
    jaw.rotation.x = JAW0 + S.jw.x

    for k0 = 0, 1 do
      local Ar = arms[k0 + 1]
      local rc = RC[k0 + 1]
      local pt = ((m.point and m.point.arm == k0) and m.point.w or 0)*(1 - rc.fist)
      local flick = rc.w.x + rc.press*sin(t*37 + k0)*0.02
      local function recoil_on() Ar.sh.rotation.x = rc.sh; Ar.el.rotation.x = rc.el end
      if pt <= 0 and abs(flick) < 1e-4 then recoil_on()
      else
        Ar.el:update_world_matrix(true, false)
        Ar.el:get_world_quaternion(AQ.e)
        AQ.c:identity()
        local tipn = Ar.fingers[1].tip
        tipn:update_world_matrix(true, false); tipn:get_world_position(AV.t)
        Ar.fingers[1][1]:get_world_position(AV.b)
        AV.f:sub_vectors(AV.t, AV.b):normalize()
        if pt > 0 and AV.d:set(m.point.x, m.point.y, m.point.z):distance_to(AV.t) > 0.3 then
          AV.d:sub(AV.t):normalize()
          AQ.t:set_from_unit_vectors(AV.f, AV.d)
          AQ.c:slerp(AQ.t, pt)
          local ang = 2*acos(clamp(AQ.c.w, -1, 1))
          if ang > 0.8 then AQ.t:copy(AQ.c); AQ.c:identity():slerp(AQ.t, 0.8/ang) end
          AV.f:apply_quaternion(AQ.c)
        end
        AV.ax:cross_vectors(AV.f, AV.up)
        if AV.ax:length_sq() > 1e-6 and abs(flick) > 1e-4 then AV.ax:normalize(); AQ.r:set_from_axis_angle(AV.ax, flick); AQ.c:premultiply(AQ.r) end
        AQ.t:copy(AQ.e):invert():multiply(AQ.c):multiply(AQ.e)
        Ar.wr.quaternion:premultiply(AQ.t)
        recoil_on()
      end
    end
  end

  function lich.hit(a)
    a = a or 1
    S.hp.v = S.hp.v - 3.2*a; S.hr.v = S.hr.v + hit_rng.sign()*1.4*a; S.cp.v = S.cp.v - 1.8*a; S.bp.v = S.bp.v - 0.9*a
    S.cy.v = S.cy.v + hit_rng.sign()*1.2*a
    HURT.drop.v = HURT.drop.v - 1.1*a; HURT.clench.v = HURT.clench.v + 9*a; HURT.legs.v = HURT.legs.v - 2.4*a; S.jw.v = S.jw.v + 3.5*a
    RC[2].kick = RC[2].kick + 0.55*a*lich.recoil_gain
    AU.play('lich_hurt', { pos = lich.head_pos(SND_P), volume = math.min(1, 0.35 + 0.35*a), gap = 0.12 })
  end
  -- (2026-10-16, the ending's slam: his body sinks with the blow he brings down, knees and head going with it; no sound,
  -- no arm kick, no draw: lich.hit's jolts without its voice)
  function lich.slam(a)
    a = a or 1
    S.hp.v = S.hp.v - 2.6*a; S.cp.v = S.cp.v - 1.6*a; S.bp.v = S.bp.v - 0.8*a
    HURT.drop.v = HURT.drop.v - 1.8*a; HURT.legs.v = HURT.legs.v - 2.6*a; S.jw.v = S.jw.v + 2.0*a
  end
  function lich.kick(k, amount) RC[k + 1].kick = RC[k + 1].kick + (amount or 1)*lich.recoil_gain*RECOILS[recoil + 1].gain end
  function lich.curl(k)
    local rc = RC[k + 1]
    if rc.curl_t < CURL.hold then return end
    rc.curl_t = 0
    S.cy.v = S.cy.v + arms[k + 1].s*0.9; S.cp.v = S.cp.v - 0.5; S.hp.v = S.hp.v - 0.6
    AU.play('lift_fist', { pos = lich.fingertip(k, SND_P) })
  end
  function lich.press(k, w) RC[k + 1].press = w*lich.recoil_gain*RECOILS[recoil + 1].gain end
  function lich.update(t) GU.uGemTime.value = t end
  function lich.fingertip(k, out) out = out or Vector3.new(); local n = arms[k + 1].fingers[1].tip; n:update_world_matrix(true, false); return n:get_world_position(out) end
  function lich.arm_speed(k) local Q = S.arms[k + 1]; return abs(Q.p.v) + abs(Q.r.v) + abs(Q.e.v) end
  function lich.finger_dir(k, out)
    out = out or Vector3.new()
    local f = arms[k + 1].fingers[1]
    local n = f.tip
    n:update_world_matrix(true, false); n:get_world_position(out)
    f[1]:get_world_position(TV)
    return out:sub(TV):normalize()
  end
  function lich.head_pos(out) out = out or Vector3.new(); head:update_world_matrix(true, false); return head:get_world_position(out):add(TIP:set(0, 0.08, 0)) end
  lich.gem_u = GU
  return lich
end

return L
