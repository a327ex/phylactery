--[[
  collider3 — thin wrapper around a Box3D physics body + shape.

  3D sibling of collider. Same design: a class bundling body + shape + tag,
  owner back-reference, user_data set to owner.id so physics3 queries resolve
  back to entities. Positions in meters (y-up), rotations as quaternions
  (x, y, z, w).

  Usage:
    function ball:new(x, y, z)
      self.x, self.y, self.z = x, y, z
      make_entity(self)
      self.collider = collider3(self, 'ball', 'dynamic', 'sphere', 0.5)
      self.collider:set_position(x, y, z)
    end

    function ball:update(dt)
      self.collider:sync()   -- copies position AND rotation to self
    end

    function ball:draw(scene)
      layer3_sphere(scene, self.x, self.y, self.z, 0.5, self.color)
      -- or: self.collider:draw(scene, self.color) which draws the collider's
      -- own shape at its current transform
    end

    function ball:destroy()
      self.collider:destroy()
    end

  Shape types and their arguments (opts table last, optional):
    'sphere'   radius
    'box'      w, h, d
    'capsule'  height, radius        (height = total, tip to tip)
    'cylinder' height, radius
    'hull'     points                (flat array {x1,y1,z1, x2,y2,z2, ...})
]]

collider3 = class()

