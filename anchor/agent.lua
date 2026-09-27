--[[
  agent — the kit an agent drives a running game with, through the eval
  channel (`anchor drive eval <game> '<lua>'`). Every helper here is a plain
  Lua function callable from any eval; the engine primitives underneath are
  engine_step / input_inject_* / engine_snapshot / replay_mark.

  Usage (from a driver):
    anchor drive start knightvspawns
    anchor drive eval  knightvspawns 'engine_step(120)'
    anchor drive eval  knightvspawns 'agent_tap("right")'
    anchor drive eval  knightvspawns 'agent_wait_until(function() return #pawns > 3 end, 600)'
    anchor drive eval  knightvspawns 'agent_shot()'
    anchor drive eval  knightvspawns '#pawns'
    anchor drive stop  knightvspawns

  HOW COMMANDS EVOLVE (the process, for every future instance):
    1. Ad-hoc eval — anything, any time; no process.
    2. GAME-LEVEL commands: functions in the game's own files prefixed
       `agent_` (agent_spawn_wave, agent_pick_item('comet')). Add them freely
       when a task needs them, with a one-line comment; they are the game's
       vocabulary and stay with the game.
    3. KIT-LEVEL commands (this file): promoted when a helper proved useful
       in two games or is engine-generic. Add it here with annotations, and
       append a line to the LOG below (date, name, why, motivating game); the
       doc generator lists it in docs/AGENT.md.
    Rules: check this kit and agent_globals('agent_') before adding; add when
    you would need it twice; name the intent, not the mechanism; never rename
    or break an existing command — add beside it. Recordings of agent runs
    are the shared memory: every eval is a MARK in the .apr, so what worked
    is visible in the logs.

  Stepping helpers require an --agent instance (engine_step raises in a
  visible one — the owner's loop paces itself). Injection helpers work in
  both: in a visible instance the live loop consumes the injected events.

  LOG
    2026-09-05  agent_tap, agent_click, agent_wait_until, agent_dump,
                agent_globals, agent_shot — the initial kit (Phase 1 of
                reference/agent-workflow-plan.md; motivating game: Horse Game)
]]

--- Press and release a key with `frames` rendered frames in between (default 1),
--- so the framework's update-time edges see a clean press then release.
---@param name string   engine key name ('right', 'space', 'a', ...)
---@param frames? integer
---@return integer   frames stepped
function agent_tap(name, frames)
  input_inject_key(name, true)
  local n = engine_step(frames or 1)
  input_inject_key(name, false)
  return n + engine_step(1)
end

--- Click at a GAME-space point: move, press, step, release, step.
---@param x number
---@param y number
---@param button? integer   1 left (default), 2 right, 3 middle
---@return integer   frames stepped
function agent_click(x, y, button)
  input_inject_mouse_move(x, y)
  engine_step(1)
  input_inject_mouse_button(button or 1, true)
  engine_step(1)
  input_inject_mouse_button(button or 1, false)
  return 2 + engine_step(1)
end

--- Step until `pred()` holds, at most `max_steps` frames (default 600 = 10 s).
--- Returns the frames stepped and whether the predicate held.
---@param pred fun(): boolean
---@param max_steps? integer
---@return integer stepped
---@return boolean satisfied
function agent_wait_until(pred, max_steps)
  local limit = max_steps or 600
  for i = 1, limit do
    if pred() then return i - 1, true end
    if engine_step(1) == 0 then return i - 1, false end
  end
  return limit, pred() and true or false
end

--- A readable dump of a table (the channel already renders results, this is
--- for deeper or selective looks: pick the depth).
---@param t any
---@param depth? integer   default 2
---@param indent? string
---@return string
function agent_dump(t, depth, indent)
  depth = depth or 2
  indent = indent or ''
  if type(t) ~= 'table' then return tostring(t) end
  if depth <= 0 then return '{…}' end
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do
    local v = t[k]
    local vs = type(v) == 'table' and agent_dump(v, depth - 1, indent .. '  ') or tostring(v)
    out[#out + 1] = indent .. tostring(k) .. ' = ' .. vs
  end
  return '{\n' .. table.concat(out, '\n') .. '\n' .. indent .. '}'
end

--- Names of global functions matching a Lua pattern (default: the agent_ vocabulary).
---@param pattern? string
---@return string[]
function agent_globals(pattern)
  pattern = pattern or '^agent_'
  local names = {}
  for k, v in pairs(_G) do
    if type(v) == 'function' and type(k) == 'string' and k:find(pattern) then names[#names + 1] = k end
  end
  table.sort(names)
  return names
end

--- Save the current frame as a PNG. Default path replays/shots/<frame>.png
--- (the dir is created). Returns the path.
---@param path? string
---@return string
function agent_shot(path)
  path = path or ('replays/shots/%06d.png'):format(engine_state().frame)
  engine_snapshot(path)
  return path
end
