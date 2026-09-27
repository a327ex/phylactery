--[[
  camera — procedural 2D camera with follow, bounds, and integrated shake.

  Usage:
    main_camera = camera_new(width, height)

    -- In update:
    camera_update(main_camera, dt)

    -- In draw:
    camera_attach(main_camera, game_layer)
    layer_circle(game_layer, 100, 100, 20, red())
    -- ... more draws to game_layer
    camera_detach(main_camera, game_layer)

    -- Follow a target:
    camera_follow(main_camera, p1)
    camera_follow(main_camera, p1, 0.9, 0.3)   -- 90% distance in 0.3s
    camera_follow(main_camera, nil)             -- stop following

    -- Bounds:
    camera_set_bounds(main_camera, 0, map_w, 0, map_h)

  Shake is an integrated sub-structure accessible as camera.shake.
  Use the shake_* functions on it:
    shake_push(main_camera.shake, angle, amount)
    shake_shake(main_camera.shake, 10, 0.3)
    shake_trauma(main_camera.shake, 0.5, 0.3)

  Design notes:
    - Camera is not attached to layers automatically. Use camera_attach/detach
      to push/pop transforms onto a layer's stack before/after drawing.
    - follow_target_id is an entity ID (not a direct reference), resolved via
      the entities table each frame. If the target dies, follow stops automatically.
    - For non-entity follow targets (e.g., a raw {x, y} table), follow with a
      direct reference by setting camera.follow_target directly.
]]

--[[
  camera_new([w], [h])
  Creates a new camera. Defaults width and height to global `width`/`height`
  if set (e.g. at framework init time), otherwise to 480x270.
]]
function camera_new(w, h)
  local cw = w or width or 480
  local ch = h or height or 270
  local c = {
    w = cw,
    h = ch,
    x = cw/2,
    y = ch/2,
    rotation = 0,
    zoom = 1,
    mouse = {x = 0, y = 0},
    follow_target = nil,
    follow_target_id = nil,
    follow_lerp = 0.9,
    follow_lerp_time = 0.5,
    follow_lead = 0,
    bounds = nil,
    shake = shake_new(),
  }
  return c
end

--[[
  camera_follow(c, target, [lerp], [lerp_time], [lead])
  Set a target for the camera to follow. Target can be:
    - An entity (has .id field) — stored as ID, resolved each frame
    - A plain table with .x/.y — stored as direct reference
    - nil to stop following
]]
function camera_follow(c, target, lerp, lerp_time, lead)
  if target == nil then
    c.follow_target = nil
    c.follow_target_id = nil
  elseif target.id then
    c.follow_target_id = target.id
    c.follow_target = nil
  else
    c.follow_target = target
    c.follow_target_id = nil
  end
  if lerp then c.follow_lerp = lerp end
  if lerp_time then c.follow_lerp_time = lerp_time end
  if lead then c.follow_lead = lead end
end

--[[
  camera_set_bounds(c, min_x, max_x, min_y, max_y)
  Clamp camera position to these world-space bounds. Pass nil to remove.
]]
function camera_set_bounds(c, min_x, max_x, min_y, max_y)
  if min_x == nil then
    c.bounds = nil
  else
    c.bounds = {min_x = min_x, max_x = max_x, min_y = min_y, max_y = max_y}
  end
end

--[[
  camera_get_effects(c)
  Returns ox, oy, rotation_offset, zoom_offset from shake and other effects.
]]
function camera_get_effects(c)
  return shake_get_effects(c.shake)
end

--[[
  camera_to_world(c, sx, sy)
  Convert screen coordinates to world coordinates.
]]
function camera_to_world(c, sx, sy)
  local ox, oy, r_off, z_off = camera_get_effects(c)
  local cx = c.x + ox
  local cy = c.y + oy
  local rot = c.rotation + r_off
  local zoom = c.zoom*(1 + z_off)

  local x = sx - c.w/2
  local y = sy - c.h/2
  x = x/zoom
  y = y/zoom
  local cos_r = math.cos(-rot)
  local sin_r = math.sin(-rot)
  return x*cos_r - y*sin_r + cx, x*sin_r + y*cos_r + cy
end

--[[
  camera_to_screen(c, wx, wy)
  Convert world coordinates to screen coordinates.
]]
function camera_to_screen(c, wx, wy)
  local ox, oy, r_off, z_off = camera_get_effects(c)
  local cx = c.x + ox
  local cy = c.y + oy
  local rot = c.rotation + r_off
  local zoom = c.zoom*(1 + z_off)

  local x = wx - cx
  local y = wy - cy
  local cos_r = math.cos(rot)
  local sin_r = math.sin(rot)
  return (x*cos_r - y*sin_r)*zoom + c.w/2, (x*sin_r + y*cos_r)*zoom + c.h/2
end

--[[
  camera_attach(c, layer, [parallax_x], [parallax_y])
  Push camera transform onto a layer's matrix stack. Call before drawing to
  that layer. Parallax values < 1 make the layer scroll slower (background);
  parallax = 0 keeps the layer stationary (UI-style fixed background).
]]
function camera_attach(c, layer, parallax_x, parallax_y)
  parallax_x = parallax_x or 1
  parallax_y = parallax_y or 1
  local ox, oy, r_off, z_off = camera_get_effects(c)
  local cx = c.x*parallax_x + ox
  local cy = c.y*parallax_y + oy
  local rot = c.rotation + r_off
  local zoom = c.zoom*(1 + z_off)

  layer_push(layer, c.w/2, c.h/2, rot, zoom, zoom)
  layer_push(layer, -cx, -cy, 0, 1, 1)
end

--[[
  camera_detach(c, layer)
  Pop the camera transform from a layer's matrix stack.
]]
function camera_detach(c, layer)
  layer_pop(layer)
  layer_pop(layer)
end

--[[
  camera_update(c, dt)
  Advances follow, bounds, mouse resolution, and shake.
  Call once per frame per camera.
]]
function camera_update(c, dt)
  -- Resolve follow target: prefer ID-based resolution, fall back to direct ref
  local target = c.follow_target
  if c.follow_target_id then
    target = entities[c.follow_target_id]
    if not target then c.follow_target_id = nil end
  end

  if target then
    local tx = target.x
    local ty = target.y
    if c.follow_lead > 0 and target.collider then
      local vx, vy = target.collider:get_velocity()
      tx = tx + vx*c.follow_lead
      ty = ty + vy*c.follow_lead
    end
    c.x = math.lerp_dt(c.follow_lerp, c.follow_lerp_time, dt, c.x, tx)
    c.y = math.lerp_dt(c.follow_lerp, c.follow_lerp_time, dt, c.y, ty)
  end

  -- Apply bounds
  if c.bounds then
    local half_w = c.w/(2*c.zoom)
    local half_h = c.h/(2*c.zoom)
    c.x = math.clamp(c.x, c.bounds.min_x + half_w, c.bounds.max_x - half_w)
    c.y = math.clamp(c.y, c.bounds.min_y + half_h, c.bounds.max_y - half_h)
  end

  -- Update mouse world position
  local mx, my = mouse_position()
  c.mouse.x, c.mouse.y = camera_to_world(c, mx, my)

  -- Update shake
  shake_update(c.shake, dt)
end
