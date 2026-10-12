--[[
  LICH'S OWN since 2026-10-11 (round 68g): forked from megablock's mb/soundui.lua (megablock 012a1f1), first through
  tools/port_soundui.py (retired; it lists every change up to the fork). Megablock's later changes come over by hand.
  soundui.lua -- sounds as words, and the editor that tunes them (soundui.js + soundlib.js of the web
  build, native; round 5: the Tab list, the slot editor, 3D).
  While playing, every sound the game asks for shows up as its slot name: at its place in the world, or stacked
  near the bottom when it has none; a loop shows (name) while it sounds. Green = it has a file, yellow = no file yet,
  RED = no file ON PURPOSE (a pick nobody was sure of: it waits for him), grey = muted.

    TAB      the game stops and lists the sounds that were playing when you pressed it (and loops that just ended),
             then every red slot. Click one to edit it. TAB again or a click outside: play.
    ESC      the game stops and every slot is listed (the whole catalogue). Click one to edit it.
    EDITOR   one slot, in LAYERS: every play plays each layer, one of its files at random (its variations). A row
             per layer: LAYER n (click: the sliders are that layer's own, it plays), ONE AT RANDOM / ALL AT ONCE
             (how many of its files play), in a loop's slot LOOPS / PLAYS ONCE (once = as the loop starts), its files
             (click one: it plays alone and the sliders are its own; X removes it), + (find a file for that layer);
             + NEW LAYER; with a file clicked, MOVE IT TO another layer. RIGHT-CLICK a file or a layer: OUT / BACK IN
             (an out one stays listed, greyed and struck through, and never plays: for trying sets of variations).
             NAME* = settings of its own. Settings resolve file -> layer -> the whole sound -> the
             defaults (8 bits, 3x crush); right-click on a slider = back to the level above. Horse Game's tuner
             (volume, a random pitch range, a delay whose negative side starts into the clip, bits, sample-rate crush,
             low cut) and the 3D settings (spatial, binaural, the distance curve, near / far / rolloff, air, walls,
             the reverb send, width, doppler, travel time); below them the cave's reverb and EAR. Every change
             replays what is clicked from where it last played. SPACE plays, F finds a file, RESET clears where the
             editor is set, CTRL+Z / UNDO takes back the last change, ESC goes back. Everything saves itself
             (sound_picks.lua, sound_rooms.lua). A red slot shows its suggestions: click to listen, again to add.
    PICKER   (F, or a layer's +) Horse Game's sound picker over Desktop/sound packs: type to search, arrows or a click
             to listen, Enter (or a second click) ADDS it to the layer named at the top (nothing is ever replaced),
             Shift adds it as a new layer (the next adds join that one), Tab listens again.

  The game calls (port/game.lua):
    M.update(dt)          while stopped: keys, typing, clicks, drags, wheel
    M.draw(HUD, camera)   every frame, after the HUD
    M.open_list() / M.pause() / M.resume() / M.mode() -> 'play' | 'pause' | 'list' | 'edit' | 'picker'
    M.click_consumed()    true when this frame's left click is the UI's (the game must not grab the mouse)
    M.take_resume()       true once after the UI asked to go back to playing (TAB in the list)
  Also (the harness can drive it without a mouse): M.KNOWN, M.all_slots(), M.open_edit(name), M.open_picker(name),
  M.close_picker(), M.any_picks(), M.ui, M.lib, M.build_index(), M.search(q), M.SLIDERS.
]]
local AU = require('port.audio')
local TM = require('port.three.math')

local M = {}

-- every slot the code names (more appear as the game uses them)
M.KNOWN = {
  'cave_amb', 'shaft_hum', 'egg_shiver', 'lich_hover', 'lich_hurt', 'lich_hurt_pose', 'lich_die', 'lich_thud',
  'mask_drop', 'snake_hiss', 'snake_slither', 'snake_strike', 'coil_grip', 'coil_squeeze', 'coil_win', 'snake_dissolve',
  'snake_ash', 'fire_cast', 'fire_ignite', 'fire_burn', 'fire_sweep', 'lift_cast', 'lift_hold', 'lift_knot',
  'lift_swell', 'lift_fist', 'lift_burst', 'gore_crush', 'gore_land', 'mass_burst', 'rock_rip', 'rock_hold',
  'rock_throw', 'rock_hit', 'rock_land', 'leak_whisper', 'leak_ripple', 'leak_snake', 'beam_cast', 'beam_channel',
  'beam_shot', 'beam_bite', 'beam_shatter', 'beam_petals', 'lens_form', 'lens_charge', 'lens_fire', 'lens_cut',
  'lens_dissolve', 'item_throw', 'item_land_mask', 'item_land_hand', 'item_land_lodestone', 'item_land_orbs', 'item_land_gem', 'item_land_lens',
  'orb_clack', 'item_pickup', 'orb_hover', 'ui_hover', 'ui_click', 'viewer_open', 'viewer_close', 'viewer_next',
  'viewer_throw', 'power_lost', 'ending_begin', 'egg_knock', 'egg_crack', 'egg_open', 'egg_piece_land',
  'lens_shard_land',     -- (Lich, round 69: the broken lens's shards landing; no file yet)
  'lift_ball_burst',     -- (Lich, 2026-10-12: the lift's ball of snakes bursting; lift_burst = single ones)
}

local YELLOW, GREEN, RED, GREY = '#ffd65a', '#9be58f', '#ff5a4e', '#8d8a84'
local CREAM, DIM, INK = '#ece6d8', 'rgba(236,230,216,0.6)', 'rgba(8,8,10,0.78)'
local ORANGE = '#e88a64'
local LIFE = 1.6
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local function round(x) return floor(x + 0.5) end

-- sel / scroll / heard are 1-based row indices into ui.rows (0 / nil = none)
local ui = { mode = 'play', slot = nil, q = '', results = {}, rows = {}, sel = 0, scroll = 0, heard = nil,
  mx = -1, my = -1, panel_scroll = 0, list_scroll = 0, msg = '', msg_t = 0, back = 'list', list = {}, drag = nil,
  dirty = false, dirty_rooms = false, aud_t = 0, rt = 0, cand_heard = nil, resume = false }
M.ui = ui
local hits = {}          -- clickable rects of the last drawn frame: { x, y, w, h, act, drag, right, id }
local HUD                -- port/hud.lua, handed in by draw

local function tw(s, scale) return HUD.text_width(s, scale) end
local function say(m) ui.msg = m; ui.msg_t = 3 end

-- a slot's colour: what state it is in
local function status_color(name)
  if AU.muted(name) then return GREY end
  if AU.assigned(name) then return GREEN end
  if AU.unsure(name) then return RED end
  return YELLOW
end
M.status_color = status_color

function M.all_slots()
  local set, out = {}, {}
  for _, n in ipairs(M.KNOWN) do if not set[n] then set[n] = true; out[#out + 1] = n end end
  for n in pairs(AU.seen) do if not set[n] then set[n] = true; out[#out + 1] = n end end
  for n in pairs(AU.slots) do if not set[n] then set[n] = true; out[#out + 1] = n end end
  table.sort(out)
  return out
end

function M.unsure_slots()
  local out = {}
  for _, n in ipairs(M.all_slots()) do if AU.unsure(n) then out[#out + 1] = n end end
  return out
end

function M.any_picks()
  for _, s in pairs(AU.slots) do if s.files and #s.files > 0 then return true end end
  return false
end

local function is_loop(name)
  for L in pairs(AU.loop_set) do if L.name == name then return true end end
  return false
end

-- ================================================================================================ the library
-- (soundlib.js) His sound-pack library, Desktop/sound packs. Search is Horse Game's: every space-separated
-- token must match the relative path, filename hits rank above folder hits, word-boundary and early hits
-- rank higher.
local WINDOWS = package.config:sub(1, 1) == '\\'
local ROOT = WINDOWS and (((os.getenv('USERPROFILE') or 'C:/Users/a327e'):gsub('\\', '/')) .. '/Desktop/sound packs')
  or ((os.getenv('HOME') or '') .. '/sound packs')
local EXTS = { 'wav', 'ogg', 'mp3', 'flac' }      -- what the engine can audition (the packs hold wav + ogg)
local MAX_RESULTS = 500
local LIB = { root = ROOT, index = nil, folders = {}, reading_shown = false, error = '', ffmpeg = nil }
M.lib = LIB

function M.build_index()
  local index = {}
  local prefix = #ROOT + 2       -- strip 'ROOT/'
  local function add(path)
    local rel = path:sub(prefix)
    if #rel > 0 then
      local low = rel:lower()
      index[#index + 1] = { rel = rel, low = low, fstart = (low:find('[^/]*$')) }
    end
  end
  LIB.error = ''
  if WINDOWS then
    -- `dir /s /b` takes one quoted pattern per extension and prints absolute backslash paths, one per
    -- line; 2>nul swallows the "File Not Found" a pattern with no hits writes to stderr.
    local root, pats = ROOT:gsub('/', '\\'), {}
    for _, ext in ipairs(EXTS) do pats[#pats + 1] = ('"%s\\*.%s"'):format(root, ext) end
    local f = io.popen(('dir /s /b %s 2>nul'):format(table.concat(pats, ' ')), 'r')
    if not f then LIB.error = 'CANNOT RUN DIR' else
      for line in f:lines() do
        local path = line:gsub('\\', '/'):gsub('%s+$', '')
        if #path > 0 then add(path) end
      end
      f:close()
    end
  else
    local ors = {}
    for i, ext in ipairs(EXTS) do ors[#ors + 1] = (i > 1 and '-o ' or '') .. ("-iname '*.%s'"):format(ext) end
    local f = io.popen(("find '%s' -type f \\( %s \\) -print0 2>/dev/null"):format(ROOT, table.concat(ors, ' ')), 'r')
    if not f then LIB.error = 'CANNOT RUN FIND' else
      local blob = f:read('*a') or ''
      f:close()
      for path in blob:gmatch('%Z+') do add(path) end
    end
  end
  table.sort(index, function(a, b) if a.low ~= b.low then return a.low < b.low end; return a.rel < b.rel end)
  local seen, folders = {}, {}
  for _, e in ipairs(index) do
    local top = e.rel:match('^[^/]+')
    if top and not seen[top] then seen[top] = true; folders[#folders + 1] = top end
  end
  table.sort(folders, function(a, b) return a:lower() < b:lower() end)
  LIB.index, LIB.folders = index, folders
  print(('soundui: indexed %d files under %s'):format(#index, ROOT))
end

-- one token against one entry: filename hits beat path hits, boundaries and early positions beat buried
-- ones; nil = no match (the entry is out)
local BOUNDARY = '[/_%-%.%s%(%)%[%]0-9]'
local function tok_score(e, tok)
  local p = e.low:find(tok, e.fstart, true)
  if p then
    local s = 100
    local prev = (p == 1) and '/' or e.low:sub(p - 1, p - 1)
    if prev:match(BOUNDARY) then s = s + 30 end
    return s + max(0, 30 - (p - e.fstart))
  end
  p = e.low:find(tok, 1, true)
  if not p then return nil end
  local s = 40
  local prev = (p == 1) and '/' or e.low:sub(p - 1, p - 1)
  if prev:match(BOUNDARY) then s = s + 10 end
  return s + max(0, 20 - p)
end

function M.search(q)
  local toks = {}
  for t in q:lower():gmatch('%S+') do toks[#toks + 1] = t end
  if #toks == 0 or not LIB.index then return {} end
  local out = {}
  for _, e in ipairs(LIB.index) do
    local total = 0
    for _, t in ipairs(toks) do
      local s = tok_score(e, t)
      if not s then total = nil; break end
      total = total + s
    end
    if total then out[#out + 1] = { e = e, s = total } end
  end
  table.sort(out, function(a, b)
    if a.s ~= b.s then return a.s > b.s end
    if #a.e.rel ~= #b.e.rel then return #a.e.rel < #b.e.rel end
    return a.e.rel < b.e.rel
  end)
  for i = #out, MAX_RESULTS + 1, -1 do out[i] = nil end
  return out
end

-- ================================================================================================ picks -> sound
local function file_exists(path)
  local f = io.open(path, 'rb')
  if f then f:close(); return true end
  return false
end

local function have_ffmpeg()
  if LIB.ffmpeg then return true end
  local f = io.popen('ffmpeg -version 2>&1', 'r')
  if not f then return false end
  local out = f:read('*a') or ''
  f:close()
  LIB.ffmpeg = out:find('ffmpeg version', 1, true) ~= nil
  return LIB.ffmpeg
end

-- the pack file -> assets/sfx/<slot>_<n>.ogg (full length, no trims: the owner's rule); a fresh n each
-- time, so a file the game has loaded is never overwritten under it
local function convert(name, rel, s)
  dir_create('assets'); dir_create('assets/sfx')
  local base = name:gsub('[^%w_%-]', '_')
  local out, n = nil, 1
  while true do
    out = ('assets/sfx/%s_%d.ogg'):format(base, n)
    local used = false
    for _, f in ipairs(s.files) do if f == out then used = true; break end end
    if not used and not file_exists(out) then break end
    n = n + 1
  end
  local cmd = ('ffmpeg -y -loglevel error -i "%s" -c:a libvorbis -q:a 10 "%s" 2>&1'):format(ROOT .. '/' .. rel, out)
  local f = io.popen(cmd, 'r')
  if not f then return nil, 'CANNOT RUN FFMPEG' end
  local log = f:read('*a') or ''
  local ok = f:close()
  if not ok or not file_exists(out) then
    return nil, 'FFMPEG FAILED: ' .. ((log:match('[^\r\n]+') or 'NO OUTPUT'):sub(1, 80))
  end
  return out
end

local function reload(name)
  local ok, err = pcall(AU.reload, name)
  if not ok then say('CANNOT LOAD ' .. name:upper() .. ': ' .. tostring(err):sub(1, 60)) end
end

local function slot_of(name)
  local s = AU.slots[name] or { files = {}, src = {} }
  s.files = s.files or {}
  s.src = s.src or {}
  return s
end

-- (Lich) a pack file into the slot: always ADDED, nothing is ever replaced (X removes; CTRL+Z undoes). `layer` = the
-- layer it joins (a number) or 'new' (a layer of its own after the others). -> the layer it went into
local function add_pick(name, rel, layer)
  local s = slot_of(name)
  for _, r in ipairs(s.src) do if r == rel then say('ALREADY IN ' .. name:upper()); return end end
  if not have_ffmpeg() then say('FFMPEG NOT FOUND ON PATH'); return end
  local out, err = convert(name, rel, s)
  if not out then say(err); return end
  AU.slots[name] = s
  local list = AU.layers(name)
  if layer == 'new' then layer = #list > 0 and list[#list] + 1 or 1 end
  s.files[#s.files + 1] = out; s.src[#s.src + 1] = rel
  AU.set_layer_of(name, #s.files, layer or 1)
  AU.compact_layers(name)
  layer = AU.layer_of(name, #s.files)
  s.unsure = nil            -- a pick he made: no longer waiting for him
  AU.save_picks()
  reload(name)
  say('ADDED TO ' .. name:upper() .. ', LAYER ' .. layer)
  return layer
end

local function remove_pick(name, i)
  local s = AU.slots[name]
  if not s or not s.files then return end
  if s.per and s.files[i] then s.per[s.files[i]] = nil; if not next(s.per) then s.per = nil end end   -- (Lich)
  table.remove(s.files, i)
  if s.src and s.src[i] then table.remove(s.src, i) end
  AU.compact_layers(name)                                       -- (Lich) an emptied layer goes
  if ui.focus and ui.focus.slot == name then ui.focus = nil end
  AU.save_picks()
  reload(name)
end

-- (Lich) a file into another layer (n past the last = a new one)
local function move_file(name, fi, n)
  AU.set_layer_of(name, fi, n)
  AU.compact_layers(name)
  AU.save_picks()
  say('MOVED TO LAYER ' .. AU.layer_of(name, fi))
end

-- (Lich) where the editor is set: nil = the whole sound; { slot, kind = 'layer' | 'file', n }
local function focus_of(name)
  local f = ui.focus
  if f and f.slot == name then return f end
end

-- ================================================================================================ the settings
-- One row per setting: lo..hi, `map` = 'lin' | 'sq' (fine near lo) | 'log'; `q` = the step the value is kept at;
-- `fmt` = how it reads (`mul` scales it for reading). ROOM rows edit the reverb of the zone you stand in.
M.SLIDERS = {
  sound = {
    { key = 'vol', label = 'VOLUME', lo = 0, hi = 4, map = 'sq', q = 0.01, fmt = '%.2f' },
    { key = 'pitch_lo', label = 'PITCH LO', lo = 0.5, hi = 2, map = 'lin', q = 0.01, fmt = '%.2f' },
    { key = 'pitch_hi', label = 'PITCH HI', lo = 0.5, hi = 2, map = 'lin', q = 0.01, fmt = '%.2f' },
    { key = 'delay', label = 'DELAY', lo = -0.5, hi = 0.5, map = 'lin', q = 0.01, fmt = '%+dMS', mul = 1000 },
    { key = 'bits', label = 'BITS', lo = 16, hi = 1, map = 'lin', q = 1, fmt = '%d' },
    { key = 'sr', label = 'SR CRUSH', lo = 1, hi = 16, map = 'lin', q = 1, fmt = '%dX' },
    { key = 'lowcut', label = 'LOW CUT', lo = 0, hi = 2000, map = 'sq', q = 10, fmt = '%dHZ' },
    -- (Lich) a loop's: when the game stops it, it dies away over this long (0 = at once); shown for loops only
    { key = 'fade', label = 'FADE OUT', lo = 0, hi = 5, map = 'sq', q = 0.01, fmt = '%.2fS' },
  },
  space = {
    { key = 'near', label = 'NEAR', lo = 0.1, hi = 10, map = 'log', q = 0.05, fmt = '%.2fM' },
    { key = 'far', label = 'FAR', lo = 2, hi = 120, map = 'log', q = 0.5, fmt = '%.1fM' },
    { key = 'rolloff', label = 'ROLLOFF', lo = 0, hi = 4, map = 'lin', q = 0.05, fmt = '%.2f' },
    { key = 'air', label = 'AIR', lo = 0, hi = 6, map = 'sq', q = 0.05, fmt = '%.2f' },
    { key = 'occlusion', label = 'WALLS', lo = 0, hi = 2, map = 'lin', q = 0.05, fmt = '%.2f' },
    { key = 'reverb', label = 'REVERB', lo = 0, hi = 2, map = 'sq', q = 0.01, fmt = '%.2f' },
    { key = 'width', label = 'WIDTH', lo = 0, hi = 1, map = 'lin', q = 0.05, fmt = '%.2f' },
    { key = 'doppler', label = 'DOPPLER', lo = 0, hi = 30, map = 'sq', q = 0.1, fmt = '%.1fX' },
    { key = 'travel', label = 'TRAVEL', lo = 0, hi = 30, map = 'sq', q = 0.1, fmt = '%.1fX' },
  },
  room = {
    { key = 'size', label = 'SIZE', lo = 0, hi = 1, map = 'lin', q = 0.01, fmt = '%.2f' },
    { key = 'damp', label = 'DAMP', lo = 0, hi = 1, map = 'lin', q = 0.01, fmt = '%.2f' },
    { key = 'predelay', label = 'PREDELAY', lo = 0, hi = 0.25, map = 'sq', q = 0.001, fmt = '%dMS', mul = 1000 },
    { key = 'gain', label = 'LEVEL', lo = 0, hi = 3, map = 'sq', q = 0.01, fmt = '%.2f' },
    { key = 'width', label = 'WIDTH', lo = 0, hi = 1, map = 'lin', q = 0.01, fmt = '%.2f' },
    { key = 'lowcut', label = 'LOW CUT', lo = 0, hi = 1000, map = 'sq', q = 5, fmt = '%dHZ' },
    { key = 'head', label = 'EAR', lo = 0, hi = 1, map = 'lin', q = 0.01, fmt = '%d%% TO HIM', mul = 100 },   -- (Lich: 100% = his head, 0% = the camera)
  },
}

local function to_t(sp, v)
  local t
  if sp.map == 'log' then t = math.log(max(v, sp.lo) / sp.lo) / math.log(sp.hi / sp.lo)
  else t = (v - sp.lo) / (sp.hi - sp.lo) end
  t = max(0, min(1, t))
  if sp.map == 'sq' then t = math.sqrt(t) end
  return t
end
local function from_t(sp, t)
  t = max(0, min(1, t))
  local v
  if sp.map == 'log' then v = sp.lo * (sp.hi / sp.lo) ^ t
  elseif sp.map == 'sq' then v = sp.lo + (sp.hi - sp.lo) * t * t
  else v = sp.lo + (sp.hi - sp.lo) * t end
  return round(v / sp.q) * sp.q
end
local function fmt(sp, v)
  local x = v * (sp.mul or 1)
  return sp.fmt:format(sp.fmt:find('d', 1, true) and round(x) or x)
end

-- the reverb send of a slot as the editor shows it: its own, else what the game's call asks for
-- a setting changed: keep it, hear it (the drag replays at most every 0.25 s, as Horse Game's tuner)
-- (Lich) the editor's replays: the file clicked alone, the layer clicked (one of its files), else the whole sound
local function preview(name)
  local f = focus_of(name)
  if f and f.kind == 'file' then return AU.preview(name, f.n) end
  if f and f.kind == 'layer' then return AU.preview(name, nil, f.n) end
  return AU.preview(name)
end
local function changed(name, room)
  if room then ui.dirty_rooms = true else ui.dirty = true end
  if name and ui.rt - ui.aud_t > 0.25 then     -- (Lich: loops too: their game voice could be near silent or absent)
    ui.aud_t = ui.rt
    preview(name)
  end
end
local function flush_saves()
  if ui.dirty then AU.save_picks(); ui.dirty = false end
  if ui.dirty_rooms then AU.save_rooms(); ui.dirty_rooms = false end
end

local function reset_slot(name)
  local s = AU.slots[name]
  if not s then return end
  -- (Lich) RESET clears the settings of where the editor is set: a file's own, a layer's own, or the whole sound's
  -- with every layer's and file's own. The make-up stays: which layer a file is in, what is in or out, a layer's
  -- ONCE / LOOPS and ONE AT RANDOM / ALL AT ONCE
  local KEEP = { layer = true, off = true, once = true, all = true }
  local function clear(t) if t then for k in pairs(t) do if not KEEP[k] then t[k] = nil end end end end
  local f = focus_of(name)
  if f and f.kind == 'file' then
    local path = s.files and s.files[f.n]
    if path and s.per and s.per[path] then clear(s.per[path]); if not next(s.per[path]) then s.per[path] = nil end end
  elseif f and f.kind == 'layer' then
    local l = s.lay and s.lay[tostring(f.n)]
    if l then clear(l); if not next(l) then s.lay[tostring(f.n)] = nil end end
  else
    for k in pairs(AU.DEFAULTS) do if k ~= 'vol' and not KEEP[k] then s[k] = nil end end
    s.reverb = nil
    for _, p in pairs(s.per or {}) do clear(p) end
    for _, l in pairs(s.lay or {}) do clear(l) end
  end
  if s.per then for k, p in pairs(s.per) do if not next(p) then s.per[k] = nil end end; if not next(s.per) then s.per = nil end end
  if s.lay then for k, l in pairs(s.lay) do if not next(l) then s.lay[k] = nil end end; if not next(s.lay) then s.lay = nil end end
  ui.dirty = true
  flush_saves()
  preview(name)
end

-- ================================================================================================ modes
function M.mode() return ui.mode end
function M.pause() if ui.mode == 'play' then ui.mode = 'pause'; ui.back = 'pause'; ui.fresh = true end end
function M.resume() AU.stop_audition(); flush_saves(); ui.mode = 'play'; ui.drag = nil end
function M.take_resume() local r = ui.resume; ui.resume = false; return r end

-- TAB: what is sounding now and everything heard in the last RECENT seconds, newest first (Lich: was 1.5 s, and a
-- sound a few seconds before the one he noticed, lens_form before the lens's burn, could never be found)
local RECENT = 10
function M.open_list()
  local now, rows, seen = AU.now, {}, {}
  local playing = AU.playing()
  ui.list_age = {}
  for i = #AU.events, 1, -1 do
    local e = AU.events[i]
    if not seen[e.name] and (playing[e.name] or now - e.t <= RECENT) and now - e.t >= -0.01 then
      seen[e.name] = true; rows[#rows + 1] = e.name
      ui.list_age[e.name] = playing[e.name] and 0 or now - e.t
    end
  end
  local loops = {}
  for n in pairs(playing) do if not seen[n] then loops[#loops + 1] = n; ui.list_age[n] = 0 end end
  for n, t in pairs(AU.loop_end) do
    if not seen[n] and not playing[n] and now - t <= RECENT then loops[#loops + 1] = n; ui.list_age[n] = now - t end
  end
  table.sort(loops, function(a, b) return ui.list_age[a] < ui.list_age[b] end)
  for _, n in ipairs(loops) do seen[n] = true; rows[#rows + 1] = n end
  ui.list = rows
  ui.list_scroll = 0
  ui.mode = 'list'; ui.back = 'list'
  ui.fresh = true          -- the TAB that opened it must not close it in the same frame
end

function M.open_edit(name)
  ui.mode = 'edit'; ui.slot = name; ui.cand_heard = nil
  if not focus_of(name) then ui.focus = nil end     -- (Lich) back in the same sound: still set where it was
  engine_get_typed_text()
end

-- (Lich) target = the layer an added file joins (a number, or 'new'); nil = the layer clicked (or the clicked file's),
-- else the first
function M.open_picker(name, target)
  ui.mode = 'picker'; ui.slot = name; ui.q = ''; ui.results = {}; ui.sel = 0; ui.scroll = 0; ui.heard = nil
  if target == nil then
    local f = focus_of(name)
    target = f and (f.kind == 'layer' and f.n or AU.layer_of(name, f.n)) or 1
  end
  ui.target = target
  M.set_rows()
  engine_get_typed_text()    -- drop what was typed before it opened
end
function M.close_picker() AU.stop_audition(); ui.mode = 'edit'; ui.heard = nil end
-- (Lich) the picker's add (Enter, or a second click): into its layer; with Shift, a new layer of its own, which the
-- next adds then join (a sound plus its variations)
local function add_here(rel)
  local shift = key_is_down('lshift') or key_is_down('rshift')
  local n = add_pick(ui.slot, rel, shift and 'new' or ui.target)
  if n and (shift or ui.target == 'new') then ui.target = n end
end

-- (Lich) UNDO / CTRL+Z: the slot as it was before each change (a slider's whole drag is one change), up to 60 back
ui.undo = {}
local function undo_watch()
  local name = ui.slot
  if not name then return end
  local cur = AU.ser(AU.slots[name])
  local w = ui.undo_w
  if not w or w.name ~= name then ui.undo_w = { name = name, ser = cur }; return end
  if cur ~= w.ser then
    if not (ui.drag and w.drag) then
      ui.undo[#ui.undo + 1] = { name = name, ser = w.ser }
      if #ui.undo > 60 then table.remove(ui.undo, 1) end
    end
    w.drag = ui.drag ~= nil
    w.ser = cur
  elseif not ui.drag then w.drag = false end
end
function M.undo()
  local u = table.remove(ui.undo)
  if not u then say('NOTHING TO UNDO'); return end
  local f = load('return ' .. u.ser, 'undo', 't', {})
  local ok, t = pcall(f)
  AU.slots[u.name] = (ok and type(t) == 'table') and t or nil
  AU.save_picks()
  reload(u.name)
  if ui.undo_w and ui.undo_w.name == u.name then ui.undo_w.ser = AU.ser(AU.slots[u.name]) end
  if ui.focus and ui.focus.slot == u.name then ui.focus = nil end
  say('UNDONE (' .. u.name:upper() .. ')')
end
local function close_edit() AU.stop_audition(); flush_saves(); ui.mode = ui.back == 'pause' and 'pause' or 'list'; ui.slot = nil end

function M.set_rows()   -- what the picker's list shows: search results, or the pack folders when the query is empty
  local rows = {}
  if ui.q:match('%S') then
    for i, r in ipairs(ui.results) do rows[i] = { rel = r.e.rel } end
  else
    for i, f in ipairs(LIB.folders) do rows[i] = { folder = f } end
  end
  ui.rows = rows
end
local function set_query(q)
  ui.q = q
  ui.results = M.search(q)
  ui.sel = #ui.results > 0 and 1 or 0
  ui.scroll = 0
  ui.heard = nil
  M.set_rows()
end

local function listen(i)
  local r = ui.rows[i]
  if not r or not r.rel then return end
  ui.sel = i
  local ok, played = pcall(AU.audition, ROOT .. '/' .. r.rel, 0.5, ui.slot)
  if ok and played then ui.heard = i else ui.heard = nil; say('CANNOT DECODE ' .. r.rel:sub(-60)) end
end

-- ================================================================================================ input
local LIST_TOP, ROW_H, LIST_ROWS = 74, 10, 26

local function hit_at(x, y)
  for i = #hits, 1, -1 do
    local h = hits[i]
    if x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h then return h end
  end
  return nil
end
local function hit_by_id(id)
  for i = #hits, 1, -1 do if hits[i].id == id then return hits[i] end end
  return nil
end
M.hit_by_id = hit_by_id     -- (the harness clicks what the last frame drew: a button's text, a slider's id)

-- true when this frame's left click is ours: a name, a panel, or anywhere on the editor or the picker (they eat
-- stray clicks); the paused views let the rest resume the game. Called by the game before M.update.
function M.click_consumed()
  if ui.mode == 'play' then return false end
  if ui.mode == 'picker' or ui.mode == 'edit' then return true end
  local x, y = mouse_position()
  return hit_at(x, y) ~= nil
end

local function key_hit(k) return key_is_pressed(k) or key_is_repeated(k) end

function M.update(dt)
  ui.rt = ui.rt + dt
  if ui.msg_t > 0 then ui.msg_t = ui.msg_t - dt end
  local typed = engine_get_typed_text() or ''
  -- (Lich) the slot the editor is on: the game's own loops of it are hushed meanwhile (audio refresh)
  AU.editing = (ui.mode == 'edit' or ui.mode == 'picker') and ui.slot or nil
  if ui.mode == 'play' then return end
  AU.paused_update(dt)
  if ui.mode == 'edit' or ui.mode == 'picker' then     -- (Lich) undo
    undo_watch()
    if key_is_pressed('z') and (key_is_down('lctrl') or key_is_down('rctrl')) then M.undo() end
  end
  if ui.fresh then ui.fresh = false; return end
  ui.mx, ui.my = mouse_position()
  -- a drag in progress
  if ui.drag then
    if mouse_is_down(1) then
      local h = hit_by_id(ui.drag)
      if h and h.drag then h.drag(ui.mx) end
    else
      ui.drag = nil
      flush_saves()
    end
    return
  end
  -- the wheel
  local _, wy = mouse_wheel()
  if wy and wy ~= 0 then
    local d = wy > 0 and -3 or 3
    if ui.mode == 'picker' then ui.scroll = max(0, min(max(0, #ui.rows - LIST_ROWS), ui.scroll + d))
    elseif ui.mode == 'list' then ui.list_scroll = max(0, ui.list_scroll + d)
    else ui.panel_scroll = max(0, ui.panel_scroll + d) end
  end
  -- clicks on whatever the last frame drew there
  if mouse_is_pressed(1) then
    local h = hit_at(ui.mx, ui.my)
    if h then
      if h.drag then ui.drag = h.id; h.drag(ui.mx)
      elseif h.act then h.act() end
      return
    end
  end
  if mouse_is_pressed(2) then
    local h = hit_at(ui.mx, ui.my)
    if h and h.right then h.right(); return end
  end
  if ui.mode == 'list' then
    if key_is_pressed('tab') then M.resume(); ui.resume = true end
    return
  end
  if ui.mode == 'edit' then
    if key_is_pressed('escape') then close_edit(); return end
    if key_is_pressed('space') then
      preview(ui.slot)     -- (Lich: a loop's too; the game's own loop of it is hushed while the editor is on it)
    end
    if key_is_pressed('f') then M.open_picker(ui.slot) end
    return
  end
  if ui.mode ~= 'picker' then return end
  -- the library: read on the first open, after one frame has said so
  if not LIB.index then
    if LIB.reading_shown then M.build_index(); set_query(ui.q) end
    if key_is_pressed('escape') then M.close_picker() end
    return
  end
  -- the picker's keys
  if key_is_pressed('escape') then M.close_picker(); return end
  local changed_q = false
  local q = ui.q
  for ch in typed:gmatch('.') do
    if ch:match('[%g ]') then q = q .. ch; changed_q = true end
  end
  if key_hit('backspace') and #q > 0 then q = q:sub(1, -2); changed_q = true end
  if changed_q then set_query(q) end
  local n = #ui.rows
  local down, up = key_hit('down'), key_hit('up')
  if (down or up) and n > 0 then
    local i = max(1, min(n, ui.sel + (down and 1 or -1)))
    if i - 1 < ui.scroll then ui.scroll = i - 1 end
    if i > ui.scroll + LIST_ROWS then ui.scroll = i - LIST_ROWS end
    if ui.rows[i].rel then listen(i) else ui.sel = i end
  end
  if key_is_pressed('tab') and ui.sel > 0 then listen(ui.sel) end
  if key_is_pressed('return') then
    local r = ui.rows[ui.sel]
    if r and r.rel then add_here(r.rel)
    elseif r and r.folder then set_query(r.folder:lower() .. ' ') end
  end
end

-- ================================================================================================ drawing
local _p, _v = {}, TM.Vector3.new()
-- world -> HUD pixels; nil when off screen (the NDC test of the JS, with `lim` the x/y slack)
local CAM = nil           -- the world camera, from the last draw (Lich: no mb.gfx)
local function project(pos, lim, near)
  if not CAM then return nil end
  _v:copy(pos):project(CAM)
  if _v.z > 1 or (near and _v.z < -1) or math.abs(_v.x) > lim or math.abs(_v.y) > lim then return nil end
  return (_v.x*0.5 + 0.5)*640, (0.5 - _v.y*0.5)*360
end

local function label(txt, x, y, color, act, alpha)
  local w, h = tw(txt) + 4, 11
  x = round(max(2, min(638 - w, x - w / 2)))
  y = round(max(2, min(346, y)))
  HUD.alpha(alpha or 1)
  local hot = act and ui.mx >= x and ui.mx < x + w and ui.my >= y and ui.my < y + h
  HUD.rect(x, y, w, h, hot and 'rgba(60,60,70,0.92)' or INK)
  HUD.text(txt, x + 2, y + 2, color)
  HUD.alpha(1)
  if act then hits[#hits + 1] = { x = x, y = y, w = w, h = h, act = act } end
end

local function button(txt, x, y, act, color, on)
  local w, h = tw(txt) + 6, 11
  local hot = ui.mx >= x and ui.mx < x + w and ui.my >= y and ui.my < y + h
  HUD.rect(x, y, w, h, on and 'rgba(70,96,64,0.95)' or (hot and 'rgba(90,90,104,0.95)' or 'rgba(44,44,52,0.95)'))
  HUD.text(txt, x + 3, y + 2, color or CREAM)
  hits[#hits + 1] = { x = x, y = y, w = w, h = h, act = act, id = txt }
  return x + w + 4
end

local draw_panel, draw_list, draw_edit, draw_picker

-- the labels: called every frame after the HUD with the world camera
function M.draw(hud, camera)
  CAM = camera
  HUD = hud
  hits = {}
  local now, paused = AU.now, ui.mode ~= 'play'
  if paused then ui.mx, ui.my = mouse_position() end
  -- the names are clickable while stopped (under the editor and the picker they are covered)
  local clickable = ui.mode == 'pause' or ui.mode == 'list'
  if ui.mode ~= 'edit' and ui.mode ~= 'picker' then
    local placed = {}
    -- (Lich) the TAB list's and the ESC panel's rects count as taken: the HUD draws text after rects, so a name in
    -- the world showed through the panel over its rows
    if ui.mode == 'list' then placed[1] = { x = 6, y = 6, w = 330, h = 348 } end
    if ui.mode == 'pause' then placed[1] = { x = 470, y = 6, w = 164, h = 348 } end
    local function fits(r)
      for _, p in ipairs(placed) do
        if r.x < p.x + p.w and p.x < r.x + r.w and r.y < p.y + p.h and p.y < r.y + r.h then return false end
      end
      return true
    end
    local stack = 0
    if camera and camera.update_matrix_world then camera:update_matrix_world() end
    local evs = AU.events
    for i = #evs, 1, -1 do
      local e = evs[i]
      local age = now - e.t
      if age >= 0 and age <= (paused and 4 or LIFE) then
        local alpha = paused and 1 or min(1, 1.6 * (1 - age / LIFE))
        local txt = e.name .. (e.count > 1 and (' X' .. e.count) or '')
        local name = e.name
        local act = clickable and function() M.open_edit(name) end or nil
        local x, y
        if e.pos then
          x, y = project(e.pos, 1.05, true)
          if y then y = y - 6 end
        else
          x, y = 320, 300 - stack * 12
          stack = stack + 1
        end
        if x then
          -- nudge up until it doesn't cover another label
          local r = nil
          local w = tw(txt) + 4
          for k = 0, 7 do
            local rr = { x = round(x - w / 2), y = round(y - k * 12), w = w, h = 11 }
            if fits(rr) then r = rr; break end
          end
          if r then
            placed[#placed + 1] = r
            label(txt, r.x + r.w / 2, r.y, status_color(name), act, alpha)
          end
        end
      end
    end
    -- loops: where they play from; while stopped all of them, while playing those sounding now (Lich: its loops are
    -- the game's actions, the lens cutting through the floor, the beam, a burning snake, and went unseen in play)
    do
      local loops = {}
      for L in pairs(AU.loop_set) do loops[#loops + 1] = L end
      table.sort(loops, function(a, b) return a.name < b.name end)
      for _, L in ipairs(loops) do
        local p = L.opts and L.opts.pos
        if p and (paused or L.h) then
          local x, y = project(p, 1, false)
          if x then
            local txt = '(' .. L.name .. ')'     -- (Lich: a loop in brackets; the font has no ~, it drew ?)
            local w = tw(txt) + 4
            local rr
            for k = 0, 7 do      -- (Lich: nudged up off the other names, as the one-shots' are)
              local r = { x = round(x - w / 2), y = round(y - k * 12), w = w, h = 11 }
              if fits(r) then rr = r; break end
            end
            if rr then
              placed[#placed + 1] = rr
              local name = L.name
              label(txt, x, rr.y, status_color(name), clickable and function() M.open_edit(name) end or nil, paused and 0.9 or 0.75)
            end
          end
        end
      end
    end
  end
  if ui.mode == 'pause' then draw_panel(now) end
  if ui.mode == 'list' then draw_list() end
  if ui.mode == 'edit' then hits = {}; draw_edit() end
  if ui.mode == 'picker' then hits = {}; draw_picker() end
end

-- where a slot was last heard from, as words: "6.2M 1 WALL" / "IN YOUR HEAD"
local _info = {}
local function where(name)
  local lp = AU.last_play[name]
  if not lp then return 'NOT HEARD YET' end
  if not lp.pos then return 'IN YOUR HEAD' end
  local _, info = AU.spatial(name, lp.pos, lp, nil, nil, {}, _info)
  local s = ('%.1fM'):format(info.d or 0)
  if (info.walls or 0) > 0 then s = s .. (' %d WALL%s'):format(info.walls, info.walls > 1 and 'S' or '') end
  return s
end

function draw_panel(now)
  local recent, looping = {}, {}
  for _, e in ipairs(AU.events) do if now - e.t < RECENT then recent[e.name] = true end end
  for L in pairs(AU.loop_set) do looping[L.name] = true end
  for n, t in pairs(AU.loop_end) do if now - t < RECENT then recent[n] = true end end   -- (Lich: a loop that just ended)
  local names = M.all_slots()
  local x0, y0, w, row_h = 470, 6, 164, 9
  local fit_rows = floor((360 - 34) / row_h)
  ui.panel_scroll = min(ui.panel_scroll, max(0, #names - fit_rows))
  HUD.rect(x0, y0, w, 348, 'rgba(8,8,10,0.82)')
  HUD.text('SOUND SLOTS', x0 + 4, y0 + 3, CREAM)
  local picked = 0
  for _, s in pairs(AU.slots) do if s.files and #s.files > 0 then picked = picked + 1 end end
  HUD.text(picked .. '/' .. #names, x0 + w - 4, y0 + 3, DIM, 1, 'right')
  for i = 1, fit_rows do
    local n = names[ui.panel_scroll + i]
    if not n then break end
    local y = y0 + 16 + (i - 1) * row_h
    local hot = ui.mx >= x0 and ui.mx < x0 + w and ui.my >= y - 1 and ui.my < y + row_h - 1
    if hot then HUD.rect(x0 + 1, y - 1, w - 2, row_h, 'rgba(70,70,82,0.9)') end
    local s = AU.slots[n]
    local files = s and s.files and #s.files or 0
    local col = status_color(n)
    HUD.alpha((recent[n] or hot) and 1 or 0.7)
    HUD.text((recent[n] and '> ' or '  ') .. n .. (looping[n] and ' (LOOP)' or ''), x0 + 4, y, col)
    HUD.alpha(1)
    if files > 0 then HUD.text(tostring(files), x0 + w - 4, y, DIM, 1, 'right') end
    hits[#hits + 1] = { x = x0, y = y - 1, w = w, h = row_h, act = function() M.open_edit(n) end }
  end
  -- the hint, top left
  local lines = { 'PAUSED: SOUNDS ARE NAMES. GREEN = PICKED, YELLOW = NO FILE YET,', 'RED = NOT PICKED ON PURPOSE (UNSURE), GREY = MUTED.',
    'CLICK A NAME (ON SCREEN OR IN THE LIST) TO EDIT IT. TAB IN GAME = WHAT IS PLAYING.', 'CLICK ANYWHERE ELSE TO PLAY.' }
  HUD.rect(6, 6, 400, 47, 'rgba(8,8,10,0.7)')
  for i, l in ipairs(lines) do HUD.text(l, 10, 10 + (i - 1) * 11, i == 4 and DIM or CREAM) end
end

-- TAB: the sounds that were playing, then the red ones
function draw_list()
  local x0, y0, w = 6, 6, 330
  HUD.rect(x0, y0, w, 348, 'rgba(8,8,10,0.94)')
  HUD.text('HEARD IN THE LAST ' .. RECENT .. ' SECONDS, NEWEST FIRST', x0 + 6, y0 + 5, CREAM)
  -- the global switches, A/B
  local bx = x0 + 6
  bx = button(AU.on3d and '3D ON' or '3D OFF', bx, y0 + 18, function() AU.on3d = not AU.on3d; AU.save_rooms() end, AU.on3d and GREEN or GREY, AU.on3d)
  bx = button(AU.reverb_on and 'REVERB ON' or 'REVERB OFF', bx, y0 + 18, function() AU.reverb_on = not AU.reverb_on; AU.save_rooms() end, AU.reverb_on and GREEN or GREY, AU.reverb_on)
  HUD.text('ROOM: ' .. (AU.zone or '?'):upper(), bx + 4, y0 + 20, DIM)
  local rows = {}
  for _, n in ipairs(ui.list) do rows[#rows + 1] = { name = n } end
  if #ui.list == 0 then rows[#rows + 1] = { text = 'NOTHING IN THE LAST ' .. RECENT .. ' SECONDS' } end
  local unsure = M.unsure_slots()
  rows[#rows + 1] = { gap = true }
  rows[#rows + 1] = { text = 'UNSURE (RED): NO FILE ON PURPOSE, ' .. #unsure .. ' LEFT', head = true }
  for _, n in ipairs(unsure) do rows[#rows + 1] = { name = n } end
  local row_h, top = 11, y0 + 36
  local fit = floor((y0 + 340 - top) / row_h)
  ui.list_scroll = min(ui.list_scroll, max(0, #rows - fit))
  for i = 1, fit do
    local r = rows[ui.list_scroll + i]
    if not r then break end
    local y = top + (i - 1) * row_h
    if r.text then HUD.text(r.text, x0 + 6, y, r.head and RED or DIM)
    elseif r.name then
      local n = r.name
      local hot = ui.mx >= x0 and ui.mx < x0 + w and ui.my >= y - 1 and ui.my < y + row_h - 1
      if hot then HUD.rect(x0 + 1, y - 2, w - 2, row_h, 'rgba(70,70,82,0.9)') end
      local s = AU.slots[n]
      local files = s and s.files and #s.files or 0
      HUD.text(n .. (is_loop(n) and ' (LOOP)' or ''), x0 + 8, y, status_color(n))
      local age = ui.list_age and ui.list_age[n]       -- (Lich) how long ago
      if age then HUD.text(age < 0.05 and 'NOW' or ('%.1fS'):format(age), x0 + 136, y, age < 0.05 and GREEN or CREAM) end
      HUD.text(where(n), x0 + 172, y, DIM)
      HUD.text(files > 0 and (files .. (files > 1 and ' FILES' or ' FILE')) or (AU.unsure(n) and 'UNSURE' or 'NO FILE'), x0 + w - 6, y, DIM, 1, 'right')
      hits[#hits + 1] = { x = x0, y = y - 2, w = w, h = row_h, act = function() M.open_edit(n) end }
    end
  end
  HUD.text('CLICK ONE TO EDIT IT. TAB OR A CLICK OUTSIDE = PLAY.', x0 + 6, y0 + 336, DIM)
end

-- a slider row: label, track, value; drag it, right-click = the default
local function slider(id, sp, x, y, w, v, is_default, on_set, on_reset)
  local lw, vw = 52, 44
  local tx, tw_ = x + lw, w - lw - vw
  HUD.text(sp.label, x, y, is_default and DIM or CREAM)
  HUD.rect(tx, y + 3, tw_, 2, 'rgba(236,230,216,0.22)')
  local t = to_t(sp, v)
  local hx = round(tx + t * (tw_ - 3))
  local active = ui.drag == id
  HUD.rect(tx, y + 3, hx - tx, 2, is_default and 'rgba(236,230,216,0.35)' or 'rgba(255,214,90,0.55)')
  HUD.rect(hx, y, 3, 8, active and '#ffffff' or (is_default and CREAM or YELLOW))
  HUD.text(fmt(sp, v), x + w, y, is_default and DIM or CREAM, 1, 'right')
  hits[#hits + 1] = { id = id, x = tx - 3, y = y - 2, w = tw_ + 6, h = 11,
    drag = function(mx) on_set(from_t(sp, (mx - tx) / max(1, tw_ - 3))) end, right = on_reset }
end

local _fx, _inf = {}, {}
function draw_edit()
  local name = ui.slot
  local s = AU.slots[name] or { files = {}, src = {} }
  local files, src = s.files or {}, s.src or {}
  -- (Lich) what the sliders are set on: the whole sound, one layer (its own over the sound's) or one file (its own
  -- over its layer's); a file clicked also plays alone, a layer clicked plays one of its files
  local f = focus_of(name)
  if f and ((f.kind == 'file' and not files[f.n]) or (f.kind == 'layer' and #files == 0)) then ui.focus, f = nil, nil end
  local fi = f and f.kind == 'file' and f.n or nil
  local li = f and f.kind == 'layer' and f.n or nil
  local function get(k) return AU.get(name, k, fi, li) end
  local function set(k, v)
    if fi then AU.set_file(name, fi, k, v) elseif li then AU.set_layer(name, li, k, v) else AU.set(name, k, v) end
  end
  local function is_own(k)
    if fi then return AU.own_file(name, fi, k) elseif li then return AU.own_layer(name, li, k) end
    return s[k] ~= nil
  end
  local function short_of(i)
    local t = (src[i] or files[i]):match('[^/]*$') or files[i]
    return #t > 30 and (t:sub(1, 28) .. '..') or t
  end
  HUD.rect(6, 6, 628, 348, 'rgba(10,10,13,0.95)')
  local col = status_color(name)
  HUD.text(name, 12, 11, col, 2)
  local state = AU.muted(name) and 'MUTED' or (#files > 0 and 'PICKED' or (AU.unsure(name) and 'UNSURE: NOT PICKED ON PURPOSE' or 'NO FILE YET'))
  HUD.text(state .. (AU.loop_slot[name] and '  (A LOOP)' or ''), 12 + tw(name, 2) + 10, 15, col)
  -- the buttons, top right
  local bx = 628 - (tw('PLAY (SPACE)') + tw('FIND (F)') + tw('UNMUTE') + tw('RESET') + tw('UNDO') + tw('BACK (ESC)') + 36 + 20)
  bx = button('PLAY (SPACE)', bx, 10, function() preview(name) end, GREEN)
  bx = button('FIND (F)', bx, 10, function() M.open_picker(name) end)
  bx = button(AU.muted(name) and 'UNMUTE' or 'MUTE', bx, 10, function()
    local m = not AU.muted(name)
    AU.set(name, 'mute', m or nil)
    AU.save_picks()
    if not m then for L in pairs(AU.loop_set) do if L.name == name and not L.h then AU.start_loop(L) end end end
  end, nil, AU.muted(name))
  bx = button('RESET', bx, 10, function() reset_slot(name) end, ORANGE)
  bx = button('UNDO', bx, 10, function() M.undo() end)
  button('BACK (ESC)', bx, 10, close_edit)
  -- (Lich) the layers: every play plays each layer, one of its files at random (its variations). A row each: the
  -- layer (click: its own sliders), LOOPS / ONCE in a loop's slot, its files (click: that file alone and its own
  -- sliders; X removes it), + (find a file for this layer). Then + NEW LAYER, and with a file clicked, MOVE IT TO.
  local y = 30
  local layers, by = AU.layers(name)
  if #files == 0 then
    HUD.text('NO FILE: THIS SOUND IS SILENT. F = SEARCH THE PACKS.', 12, y, DIM)
    y = y + 12
  else
    for _, n in ipairs(layers) do
      local lo = s.lay and s.lay[tostring(n)]
      local mine = false
      if lo then for k in pairs(lo) do if k ~= 'once' and k ~= 'all' and k ~= 'off' then mine = true end end end
      local lout = AU.layer_off(name, n)
      local x = button('LAYER ' .. n .. (mine and '*' or '') .. (lout and ' OUT' or ''), 12, y - 2, function()
        if li == n then ui.focus = nil else ui.focus = { slot = name, kind = 'layer', n = n } end
        preview(name)
      end, lout and GREY or (li == n and YELLOW or CREAM), li == n)
      hits[#hits].right = function()       -- right-click: the whole layer out / back in
        AU.set_layer(name, n, 'off', (not lout) or nil); ui.dirty = true; flush_saves()
        say('LAYER ' .. n .. (lout and ' BACK IN' or ' OUT: IT DOES NOT PLAY'))
      end
      -- its two switches: how many of its files play, and (a loop's) whether it loops
      if #by[n] > 1 then
        local all = AU.get(name, 'all', nil, n)
        x = button(all and 'ALL AT ONCE' or 'ONE AT RANDOM', x, y - 2, function()
          AU.set_layer(name, n, 'all', (not all) or nil); ui.dirty = true; flush_saves(); changed(name)
        end, all and YELLOW or GREY, all)
      end
      if AU.loop_slot[name] then
        local once = AU.get(name, 'once', nil, n)
        x = button(once and 'PLAYS ONCE' or 'LOOPS', x, y - 2, function()
          AU.set_layer(name, n, 'once', (not once) or nil); ui.dirty = true; flush_saves()
        end, once and YELLOW or GREY, once)
      end
      local x0 = x
      for _, i in ipairs(by[n]) do
        local pm = s.per and s.per[files[i]]
        local own = false
        if pm then for k in pairs(pm) do if k ~= 'layer' and k ~= 'off' then own = true end end end
        local out = AU.file_off(name, i)
        local label = short_of(i) .. (own and '*' or '')
        local fw = tw(label)
        if x + fw + 24 > 612 and x > x0 then y, x = y + 11, x0 end
        x = button('X', x, y - 2, function() remove_pick(name, i) end, ORANGE)
        local sel = fi == i
        local hot = ui.mx >= x - 2 and ui.mx < x + fw + 2 and ui.my >= y - 2 and ui.my < y + 8
        if hot or sel then HUD.rect(x - 2, y - 2, fw + 4, 10, sel and 'rgba(80,72,40,0.95)' or 'rgba(50,50,60,0.9)') end
        HUD.text(label, x, y, (out or lout) and GREY or GREEN)
        if out then HUD.rect(x - 1, y + 3, fw + 2, 1, GREY) end      -- struck through: out
        hits[#hits + 1] = { id = 'file_' .. i, x = x - 2, y = y - 2, w = fw + 4, h = 10, act = function()
          if sel then ui.focus = nil else ui.focus = { slot = name, kind = 'file', n = i } end
          preview(name)
        end, right = function()        -- right-click: this file out / back in
          AU.set_file(name, i, 'off', (not out) or nil); ui.dirty = true; flush_saves()
          say(short_of(i) .. (out and ' BACK IN' or ' OUT: IT DOES NOT PLAY'))
        end }
        x = x + fw + 8
      end
      button('+', x, y - 2, function() M.open_picker(name, n) end, GREEN)
      y = y + 12
    end
    local x = button('+ NEW LAYER', 12, y - 2, function() M.open_picker(name, 'new') end, GREEN)
    if fi then
      local cur = AU.layer_of(name, fi)
      local txt = 'MOVE ' .. short_of(fi) .. ' TO:'
      HUD.text(txt, x + 6, y, DIM)
      x = x + tw(txt) + 12
      for _, n in ipairs(layers) do
        if n ~= cur then x = button('LAYER ' .. n, x, y - 2, function() move_file(name, fi, n) end) end
      end
      if #by[cur] > 1 then button('A NEW LAYER', x, y - 2, function() move_file(name, fi, layers[#layers] + 1) end) end
    end
    y = y + 12
  end
  -- a red slot: the suggestions nobody was sure of
  local cands = s.candidates or {}
  if #files == 0 and #cands > 0 then
    HUD.text('SUGGESTIONS (NOT USED): CLICK = LISTEN, AGAIN = ADD IT', 12, y, RED)
    for i = 1, min(6, #cands) do
      local rel = cands[i]
      local ry = y + 2 + i * 10
      local short = rel:match('[^/]*$') or rel
      local folder = (rel:match('^(.*)/[^/]*$') or ''):match('[^/]*$') or ''
      local hot = ui.mx >= 10 and ui.mx < 624 and ui.my >= ry - 1 and ui.my < ry + 9
      if hot or ui.cand_heard == i then HUD.rect(10, ry - 2, 614, 10, ui.cand_heard == i and 'rgba(80,72,40,0.95)' or 'rgba(50,50,60,0.9)') end
      HUD.text(short, 14, ry, CREAM)
      HUD.text(folder, 620, ry, DIM, 1, 'right')
      hits[#hits + 1] = { x = 10, y = ry - 2, w = 614, h = 10, act = function()
        if ui.cand_heard == i then add_pick(name, rel, 1); ui.cand_heard = nil
        else
          local ok, played = pcall(AU.audition, ROOT .. '/' .. rel, 0.5, name)
          ui.cand_heard = (ok and played) and i or nil
          if not (ok and played) then say('CANNOT DECODE ' .. short) end
        end
      end }
    end
    y = y + 4 + min(6, #cands) * 10
  end
  -- the settings: SOUND (left), 3D (right), each saying whose they are
  local top = max(64, y + 4)
  local lx, rx, cw = 12, 326, 296
  local sp_y = top
  local whose = fi and (short_of(fi) .. "'S OWN") or (li and ('LAYER ' .. li .. "'S OWN") or 'THE WHOLE SOUND')
  HUD.text('SOUND: ' .. whose, lx, sp_y, YELLOW)
  HUD.text('3D: ' .. whose, rx, sp_y, YELLOW)
  for i, sp in ipairs(M.SLIDERS.sound) do
    if sp.key ~= 'fade' or AU.loop_slot[name] then     -- (Lich) FADE OUT is a loop's: one-shots end by themselves
      local v = get(sp.key)
      local own = is_own(sp.key)
      slider('s_' .. sp.key, sp, lx, sp_y + 4 + i * 11, cw, v, not own,
        function(nv)
          if sp.key == 'pitch_lo' and nv > get('pitch_hi') then set('pitch_hi', nv) end
          if sp.key == 'pitch_hi' and nv < get('pitch_lo') then set('pitch_lo', nv) end
          if nv ~= v then set(sp.key, nv); changed(name) end
        end,
        function() set(sp.key, nil); ui.dirty = true; flush_saves(); changed(name) end)
    end
  end
  -- the 3D toggles
  local ty = sp_y + 15
  local tx = rx
  local function toggle(txt, key)
    local on = get(key)
    tx = button(txt .. (on and ' ON' or ' OFF'), tx, ty - 2, function()
      set(key, not on); ui.dirty = true; flush_saves(); changed(name)
    end, on and GREEN or GREY, on)
  end
  toggle('SPATIAL', 'spatial')
  toggle('BINAURAL', 'binaural')
  local curve = get('curve')
  tx = button('CURVE ' .. curve:upper(), tx, ty - 2, function()
    local i = 1
    for k, c in ipairs(AU.CURVES) do if c == curve then i = k end end
    set('curve', AU.CURVES[i % #AU.CURVES + 1]); ui.dirty = true; flush_saves(); changed(name)
  end)
  for i, sp in ipairs(M.SLIDERS.space) do
    local v, own
    v, own = get(sp.key), is_own(sp.key)
    if sp.key == 'reverb' and v == nil then local lp0 = AU.last_play[name]; v = (lp0 and lp0.reverb) or 0.25 end   -- (the game's send)
    slider('3_' .. sp.key, sp, rx, ty + 2 + i * 11, cw, v, not own,
      function(nv) if nv ~= v or not own then set(sp.key, nv); changed(name) end end,
      function() set(sp.key, nil); ui.dirty = true; flush_saves(); changed(name) end)
  end
  -- the room you stand in (every sound's reverb)
  local zy = ty + 2 + (#M.SLIDERS.space + 1) * 11 + 6
  local zone = AU.zone
  local rm = zone and AU.rooms[zone]
  HUD.rect(12, zy - 4, 616, 1, 'rgba(236,230,216,0.18)')
  if rm then
    HUD.text('THE ROOM YOU STAND IN: ' .. zone:upper() .. ' (ITS REVERB, FOR EVERY SOUND)', lx, zy, YELLOW)
    local half = math.ceil(#M.SLIDERS.room / 2)
    for i, sp in ipairs(M.SLIDERS.room) do
      local col_x = i <= half and lx or rx
      local row = i <= half and i or i - half
      local v = rm[sp.key]
      local d = AU.ROOM_DEFAULTS[zone][sp.key]
      slider('r_' .. sp.key, sp, col_x, zy + row * 11, cw, v, abs(v - d) < 1e-6,
        function(nv) if nv ~= v then rm[sp.key] = nv; changed(name, true) end end,
        function() rm[sp.key] = d; ui.dirty_rooms = true; flush_saves(); changed(name, true) end)
    end
    zy = zy + (half + 1) * 11
  end
  -- what each ear gets, heard from where you stand
  local lp = AU.last_play[name]
  local fx, info = AU.spatial(name, lp and lp.pos, lp and { reverb = lp.reverb, fi = fi, li = li }, nil, nil, _fx, _inf)
  local ry = 318
  HUD.rect(12, ry - 4, 616, 1, 'rgba(236,230,216,0.18)')
  local function db(g) return g <= 0.0001 and '-INF' or ('%+.1f'):format(20 * math.log(g, 10)) end
  local line1, line2
  if not (lp and lp.pos) then
    line1 = 'HEARD IN YOUR HEAD (THE GAME GIVES IT NO PLACE): BOTH EARS 0 DB'
  else
    line1 = ('HEARD FROM HERE: %.1f M, %s, %s'):format(info.d or 0,
      (info.walls or 0) > 0 and ((info.walls) .. ' WALL' .. (info.walls > 1 and 'S' or '')) or 'NO WALLS',
      (info.z or 1) < 0 and 'BEHIND YOU' or 'AHEAD')
    line1 = line1 .. ('   LEFT %s DB  RIGHT %s DB'):format(db(fx.gain_l * fx.dry), db(fx.gain_r * fx.dry))
  end
  line2 = ('EAR DELAY %.2f MS   LOW-PASS L %d R %d HZ   REVERB SEND %.2f   DOPPLER X%.3f'):format(
    (info.itd or 0) * 1000, round(min(fx.lp_l, 20000)), round(min(fx.lp_r, 20000)), fx.wet or 0, info.pf or 1)
  HUD.text(line1, 12, ry, CREAM)
  HUD.text(line2, 12, ry + 10, CREAM)
  -- (Lich) what the sliders are and what a click does, for where the editor is set; a message takes its place for
  -- its 3 s (at the top it covered the layers)
  if ui.msg_t > 0 then HUD.text(ui.msg, 12, 342, GREEN)
  elseif fi then HUD.text("THIS FILE ALONE: ITS OWN SLIDERS (RIGHT-CLICK = ITS LAYER'S). CLICK IT AGAIN FOR THE WHOLE SOUND.", 12, 342, YELLOW)
  elseif li then HUD.text("LAYER " .. li .. ": ITS OWN SLIDERS (RIGHT-CLICK ONE = THE SOUND'S). RIGHT-CLICK A FILE: OUT / BACK IN.", 12, 342, YELLOW)
  else HUD.text('EVERY LAYER PLAYS EACH TIME. CLICK A LAYER OR FILE: TUNE IT. RIGHT-CLICK: OUT / BACK IN. CTRL+Z: UNDO.', 12, 342, DIM) end
end

local function short_name(path)
  local s = path:match('[^/]*$') or path
  if #s > 40 then s = s:sub(1, 38) .. '..' end
  return s
end

function draw_picker()
  HUD.rect(6, 6, 628, 348, 'rgba(10,10,13,0.94)')
  local name = ui.slot
  local s = AU.slots[name] or { files = {}, src = {}, vol = 1 }
  local files, src = s.files or {}, s.src or {}
  HUD.text('FIND: ' .. name, 12, 12, status_color(name), 2)
  local bx = 12 + tw('FIND: ' .. name, 2) + 12
  HUD.text(ui.target == 'new' and 'ADDS AS A NEW LAYER' or ('ADDS TO LAYER ' .. tostring(ui.target) .. '   (SHIFT: A NEW LAYER)'), bx + 6, 16, YELLOW)   -- (Lich)
  button('BACK (ESC)', 628 - tw('BACK (ESC)') - 6, 10, M.close_picker)
  -- current files (named by the pack file they came from)
  local y = 32
  if #files == 0 then HUD.text('NO FILE YET: THIS SOUND IS SILENT', 12, y, DIM)
  else
    local x = 12
    HUD.text('PLAYS:', x, y, DIM); x = x + 34
    for i = 1, min(4, #files) do
      local short = short_name(src[i] or files[i])
      x = button('X', x, y - 2, function() remove_pick(name, i) end, ORANGE)
      HUD.text(short, x, y, GREEN)
      x = x + tw(short) + 10
      if x > 560 then break end
    end
    if #files > 4 then HUD.text('+' .. (#files - 4), x, y, DIM) end
  end
  -- library state
  y = 46
  if not LIB.index then
    HUD.text('READING ' .. ROOT .. ' ...', 12, y + 10, CREAM)
    LIB.reading_shown = true
  elseif #LIB.index == 0 then
    HUD.text('NO SOUND FILES UNDER ' .. ROOT, 12, y + 10, YELLOW)
    button('RESCAN', 628 - tw('RESCAN') - 6, 30, function() M.build_index(); set_query(ui.q) end)
  else
    -- the search line
    HUD.rect(12, y, 616, 14, 'rgba(30,30,36,1)')
    HUD.text('> ' .. ui.q .. '_', 16, y + 4, YELLOW)
    local searching = ui.q:match('%S') ~= nil
    local count = searching and ((#ui.results >= MAX_RESULTS and (MAX_RESULTS .. '+') or tostring(#ui.results)) .. ' MATCHES')
      or (#LIB.index .. ' FILES, ' .. #LIB.folders .. ' PACKS')
    HUD.text(count, 624, y + 4, DIM, 1, 'right')
    local list = ui.rows
    if not searching then HUD.text('TYPE TO SEARCH (SPACES = AND), OR CLICK A PACK:', 12, LIST_TOP - 11, DIM)
    elseif #list == 0 then HUD.text('NO MATCHES', 12, LIST_TOP, DIM) end
    local used = {}
    for _, r in ipairs(src) do used[r] = true end
    for i = 1, LIST_ROWS do
      local ri = ui.scroll + i
      local r = list[ri]
      if not r then break end
      local ry = LIST_TOP + (i - 1) * ROW_H
      local hot = ui.mx >= 10 and ui.mx < 624 and ui.my >= ry - 1 and ui.my < ry + ROW_H - 1
      if ri == ui.sel or hot then HUD.rect(10, ry - 2, 614, ROW_H, ri == ui.sel and 'rgba(80,72,40,0.95)' or 'rgba(50,50,60,0.9)') end
      local txt = r.rel or (r.folder .. '/')
      if #txt > 100 then txt = '..' .. txt:sub(-98) end
      HUD.text(txt, 14, ry, (r.rel and used[r.rel]) and GREEN or (ri == ui.sel and '#ffffff' or (r.folder and YELLOW or 'rgba(236,230,216,0.82)')))
      hits[#hits + 1] = { x = 10, y = ry - 2, w = 614, h = ROW_H, act = function()
        if r.folder then set_query(r.folder:lower() .. ' '); return end
        -- a second click on the row that's playing: use it
        if ui.sel == ri and ui.heard == ri then add_here(r.rel) else listen(ri) end
      end }
    end
    local n = #list
    if n > LIST_ROWS then
      local th, tx = LIST_ROWS * ROW_H, 627
      local thumb = max(6, floor(th * LIST_ROWS / n))
      local ty = LIST_TOP + floor((th - thumb) * (ui.scroll / max(1, n - LIST_ROWS)))
      HUD.rect(tx, LIST_TOP - 2, 3, th, 'rgba(236,230,216,0.25)')
      HUD.rect(tx, ty - 2, 3, thumb, CREAM)
    end
    button('RESCAN', 628 - tw('RESCAN') - 6, 30, function() M.build_index(); set_query(ui.q) end)
  end
  HUD.text('TYPE = SEARCH  UP/DOWN OR CLICK = LISTEN  ENTER OR CLICK AGAIN = ADD IT  SHIFT = TO A NEW LAYER  CTRL+Z = UNDO', 12, 342, DIM)
  if ui.msg_t > 0 then HUD.text(ui.msg, 628, 330, GREEN, 1, 'right') end
  if LIB.error ~= '' then HUD.text(LIB.error:sub(1, 100), 12, 330, ORANGE) end
end

return M
