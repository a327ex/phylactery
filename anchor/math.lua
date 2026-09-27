--[[
  Math utility functions and easing curves.

  Utility functions:
    lerp, lerp_dt             - Linear interpolation
    lerp_angle, lerp_angle_dt - Angle interpolation with wrapping
    clamp                     - Clamp value to range
    remap                     - Remap value from one range to another
    loop                      - Loop value within range (for angles)
    sign                      - Sign of a number (-1, 0, 1)
    length                    - Length of a 2D vector
    angle                     - Angle from vector components
    angle_to_point            - Angle between two points
    distance                  - Distance between two points
    normalize                 - Normalize a vector to unit length
    direction                 - Unit vector from angle
    rotate                    - Rotate a vector by angle
    reflect                   - Reflect angle off a surface normal
    snap                      - Snap value to nearest grid
    limit                     - Limit vector length

  Easing functions:
    linear, sine_*, quad_*, cubic_*, quart_*, quint_*,
    expo_*, circ_*, bounce_*, back_*, elastic_*
]]

-- Constants for easing functions
PI = math.pi
PI2 = math.pi/2
LN2 = math.log(2)
LN210 = 10*math.log(2)

-- Overshoot for back easing
overshoot = 1.70158

-- Amplitude and period for elastic easing
amplitude = 1
period = 0.0003

--[[
  Linearly interpolates between source and destination.

  Usage:
    math.lerp(0.5, 0, 100)   -> 50
    math.lerp(0, 0, 100)     -> 0
    math.lerp(1, 0, 100)     -> 100

  Parameters:
    t           - Interpolation factor (0 = source, 1 = destination)
    source      - Start value
    destination - End value

  Returns: interpolated value
]]
function math.lerp(t, source, destination)
  return source*(1 - t) + destination*t
end

--[[
  Framerate-independent linear interpolation.

  Usage:
    x = math.lerp_dt(0.9, 1, dt, x, target)   -> covers 90% of distance in 1 second
    x = math.lerp_dt(0.5, 0.5, dt, x, target)  -> covers 50% of distance in 0.5 seconds

  Parameters:
    p           - Percentage of distance to cover (0.9 = 90%)
    t           - Time in seconds to cover that percentage
    dt          - Delta time
    source      - Current value
    destination - Target value

  Returns: new value moved towards destination

  Behavior:
    - Exponential approach: value gets closer but never quite reaches target
    - Useful for smooth camera follow, UI animations, etc.
]]
function math.lerp_dt(p, t, dt, source, destination)
  return math.lerp(1 - (1 - p)^(dt/t), source, destination)
end

--[[
  Framerate-independent damping (decay toward zero).

  Usage:
    x = math.damping(0.9, 1, dt, x)   -> after 1 second, x will be 10% of its initial value
    x = math.damping(0.5, 0.5, dt, x)  -> after 0.5 seconds, x will be 50% of its initial value

  Parameters:
    p  - Percentage of value to decay (0.9 = decay 90%, leaving 10%)
    t  - Time in seconds to reach that decay
    dt - Delta time
    v  - Current value

  Returns: decayed value
]]
function math.damping(p, t, dt, v)
  return (v or 0)*(1 - p)^(dt/t)
end

--[[
  Loops value t to stay within [0, length] range.

  Usage:
    math.loop(3*math.pi, 2*math.pi)  -> math.pi
    math.loop(5, 3)                    -> 2
    math.loop(-1, 4)                   -> 3

  Parameters:
    t      - Value to loop
    length - Range length (result will be in [0, length])

  Returns: looped value

  Behavior:
    - Useful for keeping angles in [0, 2*pi] range
    - Handles negative values correctly
]]
function math.loop(t, length)
  return math.clamp(t - math.floor(t/length)*length, 0, length)
end

--[[
  Linearly interpolates between angles with correct wrapping.

  Usage:
    math.lerp_angle(0.5, 0, math.pi)          -> math.pi/2
    math.lerp_angle(0.5, -math.pi, math.pi)   -> 0 (takes shortest path)

  Parameters:
    t           - Interpolation factor (0 = source, 1 = destination)
    source      - Start angle in radians
    destination - End angle in radians

  Returns: interpolated angle

  Behavior:
    - Takes the shortest path around the circle
    - Keeps result in valid angle range
]]
function math.lerp_angle(t, source, destination)
  local dt = math.loop(destination - source, 2*math.pi)
  if dt > math.pi then dt = dt - 2*math.pi end
  return source + dt*math.clamp(t, 0, 1)
end

