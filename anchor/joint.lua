--[[
  joint.lua — thin wrappers over the engine's Box2D distance-joint bindings.

  A joint connects two colliders. These helpers take collider objects (and
  reach their `.body` handle) so game code stays in collider terms. The
  returned value is the raw joint handle (userdata wrapping a b2JointId);
  pass it back to the joint_* mutators / joint_destroy.

  A distance joint holds two colliders at a target separation. With a
  spring (hertz > 0) it behaves like a soft link; add a length limit and
  it's a springy-but-bounded link — the building block for the chain.

    j = joint_distance(a, b, { length = 16, hertz = 4, damping_ratio = 0.7 })
    joint_set_spring(j, 6, 0.8)        -- live-tune stiffness / damping
    joint_set_length(j, 14)            -- live-tune rest length
    joint_set_length_range(j, 8, 20)   -- enable + set min/max length
    joint_destroy(j)

  opts (all optional): length (px), hertz, damping_ratio, enable_spring
  (defaults to hertz > 0), enable_limit, min_length / max_length (px),
  collide_connected (default false — chained units don't shove each other).
]]

function joint_distance(a, b, opts)
  return physics_create_distance_joint(a.body, b.body, opts or {})
end

function joint_destroy(j)
  if j then physics_destroy_joint(j) end
end

function joint_is_valid(j)
  return j ~= nil and physics_joint_is_valid(j)
end

function joint_set_length(j, length)
  physics_distance_joint_set_length(j, length)
end

function joint_set_spring(j, hertz, damping_ratio)
  physics_distance_joint_set_spring(j, hertz, damping_ratio)
end

function joint_set_length_range(j, min_length, max_length)
  physics_distance_joint_set_length_range(j, min_length, max_length)
end
