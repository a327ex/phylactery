--[[
  shake — procedural camera shake system.

  Lives as a sub-structure of a camera. Tracks trauma (Perlin noise shake),
  spring-based push, random shake, sine/square wave shakes, and handcam
  (continuous subtle motion).

  Usage:
    -- Part of camera_new; normally you don't create shake directly.
    -- In game code you access camera.shake.
    shake_push(camera.shake, angle, amount)
    shake_shake(camera.shake, amplitude, duration)
    shake_trauma(camera.shake, amount, duration)

  Get the current transform offset for the camera each frame:
    local ox, oy, r, z = shake_get_effects(camera.shake)
]]

--[[
  shake_new()
  Create a new shake state table. Normally called by camera_new.
]]
function shake_new()
  return {
    -- Trauma (Perlin noise shake)
    trauma_instances = {},
    trauma_amplitude = {x = 24, y = 24, rotation = 0.2, zoom = 0.2},
    trauma_time = 0,

    -- Spring-based push (directional impulses)
    spring = nil,  -- set below
    push_cap = nil,
    push_used = 0,

    -- Random shake instances
    shake_instances = {},

    -- Sine / square wave shakes
    sine_instances = {},
    square_instances = {},

    -- Handcam (continuous subtle motion)
    handcam_enabled = false,
    handcam_amplitude = {x = 5, y = 5, rotation = 0.02, zoom = 0.02},
    handcam_frequency = 0.5,
    handcam_time = 0,
  }
end

-- Shake requires a spring sub-structure for push. Create it lazily so that
-- spring.lua load order is flexible.
local function ensure_spring(s)
  if not s.spring then
    s.spring = spring_new()
    spring_add(s.spring, 'x', 0, 3, 0.5)
    spring_add(s.spring, 'y', 0, 3, 0.5)
  end
end

--[[
  shake_trauma(s, amount, [duration], [amplitude])
  Adds a Perlin noise shake instance that decays over time.
  amount is the trauma value (intensity is amount^2 * amplitude * noise).
  amplitude (optional) overrides the global trauma_amplitude for this instance.
]]
function shake_trauma(s, amount, duration, amplitude)
  duration = duration or 0.5
  s.trauma_instances[#s.trauma_instances + 1] = {
    value = amount,
    decay = amount/duration,
    amplitude = amplitude,
  }
end

--[[
  shake_set_trauma_parameters(s, amplitude)
  Sets the global trauma amplitude (x, y, rotation, zoom).
]]
function shake_set_trauma_parameters(s, amplitude)
  if amplitude.x then s.trauma_amplitude.x = amplitude.x end
  if amplitude.y then s.trauma_amplitude.y = amplitude.y end
  if amplitude.rotation then s.trauma_amplitude.rotation = amplitude.rotation end
  if amplitude.zoom then s.trauma_amplitude.zoom = amplitude.zoom end
end

--[[
  shake_shake(s, amplitude, duration, [frequency])
  Random displacement each frame (jittery/chaotic). frequency controls
  how often (per second) new random values are picked. Default 60.
]]
function shake_shake(s, amplitude, duration, frequency)
  frequency = frequency or 60
  s.shake_instances[#s.shake_instances + 1] = {
    amplitude = amplitude,
    duration = duration,
    frequency = frequency,
    time = 0,
    current_x = 0,
    current_y = 0,
    last_change = 0,
  }
end

--[[
  shake_push(s, angle, amount, [frequency], [bounce])
  Directional spring-based impulse. Multiple pushes combine additively.
  If push_cap is set, per-frame push accumulation is capped.
]]
function shake_push(s, angle, amount, frequency, bounce)
  ensure_spring(s)
  if s.push_cap then
    local remaining = s.push_cap - s.push_used
    if remaining <= 0 then return end
    if amount > remaining then amount = remaining end
    s.push_used = s.push_used + amount
  end
  spring_pull(s.spring, 'x', math.cos(angle)*amount, frequency, bounce)
  spring_pull(s.spring, 'y', math.sin(angle)*amount, frequency, bounce)
end

--[[
  shake_sine(s, angle, amplitude, frequency, duration)
  Sinusoidal oscillation along angle.
]]
function shake_sine(s, angle, amplitude, frequency, duration)
  s.sine_instances[#s.sine_instances + 1] = {
    angle = angle,
    amplitude = amplitude,
    frequency = frequency,
    duration = duration,
    time = 0,
  }
end

--[[
  shake_square(s, angle, amplitude, frequency, duration)
  Square wave oscillation (snaps between +/- amplitude).
]]
function shake_square(s, angle, amplitude, frequency, duration)
  s.square_instances[#s.square_instances + 1] = {
    angle = angle,
    amplitude = amplitude,
    frequency = frequency,
    duration = duration,
    time = 0,
  }
end

