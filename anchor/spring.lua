--[[
  spring — procedural damped spring animation.

  Usage:
    self.spring = spring_new()                       -- in constructor
    spring_add(self.spring, 'scale', 1, 5, 0.5)      -- name, initial value, frequency, bounce
    spring_pull(self.spring, 'scale', 0.3)           -- apply impulse
    spring_update(self.spring, dt)                   -- in update

    -- Read current value:
    local s = self.spring.scale.x

  A default 'main' spring at value 1 is created on spring_new() for convenience.
  You typically use spring.main.x as a single pulsing value for hit flashes,
  click feedback, etc.

  Spring parameters:
    frequency - oscillations per second (higher = faster)
    bounce    - bounciness 0-1 (0=no overshoot, 1=infinite oscillation)
    bounce=0.5 is moderate overshoot, common for hit reactions.

  ⚠ FREQUENCY CEILING: the integrator is explicit Euler at the 60 Hz frame
  step, stable only while k*dt^2 stays small — above frequency ~12 the spring
  DIVERGES exponentially, which shows up not as a physics error but as a
  sprite scaled over the whole screen for a frame or two (draw scales multiply
  by spring.main.x). spring_add and spring_pull therefore raise on
  frequency > SPRING_MAX_FREQUENCY; want a faster pop, give it a longer life.
]]

SPRING_MAX_FREQUENCY = 12

---@class SpringEntry
---@field x number          current value
---@field target_x number   rest value
---@field v number          velocity
---@field k number          stiffness (2*pi*frequency)^2
---@field d number          damping

---@class Spring
---@field _names string[]
---@field main SpringEntry
---@field [string] SpringEntry

local function check_frequency(frequency, where)
  if frequency and frequency > SPRING_MAX_FREQUENCY then
    error(('%s: frequency %g exceeds the stable ceiling %g — the explicit-Euler spring diverges above it (symptom: a sprite covering the screen for a frame); use a lower frequency and a longer life'):format(where, frequency, SPRING_MAX_FREQUENCY), 3)
  end
end

--[[
  spring_new()
  Creates a new spring container with a default 'main' spring at value 1.
]]
---@return Spring
function spring_new()
  local s = {
    _names = {},
  }
  spring_add(s, 'main', 1)
  return s
end

--[[
  spring_add(s, name, [x], [frequency], [bounce])
  Creates a new named spring with initial value x (default 0), frequency
  (default 5 Hz), and bounce (default 0.5).
]]
---@param s Spring
---@param name string
---@param x? number          initial value, default 0
---@param frequency? number  Hz, default 5, max SPRING_MAX_FREQUENCY
---@param bounce? number     0-1, default 0.5
function spring_add(s, name, x, frequency, bounce)
  x = x or 0
  frequency = frequency or 5
  bounce = bounce or 0.5
  check_frequency(frequency, 'spring_add')
  if not s[name] then
    s._names[#s._names + 1] = name
  end
  local k = (2*math.pi*frequency)^2
  local d = 4*math.pi*(1 - bounce)*frequency
  s[name] = {
    x = x,
    target_x = x,
    v = 0,
    k = k,
    d = d,
  }
end

--[[
  spring_pull(s, name, force, [frequency], [bounce])
  Applies an impulse to a named spring. Optionally updates frequency/bounce.
  This is the "jolt" operation used for hit reactions.
]]
---@param s Spring
---@param name string
---@param force number
---@param frequency? number  Hz, max SPRING_MAX_FREQUENCY
---@param bounce? number     0-1, default 0.5
function spring_pull(s, name, force, frequency, bounce)
  local sp = s[name]
  if not sp then return end
  if frequency then
    check_frequency(frequency, 'spring_pull')
    sp.k = (2*math.pi*frequency)^2
    sp.d = 4*math.pi*(1 - (bounce or 0.5))*frequency
  end
  sp.x = sp.x + force
end

--[[
  spring_set_target(s, name, value)
  Changes where the named spring settles.
]]
---@param s Spring
---@param name string
---@param value number
function spring_set_target(s, name, value)
  if s[name] then s[name].target_x = value end
end

--[[
  spring_at_rest(s, name, [threshold])
  Returns true if the named spring has settled near its target.
]]
---@param s Spring
---@param name string
---@param threshold? number   default 0.01
---@return boolean
function spring_at_rest(s, name, threshold)
  threshold = threshold or 0.01
  local sp = s[name]
  if not sp then return true end
  local dx = sp.x - sp.target_x
  if dx < 0 then dx = -dx end
  local v = sp.v
  if v < 0 then v = -v end
  return dx < threshold and v < threshold
end

--[[
  spring_update(s, dt)
  Advances all springs by dt. Call once per frame for each spring container you own.
  Standard damped spring equation: a = -k*(x - target) - d*v
]]
---@param s Spring
---@param dt number
function spring_update(s, dt)
  local names = s._names
  for i = 1, #names do
    local sp = s[names[i]]
    local a = -sp.k*(sp.x - sp.target_x) - sp.d*sp.v
    sp.v = sp.v + a*dt
    sp.x = sp.x + sp.v*dt
  end
end
