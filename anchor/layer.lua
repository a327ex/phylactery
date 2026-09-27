--[[
  Layer module — procedural API over the engine layer handle.

  Layers are FBOs that accumulate draw commands during the frame. Commands are
  deferred and processed via layer_render() with GL batching. Composite to the
  screen with layer_draw().

  Usage:
    game_layer = layer_new('game')
    layer_rectangle(game_layer, 100, 100, 50, 30, color)
    layer_render(game_layer)
    layer_draw(game_layer)

  State table shape (from layer_new): { name, handle, parallax_x, parallax_y }
  All layer_* functions below take that table as the first argument `lyr`.

  DRAW ORIGINS (the parameter names say it, the docs repeat it):
    (cx, cy) = CENTER      layer_image / layer_texture / layer_spritesheet /
                           layer_animation / layer_circle / layer_capsule
    (x, y)   = TOP-LEFT    layer_rectangle / layer_rounded_rectangle /
                           layer_text and the gradient rectangles
  The classic bug is subtracting half the size to "center" an image: the
  engine already centers it, so that double-offsets it up-left.

  COLORS: every color parameter accepts either a packed rgba integer (what the
  engine wants) or a Color table (color.lua) — the wrappers pack a table by
  calling it, so `white` and `white()` both work.

  ---------------------------------------------------------------------------
  ENGINE NAME CONFLICTS (Lua globals registered by anchor.c)

  The C engine binds the same symbol names to raw engine implementations whose
  first argument is a C layer pointer (lightuserdata), e.g. layer_rectangle(ptr, ...).

  This file captures those implementations in `eng` at load time, then REPLACES
  the globals with wrappers whose first argument is a layer state table from
  layer_new() (field .handle holds the pointer). Wrappers also accept a raw
  handle for occasional interop. (Since 2026-09-05 the raw C bindings resolve a
  table's .handle themselves too, so an unshadowed binding reached with a layer
  table raises a Lua error instead of crashing the process.)

  After require('anchor.layer'), direct engine-style calls like
  layer_rectangle(userdata_ptr, x, y, w, h, c) no longer use the C binding
  unless you passed a lightuserdata: the wrapper treats a non-table first arg
  as a raw handle (see lyr_handle).

  Shadowed globals: layer_rectangle, layer_circle, layer_line, layer_render,
  layer_draw, layer_push, layer_pop, layer_clear, layer_get_texture, and every
  other layer_* wrapper defined below. layer_create is NOT shadowed — use
  layer_new() from game code.
  ---------------------------------------------------------------------------
]]

---@class Layer
---@field name string
---@field handle lightuserdata   the engine layer pointer
---@field filter string|nil      'rough' | 'smooth' | nil (engine default)
---@field parallax_x number
---@field parallax_y number

---@alias ColorArg integer|Color   packed rgba integer, or a Color table (packed by the wrapper)

-- Raw engine bindings (first arg = C layer pointer). Captured before we shadow globals.
-- Typed loosely on purpose: after this file loads, the global names resolve
-- to the WRAPPERS below, so a static checker would otherwise type these raw
-- C entry points with the wrappers' Layer-table signatures.
---@type table<string, function>
local eng = {
  create = layer_create,
  rectangle = layer_rectangle,
  circle = layer_circle,
  rectangle_line = layer_rectangle_line,
  circle_line = layer_circle_line,
  line = layer_line,
  capsule = layer_capsule,
  capsule_line = layer_capsule_line,
  triangle = layer_triangle,
  triangle_line = layer_triangle_line,
  polygon = layer_polygon,
  polygon_line = layer_polygon_line,
  rounded_rectangle = layer_rounded_rectangle,
  rounded_rectangle_line = layer_rounded_rectangle_line,
  rectangle_gradient_h = layer_rectangle_gradient_h,
  rectangle_gradient_v = layer_rectangle_gradient_v,
  draw_texture = layer_draw_texture,
  draw_spritesheet_frame = layer_draw_spritesheet_frame,
  draw_text = layer_draw_text,
  push = layer_push,
  pop = layer_pop,
  set_blend_mode = layer_set_blend_mode,
  draw = layer_draw,
  apply_shader = layer_apply_shader,
  shader_set_float = layer_shader_set_float,
  shader_set_vec2 = layer_shader_set_vec2,
  shader_set_vec4 = layer_shader_set_vec4,
  shader_set_int = layer_shader_set_int,
  shader_set_texture = layer_shader_set_texture,
  get_texture = layer_get_texture,
  reset_effects = layer_reset_effects,
  clear = layer_clear,
  render = layer_render,
  draw_from = layer_draw_from,
  stencil_mask = layer_stencil_mask,
  stencil_test = layer_stencil_test,
  stencil_test_inverse = layer_stencil_test_inverse,
  stencil_off = layer_stencil_off,
}

