--[[
  physics3 — entity-resolving wrappers for 3D physics queries.

  3D sibling of physics.lua: resolves body handles to entities via
  physics3_get_user_data + entities, and normalizes event ordering so `a`
  always corresponds to the first tag argument. See physics.lua for the full
  rationale. Positions in meters; normals are 3D.

  Usage:
    for _, ev in ipairs(collision3_entities_begin('ball', 'ground')) do
      ev.a:bounced(ev.ny)     -- ev.a always the ball, ev.b the ground entity
    end
]]

local function body3_to_entity(body)
  local id = physics3_get_user_data(body)
  return entities[id]
end

--[[
  query3_entities_sphere(x, y, z, r, tags)
]]
function query3_entities_sphere(x, y, z, r, tags)
  local bodies = physics3_query_sphere(x, y, z, r, tags)
  local result = {}
  for i = 1, #bodies do
    local e = body3_to_entity(bodies[i])
    if e then result[#result + 1] = e end
  end
  return result
end

--[[
  query3_entities_aabb(min_x, min_y, min_z, max_x, max_y, max_z, tags)
]]
function query3_entities_aabb(min_x, min_y, min_z, max_x, max_y, max_z, tags)
  local bodies = physics3_query_aabb(min_x, min_y, min_z, max_x, max_y, max_z, tags)
  local result = {}
  for i = 1, #bodies do
    local e = body3_to_entity(bodies[i])
    if e then result[#result + 1] = e end
  end
  return result
end

--[[
  query3_entities_box(x, y, z, w, h, d, tags)
]]
function query3_entities_box(x, y, z, w, h, d, tags)
  local bodies = physics3_query_box(x, y, z, w, h, d, tags)
  local result = {}
  for i = 1, #bodies do
    local e = body3_to_entity(bodies[i])
    if e then result[#result + 1] = e end
  end
  return result
end

--[[
  raycast3_entity(x1, y1, z1, x2, y2, z2, tags)
  Returns the first entity hit by a ray, plus hit info, or nil.
]]
function raycast3_entity(x1, y1, z1, x2, y2, z2, tags)
  local hit = physics3_raycast(x1, y1, z1, x2, y2, z2, tags)
  if not hit then return nil end
  local e = body3_to_entity(hit.body)
  if not e then return nil end
  return {
    entity = e,
    point_x = hit.point_x, point_y = hit.point_y, point_z = hit.point_z,
    normal_x = hit.normal_x, normal_y = hit.normal_y, normal_z = hit.normal_z,
    fraction = hit.fraction,
  }
end

--[[
  raycast3_entities_all(x1, y1, z1, x2, y2, z2, tags)
]]
function raycast3_entities_all(x1, y1, z1, x2, y2, z2, tags)
  local hits = physics3_raycast_all(x1, y1, z1, x2, y2, z2, tags)
  local result = {}
  for i = 1, #hits do
    local hit = hits[i]
    local e = body3_to_entity(hit.body)
    if e then
      result[#result + 1] = {
        entity = e,
        point_x = hit.point_x, point_y = hit.point_y, point_z = hit.point_z,
        normal_x = hit.normal_x, normal_y = hit.normal_y, normal_z = hit.normal_z,
        fraction = hit.fraction,
      }
    end
  end
  return result
end

--[[
  collision3_entities_begin(tag_a, tag_b)
  Each event: {a, b, x, y, z, nx, ny, nz} with `a` matching tag_a.
]]
function collision3_entities_begin(tag_a, tag_b)
  local events = physics3_get_collision_begin(tag_a, tag_b)
  local result = {}
  for i = 1, #events do
    local ev = events[i]
    local body_a, body_b = ev.body_a, ev.body_b
    if ev.tag_a == tag_b and ev.tag_b == tag_a then
      body_a, body_b = body_b, body_a
    end
    local a = body3_to_entity(body_a)
    local b = body3_to_entity(body_b)
    if a and b then
      result[#result + 1] = {
        a = a, b = b,
        x = ev.point_x, y = ev.point_y, z = ev.point_z,
        nx = ev.normal_x, ny = ev.normal_y, nz = ev.normal_z,
      }
    end
  end
  return result
end

--[[
  collision3_entities_end(tag_a, tag_b)
]]
function collision3_entities_end(tag_a, tag_b)
  local events = physics3_get_collision_end(tag_a, tag_b)
  local result = {}
  for i = 1, #events do
    local ev = events[i]
    local body_a, body_b = ev.body_a, ev.body_b
    if ev.tag_a == tag_b and ev.tag_b == tag_a then
      body_a, body_b = body_b, body_a
    end
    local a = body3_to_entity(body_a)
    local b = body3_to_entity(body_b)
    if a and b then
      result[#result + 1] = {a = a, b = b}
    end
  end
  return result
end

--[[
  sensor3_entities_begin(tag_a, tag_b)
]]
function sensor3_entities_begin(tag_a, tag_b)
  local events = physics3_get_sensor_begin(tag_a, tag_b)
  local result = {}
  for i = 1, #events do
    local ev = events[i]
    local body_a, body_b = ev.sensor_body, ev.visitor_body
    if ev.sensor_tag == tag_b and ev.visitor_tag == tag_a then
      body_a, body_b = body_b, body_a
    end
    local a = body3_to_entity(body_a)
    local b = body3_to_entity(body_b)
    if a and b then
      result[#result + 1] = {a = a, b = b}
    end
  end
  return result
end

--[[
  sensor3_entities_end(tag_a, tag_b)
]]
function sensor3_entities_end(tag_a, tag_b)
  local events = physics3_get_sensor_end(tag_a, tag_b)
  local result = {}
  for i = 1, #events do
    local ev = events[i]
    local body_a, body_b = ev.sensor_body, ev.visitor_body
    if ev.sensor_tag == tag_b and ev.visitor_tag == tag_a then
      body_a, body_b = body_b, body_a
    end
    local a = body3_to_entity(body_a)
    local b = body3_to_entity(body_b)
    if a and b then
      result[#result + 1] = {a = a, b = b}
    end
  end
  return result
end

--[[
  hit3_entities(tag_a, tag_b)
  Hit events with approach_speed (m/s) for impact-scaled effects.
]]
function hit3_entities(tag_a, tag_b)
  local events = physics3_get_hit(tag_a, tag_b)
  local result = {}
  for i = 1, #events do
    local ev = events[i]
    local body_a, body_b = ev.body_a, ev.body_b
    if ev.tag_a == tag_b and ev.tag_b == tag_a then
      body_a, body_b = body_b, body_a
    end
    local a = body3_to_entity(body_a)
    local b = body3_to_entity(body_b)
    if a and b then
      result[#result + 1] = {
        a = a, b = b,
        x = ev.point_x, y = ev.point_y, z = ev.point_z,
        nx = ev.normal_x, ny = ev.normal_y, nz = ev.normal_z,
        approach_speed = ev.approach_speed,
      }
    end
  end
  return result
end
