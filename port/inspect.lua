--[[
  inspect.lua -- the port to Anchor: web/src/inspect.js. The inspect view: the game stops; its last
  frame stays behind, darkened and softened; the object comes up to the middle of the screen in its
  own light (a key from above, a warm bounce from below, a rim behind, the prefiltered cave-like
  environment the three.js build made) and turns slowly until taken in hand: left-drag turns it,
  the wheel brings it closer, A/D the next object, I or Esc puts it away. Drawn by the game's own
  pipeline (post.lua world_override).
]]
local TM = require('port.three.math')
local T = require('port.three.core')
local MAT = require('port.three.materials')
local U = require('port.util')
local OB = require('port.objects')
local ITM = require('port.items')
local HUD = require('port.hud')
local Vector2, Vector3, Quaternion, Euler, Color = TM.Vector2, TM.Vector3, TM.Quaternion, TM.Euler, TM.Color
local clamp, smoothstep, damp = U.clamp, U.smoothstep, U.damp
local sin, cos, tan, exp, max, pi = math.sin, math.cos, math.tan, math.exp, math.max, math.pi

local IN = {}
local ORB_R = { 0.05, 0.036, 0.042, 0.028, 0.032 }

function IN.create(ctx)
  local R, items, ITEMS = ctx.R, ctx.items, ctx.ITEMS
  local A = ITM.assets()
  local X = A.manifest.items
  local E = X.env

  local scene = T.Scene.new(); scene.name = 'inspect'; scene.program_scene = 'inspect'
  scene.background = Color.new(0x000000)
  scene.environment = A.texture(E.pmrem)
  scene.environment_intensity = E.intensity
  local camera = T.PerspectiveCamera.new(30, R.W/R.H, 0.02, 30)
  camera.position:set(0, 0, 1)
  local function dlight(l)
    local d = T.DirectionalLight.new(0xffffff, l.intensity)
    d.color:set_rgb(l.color[1], l.color[2], l.color[3])
    d.position:set(l.position[1], l.position[2], l.position[3])
    return d
  end
  local key, fill, rim = dlight(E.lights[1]), dlight(E.lights[2]), dlight(E.lights[3])
  local amb = T.AmbientLight.new(0xffffff, E.ambient[4])
  amb.color:set_rgb(E.ambient[1], E.ambient[2], E.ambient[3])
  scene:add(key, fill, rim, amb)
  local sun = { dir = key.position:clone():normalize(), col = Vector3.new(1, 0.9, 0.72):multiply_scalar(22) }
  local gem_sun = { dir = sun.dir, col = Vector3.new(1, 0.9, 0.72):multiply_scalar(45) }

  -- the frozen frame behind
  local back_mat = MAT.ShaderMaterial.new({ name = 'inspect.backdrop',
    uniforms = { tFrame = { value = nil }, uDim = { value = 1 }, uRes = { value = Vector2.new(R.W, R.H) }, uExposure = { value = 1 }, uBlur = { value = 0 }, uBlack = { value = 0 }, uGlow = { value = 0 } },
    depth_write = false, depth_test = false })
  local tri = T.BufferGeometry.new()
  tri:set_attribute('position', T.BufferAttribute.new({ -1, -1, 0, 3, -1, 0, -1, 3, 0 }, 3))
  local back = T.Mesh.new(tri, back_mat)
  back.frustum_culled = false; back.render_order = -10
  scene:add(back)

  local holder = T.Group.new()
  scene:add(holder)

  local S = { active = false, t = 0, idx = 5, model = nil, radius = 0.2, backdrop = 0, q = Quaternion.new(), wv = Vector2.new(0, 0), zoom = 1, zoom_t = 1,
    idle = 0, closing = -1, drag = nil, saved = nil, hover = nil }

  local function orbs_hover(orbs)
    local ORBIT = {}
    local tilts = { 0.2, -0.5, 0.7, -0.3, 0.45 }
    for i = 0, #ORB_R - 1 do
      ORBIT[i + 1] = { rad = 0.015 + 0.045*i, speed = (0.3 + 0.1*i)*((i % 2) ~= 0 and -1 or 1), tilt = tilts[i + 1], ph = i*1.9, bob = 0.012 + 0.004*i }
    end
    return function(t)
      for i, m in ipairs(orbs) do
        local o = ORBIT[i]
        local a = o.ph + t*o.speed
        local x, z = cos(a)*o.rad, sin(a)*o.rad
        m.position:set(x, sin(t*0.7 + o.ph)*o.bob + z*cos(o.tilt), z*sin(o.tilt))
      end
      for _ = 1, 3 do for i = 1, #orbs do for j = i + 1, #orbs do
        local a, b = orbs[i].position, orbs[j].position
        local d = a:distance_to(b)
        local mn = (ORB_R[i] + ORB_R[j])*1.15
        if d < mn and d > 1e-6 then
          local k = (mn - d)/d*0.5
          local dx, dy, dz = (b.x - a.x)*k, (b.y - a.y)*k, (b.z - a.z)*k
          a.x = a.x - dx; a.y = a.y - dy; a.z = a.z - dz; b.x = b.x + dx; b.y = b.y + dy; b.z = b.z + dz
        end
      end end end
    end
  end

  -- i: 0-based, as inspect.js
  local function build(i)
    if S.model then holder:remove(S.model); S.model = nil end
    local it = ITEMS[i + 1]
    S.idx = i
    if not it.build then return end
    if i == 1 then ITM.set_hand_material(items.opts.hand_mat) end
    local d = X.inspect[i + 1]
    local B = OB.builder(A, X.mats, {})
    local g = B.node(d.node)
    S.hover = nil
    if i == 4 then local m = g.children[1]; ITM.trace_hook(m, m.material, gem_sun, false) end
    if #d.orbs > 0 then
      local orbs = {}
      for _, ix in ipairs(d.orbs) do local m = g.children[ix + 1]; m.user_data.r = m.user_data.r or m.scale.x; ITM.trace_hook(m, m.material, sun, true); orbs[#orbs + 1] = m end
      S.hover = orbs_hover(orbs)
    end
    local c, size = d.box.c, d.box.s
    g.position:sub(Vector3.new(c[1], c[2], c[3]))
    local wrap = T.Group.new(); wrap:add(g)
    S.model = wrap; S.radius = max(size[1], size[2], size[3])*0.55
    holder:add(wrap)
    local v = it.view or { 0.55, 0.4, 0.0 }
    S.q:set_from_euler(Euler.new(v[1], v[2], v[3], 'YXZ'))
  end

  local insp = { S = S, scene = scene, camera = camera, holder = holder }
  function insp.open(i)
    if i == nil then i = S.idx end
    if S.active then return end
    S.active = true; S.t = 0; S.closing = -1; S.idle = 0; S.zoom = 1; S.zoom_t = 1; S.wv:set(0, 0)
    local hud = R.params.hud; R.params.hud = 0; R.params.world_override = nil; R.render(0); R.params.hud = hud
    back_mat.uniforms.tFrame.value = R.freeze()
    gpu_end()                 -- (rendered outside the frame's draw: hand the 2D pipeline its state back)
    S.saved = { bloom = R.params.bloom.strength }
    build(i)
  end
  function insp.close() if S.active and S.closing < 0 then S.closing = 0 end end
  function insp.next(d)
    local i = S.idx
    local n = #ITEMS
    for _ = 1, n do i = (i + d + n) % n; if ITEMS[i + 1].build then break end end
    build(i); S.t = 0.12; S.idle = 0; S.zoom_t = 1
  end
  local qa, ax = Quaternion.new(), Vector3.new()
  local function turn(yaw, pitch)
    qa:set_from_axis_angle(ax:set(0, 1, 0), yaw); S.q:premultiply(qa)
    qa:set_from_axis_angle(ax:set(1, 0, 0), pitch); S.q:premultiply(qa)
  end
  -- input (game.lua calls these while the view is up): mouse in game pixels; drag turns as
  -- inspect.js turns by CSS pixels over the canvas height
  function insp.pointer_down(x, y) if S.active then S.drag = { x, y }; S.idle = 0 end end
  function insp.pointer_up() S.drag = nil end
  function insp.pointer_move(x, y)
    if not S.active or not S.drag then return end
    local dx, dy = x - S.drag[1], y - S.drag[2]
    S.drag = { x, y }
    local k = 3.2/R.H
    S.wv:set(dx*k*60, dy*k*60)
    turn(dx*k, dy*k)
    S.idle = 0
  end
  function insp.wheel(deltaY) if S.active then S.zoom_t = clamp(S.zoom_t*exp(-deltaY*0.0012), 0.8, 3.2); S.idle = 0 end end
  function insp.tick(dt)
    if not S.active then return end
    S.t = S.t + dt
    if S.closing >= 0 then S.closing = S.closing + dt end
    S.idle = S.idle + dt
    if not S.drag then
      turn(S.wv.x*dt, S.wv.y*dt)
      S.wv:multiply_scalar(exp(-3.5*dt))
      local auto = 0.35*smoothstep(1.5, 3.0, S.idle)
      turn(auto*dt, 0)
    end
    S.zoom = damp(S.zoom, S.zoom_t, 10, dt)
    if S.model and S.hover then S.hover(S.t) end
    if S.closing > 0.3 then S.active = false; R.params.world_override = nil; R.params.bloom.strength = S.saved.bloom end
  end
  function insp.render_setup()
    if not S.active then return false end
    local a = smoothstep(0, 0.3, S.t)*(S.closing >= 0 and 1 - smoothstep(0, 0.28, S.closing) or 1)
    local dist = S.radius/tan(15*pi/180)/0.62/S.zoom
    camera.position:set(0, 0, dist)
    camera.near = dist*0.05; camera.far = dist*6; camera:update_projection_matrix()
    camera:look_at(0, 0, 0)
    holder.quaternion:copy(S.q)
    local e = 1 - a
    holder.position:set(0, -S.radius*0.9*e*e + S.radius*0.06, -S.radius*1.2*e)
    holder.scale:set_scalar(0.001 + a)
    local BU = back_mat.uniforms
    BU.uDim.value = 1 - 0.78*smoothstep(0, 0.3, S.t)*(S.closing >= 0 and 1 - smoothstep(0, 0.28, S.closing) or 1)
    BU.uBlur.value = 1.6*(1 - BU.uDim.value)/0.78
    BU.uExposure.value = R.params.exposure
    BU.uGlow.value = a
    R.params.world_override = { scene = scene, camera = camera }
    return true
  end
  function insp.draw_hud()
    if not S.active then return end
    local it = ITEMS[S.idx + 1]
    local a = smoothstep(0.15, 0.45, S.t)*(S.closing >= 0 and 1 - smoothstep(0, 0.15, S.closing) or 1)
    if a <= 0 then return end
    HUD.alpha(a)
    local ink = 'rgba(8,6,5,0.9)'
    HUD.text(it.name, R.W/2, R.H - 64, '#f2e3c2', 2, 'center', nil, ink)
    HUD.text('THE ' .. it.power .. ' POWER', R.W/2, R.H - 44, '#a8987c', 1, 'center', nil, ink)
    HUD.text('[ YOUR TEXT ]', R.W/2, R.H - 30, '#6f6252', 1, 'center', nil, ink)
    HUD.text("DRAG: TURN   WHEEL: CLOSER   A D: NEXT   M: THE HAND'S METAL   I: PUT AWAY", R.W/2, R.H - 12, '#6a5e4e', 1, 'center', nil, ink)
    HUD.alpha(1)
  end
  function insp.rebuild() if S.active then local q = S.q:clone(); build(S.idx); S.q:copy(q) end end
  function insp.pose(yaw, pitch, roll, zoom)
    S.q:set_from_euler(Euler.new(pitch, yaw, roll or 0, 'YXZ')); S.zoom = zoom or 1; S.zoom_t = zoom or 1; S.wv:set(0, 0); S.idle = -1e9
  end
  return insp
end

return IN