--[[
  Framerate-independent angle interpolation with correct wrapping.

  Usage:
    angle = math.lerp_angle_dt(0.9, 1, dt, angle, target_angle)

  Parameters:
    p           - Percentage of distance to cover (0.9 = 90%)
    t           - Time in seconds to cover that percentage
    dt          - Delta time
    source      - Current angle in radians
    destination - Target angle in radians

  Returns: new angle moved towards destination

  Behavior:
    - Takes the shortest path around the circle
    - Exponential approach like lerp_dt
]]
function math.lerp_angle_dt(p, t, dt, source, destination)
  return math.lerp_angle(1 - (1 - p)^(dt/t), source, destination)
end

--[[
  Returns the sign of a number.

  Usage:
    math.sign(5)    -> 1
    math.sign(-5)   -> -1
    math.sign(0)    -> 0

  Parameters:
    value - Number to get sign of

  Returns: 1, -1, or 0
]]
function math.sign(value)
  if value > 0 then return 1
  elseif value < 0 then return -1
  else return 0 end
end

--[[
  Returns the length (magnitude) of a 2D vector.

  Usage:
    math.length(3, 4)       -> 5
    math.length(vx, vy)     -> speed

  Parameters:
    x - X component of the vector
    y - Y component of the vector

  Returns: The Euclidean length of the vector
]]
function math.length(x, y)
  return math.sqrt(x*x + y*y)
end

--[[
  Clamps value to stay within [min, max] range.

  Usage:
    math.clamp(5, 0, 10)   -> 5
    math.clamp(-5, 0, 10)  -> 0
    math.clamp(15, 0, 10)  -> 10

  Parameters:
    value - Value to clamp
    min   - Minimum bound
    max   - Maximum bound

  Returns: clamped value
]]
function math.clamp(value, min, max)
  if value < min then return min
  elseif value > max then return max
  else return value end
end

--[[
  Remaps a value from one range to another.

  Usage:
    math.remap(10, 0, 20, 0, 1)        -> 0.5 (10 is 50% of [0, 20], maps to 50% of [0, 1])
    math.remap(3, 0, 3, 0, 100)        -> 100
    math.remap(2.5, -5, 5, -100, 100)  -> 50
    math.remap(-10, 0, 10, 0, 1000)    -> -1000 (extrapolates outside range)

  Parameters:
    value   - Value to remap
    old_min - Original range minimum
    old_max - Original range maximum
    new_min - Target range minimum
    new_max - Target range maximum

  Returns: value mapped from old range to new range

  Behavior:
    - Does not clamp: values outside old range will extrapolate
    - To clamp, combine with math.clamp on input or output
]]
function math.remap(value, old_min, old_max, new_min, new_max)
  return ((value - old_min)/(old_max - old_min))*(new_max - new_min) + new_min
end

--[[
  Returns the angle of a 2D vector in radians.

  Usage:
    math.angle(1, 0)        -> 0 (pointing right)
    math.angle(0, 1)        -> pi/2 (pointing down)
    math.angle(-1, 0)       -> pi (pointing left)
    math.angle(vx, vy)      -> direction of velocity

  Parameters:
    x - X component of the vector
    y - Y component of the vector

  Returns: angle in radians (-pi to pi)
]]
function math.angle(x, y)
  return math.atan(y, x)
end

--[[
  Returns the angle from point 1 to point 2.

  Usage:
    math.angle_to_point(0, 0, 100, 0)     -> 0 (target is to the right)
    math.angle_to_point(0, 0, 0, 100)     -> pi/2 (target is below)
    math.angle_to_point(self.x, self.y, enemy.x, enemy.y)

  Parameters:
    x1, y1 - Source point
    x2, y2 - Target point

  Returns: angle in radians from source to target
]]
function math.angle_to_point(x1, y1, x2, y2)
  return math.atan(y2 - y1, x2 - x1)
end

--[[
  Returns the distance between two points.

  Usage:
    math.distance(0, 0, 3, 4)      -> 5
    math.distance(self.x, self.y, target.x, target.y)

  Parameters:
    x1, y1 - First point
    x2, y2 - Second point

  Returns: Euclidean distance between points
]]
function math.distance(x1, y1, x2, y2)
  local dx = x2 - x1
  local dy = y2 - y1
  return math.sqrt(dx*dx + dy*dy)
end

--[[
  Normalizes a 2D vector to unit length.

  Usage:
    nx, ny = math.normalize(3, 4)      -> 0.6, 0.8
    nx, ny = math.normalize(vx, vy)

  Parameters:
    x - X component of the vector
    y - Y component of the vector

  Returns: x, y components of unit vector (or 0, 0 if input is zero vector)
]]
function math.normalize(x, y)
  local len = math.length(x, y)
  if len > 0 then
    return x/len, y/len
  else
    return 0, 0
  end
