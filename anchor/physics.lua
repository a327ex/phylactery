--[[
  physics — entity-resolving wrappers for physics queries.

  The C engine's physics_query_* and physics_get_*_begin/end functions return
  raw body handles with tag names. These framework helpers:
    1. Resolve bodies to their owning entities via physics_get_user_data + entities
    2. Normalize event ordering so `a` always corresponds to the first tag
       argument in the query and `b` to the second

  The normalization matters because the engine's `tags_match` is order-
  insensitive, so a query like `collision_entities_begin('player', 'enemy')`
  could receive events where the collision was recorded as
  `tag_a='enemy', tag_b='player'`. Without normalization, you'd get `ev.a`
  being the enemy when you expected the player. These helpers check the
  tag names and swap if needed so `ev.a` is always the first-tag entity.

  Usage:
    for _, ev in ipairs(collision_entities_begin('player', 'enemy')) do
      ev.a:hit(1)   -- always the player (first query tag)
      -- ev.b        -- always the enemy (second query tag)
    end

    for _, ev in ipairs(sensor_entities_begin('bullet', 'enemy')) do
      ev.a:kill()   -- the bullet
      ev.b:hit(1)   -- the enemy
    end
]]

---@alias Entity table   a game entity registered in the global `entities` table by id

---@class RaycastHit
---@field entity Entity
---@field point_x number
---@field point_y number
---@field normal_x number
---@field normal_y number
---@field fraction number   0-1 along the ray

---@class CollisionEvent
---@field a Entity   matches the first query tag
---@field b Entity   matches the second query tag
---@field x number|nil
---@field y number|nil
---@field nx number|nil
---@field ny number|nil

---@class HitEvent : CollisionEvent
---@field approach_speed number

-- Internal: resolve a body handle to its owning entity via user_data.
local function body_to_entity(body)
  local id = physics_get_user_data(body)
  return entities[id]
end

