--[[
  timer — procedural scheduler for delayed, repeating, and conditional callbacks.

  Usage:
    self.timer = timer_new()                                     -- in your constructor
    timer_after(self.timer, 1, function() print('fired') end)
    timer_every(self.timer, 0.5, 'attack', function() self:attack() end)
    timer_update(self.timer, dt)                                 -- in your update

  All schedule functions accept an optional name parameter (as first arg after
  the timer) for naming the scheduled callback. Named callbacks can be cancelled,
  triggered manually, and replace previous ones with the same name. Anonymous
  callbacks get auto-generated internal IDs.

  Available schedule modes:
    timer_after     - fire once after delay
    timer_every     - fire repeatedly every delay (optionally N times)
    timer_during    - fire every frame for duration, receives progress 0-1
    timer_tween     - interpolate target properties over duration with easing
    timer_watch     - fire when a field on a target changes
    timer_when      - fire when a condition transitions false -> true
    timer_cooldown  - fire every delay seconds while condition is true
    timer_every_step  - fire N times with delays interpolating start to end
    timer_during_step - fit as many calls as possible in duration, with varying delays

  Control:
    timer_cancel          - cancel a named callback
    timer_trigger         - fire a named callback immediately
    timer_set_multiplier  - dynamically adjust timer speed
    timer_get_time_left   - query remaining time until a named callback fires

  Design notes:
    - No `self` on the timer. Call functions with the timer as first argument.
    - The watch mode takes the target object explicitly (v1 used self.parent,
      which depended on the tree). Pass the target: timer_watch(t, target, 'hp', fn).
    - Update is explicit: call timer_update(t, dt) from wherever you own the timer.
    - Tweens and `math.lerp`/easing depend on math.lua being loaded.
    - Reload-friendliness (2026-09): short-lived closures that capture DATA and
      call globals by name are fine across a code reload — their captured values
      stay valid and the globals resolve to the new code. Long-lived schedules
      (every / cooldown / watch / when) keep running their OLD body after a
      reload; create those in the game's on_reload() so they are re-made.
]]

---@class Timer
---@field entries table[]
---@field next_id integer

---@alias TimerCallback fun()
---@alias EasingFn fun(t: number): number

--[[
  timer_new()
  Creates a new timer state.
]]
---@return Timer
function timer_new()
  return {
    entries = {},
    next_id = 1,
  }
end

-- Internal: generate a unique internal name for anonymous entries.
local function uid(t)
  local id = "_anon_" .. t.next_id
  t.next_id = t.next_id + 1
  return id
end

-- Internal: find entry index by name.
local function find(t, name)
  for i = 1, #t.entries do
    if t.entries[i].name == name then return i end
  end
  return nil
end

