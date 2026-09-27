--[[
  collider — thin wrapper around a Box2D physics body + shape.

  Stays as a class (with :method syntax) because:
    1. It bundles body + shape + tag into one object
    2. Steering behaviors logically operate on the collider, not a bare body
    3. Multiple method calls per entity per frame — call site ergonomics matter

  Usage:
    function seeker:new(x, y, args)
      self.x = x
      self.y = y
      make_entity(self)                                        -- must be before collider
      self.collider = collider(self, 'enemy', 'dynamic', 'box', 14, 6)
      self.collider:set_position(x, y)
    end

    function seeker:update(dt)
      -- sync position from physics body to self.x/self.y
      self.x, self.y = self.collider:get_position()
      -- or call self.collider:sync() which does it for you
    end

    function seeker:destroy()
      self.collider:destroy()
    end

  The collider stores a back-reference to its owner (`self.owner`) set at
  creation. The physics body's user_data is set to owner.id, so physics
  queries can resolve bodies back to entities via entities[user_data].
]]

collider = class()

function collider:new(owner, tag, body_type, shape_type, ...)
  self.owner = owner
  self.tag = tag
  self.body_type = body_type
  self.shape_type = shape_type
  self.body = physics_create_body(body_type, 0, 0)

  -- Set user_data to the owner's ID so physics queries resolve via entities[id]
  if owner and owner.id then
    physics_set_user_data(self.body, owner.id)
  end

  -- Add initial shape based on shape_type
  -- Last arg can be an opts table (e.g. {sensor = true})
  local shape_args = {...}
  if shape_type == 'chain' then
    self.chain = physics_add_chain(self.body, tag, shape_args[1], shape_args[2] or true)
  else
    local opts = {}
    if type(shape_args[#shape_args]) == 'table' then
      opts = table.remove(shape_args)
    end
    if shape_type == 'circle' then
      self.shape = physics_add_circle(self.body, tag, shape_args[1], opts)
    elseif shape_type == 'box' then
      self.shape = physics_add_box(self.body, tag, shape_args[1], shape_args[2], opts)
    elseif shape_type == 'capsule' then
      self.shape = physics_add_capsule(self.body, tag, shape_args[1], shape_args[2], opts)
    elseif shape_type == 'polygon' then
      self.shape = physics_add_polygon(self.body, tag, shape_args[1], opts)
    end
  end
end

--[[
  collider:destroy()
  Destroys the physics body. Call from the owner's destroy method.
]]
function collider:destroy()
  if self.body then
    physics_destroy_body(self.body)
    self.body = nil
  end
end

--[[
  collider:sync()
  Copies the body's position to owner.x/y. Convenience for entities that
  want their logical position to track the physics position each frame.
]]
function collider:sync()
  if self.owner and self.body then
    self.owner.x, self.owner.y = physics_get_position(self.body)
  end
end

-- Position
function collider:get_position() return physics_get_position(self.body) end
function collider:set_position(x, y) physics_set_position(self.body, x, y) end
function collider:get_angle() return physics_get_angle(self.body) end
function collider:set_angle(angle) physics_set_angle(self.body, angle) end

-- Velocity
function collider:get_velocity() return physics_get_velocity(self.body) end
function collider:set_velocity(vx, vy) physics_set_velocity(self.body, vx, vy) end
function collider:get_angular_velocity() return physics_get_angular_velocity(self.body) end
function collider:set_angular_velocity(av) physics_set_angular_velocity(self.body, av) end

-- Forces & impulses
function collider:apply_force(fx, fy) physics_apply_force(self.body, fx, fy) end
function collider:apply_force_at(fx, fy, px, py) physics_apply_force_at(self.body, fx, fy, px, py) end
function collider:apply_impulse(ix, iy) physics_apply_impulse(self.body, ix, iy) end
function collider:apply_impulse_at(ix, iy, px, py) physics_apply_impulse_at(self.body, ix, iy, px, py) end
function collider:apply_torque(torque) physics_apply_torque(self.body, torque) end
function collider:apply_angular_impulse(impulse) physics_apply_angular_impulse(self.body, impulse) end

-- Body properties
function collider:set_linear_damping(damping) physics_set_linear_damping(self.body, damping) end
function collider:set_angular_damping(damping) physics_set_angular_damping(self.body, damping) end
function collider:set_gravity_scale(scale) physics_set_gravity_scale(self.body, scale) end
function collider:set_fixed_rotation(fixed) physics_set_fixed_rotation(self.body, fixed) end
function collider:set_bullet(bullet) physics_set_bullet(self.body, bullet) end

-- Shape properties (operate on self.shape by default, or pass explicit shape)
function collider:set_friction(friction, shape) physics_shape_set_friction(shape or self.shape, friction) end
function collider:get_friction(shape) return physics_shape_get_friction(shape or self.shape) end
function collider:set_restitution(restitution, shape) physics_shape_set_restitution(shape or self.shape, restitution) end
function collider:get_restitution(shape) return physics_shape_get_restitution(shape or self.shape) end
function collider:set_density(density, shape) physics_shape_set_density(shape or self.shape, density) end
function collider:get_density(shape) return physics_shape_get_density(shape or self.shape) end
function collider:set_filter_group(group, shape) physics_shape_set_filter_group(shape or self.shape, group) end
function collider:destroy_shape(shape, update_mass)
  if update_mass == nil then update_mass = true end
  physics_shape_destroy(shape, update_mass)
end

-- Additional shapes (multi-shape bodies)
function collider:add_circle(tag, radius, opts)
  return physics_add_circle(self.body, tag, radius, opts or {})
end
function collider:add_box(tag, width, height, opts)
  return physics_add_box(self.body, tag, width, height, opts or {})
end
function collider:add_capsule(tag, length, radius, opts)
  return physics_add_capsule(self.body, tag, length, radius, opts or {})
end
function collider:add_polygon(tag, vertices, opts)
  return physics_add_polygon(self.body, tag, vertices, opts or {})
end
function collider:add_chain(tag, vertices, is_loop)
  return physics_add_chain(self.body, tag, vertices, is_loop)
end

-- Body queries
function collider:get_mass() return physics_get_mass(self.body) end
function collider:set_center_of_mass(x, y) physics_set_center_of_mass(self.body, x, y) end
function collider:get_body_type() return physics_get_body_type(self.body) end
function collider:is_awake() return physics_is_awake(self.body) end
function collider:set_awake(awake) physics_set_awake(self.body, awake) end
function collider:get_shapes_geometry() return physics_get_shapes_geometry(self.body) end

--[[
  Steering behaviors.
  Each returns (fx, fy) force vectors that can be combined and applied.

  Usage:
    local sx, sy = self.collider:steering_seek(target_x, target_y, max_speed, max_force)
    local wx, wy = self.collider:steering_wander(50, 50, 20, dt, max_speed, max_force)
    self.collider:apply_force(sx + wx, sy + wy)

  Behaviors use self.owner.x, self.owner.y as the position reference. The owner
  must have its .x/.y fields up-to-date (either synced from physics via :sync()
  or set directly).
]]

function collider:steering_seek(x, y, max_speed, max_force)
  local dx, dy = x - self.owner.x, y - self.owner.y
  dx, dy = math.normalize(dx, dy)
  dx, dy = dx*max_speed, dy*max_speed
  local vx, vy = self:get_velocity()
  dx, dy = dx - vx, dy - vy
  dx, dy = math.limit(dx, dy, max_force or 1000)
  return dx, dy
end

function collider:steering_flee(x, y, max_speed, max_force)
  local dx, dy = self.owner.x - x, self.owner.y - y
  dx, dy = math.normalize(dx, dy)
  dx, dy = dx*max_speed, dy*max_speed
  local vx, vy = self:get_velocity()
  dx, dy = dx - vx, dy - vy
  dx, dy = math.limit(dx, dy, max_force or 1000)
  return dx, dy
end

function collider:steering_arrive(x, y, rs, max_speed, max_force)
  local dx, dy = x - self.owner.x, y - self.owner.y
  local d = math.length(dx, dy)
  dx, dy = math.normalize(dx, dy)
  if d < rs then
    dx, dy = dx*math.remap(d, 0, rs, 0, max_speed), dy*math.remap(d, 0, rs, 0, max_speed)
  else
    dx, dy = dx*max_speed, dy*max_speed
  end
  local vx, vy = self:get_velocity()
  dx, dy = dx - vx, dy - vy
  dx, dy = math.limit(dx, dy, max_force or 1000)
  return dx, dy
end

function collider:steering_pursuit(target, max_speed, max_force)
  local tx, ty = target.x - self.owner.x, target.y - self.owner.y
  local d = math.length(tx, ty)
  local tvx, tvy = target.collider:get_velocity()
  local target_speed = math.length(tvx, tvy)
  local look_ahead = d/(max_speed + target_speed + 0.001)
  return self:steering_seek(target.x + tvx*look_ahead, target.y + tvy*look_ahead, max_speed, max_force)
end

function collider:steering_evade(pursuer, max_speed, max_force)
  local tx, ty = pursuer.x - self.owner.x, pursuer.y - self.owner.y
  local d = math.length(tx, ty)
  local pvx, pvy = pursuer.collider:get_velocity()
  local pursuer_speed = math.length(pvx, pvy)
  local look_ahead = d/(max_speed + pursuer_speed + 0.001)
  return self:steering_flee(pursuer.x + pvx*look_ahead, pursuer.y + pvy*look_ahead, max_speed, max_force)
end

function collider:steering_wander(d, rs, jitter, dt, max_speed, max_force)
  local vx, vy = self:get_velocity()
  local nx, ny = math.normalize(vx, vy)
  local cx, cy = self.owner.x + nx*d, self.owner.y + ny*d
  if not self.wander_r then self.wander_r = 0 end
  self.wander_r = self.wander_r + random_float(-jitter*dt, jitter*dt)
  local heading_r = math.atan(ny, nx)
  local tx, ty = cx + rs*math.cos(heading_r + self.wander_r), cy + rs*math.sin(heading_r + self.wander_r)
  return self:steering_seek(tx, ty, max_speed, max_force)
end

function collider:steering_separate(rs, others, max_speed, max_force, spatial_hash)
  local dx, dy, n = 0, 0, 0
  local px, py = self.owner.x, self.owner.y
  local pid = self.owner.id
  if spatial_hash then
    local cell_size = spatial_hash.cell_size
    local cells = spatial_hash.cells
    local cx0 = math.floor((px - rs)/cell_size)
    local cy0 = math.floor((py - rs)/cell_size)
    local cx1 = math.floor((px + rs)/cell_size)
    local cy1 = math.floor((py + rs)/cell_size)
    for cx = cx0, cx1 do
      for cy = cy0, cy1 do
        local key = cx*73856093 + cy*19349663
        local cell = cells[key]
        if cell then
          for i = 1, #cell do
            local obj = cell[i]
            if obj.id ~= pid and math.distance(obj.x, obj.y, px, py) < rs then
              local tx, ty = px - obj.x, py - obj.y
              local nx, ny = math.normalize(tx, ty)
              local l = math.length(nx, ny)
              dx = dx + rs*(nx/l)
              dy = dy + rs*(ny/l)
              n = n + 1
            end
          end
        end
      end
    end
  else
    for _, obj in ipairs(others) do
      if obj.id ~= pid and math.distance(obj.x, obj.y, px, py) < rs then
        local tx, ty = px - obj.x, py - obj.y
        local nx, ny = math.normalize(tx, ty)
        local l = math.length(nx, ny)
        dx = dx + rs*(nx/l)
        dy = dy + rs*(ny/l)
        n = n + 1
      end
    end
  end
  if n > 0 then dx, dy = dx/n, dy/n end
  if math.length(dx, dy) > 0 then
    dx, dy = math.normalize(dx, dy)
    dx, dy = dx*max_speed, dy*max_speed
    local vx, vy = self:get_velocity()
    dx, dy = dx - vx, dy - vy
    dx, dy = math.limit(dx, dy, max_force or 1000)
  end
  return dx, dy
end

function collider:steering_align(rs, others, max_speed, max_force)
  local dx, dy, n = 0, 0, 0
  for _, obj in ipairs(others) do
    if obj.id ~= self.owner.id and math.distance(obj.x, obj.y, self.owner.x, self.owner.y) < rs then
      local vx, vy = obj.collider:get_velocity()
      dx, dy = dx + vx, dy + vy
      n = n + 1
    end
  end
  if n > 0 then dx, dy = dx/n, dy/n end
  if math.length(dx, dy) > 0 then
    dx, dy = math.normalize(dx, dy)
    dx, dy = dx*max_speed, dy*max_speed
    local vx, vy = self:get_velocity()
    dx, dy = dx - vx, dy - vy
    dx, dy = math.limit(dx, dy, max_force or 1000)
    return dx, dy
  end
  return 0, 0
end

function collider:steering_cohesion(rs, others, max_speed, max_force)
  local dx, dy, n = 0, 0, 0
  for _, obj in ipairs(others) do
    if obj.id ~= self.owner.id and math.distance(obj.x, obj.y, self.owner.x, self.owner.y) < rs then
      dx, dy = dx + obj.x, dy + obj.y
      n = n + 1
    end
  end
  if n > 0 then
    dx, dy = dx/n, dy/n
    return self:steering_seek(dx, dy, max_speed, max_force)
  end
  return 0, 0
end

--[[
  steering_follow_path(path, index, seek_distance, max_speed, max_force)

  Advances along a list of waypoints. Each waypoint is a {x, y} table. The
  caller tracks the integer `index` (1-based). When the owner is within
  `seek_distance` of path[index], the index advances by one. Returns 0 force
  once the index moves past the last waypoint.

  Returns (fx, fy, new_index, done): the force vector to apply, the updated
  index (pass this back on the next call), and a boolean true once the path
  has been fully traversed.
]]
function collider:steering_follow_path(path, index, seek_distance, max_speed, max_force)
  index = index or 1
  if index > #path then return 0, 0, index, true end
  local p = path[index]
  local px, py = self.owner.x, self.owner.y
  if math.distance(p.x, p.y, px, py) < seek_distance then
    index = index + 1
    if index > #path then return 0, 0, index, true end
    p = path[index]
  end
  local fx, fy = self:steering_seek(p.x, p.y, max_speed, max_force)
  return fx, fy, index, false
end

--[[
  steering_flow_field(flow_field, max_speed, max_force)

  Follows a flow field: a uniform grid where each passable cell stores an
  angle (radians, 0 = +x, pi/2 = +y) indicating the desired movement direction.
  The flow field is a plain table with these fields:
    cell_w, cell_h     -- cell size in world units
    origin_x, origin_y -- world-space position of the (0, 0) cell's top-left
    cols, rows         -- grid dimensions
    angles             -- integer-indexed map of (row * cols + col) -> angle,
                          or nil for cells that have no defined direction
                          (impassable, unreachable, or the BFS source).
  Returns the force vector (fx, fy) to be applied by the caller.
  When the owner sits outside the grid or on a cell with no angle, returns 0, 0.
]]
function collider:steering_flow_field(flow_field, max_speed, max_force)
  local x, y = self.owner.x, self.owner.y
  local c = math.floor((x - flow_field.origin_x)/flow_field.cell_w)
  local r = math.floor((y - flow_field.origin_y)/flow_field.cell_h)
  if c < 0 or c >= flow_field.cols or r < 0 or r >= flow_field.rows then return 0, 0 end
  local angle = flow_field.angles[r*flow_field.cols + c]
  if not angle then return 0, 0 end
  local dvx = max_speed*math.cos(angle)
  local dvy = max_speed*math.sin(angle)
  local vx, vy = self:get_velocity()
  local fx, fy = dvx - vx, dvy - vy
  return math.limit(fx, fy, max_force or 1000)
end
