--[[
  object — entity registry, kill queue, deferred destruction.

  This is the foundation of Anchor 2's reference discipline. Entities are
  plain tables with a numeric id; the global `entities` table maps id to
  entity. Cross-entity references are stored as IDs and resolved via
  lookup, so stale references are impossible (they just return nil).

  Usage:
    seeker = class()
    function seeker:new(x, y)
      self.x = x
      self.y = y
      make_entity(self)           -- assigns self.id and registers
    end

    function seeker:destroy()     -- called at end of frame after kill()
      -- clean up sub-objects here
    end

    -- Cross-entity reference (ID, not pointer):
    self.target_id = other_entity.id

    -- Resolve at use time:
    local t = entities[self.target_id]
    if t then t:hit(5) end

    -- Kill an entity (queues for end-of-frame destruction):
    entity:kill()

    -- At end of every frame in your main loop:
    process_destroy_queue()

  Design notes:
    - There is no tree. No self:add(child). No parent/children pointers.
    - No tag system, no an:all(tag). If you need a collection, make one.
    - Compositional sub-objects (timer, spring, collider) are plain fields
      on the entity. The entity's destroy() method cleans them up
      explicitly. This is a few lines of boilerplate and worth it.
    - kill() marks the entity dead and queues it. The real cleanup runs
      at end-of-frame via process_destroy_queue. This means dead-marked
      entities are still accessible during the rest of the frame, which
      prevents mid-frame state divergence bugs.
    - If destroy() is not defined on the entity, only the entities table
      entry is cleared. That's fine for simple data entities.
]]

-- Global entity registry
entities = {}

-- Auto-incrementing ID counter (never reused)
local next_id = 1

-- Pending destruction queue, drained by process_destroy_queue
local destroy_queue = {}

--[[
  Default kill method installed on every entity at make_entity time.
  If a class defines its own kill method before calling make_entity,
  that takes precedence.
]]
local function default_kill(self)
  if self._dying then return end
  self._dying = true
  destroy_queue[#destroy_queue + 1] = self
end

--[[
  make_entity(e)
  Assigns e.id and registers e in the global entities table.
  Also installs a default kill method if none exists.
  Returns e for chaining.
]]
function make_entity(e)
  e.id = next_id
  next_id = next_id + 1
  entities[e.id] = e
  if not e.kill then e.kill = default_kill end
  return e
end

--[[
  entity_kill(e)
  Free function equivalent to e:kill(). Useful if you have a plain
  entity table and don't want to use method syntax.
]]
function entity_kill(e)
  default_kill(e)
end

--[[
  process_destroy_queue()
  Called once at the end of every frame in the game's main update.
  Drains the destroy queue until stable (entity destruction may cause
  more kills via polling in other entities' destroy methods).
]]
function process_destroy_queue()
  while #destroy_queue > 0 do
    local q = destroy_queue
    destroy_queue = {}
    for i = 1, #q do
      local e = q[i]
      if e.destroy then e:destroy() end
      if e.id then entities[e.id] = nil end
      e._dead = true
    end
  end
end