--[[
  shake_handcam(s, enabled, [amplitude], [frequency])
  Enables or disables continuous subtle noise motion (handcam feel).
]]
function shake_handcam(s, enabled, amplitude, frequency)
  s.handcam_enabled = enabled
  if amplitude then
    if amplitude.x then s.handcam_amplitude.x = amplitude.x end
    if amplitude.y then s.handcam_amplitude.y = amplitude.y end
    if amplitude.rotation then s.handcam_amplitude.rotation = amplitude.rotation end
    if amplitude.zoom then s.handcam_amplitude.zoom = amplitude.zoom end
  end
  if frequency then s.handcam_frequency = frequency end
end

--[[
  shake_get_effects(s)
  Returns ox, oy, rotation, zoom — the current combined shake offset.
  Called by camera_update to apply to the camera's transform.
]]
function shake_get_effects(s)
  local ox, oy, r, z = 0, 0, 0, 0

  -- Handcam
  if s.handcam_enabled then
    local t = s.handcam_time*s.handcam_frequency
    ox = ox + s.handcam_amplitude.x*noise(t, 0)
    oy = oy + s.handcam_amplitude.y*noise(0, t)
    r = r + s.handcam_amplitude.rotation*noise(t, t)
    z = z + s.handcam_amplitude.zoom*noise(t*0.7, 0, t)
  end

  -- Trauma
  for i = 1, #s.trauma_instances do
    local inst = s.trauma_instances[i]
    local amp = inst.amplitude or s.trauma_amplitude
    local intensity = inst.value*inst.value
    ox = ox + intensity*amp.x*noise(s.trauma_time*10, 0)
    oy = oy + intensity*amp.y*noise(0, s.trauma_time*10)
    r = r + intensity*amp.rotation*noise(s.trauma_time*10, s.trauma_time*10)
    z = z + intensity*amp.zoom*noise(s.trauma_time*5, 0, s.trauma_time*5)
  end

  -- Spring push
  if s.spring then
    ox = ox + s.spring.x.x
    oy = oy + s.spring.y.x
  end

  -- Random shake instances
  for i = 1, #s.shake_instances do
    local inst = s.shake_instances[i]
    ox = ox + inst.current_x
    oy = oy + inst.current_y
  end

  -- Sine
  for i = 1, #s.sine_instances do
    local inst = s.sine_instances[i]
    local decay = 1 - (inst.time/inst.duration)
    local wave = math.sin(inst.time*inst.frequency*2*math.pi)
    local offset = decay*inst.amplitude*wave
    ox = ox + offset*math.cos(inst.angle)
    oy = oy + offset*math.sin(inst.angle)
  end

  -- Square
  for i = 1, #s.square_instances do
    local inst = s.square_instances[i]
    local decay = 1 - (inst.time/inst.duration)
    local wave = math.sin(inst.time*inst.frequency*2*math.pi) > 0 and 1 or -1
    local offset = decay*inst.amplitude*wave
    ox = ox + offset*math.cos(inst.angle)
    oy = oy + offset*math.sin(inst.angle)
  end

  return ox, oy, r, z
end

--[[
  shake_update(s, dt)
  Advances shake state by dt. Called by camera_update each frame.
]]
function shake_update(s, dt)
  s.push_used = 0

  if s.handcam_enabled then
    s.handcam_time = s.handcam_time + dt
  end

  -- Decay trauma instances
  for i = #s.trauma_instances, 1, -1 do
    local inst = s.trauma_instances[i]
    inst.value = inst.value - inst.decay*dt
    if inst.value <= 0 then table.remove(s.trauma_instances, i) end
  end
  if #s.trauma_instances > 0 then
    s.trauma_time = s.trauma_time + dt
  end

  -- Update spring
  if s.spring then
    spring_update(s.spring, dt)
  end

  -- Update random shake instances
  for i = #s.shake_instances, 1, -1 do
    local inst = s.shake_instances[i]
    inst.time = inst.time + dt
    local change_interval = 1/inst.frequency
    if inst.time - inst.last_change >= change_interval then
      inst.last_change = inst.time
      local decay = 1 - (inst.time/inst.duration)
      if decay > 0 then
        inst.current_x = decay*inst.amplitude*random_float(-1, 1)
        inst.current_y = decay*inst.amplitude*random_float(-1, 1)
      else
        inst.current_x = 0
        inst.current_y = 0
      end
    end
    if inst.time >= inst.duration then table.remove(s.shake_instances, i) end
  end

  -- Update sine instances
  for i = #s.sine_instances, 1, -1 do
    local inst = s.sine_instances[i]
    inst.time = inst.time + dt
    if inst.time >= inst.duration then table.remove(s.sine_instances, i) end
  end

  -- Update square instances
  for i = #s.square_instances, 1, -1 do
    local inst = s.square_instances[i]
    inst.time = inst.time + dt
    if inst.time >= inst.duration then table.remove(s.square_instances, i) end
  end
end