end

--[[
  Returns a unit vector pointing in the given direction.

  Usage:
    dx, dy = math.direction(0)           -> 1, 0 (right)
    dx, dy = math.direction(math.pi/2)   -> 0, 1 (down)
    dx, dy = math.direction(self.angle)

  Parameters:
    angle - Direction in radians

  Returns: x, y components of unit vector
]]
function math.direction(angle)
  return math.cos(angle), math.sin(angle)
end

--[[
  Rotates a 2D vector by an angle.

  Usage:
    rx, ry = math.rotate(1, 0, math.pi/2)    -> 0, 1 (rotated 90 degrees)
    rx, ry = math.rotate(vx, vy, self.rotation)

  Parameters:
    x     - X component of vector
    y     - Y component of vector
    angle - Rotation angle in radians

  Returns: x, y components of rotated vector
]]
function math.rotate(x, y, angle)
  local c = math.cos(angle)
  local s = math.sin(angle)
  return x*c - y*s, x*s + y*c
end

--[[
  Reflects an angle off a surface normal.

  Usage:
    new_angle = math.reflect(projectile.angle, normal_x, normal_y)
    new_angle = math.reflect(self.angle, collision.normal_x, collision.normal_y)

  Parameters:
    angle    - Incoming angle in radians
    normal_x - X component of surface normal
    normal_y - Y component of surface normal

  Returns: reflected angle in radians

  Behavior:
    - Reflects the direction as if bouncing off a surface
    - Normal should point away from the surface
]]
function math.reflect(angle, normal_x, normal_y)
  -- Incoming direction
  local dx = math.cos(angle)
  local dy = math.sin(angle)

  -- Reflect: d' = d - 2(d·n)n
  local dot = dx*normal_x + dy*normal_y
  local rx = dx - 2*dot*normal_x
  local ry = dy - 2*dot*normal_y

  return math.atan(ry, rx)
end

--[[
  Snaps a value to the nearest multiple of grid.

  Usage:
    math.snap(7, 5)        -> 5
    math.snap(8, 5)        -> 10
    math.snap(0.7, 0.25)   -> 0.75
    math.snap(angle, math.pi/4)  -- snap to 45-degree increments

  Parameters:
    value - Value to snap
    grid  - Grid size

  Returns: nearest multiple of grid
]]
function math.snap(value, grid)
  return math.floor(value/grid + 0.5)*grid
end

--[[
  Limits a vector's length without changing direction.

  Usage:
    vx, vy = math.limit(vx, vy, max_speed)
    vx, vy = math.limit(100, 100, 50)   -> ~35.4, ~35.4

  Parameters:
    x   - X component of vector
    y   - Y component of vector
    max - Maximum length

  Returns: x, y components of limited vector

  Behavior:
    - If vector length <= max, returns unchanged
    - If vector length > max, scales to exactly max length
]]
function math.limit(x, y, max)
  local len = math.length(x, y)
  if len > max then
    local scale = max/len
    return x*scale, y*scale
  else
    return x, y
  end
end

-- Linear (no easing)
function math.linear(t) return t end

-- Sine easing
function math.sine_in(t)
  if t == 0 then return 0
  elseif t == 1 then return 1
  else return 1 - math.cos(t*PI2) end
end

function math.sine_out(t)
  if t == 0 then return 0
  elseif t == 1 then return 1
  else return math.sin(t*PI2) end
end

function math.sine_in_out(t)
  if t == 0 then return 0
  elseif t == 1 then return 1
  else return -0.5*(math.cos(t*PI) - 1) end
end

function math.sine_out_in(t)
  if t == 0 then return 0
  elseif t == 1 then return 1
  elseif t < 0.5 then return 0.5*math.sin(t*2*PI2)
  else return -0.5*math.cos((t*2 - 1)*PI2) + 1 end
end

-- Quad easing
function math.quad_in(t) return t*t end

function math.quad_out(t) return -t*(t - 2) end

function math.quad_in_out(t)
  if t < 0.5 then
    return 2*t*t
  else
    t = t - 1
    return -2*t*t + 1
  end
end

function math.quad_out_in(t)
  if t < 0.5 then
    t = t*2
    return -0.5*t*(t - 2)
  else
    t = t*2 - 1
    return 0.5*t*t + 0.5
  end
end

-- Cubic easing
function math.cubic_in(t) return t*t*t end

