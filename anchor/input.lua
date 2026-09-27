--[[
  input — thin wrapper layer over the engine's built-in action binding system.

  The C engine provides input_bind/is_down/is_pressed/is_released/etc.
  This module provides function wrappers that forward to those. Function
  wrappers (instead of direct aliases) are used so that the engine C
  functions are resolved at *call* time, not at module *load* time.
  (The engine registers its functions during engine_init(), which runs
  AFTER this module is loaded.)

  Usage:
    bind('left', 'key:a')
    bind('left', 'key:left')
    bind('shoot', 'mouse:1')

    if input_down('left') then ... end
    if input_pressed('shoot') then ... end

  Bind string format (parsed by the engine):
    'key:<name>'    -- keyboard key (e.g., 'key:a', 'key:space', 'key:left')
    'mouse:<num>'   -- mouse button: 1 = left, 2 = RIGHT, 3 = middle (LÖVE order,
                       the engine swaps SDL's 2/3 at the event boundary)

  ⚠ EDGES ARE UPDATE-ONLY: input_pressed / input_released (and the raw
  key_is_pressed / mouse_is_pressed) read a current-vs-previous snapshot that
  the engine advances right after update() and before draw(). Called from
  draw() they raise on desktop (a one-time warning on the web) — do all input
  logic in update(). Level queries (input_down, mouse_position) work anywhere.
]]

-- Registration

--- Bind an action name to a control string ('key:a', 'mouse:1', 'gamepad:a', ...).
---@param action string
---@param control string
function bind(action, control) input_bind(action, control) end

---@param action string
---@param control string
function unbind(action, control) input_unbind(action, control) end

---@param action string
function unbind_all(action) input_unbind_all(action) end

--- A chord fires when every listed action is held at once.
---@param name string
---@param actions string[]
function bind_chord(name, actions) input_bind_chord(name, actions) end

--- A sequence fires when the listed actions are pressed in order.
---@param name string
---@param sequence string[]
function bind_sequence(name, sequence) input_bind_sequence(name, sequence) end

--- A hold fires after `source` has been held for `duration` seconds.
---@param name string
---@param duration number
---@param source string
function bind_hold(name, duration, source) input_bind_hold(name, duration, source) end

-- Queries

--- Level: true every frame the action's control is held.
---@param action string
---@return boolean
function input_down(action) return is_down(action) end

--- Edge: true on the update the control went down. UPDATE-ONLY (see header).
---@param action string
---@return boolean
function input_pressed(action) return is_pressed(action) end

--- Edge: true on the update the control came up. UPDATE-ONLY (see header).
---@param action string
---@return boolean
function input_released(action) return is_released(action) end

--- Edge: true on an update where the OS auto-repeated a key bound to the action, at the
--- user's own keyboard delay and rate; never the first press. A text field reads
--- `input_pressed(a) or input_repeated(a)` instead of timing its own repeat. UPDATE-ONLY.
---@param action string
---@return boolean
function input_repeated(action) return is_repeated(action) end

-- Composite queries

--- -1, 0 or 1 from a negative/positive action pair (gamepad axes contribute analog values).
---@param neg string
---@param pos string
---@return number
function input_axis(neg, pos) return input_get_axis(neg, pos) end

--- Normalized 2D vector from four directional actions.
---@param left string
---@param right string
---@param up string
---@param down string
---@return number x
---@return number y
function input_vector(left, right, up, down) return input_get_vector(left, right, up, down) end

---@param name string
---@return number
function input_hold_duration(name) return input_get_hold_duration(name) end

--- 'keyboard' | 'mouse' | 'gamepad' — the device that produced the last input.
---@return string
function input_last_type() return input_get_last_type() end

--- The name of an action pressed this update, or nil.
---@return string|nil
function input_pressed_action() return input_get_pressed_action() end

-- Capture (for a "press a key to rebind" UI flow)

function input_capture_start() input_start_capture() end

--- The control string captured since input_capture_start, or nil.
---@return string|nil
function input_capture_get() return input_get_captured() end

function input_capture_stop() input_stop_capture() end

-- Deadzone for gamepad axes

---@param d number   0-1
function input_deadzone(d) input_set_deadzone(d) end