--- Resolve layer state table or raw C handle (lightuserdata) for engine calls.
---@param lyr Layer|lightuserdata
---@return lightuserdata
local function lyr_handle(lyr)
  if type(lyr) == 'table' then
    return lyr.handle
  end
  return lyr --[[@as lightuserdata]]
end

--- Pack a color argument: a Color table is called (its __call packs rgba), a
--- packed integer passes through, nil stays nil for `or default` at the call.
---@param c ColorArg|nil
---@return integer|nil
local function col(c)
  if type(c) == 'table' then return c() end
  return c --[[@as integer|nil]]
end

--- Create a layer state table and optionally register in global `layers`.
--- `filter` is optional: 'smooth' (antialiased edges, linear sampling) or
--- 'rough' (hard edges, nearest sampling). Defaults to the engine's current
--- global filter mode, which is 'rough' unless changed via set_filter_mode.
--- `w`, `h` are optional: a fixed-size layer that keeps its resolution
--- regardless of window/canvas resizes (the C binding already supported this
--- for embedded games; needed e.g. for window-resolution post-process passes).
---@param name string
---@param filter? string   'rough' | 'smooth'
---@param w? integer
---@param h? integer
---@return Layer
function layer_new(name, filter, w, h)
  local lyr = {
    name = name,
    handle = eng.create(name, filter, w, h),
    filter = filter,
    parallax_x = 1,
    parallax_y = 1,
  }
  if layers then
    layers[name] = lyr
  end
  return lyr
end

--- Filled rectangle. (x, y) is the TOP-LEFT corner.
---@param lyr Layer
---@param x number
---@param y number
---@param w number
---@param h number
---@param color ColorArg
function layer_rectangle(lyr, x, y, w, h, color)
  eng.rectangle(lyr_handle(lyr), x, y, w, h, col(color))
end

--- Filled circle. (cx, cy) is the CENTER.
---@param lyr Layer
---@param cx number
---@param cy number
---@param radius number
---@param color ColorArg
function layer_circle(lyr, cx, cy, radius, color)
  eng.circle(lyr_handle(lyr), cx, cy, radius, col(color))
end

--- Rectangle outline. (x, y) is the TOP-LEFT corner.
---@param lyr Layer
---@param x number
---@param y number
---@param w number
---@param h number
---@param color ColorArg
---@param line_width? number   default 1
function layer_rectangle_line(lyr, x, y, w, h, color, line_width)
  eng.rectangle_line(lyr_handle(lyr), x, y, w, h, col(color), line_width or 1)
end

--- Circle outline. (cx, cy) is the CENTER.
---@param lyr Layer
---@param cx number
---@param cy number
---@param radius number
---@param color ColorArg
---@param line_width? number   default 1
function layer_circle_line(lyr, cx, cy, radius, color, line_width)
  eng.circle_line(lyr_handle(lyr), cx, cy, radius, col(color), line_width or 1)
end

--- Line segment of the given width.
---@param lyr Layer
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param width number
---@param color ColorArg
function layer_line(lyr, x1, y1, x2, y2, width, color)
  eng.line(lyr_handle(lyr), x1, y1, x2, y2, width, col(color))
end

--- Filled capsule: the segment (x1,y1)-(x2,y2) with round caps of `radius`.
---@param lyr Layer
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param radius number
---@param color ColorArg
function layer_capsule(lyr, x1, y1, x2, y2, radius, color)
  eng.capsule(lyr_handle(lyr), x1, y1, x2, y2, radius, col(color))
end

--- Capsule outline.
---@param lyr Layer
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param radius number
---@param color ColorArg
---@param line_width? number   default 1
function layer_capsule_line(lyr, x1, y1, x2, y2, radius, color, line_width)
  eng.capsule_line(lyr_handle(lyr), x1, y1, x2, y2, radius, col(color), line_width or 1)
end

--- Filled triangle.
---@param lyr Layer
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param x3 number
---@param y3 number
---@param color ColorArg
function layer_triangle(lyr, x1, y1, x2, y2, x3, y3, color)
  eng.triangle(lyr_handle(lyr), x1, y1, x2, y2, x3, y3, col(color))
end

--- Triangle outline.
---@param lyr Layer
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param x3 number
---@param y3 number
---@param color ColorArg
---@param line_width? number   default 1
function layer_triangle_line(lyr, x1, y1, x2, y2, x3, y3, color, line_width)
  eng.triangle_line(lyr_handle(lyr), x1, y1, x2, y2, x3, y3, col(color), line_width or 1)