-- Internal: insert an entry, replacing any with the same name.
local function insert_entry(t, entry)
  local i = find(t, entry.name)
  if i then
    t.entries[i] = entry
  else
    t.entries[#t.entries + 1] = entry
  end
end

--[[
  timer_after(t, delay, [name,] callback)
  Fires callback once after delay seconds.
]]
---@param t Timer
---@param delay number
---@param name_or_callback string|TimerCallback   a name (then callback follows) or the callback
---@param callback_function? TimerCallback
---@overload fun(t: Timer, delay: number, callback: TimerCallback)
function timer_after(t, delay, name_or_callback, callback_function)
  local name, callback
  if type(name_or_callback) == 'string' then
    name, callback = name_or_callback, callback_function
  else
    name, callback = uid(t), name_or_callback
  end
  insert_entry(t, {name = name, mode = 'after', time = 0, delay = delay, callback = callback})
end

--[[
  timer_every(t, delay, [name,] callback, [times,] [after])
  Fires callback repeatedly every delay seconds. If times is specified,
  stops after that many fires and calls the `after` callback.
]]
---@param t Timer
---@param delay number
---@param name_or_callback string|TimerCallback
---@param callback_or_times? TimerCallback|integer
---@param times_or_after? integer|TimerCallback
---@param after_function? TimerCallback
---@overload fun(t: Timer, delay: number, callback: TimerCallback, times?: integer, after?: TimerCallback)
function timer_every(t, delay, name_or_callback, callback_or_times, times_or_after, after_function)
  local name, callback, times, after
  if type(name_or_callback) == 'string' then
    name, callback, times, after = name_or_callback, callback_or_times, times_or_after, after_function
  else
    name, callback, times, after = uid(t), name_or_callback, callback_or_times, times_or_after
  end
  insert_entry(t, {name = name, mode = 'every', time = 0, delay = delay, callback = callback, times = times, after = after, count = 0})
end

--[[
  timer_during(t, duration, [name,] callback, [after])
  Fires callback(dt, progress) every frame for duration seconds.
  Progress is 0 to 1 and reaches exactly 1 on the final frame.
]]
---@param t Timer
---@param duration number
---@param name_or_callback string|fun(dt: number, progress: number)
---@param callback_or_after? fun(dt: number, progress: number)|TimerCallback
---@param after_function? TimerCallback
---@overload fun(t: Timer, duration: number, callback: fun(dt: number, progress: number), after?: TimerCallback)
function timer_during(t, duration, name_or_callback, callback_or_after, after_function)
  local name, callback, after
  if type(name_or_callback) == 'string' then
    name, callback, after = name_or_callback, callback_or_after, after_function
  else
    name, callback, after = uid(t), name_or_callback, callback_or_after
  end
  insert_entry(t, {name = name, mode = 'during', time = 0, duration = duration, callback = callback, after = after})
end

--[[
  timer_tween(t, duration, [name,] target, values, [easing,] [after])
  Interpolates target's fields to values over duration using easing.
  Example: timer_tween(t, 0.5, self, {x = 100, alpha = 0}, math.cubic_out)
]]
---@param t Timer
---@param duration number
---@param name_or_target string|table
---@param target_or_values table
---@param values_or_easing? table|EasingFn
---@param easing_or_after? EasingFn|TimerCallback
---@param after_function? TimerCallback
---@overload fun(t: Timer, duration: number, target: table, values: table<string, number>, easing?: EasingFn, after?: TimerCallback)
function timer_tween(t, duration, name_or_target, target_or_values, values_or_easing, easing_or_after, after_function)
  local name, target, values, easing, after
  if type(name_or_target) == 'string' then
    name, target, values, easing, after = name_or_target, target_or_values, values_or_easing, easing_or_after, after_function
  else
    name, target, values, easing, after = uid(t), name_or_target, target_or_values, values_or_easing, easing_or_after
  end
  easing = easing or math.linear
  local initial_values = {}
  for key, _ in pairs(values --[[@as table]]) do
    initial_values[key] = target[key]
  end
  insert_entry(t, {name = name, mode = 'tween', time = 0, duration = duration, target = target, values = values, initial_values = initial_values, easing = easing, after = after})
end

--[[
  timer_watch(t, target, field, [name,] callback, [times,] [after])
  Fires callback(current, previous) when target[field] changes.
  Note: v1's watch used self.parent implicitly. v2 takes the target explicitly.
]]
---@param t Timer
---@param target table
---@param field string
---@param name_or_callback string|fun(current: any, previous: any)
---@param callback_or_times? fun(current: any, previous: any)|integer
---@param times_or_after? integer|TimerCallback
---@param after_function? TimerCallback
---@overload fun(t: Timer, target: table, field: string, callback: fun(current: any, previous: any), times?: integer, after?: TimerCallback)
function timer_watch(t, target, field, name_or_callback, callback_or_times, times_or_after, after_function)
  local name, callback, times, after
  if type(name_or_callback) == 'string' then
    name, callback, times, after = name_or_callback, callback_or_times, times_or_after, after_function
  else
    name, callback, times, after = uid(t), name_or_callback, callback_or_times, times_or_after
  end
  local initial_value = target[field]
  insert_entry(t, {name = name, mode = 'watch', time = 0, target = target, field = field, current = initial_value, previous = initial_value, callback = callback, times = times, after = after, count = 0})
end

--[[
  timer_when(t, condition_fn, [name,] callback, [times,] [after])
  Fires callback when condition_fn() transitions from false to true.
  Edge-triggered: does NOT fire every frame the condition is true.
]]
---@param t Timer
---@param condition_fn fun(): boolean
---@param name_or_callback string|TimerCallback
---@param callback_or_times? TimerCallback|integer
---@param times_or_after? integer|TimerCallback
---@param after_function? TimerCallback
---@overload fun(t: Timer, condition_fn: (fun(): boolean), callback: TimerCallback, times?: integer, after?: TimerCallback)
function timer_when(t, condition_fn, name_or_callback, callback_or_times, times_or_after, after_function)
  local name, callback, times, after
  if type(name_or_callback) == 'string' then
    name, callback, times, after = name_or_callback, callback_or_times, times_or_after, after_function
  else
    name, callback, times, after = uid(t), name_or_callback, callback_or_times, times_or_after
  end
  insert_entry(t, {name = name, mode = 'when', time = 0, condition = condition_fn, last_condition = false, callback = callback, times = times, after = after, count = 0})
end

--[[
  timer_cooldown(t, delay, condition_fn, [name,] callback, [times,] [after])
  Fires callback every delay seconds while condition_fn() is true.
  Cooldown resets when condition transitions false -> true.
]]
---@param t Timer
---@param delay number
---@param condition_fn fun(): boolean
---@param name_or_callback string|TimerCallback
---@param callback_or_times? TimerCallback|integer
---@param times_or_after? integer|TimerCallback
---@param after_function? TimerCallback
---@overload fun(t: Timer, delay: number, condition_fn: (fun(): boolean), callback: TimerCallback, times?: integer, after?: TimerCallback)
function timer_cooldown(t, delay, condition_fn, name_or_callback, callback_or_times, times_or_after, after_function)
  local name, callback, times, after
  if type(name_or_callback) == 'string' then
    name, callback, times, after = name_or_callback, callback_or_times, times_or_after, after_function
  else
    name, callback, times, after = uid(t), name_or_callback, callback_or_times, times_or_after
  end
  insert_entry(t, {name = name, mode = 'cooldown', time = 0, delay = delay, condition = condition_fn, last_condition = false, callback = callback, times = times, after = after, count = 0})
end

--[[
  timer_every_step(t, start_delay, end_delay, times, [name,] callback, [step_method,] [after])
  Fires callback `times` times with delays interpolating from start_delay to end_delay.
  Useful for effects that speed up or slow down.
]]
---@param t Timer
---@param start_delay number
---@param end_delay number
---@param times integer
---@param name_or_callback string|TimerCallback
---@param callback_or_step? TimerCallback|EasingFn
---@param step_or_after? EasingFn|TimerCallback
---@param after_function? TimerCallback
---@overload fun(t: Timer, start_delay: number, end_delay: number, times: integer, callback: TimerCallback, step_method?: EasingFn, after?: TimerCallback)
function timer_every_step(t, start_delay, end_delay, times, name_or_callback, callback_or_step, step_or_after, after_function)
  local name, callback, step_method, after
  if type(name_or_callback) == 'string' then
    name, callback, step_method, after = name_or_callback, callback_or_step, step_or_after, after_function
  else
    name, callback, step_method, after = uid(t), name_or_callback, callback_or_step, step_or_after
  end
  step_method = step_method or math.linear
  local delays = {}
  for i = 1, times do
    local tt = (i - 1)/(times - 1)
    tt = step_method(tt)
    delays[i] = math.lerp(tt, start_delay, end_delay)
  end
  insert_entry(t, {name = name, mode = 'every_step', time = 0, delays = delays, callback = callback, after = after, step_index = 1})
end

--[[
  timer_during_step(t, duration, start_delay, end_delay, [name,] callback, [step_method,] [after])
  Fits as many callback calls as possible within duration with varying delays.
]]
---@param t Timer
---@param duration number
---@param start_delay number
---@param end_delay number
---@param name_or_callback string|TimerCallback
---@param callback_or_step? TimerCallback|EasingFn
---@param step_or_after? EasingFn|TimerCallback
---@param after_function? TimerCallback
---@overload fun(t: Timer, duration: number, start_delay: number, end_delay: number, callback: TimerCallback, step_method?: EasingFn, after?: TimerCallback)
function timer_during_step(t, duration, start_delay, end_delay, name_or_callback, callback_or_step, step_or_after, after_function)
  local name, callback, step_method, after
  if type(name_or_callback) == 'string' then
    name, callback, step_method, after = name_or_callback, callback_or_step, step_or_after, after_function
  else
    name, callback, step_method, after = uid(t), name_or_callback, callback_or_step, step_or_after
  end
  step_method = step_method or math.linear
  local times = math.ceil(2*duration/(start_delay + end_delay))
  if times < 2 then times = 2 end
  local delays = {}
  for i = 1, times do
    local tt = (i - 1)/(times - 1)
    tt = step_method(tt)
    delays[i] = math.lerp(tt, start_delay, end_delay)
  end
  insert_entry(t, {name = name, mode = 'during_step', time = 0, delays = delays, callback = callback, after = after, step_index = 1})
end

--[[
  timer_cancel(t, name)
  Cancels a named callback. The `after` callback does NOT fire.
]]
---@param t Timer
---@param name string
function timer_cancel(t, name)
  local i = find(t, name)
  if i then t.entries[i].cancelled = true end
end

--[[
  timer_trigger(t, name)
  Fires a named callback immediately. Behavior depends on mode:
    - after: fires and removes
    - every/cooldown/*_step: fires and resets time
    - watch/when: fires callback once
    - during/tween: not supported (continuous modes)
]]
---@param t Timer
---@param name string
function timer_trigger(t, name)
  local i = find(t, name)
  if not i then return end
  local e = t.entries[i]
  if e.mode == 'after' then
    e.callback(); e.cancelled = true
  elseif e.mode == 'every' or e.mode == 'cooldown' or e.mode == 'every_step' or e.mode == 'during_step' then
    e.callback(); e.time = 0
  elseif e.mode == 'watch' then
    e.callback(e.current, e.previous)
  elseif e.mode == 'when' then
    e.callback()
  end
end

--[[
  timer_set_multiplier(t, name, multiplier)
  Adjusts speed of a named callback. multiplier affects delay/duration:
  actual = delay * multiplier. So multiplier=2 means slower (double delay).
  Multiplier=0.5 means faster (half delay).
]]
---@param t Timer
---@param name string
---@param multiplier? number   default 1
function timer_set_multiplier(t, name, multiplier)
  local i = find(t, name)
  if i then t.entries[i].multiplier = multiplier or 1 end
end

--[[
  timer_get_time_left(t, name)
  Returns seconds remaining until the named callback fires, or nil if
  the name isn't found or the mode isn't time-based (watch, when).
]]
---@param t Timer
---@param name string
---@return number|nil
function timer_get_time_left(t, name)
  local i = find(t, name)
  if not i then return nil end
  local e = t.entries[i]
  if e.mode == 'after' or e.mode == 'every' or e.mode == 'cooldown' then
    return e.delay*(e.multiplier or 1) - e.time
  elseif e.mode == 'during' or e.mode == 'tween' then
    return e.duration*(e.multiplier or 1) - e.time
  elseif e.mode == 'every_step' or e.mode == 'during_step' then
    return e.delays[e.step_index] - e.time
  else
    return nil
  end
end

--[[
  timer_update(t, dt)
  Advances all scheduled callbacks. Call once per frame for each timer you own.
]]
---@param t Timer
---@param dt number
function timer_update(t, dt)
  local entries = t.entries
  for i = 1, #entries do
    local e = entries[i]
    if not e.cancelled then
      e.time = e.time + dt

      if e.mode == 'after' then
        local delay = e.delay*(e.multiplier or 1)
        if e.time >= delay then
          e.callback()
          e.to_be_removed = true
        end

      elseif e.mode == 'every' then
        local delay = e.delay*(e.multiplier or 1)
        if e.time >= delay then
          e.callback()
          e.time = e.time - delay
          if e.times then
            e.count = e.count + 1
            if e.count >= e.times then
              if e.after then e.after() end
              e.to_be_removed = true
            end
          end
        end

      elseif e.mode == 'during' then
        local duration = e.duration*(e.multiplier or 1)
        local progress = e.time/duration
        if progress > 1 then progress = 1 end
        e.callback(dt, progress)
        if e.time >= duration then
          if e.after then e.after() end
          e.to_be_removed = true
        end

      elseif e.mode == 'tween' then
        local duration = e.duration*(e.multiplier or 1)
        local progress = e.time/duration
        if progress > 1 then progress = 1 end
        local eased = e.easing(progress)
        for key, target_value in pairs(e.values) do
          e.target[key] = math.lerp(eased, e.initial_values[key], target_value)
        end
        if e.time >= duration then
          if e.after then e.after() end
          e.to_be_removed = true
        end

      elseif e.mode == 'watch' then
        e.previous = e.current
        e.current = e.target[e.field]
        if e.previous ~= e.current then
          e.callback(e.current, e.previous)
          if e.times then
            e.count = e.count + 1
            if e.count >= e.times then
              if e.after then e.after() end
              e.to_be_removed = true
            end
          end
        end

      elseif e.mode == 'when' then
        local current_condition = e.condition()
        if current_condition and not e.last_condition then
          e.callback()
          if e.times then
            e.count = e.count + 1
            if e.count >= e.times then
              if e.after then e.after() end
              e.to_be_removed = true
            end
          end
        end
        e.last_condition = current_condition

      elseif e.mode == 'cooldown' then
        local delay = e.delay*(e.multiplier or 1)
        local current_condition = e.condition()
        if current_condition and not e.last_condition then
          e.time = 0
        end
        if e.time >= delay and current_condition then
          e.callback()
          e.time = 0
          if e.times then
            e.count = e.count + 1
            if e.count >= e.times then
              if e.after then e.after() end
              e.to_be_removed = true
            end
          end
        end
        e.last_condition = current_condition

      elseif e.mode == 'every_step' then
        if e.time >= e.delays[e.step_index] then
          e.callback()
          e.time = e.time - e.delays[e.step_index]
          e.step_index = e.step_index + 1
          if e.step_index > #e.delays then
            if e.after then e.after() end
            e.to_be_removed = true
          end
        end

      elseif e.mode == 'during_step' then
        if e.time >= e.delays[e.step_index] then
          e.callback()
          e.time = e.time - e.delays[e.step_index]
          e.step_index = e.step_index + 1
          if e.step_index > #e.delays then
            if e.after then e.after() end
            e.to_be_removed = true
          end
        end
      end
    else
      e.to_be_removed = true
    end
  end

  for i = #entries, 1, -1 do
    if entries[i].to_be_removed then table.remove(entries, i) end
  end
end
