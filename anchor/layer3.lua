--[[
  layer3 module — procedural API over the engine's 3D scene layer.

  Mirrors layer.lua's shadowing pattern: captures the raw engine bindings
  (first arg = C Layer3 pointer), then replaces the globals with wrappers
  whose first argument is a layer3 state table from layer3_new() (field
  .handle holds the pointer; wrappers also accept a raw handle).

  A layer3 renders flat-shaded 3D primitives into a standard layer's FBO,
  so the result composites like any other layer. The state table exposes
  the backing layer at `.layer` (a raw Layer handle — every layer_* wrapper
  accepts it directly).

  Usage:
    scene = layer3_new('scene')
    layer3_set_background(scene, bg_color())

    -- update():
    camera3_apply(cam, scene)                 -- or layer3_camera(scene, ...)
    layer3_sphere(scene, x, y, z, 0.5, red())
    layer3_box(scene, 0, -0.5, 0, 40, 1, 40, 0, 0, 0, 1, gray())

    -- draw():
    layer3_render(scene)                      -- 3D pass into the FBO
    layer_draw(scene.layer)                   -- composite like any 2D layer

  Colors are packed 0xRRGGBBAA (same as the 2D API — pass color()).
  Rotations are quaternions (x, y, z, w); use math3's quat_* helpers.
]]

-- Raw engine bindings (first arg = C Layer3 pointer). Captured before shadowing.
local eng = {
  create = layer3_create,
  get_layer = layer3_get_layer,
  camera = layer3_camera,
  set_light = layer3_set_light,
  set_shade = layer3_set_shade,
  set_fog = layer3_set_fog,
  set_jitter = layer3_set_jitter,
  set_affine = layer3_set_affine,
  set_alpha_cutoff = layer3_set_alpha_cutoff,
  set_background = layer3_set_background,
  set_sky = layer3_set_sky,
  disable_sky = layer3_disable_sky,
  set_sun = layer3_set_sun,
  set_cull = layer3_set_cull,
  billboard = layer3_billboard,
  mesh = layer3_mesh,
  box = layer3_box,
  sphere = layer3_sphere,
  cylinder = layer3_cylinder,
  capsule = layer3_capsule,
  plane = layer3_plane,
  line = layer3_line,
  render = layer3_render,
  unproject = layer3_unproject,
  debug_draw = layer3_debug_draw,
}

local function l3_handle(l3)
  if type(l3) == 'table' then
    return l3.handle
  end
  return l3
end

--- Create a layer3 state table and optionally register in global `layers`.
--- Optional w/h pin the backing layer to a fixed resolution regardless of
--- window size, and filter 'rough' composites it with nearest sampling —
--- together that's the low-res-upscaled pixel look.
function layer3_new(name, w, h, filter)
  local l3 = {
    name = name,
    handle = eng.create(name, w, h, filter),
  }
  l3.layer = eng.get_layer(l3.handle)   -- backing Layer (raw handle)
  if layers then
    layers[name] = l3
  end
  return l3
end

function layer3_camera(l3, eye_x, eye_y, eye_z, target_x, target_y, target_z, fov, near, far)
  eng.camera(l3_handle(l3), eye_x, eye_y, eye_z, target_x, target_y, target_z, fov, near, far)
end

function layer3_set_light(l3, dir_x, dir_y, dir_z, ambient)
  eng.set_light(l3_handle(l3), dir_x, dir_y, dir_z, ambient)
end

--[[
  Stylised shading, on top of the plain lambert term. All fields optional; every
  one is neutral by default and passing no table resets them, so a layer that
  never calls this renders exactly as it did before the knobs existed.

    wrap        0 = lambert, 1 = half-lambert (soft, no hard terminator)
    bands       <1 = smooth, N = quantise the light into N steps (cel)
    shadow      {r,g,b} the shaded side drifts toward; {1,1,1} = neutral
    rim         fresnel rim strength, with rim_color {r,g,b}
    spec        specular strength, with spec_power for tightness

  Components are 0..1 floats here, NOT the 0-255 that `color` uses — these feed
  the shader directly rather than going through a packed colour.
]]
function layer3_set_shade(l3, cfg)
  eng.set_shade(l3_handle(l3), cfg)
end

--- Linear distance fog, in meters. Match `color` to the layer background so
--- geometry dissolves into the backdrop instead of popping at the far plane —
--- that's what makes fog double as the draw-distance budget. Huge `far` = off.
function layer3_set_fog(l3, color, near, far)
  eng.set_fog(l3_handle(l3), color, near, far)
end

--- PS1 vertex snapping. Vertices quantize to a res_x by res_y grid in NDC;
--- lower = coarser = more visible swim. Start near the console's internal
--- resolution (160x120). Huge values = off.
function layer3_set_jitter(l3, res_x, res_y)
  eng.set_jitter(l3_handle(l3), res_x, res_y)
