--[[
  animation — procedural frame-based animation for spritesheets.

  Usage:
    self.anim = animation_new('hit1', 0.03, 'once', {
      [3] = function() print("frame 3") end,
      [0] = function() self.anim_done = true end,   -- completion callback
    })

    -- In update:
    animation_update(self.anim, dt)

    -- In draw:
    layer_spritesheet(game_layer, self.anim.spritesheet, self.anim.frame, x, y)

  Loop modes:
    'once'    - play once and set .dead = true
    'loop'    - repeat indefinitely
    'bounce'  - ping-pong back and forth

  Actions table:
    [frame_number] = function(anim)    -- fires when that frame becomes active
    [0]            = function(anim)    -- fires on completion (once mode) or loop boundary

  Design notes:
    - v1 fired actions with self.parent as first arg. v2 fires with the animation
      table itself. Closures in the actions table can capture their owner.
    - No "dead" cascade to a parent. If loop_mode='once' and completes, the animation
      sets its `dead` field to true, and the owning entity checks it or ignores it.
    - No kill() call (v1 called self:kill() which was tree-dependent).
    - Delays can be a number (uniform) or a table (per-frame).
]]

--[[
  animation_new(spritesheet_name, delay, loop_mode, actions)
  Creates a new animation state table. spritesheet_name is looked up in `spritesheets`.
]]
---@class Animation
---@field spritesheet Spritesheet
---@field spritesheet_name string
---@field delay number          seconds per frame
---@field loop_mode string      'loop' | 'once' | 'bounce'
---@field actions table         frame -> callback
---@field frame integer         current frame (1-based)
---@field timer number
---@field direction integer     1 or -1 (bounce)
---@field playing boolean

---@param spritesheet_name string
---@param delay? number
---@param loop_mode? string
---@param actions? table
---@return Animation
function animation_new(spritesheet_name, delay, loop_mode, actions)
  local a = {
    spritesheet = spritesheets[spritesheet_name],
    spritesheet_name = spritesheet_name,
    delay = delay or 0.1,
    loop_mode = loop_mode or 'loop',
    actions = actions or {},
    frame = 1,
    timer = 0,
    direction = 1,
    playing = true,
    dead = false,
  }
  if a.actions[1] then a.actions[1](a) end
  return a
end

--[[
  animation_play(a), animation_stop(a), animation_reset(a)
  Control playback.
]]
function animation_play(a)
  a.playing = true
end

function animation_stop(a)
  a.playing = false
end

function animation_reset(a)
  a.frame = 1
  a.timer = 0
  a.direction = 1
  a.dead = false
  a.playing = true
  if a.actions[1] then a.actions[1](a) end
end

--[[
  animation_set_frame(a, frame)
  Jumps to a specific frame (clamped to [1, total_frames]).
]]
function animation_set_frame(a, frame)
  local total = a.spritesheet.frames or 1
  if frame < 1 then frame = 1 end
  if frame > total then frame = total end
  a.frame = frame
  a.timer = 0
  if a.actions[a.frame] then a.actions[a.frame](a) end
end

-- Internal: resolve delay for the current frame (handles per-frame delay tables).
local function get_delay(a, frame)
  if type(a.delay) == 'table' then
    return a.delay[frame] or a.delay[1] or 0.1
  else
    return a.delay
  end
end

-- Internal: fire an action callback for a frame.
local function fire_action(a, frame)
  if a.actions[frame] then a.actions[frame](a) end
end

-- Internal: advance by one frame according to loop mode.
local function advance_frame(a)
  local total = a.spritesheet.frames or 1
  local next_frame = a.frame + a.direction

  if a.loop_mode == 'once' then
    if next_frame > total then
      a.dead = true
      a.playing = false
      fire_action(a, 0)
      return
    end
    a.frame = next_frame
    fire_action(a, a.frame)

  elseif a.loop_mode == 'loop' then
    if next_frame > total then
      a.frame = 1
      fire_action(a, 0)
      fire_action(a, a.frame)
    else
      a.frame = next_frame
      fire_action(a, a.frame)
    end

  elseif a.loop_mode == 'bounce' then
    if next_frame > total then
      a.direction = -1
      a.frame = total - 1
      fire_action(a, 0)
      if a.frame >= 1 then fire_action(a, a.frame) end
    elseif next_frame < 1 then
      a.direction = 1
      a.frame = 2
      fire_action(a, 0)
      if a.frame <= total then fire_action(a, a.frame) end
    else
      a.frame = next_frame
      fire_action(a, a.frame)
    end
  end
end

--[[
  animation_update(a, dt)
  Advances the animation timer and fires frame transitions.
]]
function animation_update(a, dt)
  if not a.playing or a.dead then return end
  a.timer = a.timer + dt
  local current_delay = get_delay(a, a.frame)
  while a.timer >= current_delay and a.playing and not a.dead do
    a.timer = a.timer - current_delay
    advance_frame(a)
    current_delay = get_delay(a, a.frame)
  end
end
