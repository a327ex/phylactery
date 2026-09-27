--[[
  memory — memory / resource tracker overlay for leak detection.

  Snapshots the engine's resource counters (engine_mem_stats) plus Lua-side
  signals (collectgarbage heap size, entity count) each frame. Renders a
  toggleable overlay comparing current values against a captured baseline
  so you can verify that a repeated action (map reload, UI open/close, etc.)
  returns every counter to its pre-action value.

  Usage:
    mem = memory_tracker_new()
    -- in update:
    memory_tracker_update(mem)
    if is_pressed('toggle_mem')   then memory_tracker_toggle(mem) end
    if is_pressed('baseline_mem') then memory_tracker_capture_baseline(mem) end
    -- in draw:
    memory_tracker_draw(mem, debug_layer, debug_font)

  The overlay shows: LABEL   CURRENT   (Δbaseline)
  Non-zero baseline deltas highlight the row — that's the leak signal.
]]

--[[
  memory_tracker_capture()
  Returns a flat snapshot table. Engine counters come from engine_mem_stats;
  lua_kb and entities are added Lua-side. The snapshot is a plain table, no
  methods — safe to copy/compare.
]]
function memory_tracker_capture()
  local s = engine_mem_stats()
  s.lua_kb = collectgarbage('count')  -- Lua heap size in KB (float)
  local n = 0
  for _ in pairs(entities) do n = n + 1 end
  s.entities = n
  return s
end

--[[
  memory_tracker_new()
  Creates an empty tracker. Capture a snapshot each frame via update(),
  capture a baseline via capture_baseline() when you want to start watching.
]]
function memory_tracker_new()
  return {
    shown = false,
    current = nil,   -- latest snapshot (updated each frame)
    prev = nil,      -- previous frame's snapshot (for frame delta, unused for now)
    baseline = nil,  -- captured baseline snapshot
  }
end

-- Only capture while shown — engine_mem_stats is cheap but calls OS memory
-- APIs every frame, which is wasted cycles when the overlay is hidden.
function memory_tracker_update(t)
  if not t.shown then return end
  t.prev = t.current
  t.current = memory_tracker_capture()
end

function memory_tracker_toggle(t)
  t.shown = not t.shown
end

function memory_tracker_set_shown(t, shown)
  t.shown = shown
end

--[[
  memory_tracker_capture_baseline(t)
  Sets baseline to the current snapshot. From this point on, the overlay
  shows deltas relative to this value — so you can do an action N times
  and verify every delta stays 0.
]]
function memory_tracker_capture_baseline(t)
  t.baseline = memory_tracker_capture()
  t.current = t.baseline
end

-- Human-readable byte formatter. Chooses B / KB / MB so numbers stay short.
local function fmt_bytes(n)
  if not n then return '?' end
  local an = n < 0 and -n or n
  if an < 1024 then
    return string.format('%dB', n)
  elseif an < 1024*1024 then
    return string.format('%.1fKB', n/1024)
  else
    return string.format('%.1fMB', n/(1024*1024))
  end
end

-- Integer formatter with sign for deltas (so +3 reads differently than 3).
local function fmt_delta_int(n)
  if n == 0 then return '' end
  if n > 0 then return string.format('+%d', n) end
  return tostring(n)
end

local function fmt_delta_bytes(n)
  if n == 0 then return '' end
  local sign = n >= 0 and '+' or '-'
  return sign .. fmt_bytes(n < 0 and -n or n)
end

