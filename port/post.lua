--[[
  post.lua -- the port to Anchor: web/src/render.js. The 640x360 targets and the frame:
    world scene -> rt_world (half float, + depth texture); warp scene -> rt_warp; view scene ->
    rt_view; bright pass -> rt_bloom (160x90) -> separable blur; final pass -> rt_final (8-bit:
    fog, shafts marched through the sun's shadow map, bloom, exposure, soft shoulder, sRGB, grade,
    ordered dither + quantize, the HUD layer composited last). The passes run three.js's own
    compiled programs (post.final / post.bright / post.blur / post.copy), fed the same uniforms.
  rt_final is presented by drawing its texture into an ordinary layer (flipped: GL keeps rows
  bottom-up), so the window scaling and engine_snapshot are Anchor's own.
]]
local TM = require('port.three.math')
local PROF = require('port.prof')       -- (2026-10-15: the benchmark's sections)
local T = require('port.three.core')
local MAT = require('port.three.materials')
local RD = require('port.three.renderer')
local Vector2, Vector3, Vector4, Matrix4, Color = TM.Vector2, TM.Vector3, TM.Vector4, TM.Matrix4, TM.Color

local P = {}
P.W, P.H = 640, 360

function P.create(opts)
  local W, H = P.W, P.H
  local renderer = RD.new({ programs = opts.programs, height = H })
  local R = { renderer = renderer, W = W, H = H }

  local rt_world = RD.RenderTarget.new(W, H, { type = 'half', min_filter = 'nearest', mag_filter = 'nearest', depth_texture = true })
  local rt_view = RD.RenderTarget.new(W, H, { type = 'half', min_filter = 'nearest', mag_filter = 'nearest' })
  local BW, BH = W//4, H//4
  local rt_bloom_a = RD.RenderTarget.new(BW, BH, { type = 'half', min_filter = 'linear', mag_filter = 'linear', depth = false })
  local rt_bloom_b = RD.RenderTarget.new(BW, BH, { type = 'half', min_filter = 'linear', mag_filter = 'linear', depth = false })
  local rt_warp = RD.RenderTarget.new(W, H, { type = 'half', min_filter = 'nearest', mag_filter = 'nearest', depth = false })
  local rt_final = RD.RenderTarget.new(W, H, { type = 'byte', min_filter = 'linear', mag_filter = 'linear', depth = false })
  local rt_freeze = RD.RenderTarget.new(W, H, { type = 'byte', min_filter = 'linear', mag_filter = 'linear', depth = false })
  local rt_comp = RD.RenderTarget.new(W, H, { type = 'byte', min_filter = 'nearest', mag_filter = 'nearest', depth = false })   -- (round 57)
  local rt_prism = RD.RenderTarget.new(W, H, { type = 'half', min_filter = 'nearest', mag_filter = 'nearest', depth = false })  -- (2026-10-16, port/prism.lua)
  -- round 59: the frame small and blurred, for the ending's background
  local rt_sb_a = RD.RenderTarget.new(W//4, H//4, { type = 'byte', min_filter = 'linear', mag_filter = 'linear', depth = false })
  local rt_sb_b = RD.RenderTarget.new(W//4, H//4, { type = 'byte', min_filter = 'linear', mag_filter = 'linear', depth = false })

  local world_scene = T.Scene.new(); world_scene.program_scene = 'world'; world_scene.name = 'world'
  world_scene.background = Color.new(0x9ec3e6)
  local world_camera = T.PerspectiveCamera.new(68, W/H, 0.05, 250)
  world_camera.rotation.order = 'YXZ'
  local view_scene = T.Scene.new(); view_scene.program_scene = 'view'
  local view_camera = T.PerspectiveCamera.new(58, W/H, 0.01, 20)
  local warp_scene = T.Scene.new(); warp_scene.program_scene = 'warp'

  local black = T.Texture.new(gpu_texture(1, 1, { format = 'rgba8', data = string.char(0, 0, 0, 0) }), 1, 1)
  local hud_tex = black                    -- set_hud(layer): the HUD layer's texture

  local params = {
    exposure = 1.0, knee = 0.8, contrast = 1.04, saturation = 1.06,
    lift = { 0.0, 0.0, 0.0 }, gamma = { 1, 1, 1 }, gain = { 1, 1, 1 },
    vignette = 0.18,
    fog = { color = Color.new(0xb8cfe0), near = 10, far = 70, max = 0.45, curve = 1.0, sky = 0.0, base_y = 0, falloff = 0.0, height_mix = 0.0 },
    bloom = { strength = 0.45, threshold = 0.95 },
    dither = 0.3, levels = 64, dither_dark = { -1, 0 },
    flash = { 1, 1, 1, 0 }, hurt = 0, hurt_color = { 0.55, 0.02, 0.02 }, desat = 0, hud = 1,
    upscale = 'sharp',
    sky = { on = false, zenith = { 0.1, 0.3, 0.8 }, horizon = { 0.6, 0.8, 0.95 }, ground = { 0.5, 0.45, 0.4 }, sun_dir = { 0, 1, 0 },
      sun_color = { 8, 7, 5 }, sun_size = 0.9988, halo = { 1, 0.8, 0.5 }, clouds = 0.5, cloud_color = { 1, 1, 1 }, cloud_shade = { 0.7, 0.75, 0.85 } },
    shafts = { on = false, light = nil, color = { 1, 0.85, 0.6 }, density = 0.02, max_dist = 30, steps = 24, phase = 0.5, ambient = 0.1 },
    world_override = nil, warp_view = false,
  }
  R.params = params

  -- the fullscreen triangle
  local tri = T.BufferGeometry.new()
  tri:set_attribute('position', T.BufferAttribute.new({ -1, -1, 0, 3, -1, 0, -1, 3, 0 }, 3))
  tri:set_attribute('uv', T.BufferAttribute.new({ 0, 0, 2, 0, 0, 2 }, 2))
  local pass_scene = T.Scene.new(); pass_scene.program_scene = 'post'
  local pass_cam = T.OrthographicCamera.new(-1, 1, 1, -1, 0, 1)
  local quad = T.Mesh.new(tri, nil)
  quad.frustum_culled = false
  pass_scene:add(quad)

  local U = {
    tWorld = { value = rt_world.texture }, tDepth = { value = rt_world.depth_texture }, tView = { value = rt_view.texture },
    tBloom = { value = black }, tHud = { value = black }, tWarp = { value = rt_warp.texture }, uRes = { value = Vector2.new(W, H) },
    uProjInv = { value = Matrix4.new() }, uCamWorld = { value = Matrix4.new() },
    uFogColor = { value = Color.new() }, uFogNear = { value = 0 }, uFogFar = { value = 1 }, uFogMax = { value = 0 },
    uFogCurve = { value = 1 }, uFogSky = { value = 0 }, uFogBaseY = { value = 0 }, uFogFalloff = { value = 0 }, uFogHeightMix = { value = 0 },
    uBloom = { value = 0 }, uExposure = { value = 1 }, uKnee = { value = 0.8 }, uContrast = { value = 1 }, uSaturation = { value = 1 },
    uVignette = { value = 0 }, uDither = { value = 0 }, uLevels = { value = 0 }, uTime = { value = 0 }, uDitherDark0 = { value = -1 }, uDitherDark1 = { value = 0 },
    uLift = { value = Vector3.new() }, uGamma = { value = Vector3.new(1, 1, 1) }, uGain = { value = Vector3.new(1, 1, 1) },
    uFlash = { value = Vector4.new(0, 0, 0, 0) }, uHurtColor = { value = Vector3.new() }, uHurt = { value = 0 }, uDesat = { value = 0 }, uHud = { value = 1 }, uWarpView = { value = 0 },
    uSkyOn = { value = 0 }, uSunSize = { value = 0.9988 }, uClouds = { value = 0 },
    uZenith = { value = Vector3.new() }, uHorizon = { value = Vector3.new() }, uGroundCol = { value = Vector3.new() },
    uSunDir = { value = Vector3.new(0, 1, 0) }, uSunCol = { value = Vector3.new() }, uHalo = { value = Vector3.new() },
    uCloudCol = { value = Vector3.new() }, uCloudShade = { value = Vector3.new() },
    uShaftStreak = { value = 0 }, uShaftRise = { value = 0 }, uShaftSoft = { value = 0 }, uShaftTop = { value = 30 },
    uShaftOn = { value = 0 }, uShaftDensity = { value = 0 }, uShaftMax = { value = 30 }, uShaftPhase = { value = 0.5 }, uShaftAmb = { value = 0 },
    uShaftCol = { value = Vector3.new() }, uShadowMap = { value = black }, uShadowMat = { value = Matrix4.new() },
  }
  local function mk(name, uniforms)
    return MAT.ShaderMaterial.new({ name = name, uniforms = uniforms, depth_test = false, depth_write = false })
  end
  local final_mat = mk('post.final', U)
  local bright_mat = mk('post.bright', { tWorld = U.tWorld, tView = U.tView, uSrc = { value = Vector2.new(W, H) }, uThreshold = { value = 1 } })
  local blur_mat = mk('post.blur', { tSrc = { value = nil }, uDir = { value = Vector2.new() } })
  local copy_mat = mk('post.copy', { tSrc = { value = rt_final.texture } })
  local comp_mat = mk('sil.comp', { tFinal = { value = rt_final.texture }, tSil = { value = black }, uE = { value = 0 },
    tBlur = { value = rt_sb_a.texture }, uDim = { value = 1 }, uBlur = { value = 0 },   -- (round 57/59)
    uFade = { value = 0 }, uFadeCol = { value = Vector3.new(0, 0, 0) },                    -- (round 62)
    tPrism = { value = black } })                                                          -- (2026-10-16)
  R.hook_uniforms = {}
  function R.rebuild() for k, v in pairs(R.hook_uniforms) do U[k] = v end end

  local function pass(mat, target)
    quad.material = mat
    renderer:set_render_target(target)
    renderer:render(pass_scene, pass_cam)
  end

  function R.freeze() pass(copy_mat, rt_freeze); return rt_freeze.texture end

  local time = 0
  local warp_blank, view_blank = false, false
  function R.render(dt)
    dt = dt or 1/60
    time = time + dt
    local p = params
    local ov = p.world_override
    local ws, wc = ov and ov.scene or world_scene, ov and ov.camera or world_camera
    local lap = PROF.on and perf_time()       -- (2026-10-15: port/prof.lua; the passes, the renderer's own inside them)
    wc:update_matrix_world()
    renderer:set_render_target(rt_world)
    renderer:set_clear_color(ws.background or Color.new(0, 0, 0), 1)
    renderer:render(ws, wc)
    lap = PROF.lap('pass.world', lap)
    -- what bends the light. (2026-10-15, the web's performance: with nothing bending it (warp.lua's R.warp_active) the
    -- target would come out clear: it is cleared once and the render skipped; the viewmodel scene, empty in this game,
    -- the same; ~1.8 ms a frame on the web)
    renderer:set_render_target(rt_warp)
    renderer:set_clear_color(0x000000, 0)
    if ov or (R.warp_active and not R.warp_active()) then
      if not warp_blank then renderer:clear(); warp_blank = true end
    else renderer:render(warp_scene, world_camera); warp_blank = false end
    -- viewmodel
    if #view_scene.children > 0 or not view_blank then
      renderer:set_render_target(rt_view)
      renderer:set_clear_color(0x000000, 0)
      renderer:render(view_scene, view_camera)
      view_blank = #view_scene.children == 0
    end
    lap = PROF.lap('pass.warp+view', lap)
    -- bloom
    local bloom_on = p.bloom.strength > 0
    if bloom_on then
      bright_mat.uniforms.uThreshold.value = p.bloom.threshold
      pass(bright_mat, rt_bloom_a)
      blur_mat.uniforms.tSrc.value = rt_bloom_a.texture; blur_mat.uniforms.uDir.value:set(1/BW, 0); pass(blur_mat, rt_bloom_b)
      blur_mat.uniforms.tSrc.value = rt_bloom_b.texture; blur_mat.uniforms.uDir.value:set(0, 1/BH); pass(blur_mat, rt_bloom_a)
      blur_mat.uniforms.tSrc.value = rt_bloom_a.texture; blur_mat.uniforms.uDir.value:set(2/BW, 0); pass(blur_mat, rt_bloom_b)
      blur_mat.uniforms.tSrc.value = rt_bloom_b.texture; blur_mat.uniforms.uDir.value:set(0, 2/BH); pass(blur_mat, rt_bloom_a)
    end
    -- final
    U.tBloom.value = bloom_on and rt_bloom_a.texture or black
    U.tHud.value = hud_tex
    local sk = p.sky
    U.uSkyOn.value = (sk and sk.on) and 1 or 0
    if sk and sk.on then
      U.uZenith.value:from_array(sk.zenith); U.uHorizon.value:from_array(sk.horizon); U.uGroundCol.value:from_array(sk.ground)
      U.uSunDir.value:from_array(sk.sun_dir):normalize(); U.uSunCol.value:from_array(sk.sun_color); U.uHalo.value:from_array(sk.halo)
      U.uSunSize.value = sk.sun_size; U.uClouds.value = sk.clouds; U.uCloudCol.value:from_array(sk.cloud_color); U.uCloudShade.value:from_array(sk.cloud_shade)
    end
    local sh = p.shafts
    local sl = sh and sh.light
    U.uShaftOn.value = (not ov and sh and sh.on and sl and sl.shadow and sl.shadow.map) and 1 or 0
    if U.uShaftOn.value == 1 then
      U.uShadowMap.value = sl.shadow.map.texture
      U.uShadowMat.value:copy(sl.shadow.matrix)
      U.uShaftDensity.value = sh.density; U.uShaftMax.value = sh.max_dist; U.uShaftPhase.value = sh.phase; U.uShaftAmb.value = sh.ambient
      U.uShaftCol.value:from_array(sh.color)
      U.uShaftStreak.value = sh.streak or 0; U.uShaftRise.value = sh.rise or 0; U.uShaftSoft.value = sh.soft or 0; U.uShaftTop.value = sh.top or 30
      if not (sk and sk.on) then U.uSunDir.value:sub_vectors(sl.position, sl.target.position):normalize() end
    end
    U.uProjInv.value:copy(wc.projection_matrix_inverse)
    U.uCamWorld.value:copy(wc.matrix_world)
    U.uFogColor.value:copy(p.fog.color)
    U.uFogNear.value = p.fog.near; U.uFogFar.value = p.fog.far; U.uFogMax.value = ov and 0 or p.fog.max; U.uFogCurve.value = p.fog.curve
    U.uFogSky.value = p.fog.sky; U.uFogBaseY.value = p.fog.base_y; U.uFogFalloff.value = p.fog.falloff; U.uFogHeightMix.value = p.fog.height_mix
    U.uBloom.value = p.bloom.strength; U.uExposure.value = p.exposure; U.uKnee.value = p.knee
    U.uContrast.value = p.contrast; U.uSaturation.value = p.saturation; U.uVignette.value = p.vignette
    U.uDither.value = p.dither; U.uLevels.value = p.levels; U.uTime.value = time
    U.uDitherDark0.value = p.dither_dark[1]; U.uDitherDark1.value = p.dither_dark[2]
    U.uLift.value:from_array(p.lift); U.uGamma.value:from_array(p.gamma); U.uGain.value:from_array(p.gain)
    U.uFlash.value:from_array(p.flash); U.uHurtColor.value:from_array(p.hurt_color); U.uHurt.value = p.hurt; U.uDesat.value = p.desat
    U.uHud.value = p.hud; U.uWarpView.value = p.warp_view and 1 or 0
    pass(final_mat, rt_final)
    lap = PROF.lap('pass.bloom+final', lap)
    -- round 57 (port/silhouette.lua): toward darkness, the egg and the lich as two flat shapes, by R.sil.e
    R.out = rt_final
    local sl = R.sil
    if sl and sl.e > 0 and not ov then
      sl.render(renderer, wc, R.sil_subjects())
      -- (round 59: the background's blur, from the finished frame at a quarter of its size)
      local bg = sl.BGS[sl.bg]
      if bg.blur > 0 then
        local SW, SH = W//4, H//4
        pass(copy_mat, rt_sb_a)
        blur_mat.uniforms.tSrc.value = rt_sb_a.texture; blur_mat.uniforms.uDir.value:set(1/SW, 0); pass(blur_mat, rt_sb_b)
        blur_mat.uniforms.tSrc.value = rt_sb_b.texture; blur_mat.uniforms.uDir.value:set(0, 1/SH); pass(blur_mat, rt_sb_a)
        blur_mat.uniforms.tSrc.value = rt_sb_a.texture; blur_mat.uniforms.uDir.value:set(2/SW, 0); pass(blur_mat, rt_sb_b)
        blur_mat.uniforms.tSrc.value = rt_sb_b.texture; blur_mat.uniforms.uDir.value:set(0, 2/SH); pass(blur_mat, rt_sb_a)
      end
      comp_mat.uniforms.uDim.value = bg.dim; comp_mat.uniforms.uBlur.value = bg.blur
      comp_mat.uniforms.tSil.value = sl.texture
      comp_mat.uniforms.uE.value = sl.e
      comp_mat.uniforms.uFade.value = sl.fade
      comp_mat.uniforms.uFadeCol.value:set(sl.fade_col[1], sl.fade_col[2], sl.fade_col[3])
      -- (2026-10-16, port/prism.lua: the force he brings down, as glass over the finished frame)
      local pr = R.prism
      if pr and pr.active() then
        renderer:set_render_target(rt_prism)
        renderer:set_clear_color(0x000000, 0)
        renderer:render(pr.scene, wc)
        comp_mat.uniforms.tPrism.value = rt_prism.texture
      else comp_mat.uniforms.tPrism.value = black end
      pass(comp_mat, rt_comp)
      R.out = rt_comp
    end
  end

  -- the HUD layer (the final pass composites it last, as three.js composited its HUD canvas)
  function R.set_hud(layer) hud_tex = T.Texture.new(gpu_layer_texture(layer.handle or layer), W, H) end
  -- rt_final into an ordinary layer, whole-screen (GL rows are bottom-up: drawn flipped)
  local final_image = gpu_texture_image(rt_final.texture.gpu)
  local comp_image = gpu_texture_image(rt_comp.texture.gpu)
  function R.present(layer)
    gpu_end()
    layer_push(layer, W/2, H/2, 0, 1, -1)
    layer_draw_texture(layer, R.out == rt_comp and comp_image or final_image, 0, 0)
    layer_pop(layer)
  end

  function R.set_shadow_light(l) params.shafts.light = l end
  R.world_scene, R.world_camera, R.view_scene, R.view_camera, R.warp_scene = world_scene, world_camera, view_scene, view_camera, warp_scene
  R.targets = { rt_world = rt_world, rt_view = rt_view, rt_final = rt_final, rt_warp = rt_warp, rt_freeze = rt_freeze }
  R.time = function() return time end
  return R
end

return P
