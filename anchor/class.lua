--[[
  class — minimal class helper for Anchor 2.

  Usage:
    seeker = class()
    function seeker:new(x, y)
      self.x = x
      self.y = y
    end
    function seeker:update(dt) ... end

    local s = seeker(10, 20)   -- calls seeker.new(instance, 10, 20)
    s:update(dt)

  Notes:
    - No inheritance. If you want a variant, copy the class and modify.
    - Constructor is :new. If a class has no :new, calling the class still
      returns an empty instance (useful for data-only classes).
    - This is ~15 lines on purpose. Don't add features.
]]

function class()
  local c = {}
  c.__index = c
  setmetatable(c, {
    __call = function(cls, ...)
      local instance = setmetatable({}, cls)
      if cls.new then cls.new(instance, ...) end
      return instance
    end
  })
  return c
end
