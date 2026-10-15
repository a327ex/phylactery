--[[
  warp.lua -- the port to Anchor: web/src/warp.js. Things that bend the light behind them: each
  piece writes into the warp scene's target how far the world behind it shifts and how far apart
  its colour channels pull (post.lua bends the world image by it). Streaks (polylines of K points
  their owner moves) and puffs (rising, swirling blobs), and flung streaks (paths thrown out of a
  burst). Seeded (make_rng(23)) in both builds.
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local MAT = require('port.three.materials')
local U = require('port.util')
local Vector2, Vector3 = TM.Vector2, TM.Vector3
local smoothstep = U.smoothstep
local abs, floor, min, max = math.abs, math.floor, math.min, math.max

local W = {}
W.K = 24
local K = W.K

function W.create(R)
  local rnd = U.run_rng(23)
  local UN = { uRes = { value = Vector2.new(R.W, R.H) }, uProj = { value = 400 }, uTime = { value = 0 }, tDepth = { value = R.targets.rt_world.depth_texture }, uNoDepth = { value = 0 } }
  local function blend(name)
    return MAT.ShaderMaterial.new({ name = name, uniforms = UN, transparent = true, depth_write = false, depth_test = false, side = MAT.DoubleSide,
      blending = MAT.CustomBlending, blend_src = MAT.OneFactor, blend_dst = MAT.OneFactor, blend_src_alpha = MAT.OneFactor, blend_dst_alpha = MAT.OneFactor,
      blend_equation = MAT.AddEquation })
  end

  -- ---------------------------------------------------------------- streaks
  local NS = 200
  -- (2026-10-15, the web's performance) the streaks in meshes of CH: a mesh's buffers are sent again only when one of
  -- its streaks moved or went off, and a mesh with none on is not drawn. They were one mesh of all 200 (9600 vertices,
  -- ~134k floats sent every frame while any one streak was on; ~11 are on at a time, the lowest free slots, so they
  -- sit in the first meshes). Drawn in the same order, additively: the same image.
  local CH = 10
  local NC = NS//CH
  local CV = CH*K*2
  local idx = {}
  for s = 0, CH - 1 do for k = 0, K - 2 do
    local a = (s*K + k)*2
    local o = #idx
    idx[o + 1], idx[o + 2], idx[o + 3], idx[o + 4], idx[o + 5], idx[o + 6] = a, a + 1, a + 3, a, a + 3, a + 2
  end end
  local smat = blend('warp.streaks')
  local chunks = {}
  for c = 1, NC do
    local posA, prvA, nxtA = T.float_attr(CV, 3), T.float_attr(CV, 3), T.float_attr(CV, 3)
    local sideA, alongA, prmA, fadeA = T.float_attr(CV, 1), T.float_attr(CV, 1), T.float_attr(CV, 4), T.float_attr(CV, 1)
    local side, along = sideA.array, alongA.array
    for s = 0, CH - 1 do for k = 0, K - 1 do for e = 0, 1 do local v = (s*K + k)*2 + e; side[v + 1] = e == 1 and 1 or -1; along[v + 1] = k/(K - 1) end end end
    local sg = T.BufferGeometry.new()
    sg:set_attribute('position', posA)
    sg:set_attribute('aPrev', prvA)
    sg:set_attribute('aNext', nxtA)
    sg:set_attribute('aSide', sideA)
    sg:set_attribute('aU', alongA)
    sg:set_attribute('aP', prmA)
    sg:set_attribute('aA', fadeA)
    sg:set_index(idx)
    local smesh = T.Mesh.new(sg, smat); smesh.frustum_culled = false; smesh.visible = false
    R.warp_scene:add(smesh)
    chunks[c] = { mesh = smesh, attrs = { posA, prvA, nxtA, prmA, fadeA },
                  pos = posA.array, prv = prvA.array, nxt = nxtA.array, prm = prmA.array, fade = fadeA.array }
  end
  local S = {}
  for i = 1, NS do
    local pts = {}
    for k = 1, K do pts[k] = Vector3.new() end
    S[i] = { on = false, pts = pts, w = 0.1, amp = 3, chroma = 0.7, a = 0, ph = rnd.next()*6.28 }
  end

  -- ---------------------------------------------------------------- puffs
  local NP = 500
  local pposA, pprmA = T.float_attr(NP, 3), T.float_attr(NP, 4)
  local ppos, pprm = pposA.array, pprmA.array
  local pg = T.BufferGeometry.new()
  pg:set_attribute('position', pposA)
  pg:set_attribute('aP', pprmA)
  local pmat = blend('warp.puffs')
  local pts = T.Points.new(pg, pmat); pts.frustum_culled = false
  R.warp_scene:add(pts)
  local P = {}
  for i = 1, NP do P[i] = { life = 0 } end
  local active = false
  local pnext = 0

  -- ---------------------------------------------------------------- flung streaks
  local FL, DS, TMP = {}, 0.06, Vector3.new()
  local function find_free() for _, q in ipairs(S) do if not q.on then return q end end end
  local function fling(o)
    local s = find_free()
    if not s then return end
    s.on = true; s.a = 0; s.w = o.w or 0.12; s.amp = o.amp or 5; s.chroma = o.chroma or 1.2; s.ph = rnd.next()*6.28
    local sp, life, len, jit = o.speed or 6, o.life or 0.5, o.len or 0.8, o.jitter or 1.5
    local d, q = o.dir:clone():normalize(), o.p:clone()
    local path = { q:clone() }
    local ax = Vector3.new():cross_vectors(d, abs(d.y) < 0.9 and Vector3.new(0, 1, 0) or Vector3.new(1, 0, 0)):normalize()
    local total = sp*life + len
    local curl = o.curl or 3
    local t = 0
    while t < total do
      TMP:copy(ax):apply_axis_angle(d, (rnd.next() - 0.5)*jit*DS*6)
      ax:copy(TMP):normalize()
      d:apply_axis_angle(ax, curl*DS + (rnd.next() - 0.5)*jit*DS*3):normalize()
      d.y = d.y - 0.35*DS; d:normalize()
      q:add_scaled_vector(d, DS)
      path[#path + 1] = q:clone()
      t = t + DS
    end
    FL[#FL + 1] = { s = s, path = path, sp = sp, len = len, life = life, t = 0 }
  end
  local function at(path, d, out)
    local f = max(0, min(#path - 1.001, d/DS))
    local i = floor(f)
    return out:lerp_vectors(path[i + 1], path[i + 2], f - i)
  end
  local function update_flings(dt)
    for i = #FL, 1, -1 do
      local q = FL[i]
      q.t = q.t + dt
      local u = q.t/q.life
      local head = q.sp*q.life*(1 - (1 - min(1, u))^2) + q.len*min(1, q.t/0.08)
      local tail = max(0, head - q.len*(1 - 0.5*u))
      for k = 0, K - 1 do at(q.path, tail + (head - tail)*k/(K - 1), q.s.pts[k + 1]) end
      q.s.a = smoothstep(0, 0.05, q.t)*(1 - smoothstep(0.55, 1, u))
      if q.t >= q.life then q.s.on = false; q.s.a = 0; table.remove(FL, i) end
    end
  end

  local warp = { K = K, U = UN, fling = fling }
  function warp.streak()
    local s = find_free()
    if not s then return nil end
    s.on = true; s.a = 0; s.w = 0.1; s.amp = 3; s.chroma = 0.7; s.ph = rnd.next()*6.28
    return s
  end
  function warp.release(s) if s then s.on = false; s.a = 0 end end
  function warp.puff(o)
    local p = P[pnext + 1]; pnext = (pnext + 1) % NP
    p.vx = 0; p.vy = 0; p.vz = 0; p.drag = 0.8; p.rise = 0; p.spin = 1; p.rot = rnd.next()*6.28; p.amp = 3.5; p.s0 = 0.15; p.s1 = 0.5
    for k, v in pairs(o) do p[k] = v end
    p.max = o.life
    return p
  end
  function warp.update(t, dt)
    UN.uTime.value = t
    update_flings(dt)
    -- (a streak that is off draws nothing whatever its points hold: written once as off, then left; a mesh with none
    -- on is not drawn, and its buffers go out again only when one of its streaks changed)
    for c = 1, NC do local ch = chunks[c]; ch.on = false; ch.dirty = false end
    for i = 0, NS - 1 do
      local s = S[i + 1]
      local ch = chunks[i//CH + 1]
      if s.on then ch.on = true end
      local sp = s.pts
      local f = s.on and s.a or 0
      if s.on or not s.written_off then
      ch.dirty = true
      s.written_off = not s.on
      local pos, prv, nxt, prm, fade = ch.pos, ch.prv, ch.nxt, ch.prm, ch.fade
      local li = i % CH
      for k = 0, K - 1 do
        local p, a, b = sp[k + 1], sp[max(0, k - 1) + 1], sp[min(K - 1, k + 1) + 1]
        for e = 0, 1 do
          local v = (li*K + k)*2 + e
          local v3, v4 = v*3, v*4
          pos[v3 + 1], pos[v3 + 2], pos[v3 + 3] = p.x, p.y, p.z
          prv[v3 + 1], prv[v3 + 2], prv[v3 + 3] = a.x, a.y, a.z
          nxt[v3 + 1], nxt[v3 + 2], nxt[v3 + 3] = b.x, b.y, b.z
          prm[v4 + 1], prm[v4 + 2], prm[v4 + 3], prm[v4 + 4] = s.w, s.amp, s.chroma, s.ph
          fade[v + 1] = f
        end
      end
      end
    end
    local any_on = false
    for c = 1, NC do
      local ch = chunks[c]
      ch.mesh.visible = ch.on
      if ch.on then any_on = true end
      if ch.dirty then for _, a in ipairs(ch.attrs) do a.needs_update = true end end
    end
    local alive, changed = false, false
    for i = 0, NP - 1 do
      local p = P[i + 1]
      if p.life <= 0 then
        if pprm[i*4 + 4] ~= 0 then pprm[i*4 + 4] = 0; changed = true end
      else
        alive, changed = true, true
        p.life = p.life - dt
        local u = 1 - p.life/p.max
        local d = 1 - p.drag*dt
        p.vx = p.vx*d; p.vy = p.vy*d + p.rise*dt; p.vz = p.vz*d
        p.x = p.x + p.vx*dt; p.y = p.y + p.vy*dt; p.z = p.z + p.vz*dt; p.rot = p.rot + p.spin*dt
        ppos[i*3 + 1] = p.x; ppos[i*3 + 2] = p.y; ppos[i*3 + 3] = p.z
        pprm[i*4 + 1] = p.s0 + (p.s1 - p.s0)*u; pprm[i*4 + 2] = p.amp; pprm[i*4 + 3] = p.rot
        pprm[i*4 + 4] = smoothstep(0, 0.15, u)*(1 - smoothstep(0.45, 1, u))
      end
    end
    -- (2026-10-15: sent only when something moved or died; none alive: not drawn)
    if changed then pposA.needs_update = true; pprmA.needs_update = true end
    pts.visible = alive
    active = any_on or alive
  end
  -- (2026-10-15) is anything bending the light: post.lua leaves the warp target cleared and skips its render if not
  R.warp_active = function() return active end
  function warp.set_camera(cam, H) UN.uProj.value = cam.projection_matrix.elements[6]*H*0.5 end
  function warp.debug()
    local n, pn, list = 0, 0, {}
    for _, s in ipairs(S) do if s.on then n = n + 1; if #list < 5 then list[#list + 1] = { s.a, s.pts[1]:to_array(), s.pts[K]:to_array() } end end end
    for _, p in ipairs(P) do if p.life > 0 then pn = pn + 1 end end
    return { streaks = list, n = n, puffs = pn }
  end
  return warp
end

return W
