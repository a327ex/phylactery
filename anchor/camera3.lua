--[[
  camera3 — orbit camera for 3D layers. Procedural module (like camera/timer):
  a plain table created by camera3_new, updated by explicit function calls.

  The camera orbits a target point at a distance, described by yaw (around Y)
  and pitch (elevation). It does NOT read input itself — the game feeds it
  deltas (mouse drag, wheel) and calls camera3_apply each frame:

    cam = camera3_new{distance = 12, pitch = 0.5}

    function update(dt)
      if mouse_is_down(2) then                       -- RMB drag orbits
        local dx, dy = mouse_delta()
        camera3_orbit(cam, dx*0.008, dy*0.008)
      end
      camera3_zoom(cam, -mouse_wheel()*1.5)
      camera3_apply(cam, scene)                      -- sets layer3 view/proj
    end

  camera3_position(cam) returns the current eye point (e.g. for audio or
  distance checks). Target can be moved directly (cam.target_x = ...) or via
  camera3_set_target.
]]

function camera3_new(config)
  config = config or {}
  local cam = {
    target_x = config.target_x or 0,
    target_y = config.target_y or 0,
    target_z = config.target_z or 0,
    yaw = config.yaw or 0.785,          -- radians around Y; 0 looks down -Z
    pitch = config.pitch or 0.5,        -- radians above horizontal
    distance = config.distance or 12,
    fov = config.fov or 60,             -- degrees, vertical
    near = config.near or 0.1,
    far = config.far or 500,
    min_pitch = config.min_pitch or 0.05,
    max_pitch = config.max_pitch or 1.45,
    min_distance = config.min_distance or 2,
    max_distance = config.max_distance or 100,
  }
  return cam
end

function camera3_orbit(cam, dyaw, dpitch)
  cam.yaw = cam.yaw + dyaw
  cam.pitch = cam.pitch + dpitch
  if cam.pitch < cam.min_pitch then cam.pitch = cam.min_pitch end
  if cam.pitch > cam.max_pitch then cam.pitch = cam.max_pitch end
end

function camera3_zoom(cam, ddistance)
  cam.distance = cam.distance + ddistance
  if cam.distance < cam.min_distance then cam.distance = cam.min_distance end
  if cam.distance > cam.max_distance then cam.distance = cam.max_distance end
end

function camera3_set_target(cam, x, y, z)
  cam.target_x, cam.target_y, cam.target_z = x, y, z
end

--[[
  camera3_position(cam)
  Returns the eye point implied by target/yaw/pitch/distance.
]]
function camera3_position(cam)
  local cp = math.cos(cam.pitch)
  local ex = cam.target_x + cam.distance*cp*math.sin(cam.yaw)
  local ey = cam.target_y + cam.distance*math.sin(cam.pitch)
  local ez = cam.target_z + cam.distance*cp*math.cos(cam.yaw)
  return ex, ey, ez
end

--[[
  camera3_apply(cam, l3)
  Pushes the camera's view/projection into a layer3. Call once per frame
  (from update) before queueing 3D draws that depend on picking, or simply
  every frame.
]]
function camera3_apply(cam, l3)
  local ex, ey, ez = camera3_position(cam)
  layer3_camera(l3, ex, ey, ez, cam.target_x, cam.target_y, cam.target_z, cam.fov, cam.near, cam.far)
end

--[[
  camera3_mouse_ray(cam, l3)
  Unprojects the current mouse position through the layer3's camera.
  Returns ox, oy, oz, dx, dy, dz (ray origin + normalized direction).
  camera3_apply must have been called on this layer3 first.
]]
function camera3_mouse_ray(cam, l3)
  local mx, my = mouse_position()
  return layer3_unproject(l3, mx, my)
end