function math.cubic_out(t)
  t = t - 1
  return t*t*t + 1
end

function math.cubic_in_out(t)
  t = t*2
  if t < 1 then
    return 0.5*t*t*t
  else
    t = t - 2
    return 0.5*(t*t*t + 2)
  end
end

function math.cubic_out_in(t)
  t = t*2 - 1
  return 0.5*(t*t*t + 1)
end

-- Quart easing
function math.quart_in(t) return t*t*t*t end

function math.quart_out(t)
  t = t - 1
  t = t*t
  return 1 - t*t
end

function math.quart_in_out(t)
  t = t*2
  if t < 1 then
    return 0.5*t*t*t*t
  else
    t = t - 2
    t = t*t
    return -0.5*(t*t - 2)
  end
end

function math.quart_out_in(t)
  if t < 0.5 then
    t = t*2 - 1
    t = t*t
    return -0.5*t*t + 0.5
  else
    t = t*2 - 1
    t = t*t
    return 0.5*t*t + 0.5
  end
end

-- Quint easing
function math.quint_in(t) return t*t*t*t*t end

function math.quint_out(t)
  t = t - 1
  return t*t*t*t*t + 1
end

function math.quint_in_out(t)
  t = t*2
  if t < 1 then
    return 0.5*t*t*t*t*t
  else
    t = t - 2
    return 0.5*t*t*t*t*t + 1
  end
end

function math.quint_out_in(t)
  t = t*2 - 1
  return 0.5*(t*t*t*t*t + 1)
end

-- Expo easing
function math.expo_in(t)
  if t == 0 then return 0
  else return math.exp(LN210*(t - 1)) end
end

function math.expo_out(t)
  if t == 1 then return 1
  else return 1 - math.exp(-LN210*t) end
end

function math.expo_in_out(t)
  if t == 0 then return 0
  elseif t == 1 then return 1
  else
    t = t*2
    if t < 1 then return 0.5*math.exp(LN210*(t - 1))
    else return 0.5*(2 - math.exp(-LN210*(t - 1))) end
  end
end

function math.expo_out_in(t)
  if t < 0.5 then return 0.5*(1 - math.exp(-20*LN2*t))
  elseif t == 0.5 then return 0.5
  else return 0.5*(math.exp(20*LN2*(t - 1)) + 1) end
end

-- Circ easing
function math.circ_in(t)
  if t < -1 or t > 1 then return 0
  else return 1 - math.sqrt(1 - t*t) end
end

function math.circ_out(t)
  if t < 0 or t > 2 then return 0
  else return math.sqrt(t*(2 - t)) end
end

function math.circ_in_out(t)
  if t < -0.5 or t > 1.5 then return 0.5
  else
    t = t*2
    if t < 1 then return -0.5*(math.sqrt(1 - t*t) - 1)
    else
      t = t - 2
      return 0.5*(math.sqrt(1 - t*t) + 1)
    end
  end
end

function math.circ_out_in(t)
  if t < 0 then return 0
  elseif t > 1 then return 1
  elseif t < 0.5 then
    t = t*2 - 1
    return 0.5*math.sqrt(1 - t*t)
  else
    t = t*2 - 1
    return -0.5*((math.sqrt(1 - t*t) - 1) - 1)
  end
end

-- Bounce easing
function math.bounce_in(t)
  t = 1 - t
  if t < 1/2.75 then return 1 - 7.5625*t*t
  elseif t < 2/2.75 then
    t = t - 1.5/2.75
    return 1 - (7.5625*t*t + 0.75)
  elseif t < 2.5/2.75 then
    t = t - 2.25/2.75
    return 1 - (7.5625*t*t + 0.9375)
  else
    t = t - 2.625/2.75
    return 1 - (7.5625*t*t + 0.984375)
  end
end

function math.bounce_out(t)
  if t < 1/2.75 then return 7.5625*t*t
  elseif t < 2/2.75 then
    t = t - 1.5/2.75
    return 7.5625*t*t + 0.75
  elseif t < 2.5/2.75 then
    t = t - 2.25/2.75
    return 7.5625*t*t + 0.9375
  else
    t = t - 2.625/2.75
    return 7.5625*t*t + 0.984375
  end
end

