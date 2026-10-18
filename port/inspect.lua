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
local AU = require('port.audio')     -- 2026-10-10: the sounds (the viewer's are not in the world: no position)
local Vector2, Vector3, Quaternion, Euler, Color = TM.Vector2, TM.Vector3, TM.Quaternion, TM.Euler, TM.Color
local clamp, smoothstep, damp = U.clamp, U.smoothstep, U.damp
local sin, cos, tan, exp, max, floor, pi = math.sin, math.cos, math.tan, math.exp, math.max, math.floor, math.pi

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
    idle = 0, closing = -1, drag = nil, saved = nil, hover = nil,
    remove = false, result = nil, buttons = {}, hot = nil,         -- (round 40: the view asks before an object is given up)
    accept = false }                                               -- (round 45: a newly found one waits for ACCEPT ARTIFACT)

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
        local mn = (orbs[i].user_data.r + orbs[j].user_data.r)*1.15
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
      for k, ix in ipairs(d.orbs) do
        local m = g.children[ix + 1]
        m.user_data.r = ITM.ORB_SIZES[k] or m.user_data.r or m.scale.x        -- (round 53: one size)
        m.scale:set_scalar(m.user_data.r)
        m.user_data.mark = k - 1; ITM.trace_hook(m, m.material, sun, true); orbs[#orbs + 1] = m
      end
      S.hover = orbs_hover(orbs)
    end
    local c, size = d.box.c, d.box.s
    g.position:sub(Vector3.new(c[1], c[2], c[3]))
    local wrap = T.Group.new(); wrap:add(g)
    S.model = wrap; S.radius = max(size[1], size[2], size[3])*0.55
    S.box = { size[1], size[2], size[3] }
    holder:add(wrap)
    local v = it.view or { 0.55, 0.4, 0.0 }
    S.q:set_from_euler(Euler.new(v[1], v[2], v[3], 'YXZ'))
  end

  local insp = { S = S, scene = scene, camera = camera, holder = holder }
  -- opts.remove: the object is about to be given up; the view asks whether (answer())
  function insp.open(i, opts)
    if i == nil then i = S.idx end
    if S.active then return end
    S.remove = (opts and opts.remove) and true or false
    S.accept = (opts and opts.accept) and true or false
    S.result = nil; S.hot = nil; S.buttons = {}
    local z = (S.remove or S.accept) and 0.85 or 1
    S.active = true; S.t = 0; S.closing = -1; S.idle = 0; S.zoom = z; S.zoom_t = z; S.wv:set(0, 0)
    local hud = R.params.hud; R.params.hud = 0; R.params.world_override = nil; R.render(0); R.params.hud = hud
    back_mat.uniforms.tFrame.value = R.freeze()
    gpu_end()                 -- (rendered outside the frame's draw: hand the 2D pipeline its state back)
    S.saved = { bloom = R.params.bloom.strength }
    build(i)
    AU.play('viewer_open')
  end
  function insp.close() if S.active and S.closing < 0 then S.closing = 0; AU.play('viewer_close') end end
  function insp.next(d)
    if S.remove or S.accept then return end
    local i = S.idx
    local n = #ITEMS
    for _ = 1, n do i = (i + d + n) % n; if ITEMS[i + 1].build then break end end
    build(i); S.t = 0.12; S.idle = 0; S.zoom_t = 1
    AU.play('viewer_next')
  end
  local qa, ax = Quaternion.new(), Vector3.new()
  local function turn(yaw, pitch)
    qa:set_from_axis_angle(ax:set(0, 1, 0), yaw); S.q:premultiply(qa)
    qa:set_from_axis_angle(ax:set(1, 0, 0), pitch); S.q:premultiply(qa)
  end
  -- input (game.lua calls these while the view is up): mouse in game pixels; drag turns as
  -- inspect.js turns by CSS pixels over the canvas height
  local function button_at(x, y)
    for name, b in pairs(S.buttons) do if x >= b[1] and x < b[1] + b[3] and y >= b[2] and y < b[2] + b[4] then return name end end
  end
  -- round 48: the one button, THROW (yes); no = put the view away and keep it
  function insp.answer(yes)
    if not (S.active and S.remove) or S.closing >= 0 then return end
    S.result = yes and 'throw' or 'keep'
    if yes then AU.play('viewer_throw') end
    insp.close()
  end
  function insp.accept()
    if not (S.active and S.accept) or S.closing >= 0 then return end
    S.result = 'accept'
    insp.close()
  end
  function insp.pointer_down(x, y)
    if not S.active then return end
    -- round 51: X closes the view (giving up nothing)
    if button_at(x, y) == 'close' then if S.remove then insp.answer(false) else insp.close() end; return end
    if S.remove then local b = button_at(x, y); if b then insp.answer(b == 'throw'); return end end
    if S.accept then local b = button_at(x, y); if b then insp.accept(); return end end
    S.drag = { x, y }; S.idle = 0
  end
  function insp.pointer_up() S.drag = nil end
  function insp.pointer_move(x, y)
    if S.active then
      local was = S.hot
      S.hot = button_at(x, y)
      if S.hot and S.hot ~= was then AU.play('ui_hover') end
    end
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
    local oy = (S.remove or S.accept) and S.radius*0.42/S.zoom or 0      -- (asking: the object a little higher, the question under it)
    camera.position:set(0, -oy, dist)
    camera.near = dist*0.05; camera.far = dist*6; camera:update_projection_matrix()
    camera:look_at(0, -oy, 0)
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
  -- where the bottom of the object's bounding sphere shows on screen, in HUD pixels, with the object where
  -- it settles once the view has opened (round 55, owner: "The object name text moves vertically depending
  -- on how the object is turned, that shouldn't happen": the sphere is the same whichever way it turns, so
  -- only zooming moves the name; round 51 followed the lowest corner of its turning box)
  local CORNER = Vector3.new()
  local function object_bottom()
    if not (S.model and S.radius) then return nil end
    camera:update_matrix_world()
    CORNER:set(0, S.radius*0.06 - S.radius, 0):project(camera)
    return (0.5 - CORNER.y*0.5)*R.H
  end
  -- round 49 (owner: "I want ONLY [item name] in normal font size, then 'throw'. Nothing else."):
  -- the name, and under it THROW when the view was opened to give it up.
  -- round 51 (owner, 2026-10-06: "Title of object closer to the object itself, throw stays in the same
  -- place, X button visible so it can be clicked to close the model viewer"): the name sits just
  -- under the object (round 55: under its bounding sphere, still while it turns), never into THROW;
  -- THROW where it was; X at the top right
  function insp.draw_hud()
    if not S.active then return end
    local UI = require('port.ui_style')
    local it = ITEMS[S.idx + 1]
    local a = smoothstep(0.15, 0.45, S.t)*(S.closing >= 0 and 1 - smoothstep(0, 0.15, S.closing) or 1)
    if a <= 0 then return end
    HUD.alpha(a)
    local ink = 'rgba(8,6,5,0.9)'
    local h1 = HUD.text_height(1)
    local cx = R.W/2
    local y = R.H - 16
    if S.remove or S.accept then
      local label = S.remove and 'THROW' or 'ACCEPT ARTIFACT'
      local bh = h1 + 8
      local bw = math.max(80, HUD.text_width(label, 1) + 32)
      y = y - bh
      local key = S.remove and 'throw' or 'accept'
      S.buttons[key] = { floor(cx - bw/2), y, bw, bh }
      UI.button(floor(cx - bw/2), y, bw, bh, label, S.hot == key, true)
      y = y - 8
    end
    local lowest = y - h1
    local want = object_bottom()
    want = want and want + 6 or lowest
    want = math.min(lowest, math.max(8, want))
    -- (2026-10-18, the serif) the name as a title, in mixed case (HUD.name_case = 'caps': in spaced capitals like
    -- the buttons)
    local was = HUD.case
    HUD.case = HUD.name_case or 'mixed'
    local name = HUD.case == 'mixed' and it.name:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end) or it.name
    HUD.text(name, cx, floor(want + 0.5), UI.CREAM, 1, 'center', nil, ink)
    HUD.case = was
    -- (round 52, owner: "Make the X on the top right normal size instead of double")
    local xs = HUD.text_height(1) + 14
    S.buttons.close = { R.W - 6 - xs, 6, xs, xs }
    UI.glyph_button(R.W - 6 - xs, 6, xs, xs, 'X', S.hot == 'close', 1)
    HUD.alpha(1)
  end
  -- an icon of object i (px square): the view's own render of it, small, against black, read back
  -- from the final frame (rows bottom-up, as GL keeps them). Call outside a frame's draw.
  function insp.icon(i, px)
    local was_active = S.active
    build(i)
    local v = ITEMS[i + 1].view or { 0.55, 0.4, 0.0 }
    S.q:set_from_euler(Euler.new(v[1], v[2], v[3], 'YXZ'))
    if S.hover then S.hover(1.3) end
    S.active = true; S.t = 1; S.closing = -1; S.remove = false; S.accept = false
    -- (the orbs hover apart and the lens is thin glass: they read better a little larger)
    S.zoom = px*0.86/(2*0.62*R.H/2)*(({ [3] = 1.55, [5] = 1.2 })[i] or 1)
    local BU = back_mat.uniforms
    local tf, black, hud, bloom = BU.tFrame.value, BU.uBlack.value, R.params.hud, R.params.bloom.strength
    BU.tFrame.value = BU.tFrame.value or R.freeze()
    BU.uBlack.value = 1
    R.params.hud = 0
    insp.render_setup()
    BU.uGlow.value = 0.7
    R.render(0)
    local rt = R.targets.rt_final
    local x0, y0 = floor(R.W/2 - px/2), floor(R.H/2 - px/2 + 0.06*0.62*R.H/2*S.zoom + 0.5)
    local bytes = gpu_read(rt.gpu, x0, y0, px, px)
    -- opaque (the final frame's alpha is not the picture's)
    local t = {}
    local A255 = string.char(255)
    for k = 1, #bytes, 4 do t[#t + 1] = bytes:sub(k, k + 2) .. A255 end
    bytes = table.concat(t)
    gpu_end()
    BU.tFrame.value, BU.uBlack.value, R.params.hud, R.params.bloom.strength = tf, black, hud, bloom
    R.params.world_override = nil
    S.active = was_active
    S.zoom = 1
    local tex = gpu_texture(px, px, { format = 'rgba8', min = 'nearest', mag = 'nearest', data = bytes })
    return gpu_texture_image(tex)
  end
  -- round 42 (the icons' sources): object i as icon() frames it, px square, its RGBA bytes (rows
  -- bottom-up) over a black backdrop, or over a flat grey one (grey = true): the two differ only
  -- where the backdrop shows, which gives tools/icons.py each object's cut-out (glass included)
  local grey_tex = nil
  function insp.icon_raw(i, px, grey, empty)
    local was_active = S.active
    build(i)
    holder.visible = not empty                -- empty: the backdrop alone (the cut-out's reference)
    local v = ITEMS[i + 1].view or { 0.55, 0.4, 0.0 }
    S.q:set_from_euler(Euler.new(v[1], v[2], v[3], 'YXZ'))
    if S.hover then S.hover(1.3) end
    S.active = true; S.t = 1; S.closing = -1; S.remove = false; S.accept = false
    S.zoom = px*0.86/(2*0.62*R.H/2)*(({ [3] = 1.55, [5] = 1.2 })[i] or 1)
    local BU = back_mat.uniforms
    local tf, black, hud = BU.tFrame.value, BU.uBlack.value, R.params.hud
    if grey and not grey_tex then
      local g = string.rep(string.char(160, 160, 160, 255), 16)
      grey_tex = T.Texture.new(gpu_texture(4, 4, { format = 'rgba8', min = 'nearest', mag = 'nearest', data = g }), 4, 4)
    end
    BU.tFrame.value = grey and grey_tex or (BU.tFrame.value or R.freeze())
    BU.uBlack.value = grey and 0 or 1
    R.params.hud = 0
    insp.render_setup()
    BU.uGlow.value = 0.7
    R.render(0)
    local rt = R.targets.rt_final
    local x0, y0 = floor(R.W/2 - px/2), floor(R.H/2 - px/2 + 0.06*0.62*R.H/2*S.zoom + 0.5)
    local bytes = gpu_read(rt.gpu, x0, y0, px, px)
    gpu_end()
    BU.tFrame.value, BU.uBlack.value, R.params.hud = tf, black, hud
    R.params.world_override = nil
    holder.visible = true
    S.active = was_active
    S.zoom = 1
    return bytes
  end
  function insp.rebuild() if S.active then local q = S.q:clone(); build(S.idx); S.q:copy(q) end end
  function insp.pose(yaw, pitch, roll, zoom)
    S.q:set_from_euler(Euler.new(pitch, yaw, roll or 0, 'YXZ')); S.zoom = zoom or 1; S.zoom_t = zoom or 1; S.wv:set(0, 0); S.idle = -1e9
  end
  return insp
end

return IN