end

--- Affine texture warping, the PS1's most recognisable artifact. 0 keeps
--- textures perspective-correct, 1 is the full swim across large polygons.
--- Blend to taste — the console had no choice, we do.
function layer3_set_affine(l3, amount)
  eng.set_affine(l3_handle(l3), amount)
end

--- Discard fragments below this alpha. 0 disables the test; ~0.5 is the usual
--- cutout value for foliage, fences and signs. Cutout only — no blending, so
--- no sorting is required.
function layer3_set_alpha_cutoff(l3, cutoff)
  eng.set_alpha_cutoff(l3_handle(l3), cutoff)
end

--- Draw an instance of a custom mesh (see mesh3.lua). Scale and rotation are
--- optional; colour multiplies the texture.
function layer3_mesh(l3, mesh, x, y, z, sx, sy, sz, qx, qy, qz, qw, color)
  eng.mesh(l3_handle(l3), mesh, x, y, z, sx, sy, sz, qx, qy, qz, qw, color)
end

--- Enable the procedural sky and set its three bands. The gradient is driven by
--- a per-pixel view ray, so the horizon stays put as the camera pitches.
--- Match the layer's fog colour to `horizon` so distant geometry dissolves into
--- the sky instead of ending at the far plane.
function layer3_set_sky(l3, zenith, horizon, ground)
  eng.set_sky(l3_handle(l3), zenith, horizon, ground)
end

function layer3_disable_sky(l3)
  eng.disable_sky(l3_handle(l3))
end

--- Sun disc. Direction points TO the sun; higher `sharpness` = smaller disc.
--- The colour is ADDED to the sky, so black means no sun.
function layer3_set_sun(l3, dx, dy, dz, color, sharpness)
  eng.set_sun(l3_handle(l3), dx, dy, dz, color, sharpness)
end

--- Backface culling. Off by default — the built-in primitives have never been
--- rendered with culling enabled, so their winding is unproven.
function layer3_set_cull(l3, enabled)
  eng.set_cull(l3_handle(l3), enabled)
end

--- Camera-facing quad. `blend` is one of:
---   'add'     order-independent, no sorting, no depth write — particles
---   'alpha'   sorted back-to-front automatically, no depth write — clouds
---   'cutout'  alpha-tested and DEPTH-WRITTEN, unsorted — foliage, signs
--- `ylock` spins the quad about world-up only, so it never pitches to face a
--- camera looking down at it. Essential for ground cover in a game where you
--- can fly: a fully camera-facing grass card seen from above is flat paper.
--- The UV rect lets one atlas hold every sprite.
function layer3_billboard(l3, x, y, z, w, h, color, texture, blend, u0, v0, u1, v1, ylock)
  eng.billboard(l3_handle(l3), x, y, z, w, h, color, texture, blend, u0, v0, u1, v1, ylock)
end

function layer3_set_background(l3, color)
  eng.set_background(l3_handle(l3), color)
end

function layer3_box(l3, x, y, z, w, h, d, qx, qy, qz, qw, color)
  eng.box(l3_handle(l3), x, y, z, w, h, d, qx, qy, qz, qw, color)
end

function layer3_sphere(l3, x, y, z, radius, color)
  eng.sphere(l3_handle(l3), x, y, z, radius, color)
end

function layer3_cylinder(l3, x, y, z, height, radius, qx, qy, qz, qw, color)
  eng.cylinder(l3_handle(l3), x, y, z, height, radius, qx, qy, qz, qw, color)
end

function layer3_capsule(l3, x, y, z, height, radius, qx, qy, qz, qw, color)
  eng.capsule(l3_handle(l3), x, y, z, height, radius, qx, qy, qz, qw, color)
end

function layer3_plane(l3, x, y, z, w, d, qx, qy, qz, qw, color)
  eng.plane(l3_handle(l3), x, y, z, w, d, qx, qy, qz, qw, color)
end

function layer3_line(l3, x1, y1, z1, x2, y2, z2, color)
  eng.line(l3_handle(l3), x1, y1, z1, x2, y2, z2, color)
end

--- Run the 3D pass into the backing layer's FBO. Composite with
--- layer_draw(l3.layer) afterwards.
function layer3_render(l3)
  eng.render(l3_handle(l3))
end

function layer3_unproject(l3, screen_x, screen_y)
  return eng.unproject(l3_handle(l3), screen_x, screen_y)
end

--- Queue the Box3D world's debug geometry into this layer3.
--- opts: {shapes=, joints=, contacts=, bounds=}
function layer3_debug_draw(l3, opts)
  eng.debug_draw(l3_handle(l3), opts)
end