end

--- Filled polygon from a flat vertex list {x1, y1, x2, y2, ...}.
---@param lyr Layer
---@param vertices number[]
---@param color ColorArg
function layer_polygon(lyr, vertices, color)
  eng.polygon(lyr_handle(lyr), vertices, col(color))
end

--- Polygon outline from a flat vertex list.
---@param lyr Layer
---@param vertices number[]
---@param color ColorArg
---@param line_width? number   default 1
function layer_polygon_line(lyr, vertices, color, line_width)
  eng.polygon_line(lyr_handle(lyr), vertices, col(color), line_width or 1)
end

--- Filled rounded rectangle. (x, y) is the TOP-LEFT corner.
---@param lyr Layer
---@param x number
---@param y number
---@param w number
---@param h number
---@param radius number   corner radius
---@param color ColorArg
function layer_rounded_rectangle(lyr, x, y, w, h, radius, color)
  eng.rounded_rectangle(lyr_handle(lyr), x, y, w, h, radius, col(color))
end

--- Rounded rectangle outline. (x, y) is the TOP-LEFT corner.
---@param lyr Layer
---@param x number
---@param y number
---@param w number
---@param h number
---@param radius number
---@param color ColorArg
---@param line_width? number   default 1
function layer_rounded_rectangle_line(lyr, x, y, w, h, radius, color, line_width)
  eng.rounded_rectangle_line(lyr_handle(lyr), x, y, w, h, radius, col(color), line_width or 1)
end

--- Horizontal gradient rectangle (color1 at the left edge, color2 at the right). TOP-LEFT origin.
---@param lyr Layer
---@param x number
---@param y number
---@param w number
---@param h number
---@param color1 ColorArg
---@param color2 ColorArg
function layer_rectangle_gradient_h(lyr, x, y, w, h, color1, color2)
  eng.rectangle_gradient_h(lyr_handle(lyr), x, y, w, h, col(color1), col(color2))
end

--- Vertical gradient rectangle (color1 at the top edge, color2 at the bottom). TOP-LEFT origin.
---@param lyr Layer
---@param x number
---@param y number
---@param w number
---@param h number
---@param color1 ColorArg
---@param color2 ColorArg
function layer_rectangle_gradient_v(lyr, x, y, w, h, color1, color2)
  eng.rectangle_gradient_v(lyr_handle(lyr), x, y, w, h, col(color1), col(color2))
end

--- Draw an image (image.lua object with .handle) with its CENTER at (cx, cy).
---@param lyr Layer
---@param img Image
---@param cx number
---@param cy number
---@param color? ColorArg   tint, default opaque white
---@param flash? number|false   0-1 white-flash amount (false = none), default 0
function layer_image(lyr, img, cx, cy, color, flash)
  eng.draw_texture(lyr_handle(lyr), img.handle, cx, cy, col(color) or 0xFFFFFFFF, flash or 0)
end

--- Draw a raw texture handle with its CENTER at (cx, cy).
---@param lyr Layer
---@param tex lightuserdata
---@param cx number
---@param cy number
---@param color? ColorArg   tint, default opaque white
function layer_texture(lyr, tex, cx, cy, color)
  eng.draw_texture(lyr_handle(lyr), tex, cx, cy, col(color) or 0xFFFFFFFF, 0)
end

--- Draw one spritesheet frame with its CENTER at (cx, cy).
---@param lyr Layer
---@param sheet Spritesheet
---@param frame integer
---@param cx number
---@param cy number
---@param color? ColorArg
---@param flash? number|false
function layer_spritesheet(lyr, sheet, frame, cx, cy, color, flash)
  eng.draw_spritesheet_frame(lyr_handle(lyr), sheet.handle, frame, cx, cy, col(color) or 0xFFFFFFFF, flash or 0)
end

--- Draw an animation object's current frame with its CENTER at (cx, cy).
---@param lyr Layer
---@param animation_object Animation
---@param cx number
---@param cy number
---@param color? ColorArg
---@param flash? number|false
function layer_animation(lyr, animation_object, cx, cy, color, flash)
  eng.draw_spritesheet_frame(
    lyr_handle(lyr),
    animation_object.spritesheet.handle,
    animation_object.frame,
    cx, cy,
    col(color) or 0xFFFFFFFF,
    flash or 0
  )
end