function collider3:new(owner, tag, body_type, shape_type, ...)
  self.owner = owner
  self.tag = tag
  self.body_type = body_type
  self.shape_type = shape_type
  self.body = physics3_create_body(body_type, 0, 0, 0)

  if owner and owner.id then
    physics3_set_user_data(self.body, owner.id)
  end

  local shape_args = {...}
  local opts = {}
  if type(shape_args[#shape_args]) == 'table' and shape_type ~= 'hull' then
    opts = table.remove(shape_args)
  elseif shape_type == 'hull' and #shape_args >= 2 and type(shape_args[2]) == 'table' then
    opts = table.remove(shape_args)
  end

  if shape_type == 'sphere' then
    self.shape = physics3_add_sphere(self.body, tag, shape_args[1], opts)
    self.shape_dims = {shape_args[1]}
  elseif shape_type == 'box' then
    self.shape = physics3_add_box(self.body, tag, shape_args[1], shape_args[2], shape_args[3], opts)
    self.shape_dims = {shape_args[1], shape_args[2], shape_args[3]}
  elseif shape_type == 'capsule' then
    self.shape = physics3_add_capsule(self.body, tag, shape_args[1], shape_args[2], opts)
    self.shape_dims = {shape_args[1], shape_args[2]}
  elseif shape_type == 'cylinder' then
    self.shape = physics3_add_cylinder(self.body, tag, shape_args[1], shape_args[2], opts)
    self.shape_dims = {shape_args[1], shape_args[2]}
  elseif shape_type == 'hull' then
    self.shape = physics3_add_hull(self.body, tag, shape_args[1], opts)
    self.shape_dims = {}
  end
end

function collider3:destroy()
  if self.body then
    physics3_destroy_body(self.body)
    self.body = nil
  end
end

--[[
  collider3:sync()
  Copies the body's position AND rotation to the owner (x/y/z, qx/qy/qz/qw).
]]
function collider3:sync()
  if self.owner and self.body then
    self.owner.x, self.owner.y, self.owner.z = physics3_get_position(self.body)
    self.owner.qx, self.owner.qy, self.owner.qz, self.owner.qw = physics3_get_rotation(self.body)
  end
end

--[[
  collider3:draw(scene, color)
  Draws this collider's shape at its current physics transform into a layer3.
  Convenience for the common "the visual IS the collider" case.
]]
function collider3:draw(scene, color)
  if not self.body then return end   -- destroyed this frame; owner still in a draw list until next update's sweep
  local x, y, z = physics3_get_position(self.body)
  local qx, qy, qz, qw = physics3_get_rotation(self.body)
  local d = self.shape_dims
  if self.shape_type == 'sphere' then
    layer3_sphere(scene, x, y, z, d[1], color)
  elseif self.shape_type == 'box' then
    layer3_box(scene, x, y, z, d[1], d[2], d[3], qx, qy, qz, qw, color)
  elseif self.shape_type == 'capsule' then
    layer3_capsule(scene, x, y, z, d[1], d[2], qx, qy, qz, qw, color)
  elseif self.shape_type == 'cylinder' then
    layer3_cylinder(scene, x, y, z, d[1], d[2], qx, qy, qz, qw, color)
  end
  -- 'hull' has no primitive mesh; draw it yourself or use layer3_debug_draw
end

-- Position & rotation
function collider3:get_position() return physics3_get_position(self.body) end
function collider3:set_position(x, y, z) physics3_set_position(self.body, x, y, z) end
function collider3:get_rotation() return physics3_get_rotation(self.body) end
function collider3:set_rotation(qx, qy, qz, qw) physics3_set_rotation(self.body, qx, qy, qz, qw) end
function collider3:set_transform(x, y, z, qx, qy, qz, qw) physics3_set_transform(self.body, x, y, z, qx, qy, qz, qw) end

-- Velocity
function collider3:get_velocity() return physics3_get_velocity(self.body) end
function collider3:set_velocity(vx, vy, vz) physics3_set_velocity(self.body, vx, vy, vz) end
function collider3:get_angular_velocity() return physics3_get_angular_velocity(self.body) end
function collider3:set_angular_velocity(wx, wy, wz) physics3_set_angular_velocity(self.body, wx, wy, wz) end

-- Forces & impulses
function collider3:apply_force(fx, fy, fz) physics3_apply_force(self.body, fx, fy, fz) end
function collider3:apply_force_at(fx, fy, fz, px, py, pz) physics3_apply_force_at(self.body, fx, fy, fz, px, py, pz) end
function collider3:apply_impulse(ix, iy, iz) physics3_apply_impulse(self.body, ix, iy, iz) end
function collider3:apply_impulse_at(ix, iy, iz, px, py, pz) physics3_apply_impulse_at(self.body, ix, iy, iz, px, py, pz) end
function collider3:apply_torque(tx, ty, tz) physics3_apply_torque(self.body, tx, ty, tz) end
function collider3:apply_angular_impulse(ix, iy, iz) physics3_apply_angular_impulse(self.body, ix, iy, iz) end

-- Body properties
function collider3:set_linear_damping(damping) physics3_set_linear_damping(self.body, damping) end
function collider3:set_angular_damping(damping) physics3_set_angular_damping(self.body, damping) end
function collider3:set_gravity_scale(scale) physics3_set_gravity_scale(self.body, scale) end
function collider3:set_motion_locks(lx, ly, lz, ax, ay, az) physics3_set_motion_locks(self.body, lx, ly, lz, ax, ay, az) end
function collider3:set_bullet(bullet) physics3_set_bullet(self.body, bullet) end
function collider3:get_mass() return physics3_get_mass(self.body) end
function collider3:is_awake() return physics3_is_awake(self.body) end
function collider3:set_awake(awake) physics3_set_awake(self.body, awake) end

-- Shape properties (operate on self.shape by default, or pass explicit shape)
function collider3:set_friction(friction, shape) physics3_shape_set_friction(shape or self.shape, friction) end
function collider3:get_friction(shape) return physics3_shape_get_friction(shape or self.shape) end
function collider3:set_restitution(restitution, shape) physics3_shape_set_restitution(shape or self.shape, restitution) end
function collider3:get_restitution(shape) return physics3_shape_get_restitution(shape or self.shape) end
function collider3:set_density(density, shape) physics3_shape_set_density(shape or self.shape, density) end
function collider3:get_density(shape) return physics3_shape_get_density(shape or self.shape) end
function collider3:set_filter_group(group, shape) physics3_shape_set_filter_group(shape or self.shape, group) end