-- Row definitions: {label, key, kind}.
-- kind: 'int' (count) or 'bytes' (display with KB/MB suffix).
-- Order groups related things (process / lua / gl / physics / audio / fonts).
local rows = {
  {'process_rss',    'process_rss',     'bytes'},
  {'process_priv',   'process_private', 'bytes'},
  {'lua_heap',       'lua_kb',          'kb'},     -- lua_kb is already KB
  {'entities',       'entities',        'int'},
  {'gl_textures',    'gl_textures',     'int'},
  {'gl_tex_bytes',   'gl_texture_bytes','bytes'},
  {'gl_fbos',        'gl_fbos',         'int'},
  {'gl_rbos',        'gl_rbos',         'int'},
  {'gl_programs',    'gl_programs',     'int'},
  {'phys_bodies',    'physics_bodies',  'int'},
  {'phys_shapes',    'physics_shapes',  'int'},
  {'phys_joints',    'physics_joints',  'int'},
  {'phys_contacts',  'physics_contacts','int'},
  {'phys_bytes',     'physics_bytes',   'bytes'},
  {'sounds',         'sounds',          'int'},
  {'sound_bytes',    'sound_bytes',     'bytes'},
  {'music',          'music',           'int'},
  {'music_bytes',    'music_bytes',     'bytes'},
  {'playing_sounds', 'playing_sounds',  'int'},
  {'fonts',          'fonts',           'int'},
  {'font_bytes',     'font_bytes',      'bytes'},
  {'spritesheets',   'spritesheets',    'int'},
}

-- Format a value for display given its kind.
local function fmt_value(v, kind)
  if kind == 'int' then return tostring(v or 0)
  elseif kind == 'kb' then return string.format('%.1fKB', v or 0)
  elseif kind == 'bytes' then return fmt_bytes(v or 0)
  end
  return tostring(v)
end

-- Format a delta for display given its kind.
local function fmt_delta(d, kind)
  if d == 0 then return '' end
  if kind == 'int' then return fmt_delta_int(d)
  elseif kind == 'kb' then
    if d > 0 then return string.format('+%.1fKB', d) end
    return string.format('%.1fKB', d)
  elseif kind == 'bytes' then return fmt_delta_bytes(d)
  end
  return tostring(d)
end

--[[
  memory_tracker_draw(t, layer, font)
  Renders the overlay onto `layer` using `font` (a font object or name).
  Draws at fixed screen-space coordinates in the top-left.
  Call BEFORE layer_render/layer_draw on that layer.
]]
function memory_tracker_draw(t, layer, font)
  if not t.shown or not t.current then return end

  local pad = 4
  local line_h = (font.height or 11) + 1
  local col_label_w = 90   -- label column width
  local col_value_w = 70   -- value column width
  local row_count = #rows + 2  -- +2 for header lines

  -- Background panel
  local panel_w = col_label_w + col_value_w + 80 + pad*2
  local panel_h = row_count*line_h + pad*2
  layer_rectangle(layer, 0, 0, panel_w, panel_h, rgba(0, 0, 0, 200))

  ---@diagnostic disable-next-line: undefined-global   (fg_color is the game's hook; nil-safe callers guard it)
  local text_color = fg_color()
  local delta_color = rgba(255, 100, 100, 255)  -- red for non-zero delta = leak signal
  local header_color = rgba(180, 180, 180, 255)

  local x = pad
  local y = pad

  -- Header
  layer_text(layer, 'MEMORY (F3 hide / F4 baseline)', font, x, y, header_color)
  y = y + line_h
  if t.baseline then
    layer_text(layer, 'baseline captured', font, x, y, header_color)
  else
    layer_text(layer, 'no baseline yet', font, x, y, header_color)
  end
  y = y + line_h

  for i = 1, #rows do
    local label = rows[i][1]
    local key = rows[i][2]
    local kind = rows[i][3]
    local cur = t.current[key] or 0
    local base = t.baseline and t.baseline[key] or cur
    local delta = cur - base

    layer_text(layer, label, font, x, y, text_color)
    layer_text(layer, fmt_value(cur, kind), font, x + col_label_w, y, text_color)
    if delta ~= 0 then
      layer_text(layer, fmt_delta(delta, kind), font, x + col_label_w + col_value_w, y, delta_color)
    end
    y = y + line_h
  end
end