--- Draw text with its TOP-LEFT at (x, y). `f` is a font object or a font name.
---@param lyr Layer
---@param text string
---@param f Font|string
---@param x number
---@param y number
---@param color ColorArg
function layer_text(lyr, text, f, x, y, color)
  local font_name = type(f) == 'string' and f or f.name
  eng.draw_text(lyr_handle(lyr), text, font_name, x, y, col(color))
end

--- Push a transform (translate, rotate, scale) for subsequent draws on this layer.
---@param lyr Layer
---@param x number
---@param y number
---@param r? number    radians
---@param sx? number
---@param sy? number
function layer_push(lyr, x, y, r, sx, sy)
  eng.push(lyr_handle(lyr), x, y, r, sx, sy)
end

--- Pop the last pushed transform.
---@param lyr Layer
function layer_pop(lyr)
  eng.pop(lyr_handle(lyr))
end

--- Set the blend mode for subsequent draws ('alpha' | 'add' | ...).
---@param lyr Layer
---@param mode string
function layer_set_blend_mode(lyr, mode)
  eng.set_blend_mode(lyr_handle(lyr), mode)
end

--- Queue this layer for compositing to the screen (after layer_render).
---@param lyr Layer
---@param x? number   default 0
---@param y? number   default 0
function layer_draw(lyr, x, y)
  eng.draw(lyr_handle(lyr), x or 0, y or 0)
end

--- Queue a post-process pass; runs when this layer's layer_render executes.
---@param lyr Layer
---@param shader integer
function layer_apply_shader(lyr, shader)
  eng.apply_shader(lyr_handle(lyr), shader)
end

---@param lyr Layer
---@param shader integer
---@param name string
---@param value number
function layer_shader_set_float(lyr, shader, name, value)
  eng.shader_set_float(lyr_handle(lyr), shader, name, value)
end

---@param lyr Layer
---@param shader integer
---@param name string
---@param x number
---@param y number
function layer_shader_set_vec2(lyr, shader, name, x, y)
  eng.shader_set_vec2(lyr_handle(lyr), shader, name, x, y)
end

---@param lyr Layer
---@param shader integer
---@param name string
---@param x number
---@param y number
---@param z number
---@param w number
function layer_shader_set_vec4(lyr, shader, name, x, y, z, w)
  eng.shader_set_vec4(lyr_handle(lyr), shader, name, x, y, z, w)
end

---@param lyr Layer
---@param shader integer
---@param name string
---@param value integer
function layer_shader_set_int(lyr, shader, name, value)
  eng.shader_set_int(lyr_handle(lyr), shader, name, value)
end

--- Bind an auxiliary sampler for the shader (unit >= 2 survives the frame's draws).
---@param lyr Layer
---@param shader integer
---@param name string
---@param texture_id integer|lightuserdata
---@param unit? integer   default 1
function layer_shader_set_texture(lyr, shader, name, texture_id, unit)
  eng.shader_set_texture(lyr_handle(lyr), shader, name, texture_id, unit or 1)
end

--- The layer's current color texture id (a GL texture, usable as a sampler source).
---@param lyr Layer
---@return integer
function layer_get_texture(lyr)
  return eng.get_texture(lyr_handle(lyr))
end

--- Reset the ping-pong effect swap; call at the top of draw() when using apply_shader.
---@param lyr Layer
function layer_reset_effects(lyr)
  eng.reset_effects(lyr_handle(lyr))
end

--- Immediate clear of the layer's FBO.
---@param lyr Layer
function layer_clear(lyr)
  eng.clear(lyr_handle(lyr))
end

--- Process queued draw commands into this layer's FBO.
--- `clear` is optional (default true): pass false for a second render pass in
--- the same frame — processes newly queued commands ON TOP of the existing FBO
--- contents instead of clearing first (e.g. applying a post-process shader to
--- content deposited by layer_draw_from).
---@param lyr Layer
---@param clear? boolean   default true
function layer_render(lyr, clear)
  eng.render(lyr_handle(lyr), clear)
end

--- Immediately draw another layer's texture into this one (optionally through a shader).
---@param lyr Layer
---@param source Layer
---@param shader? integer
function layer_draw_from(lyr, source, shader)
  eng.draw_from(lyr_handle(lyr), lyr_handle(source), shader)
end

---@param lyr Layer
function layer_stencil_mask(lyr)
  eng.stencil_mask(lyr_handle(lyr))
end

---@param lyr Layer
function layer_stencil_test(lyr)
  eng.stencil_test(lyr_handle(lyr))
end

---@param lyr Layer
function layer_stencil_test_inverse(lyr)
  eng.stencil_test_inverse(lyr_handle(lyr))
end

---@param lyr Layer
function layer_stencil_off(lyr)
  eng.stencil_off(lyr_handle(lyr))
end