--[[
  query_entities_circle(x, y, r, tags)
  Returns a table of entities whose colliders intersect the given circle.
]]
---@param x number
---@param y number
---@param r number
---@param tags string[]   required: the C query rejects nil
---@return Entity[]
function query_entities_circle(x, y, r, tags)
  local bodies = physics_query_circle(x, y, r, tags)
  local result = {}
  for i = 1, #bodies do
    local e = body_to_entity(bodies[i])
    if e then result[#result + 1] = e end
  end
  return result
end

--[[
  query_entities_box(x, y, w, h, angle, tags)
]]
---@param x number
---@param y number
---@param w number
---@param h number
---@param angle number   radians
---@param tags string[]   required: the C query rejects nil
---@return Entity[]
function query_entities_box(x, y, w, h, angle, tags)
  local bodies = physics_query_box(x, y, w, h, angle, tags)
  local result = {}
  for i = 1, #bodies do
    local e = body_to_entity(bodies[i])
    if e then result[#result + 1] = e end
  end
  return result
end

--[[
  query_entities_aabb(x, y, w, h, tags)
]]
---@param x number
---@param y number
---@param w number
---@param h number
---@param tags string[]   required: the C query rejects nil
---@return Entity[]
function query_entities_aabb(x, y, w, h, tags)
  local bodies = physics_query_aabb(x, y, w, h, tags)
  local result = {}
  for i = 1, #bodies do
    local e = body_to_entity(bodies[i])
    if e then result[#result + 1] = e end
  end
  return result
end

--[[
  query_entities_point(x, y, tags)
]]
---@param x number
---@param y number
---@param tags string[]   required: the C query rejects nil
---@return Entity[]
function query_entities_point(x, y, tags)
  local bodies = physics_query_point(x, y, tags)
  local result = {}
  for i = 1, #bodies do
    local e = body_to_entity(bodies[i])
    if e then result[#result + 1] = e end
  end
  return result
end

--[[
  raycast_entity(x1, y1, x2, y2, tags)
  Returns the first entity hit by a ray, plus hit info, or nil.
]]
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param tags string[]   required: the C query rejects nil
---@return RaycastHit|nil
function raycast_entity(x1, y1, x2, y2, tags)
  local hit = physics_raycast(x1, y1, x2, y2, tags)
  if not hit then return nil end
  local e = body_to_entity(hit.body)
  if not e then return nil end
  return {
    entity = e,
    point_x = hit.point_x,
    point_y = hit.point_y,
    normal_x = hit.normal_x,
    normal_y = hit.normal_y,
    fraction = hit.fraction,
  }
end

--[[
  raycast_entities_all(x1, y1, x2, y2, tags)
  Returns a table of all entities hit by a ray, each with hit info.
]]
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param tags string[]   required: the C query rejects nil
---@return RaycastHit[]
function raycast_entities_all(x1, y1, x2, y2, tags)
  local hits = physics_raycast_all(x1, y1, x2, y2, tags)
  local result = {}
  for i = 1, #hits do
    local hit = hits[i]
    local e = body_to_entity(hit.body)
    if e then
      result[#result + 1] = {
        entity = e,
        point_x = hit.point_x,
        point_y = hit.point_y,
        normal_x = hit.normal_x,
        normal_y = hit.normal_y,
        fraction = hit.fraction,
      }
    end
  end
  return result
end

--[[
  collision_entities_begin(tag_a, tag_b)
  Returns a table of collision-begin events between tagged entities.
  Each event: {a = entity matching tag_a, b = entity matching tag_b,
               x, y, nx, ny}
]]
---@param tag_a string
---@param tag_b string
---@return CollisionEvent[]
function collision_entities_begin(tag_a, tag_b)
  local events = physics_get_collision_begin(tag_a, tag_b)
  local result = {}
  for i = 1, #events do
    local ev = events[i]
    local body_a, body_b = ev.body_a, ev.body_b
    -- Normalize: ensure body_a corresponds to tag_a
    if ev.tag_a == tag_b and ev.tag_b == tag_a then
      body_a, body_b = body_b, body_a
    end
    local a = body_to_entity(body_a)
    local b = body_to_entity(body_b)
    if a and b then
      result[#result + 1] = {
        a = a, b = b,
        x = ev.point_x, y = ev.point_y,
        nx = ev.normal_x, ny = ev.normal_y,
      }
    end
  end
  return result
end

--[[
  collision_entities_end(tag_a, tag_b)
  Returns a table of collision-end events (same normalization).
]]
---@param tag_a string
---@param tag_b string
---@return CollisionEvent[]
function collision_entities_end(tag_a, tag_b)
  local events = physics_get_collision_end(tag_a, tag_b)
  local result = {}
  for i = 1, #events do
    local ev = events[i]
    local body_a, body_b = ev.body_a, ev.body_b
    if ev.tag_a == tag_b and ev.tag_b == tag_a then
      body_a, body_b = body_b, body_a
    end
    local a = body_to_entity(body_a)
    local b = body_to_entity(body_b)
    if a and b then
      result[#result + 1] = {a = a, b = b}
    end
  end
  return result
end

--[[
  sensor_entities_begin(tag_a, tag_b)
  Returns a table of sensor-begin events with normalized ordering so `a`
  corresponds to the first tag argument (typically the sensor) and `b`
  to the second tag argument (typically the visitor).
]]
---@param tag_a string
---@param tag_b string
---@return CollisionEvent[]
function sensor_entities_begin(tag_a, tag_b)
  local events = physics_get_sensor_begin(tag_a, tag_b)
  local result = {}
  for i = 1, #events do
    local ev = events[i]
    local body_a, body_b = ev.sensor_body, ev.visitor_body
    -- Normalize: if sensor_tag is actually the second query tag, swap
    if ev.sensor_tag == tag_b and ev.visitor_tag == tag_a then
      body_a, body_b = body_b, body_a
    end
    local a = body_to_entity(body_a)
    local b = body_to_entity(body_b)
    if a and b then
      result[#result + 1] = {a = a, b = b}
    end
  end
  return result
end

--[[
  sensor_entities_end(tag_a, tag_b)
]]
---@param tag_a string
---@param tag_b string
---@return CollisionEvent[]
function sensor_entities_end(tag_a, tag_b)
  local events = physics_get_sensor_end(tag_a, tag_b)
  local result = {}
  for i = 1, #events do
    local ev = events[i]
    local body_a, body_b = ev.sensor_body, ev.visitor_body
    if ev.sensor_tag == tag_b and ev.visitor_tag == tag_a then
      body_a, body_b = body_b, body_a
    end
    local a = body_to_entity(body_a)
    local b = body_to_entity(body_b)
    if a and b then
      result[#result + 1] = {a = a, b = b}
    end
  end
  return result
end

--[[
  hit_entities(tag_a, tag_b)
  Returns hit events with approach speed for impact-based damage scaling.
  Normalized so `a` matches the first tag argument.
]]
---@param tag_a string
---@param tag_b string
---@return HitEvent[]
function hit_entities(tag_a, tag_b)
  local events = physics_get_hit(tag_a, tag_b)
  local result = {}
  for i = 1, #events do
    local ev = events[i]
    local body_a, body_b = ev.body_a, ev.body_b
    if ev.tag_a == tag_b and ev.tag_b == tag_a then
      body_a, body_b = body_b, body_a
    end
    local a = body_to_entity(body_a)
    local b = body_to_entity(body_b)
    if a and b then
      result[#result + 1] = {
        a = a, b = b,
        x = ev.point_x, y = ev.point_y,
        nx = ev.normal_x, ny = ev.normal_y,
        approach_speed = ev.approach_speed,
      }
    end
  end
  return result
end