function math.bounce_in_out(t)
  if t < 0.5 then
    t = 1 - t*2
    if t < 1/2.75 then return (1 - 7.5625*t*t)*0.5
    elseif t < 2/2.75 then
      t = t - 1.5/2.75
      return (1 - (7.5625*t*t + 0.75))*0.5
    elseif t < 2.5/2.75 then
      t = t - 2.25/2.75
      return (1 - (7.5625*t*t + 0.9375))*0.5
    else
      t = t - 2.625/2.75
      return (1 - (7.5625*t*t + 0.984375))*0.5
    end
  else
    t = t*2 - 1
    if t < 1/2.75 then return 7.5625*t*t*0.5 + 0.5
    elseif t < 2/2.75 then
      t = t - 1.5/2.75
      return (7.5625*t*t + 0.75)*0.5 + 0.5
    elseif t < 2.5/2.75 then
      t = t - 2.25/2.75
      return (7.5625*t*t + 0.9375)*0.5 + 0.5
    else
      t = t - 2.625/2.75
      return (7.5625*t*t + 0.984375)*0.5 + 0.5
    end
  end
end

function math.bounce_out_in(t)
  if t < 0.5 then
    t = t*2
    if t < 1/2.75 then return 7.5625*t*t*0.5
    elseif t < 2/2.75 then
      t = t - 1.5/2.75
      return (7.5625*t*t + 0.75)*0.5
    elseif t < 2.5/2.75 then
      t = t - 2.25/2.75
      return (7.5625*t*t + 0.9375)*0.5
    else
      t = t - 2.625/2.75
      return (7.5625*t*t + 0.984375)*0.5
    end
  else
    t = 1 - (t*2 - 1)
    if t < 1/2.75 then return 0.5 - 7.5625*t*t*0.5 + 0.5
    elseif t < 2/2.75 then
      t = t - 1.5/2.75
      return 0.5 - (7.5625*t*t + 0.75)*0.5 + 0.5
    elseif t < 2.5/2.75 then
      t = t - 2.25/2.75
      return 0.5 - (7.5625*t*t + 0.9375)*0.5 + 0.5
    else
      t = t - 2.625/2.75
      return 0.5 - (7.5625*t*t + 0.984375)*0.5 + 0.5
    end
  end
end

-- Back easing
function math.back_in(t)
  if t == 0 then return 0
  elseif t == 1 then return 1
  else return t*t*((overshoot + 1)*t - overshoot) end
end

function math.back_out(t)
  if t == 0 then return 0
  elseif t == 1 then return 1
  else
    t = t - 1
    return t*t*((overshoot + 1)*t + overshoot) + 1
  end
end

function math.back_in_out(t)
  if t == 0 then return 0
  elseif t == 1 then return 1
  else
    t = t*2
    if t < 1 then return 0.5*(t*t*((overshoot*1.525 + 1)*t - overshoot*1.525))
    else
      t = t - 2
      return 0.5*(t*t*((overshoot*1.525 + 1)*t + overshoot*1.525) + 2)
    end
  end
end

function math.back_out_in(t)
  if t == 0 then return 0
  elseif t == 1 then return 1
  elseif t < 0.5 then
    t = t*2 - 1
    return 0.5*(t*t*((overshoot + 1)*t + overshoot) + 1)
  else
    t = t*2 - 1
    return 0.5*t*t*((overshoot + 1)*t - overshoot) + 0.5
  end
end

-- Elastic easing
function math.elastic_in(t)
  if t == 0 then return 0
  elseif t == 1 then return 1
  else
    t = t - 1
    return -(amplitude*math.exp(LN210*t)*math.sin((t*0.001 - period/4)*(2*PI)/period))
  end
end

function math.elastic_out(t)
  if t == 0 then return 0
  elseif t == 1 then return 1
  else return math.exp(-LN210*t)*math.sin((t*0.001 - period/4)*(2*PI)/period) + 1 end
end

function math.elastic_in_out(t)
  if t == 0 then return 0
  elseif t == 1 then return 1
  else
    t = t*2
    if t < 1 then
      t = t - 1
      return -0.5*(amplitude*math.exp(LN210*t)*math.sin((t*0.001 - period/4)*(2*PI)/period))
    else
      t = t - 1
      return amplitude*math.exp(-LN210*t)*math.sin((t*0.001 - period/4)*(2*PI)/period)*0.5 + 1
    end
  end
end

function math.elastic_out_in(t)
  if t < 0.5 then
    t = t*2
    if t == 0 then return 0
    else return (amplitude/2)*math.exp(-LN210*t)*math.sin((t*0.001 - period/4)*(2*PI)/period) + 0.5 end
  else
    if t == 0.5 then return 0.5
    elseif t == 1 then return 1
    else
      t = t*2 - 1
      t = t - 1
      return -((amplitude/2)*math.exp(LN210*t)*math.sin((t*0.001 - period/4)*(2*PI)/period)) + 0.5
    end
  end
end
