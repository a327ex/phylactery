--[[
  LICH'S OWN since 2026-10-11 (round 68g): forked from megablock's mb/audio.lua (megablock 012a1f1), first through
  tools/port_soundui.py (retired; it lists every change up to the fork). Megablock's later changes come over by hand.
  Lich's: its own random generator; the ear half way down the room camera's line of sight (port/game.lua); the cave;
  8 bits / 3x crush by default; gap / max / set_pos / set_volume; the site's mute and its engine without FX voices;
  LAYERS: a slot's files sit in layers (per[path].layer, 1 when unset); every play plays each layer, one of its
  files at random (its variations) or with ALL (lay["n"].all) every one; settings resolve file -> layer (lay["n"]) ->
  slot -> DEFAULTS; a layer marked ONCE in a loop plays once as the loop starts; a file or layer OUT (per/lay .off)
  never plays (A.choose).
  audio.lua -- sound slots, placed in 3D (audio.js + sfxlog.js of the web build, then round 5's 3D sound).
  The game names a SLOT for every sound; the slot plays the files picked for it (sound_picks.lua in the game
  folder, written by the editor in port/soundui.lua; the files are converted copies in assets/sfx/), and every
  request is logged so mb/soundui.lua can show it as a label.
    A.play(name, {pos, volume, pitch, delay, reverb, vel, follow})     A.loop(name, opts) -> L with L.stop()
  pos = where it happens (none = in your head: the gun, the room tone); reverb = how much of it the room
  answers (the slot's REVERB overrides it); vel = the source's velocity, follow = an Object3D it rides on.

  Every sound plays as an engine FX voice (sound_play_fx): this module works out, from the listener (the
  camera) and the source, what each ear gets, and updates it every frame:
    distance   a curve (inverse / linear / exp / none) from NEAR to FAR, silent past FAR
    direction  BINAURAL: the far ear is quieter, later (the interaural time difference, Woodworth's head) and
               duller (the head's shadow), and anything behind you is dulled a little (the outer ear);
               otherwise a plain stereo pan
    air        distance dulls the highs
    walls      walls between you and the source (hooks.occlusion) muffle and lower it, the room's answer less
    room       a send into the shared reverb, set by the zone you stand in (hooks.zone, sound_rooms.lua);
               it fades slower with distance than the direct sound, as in a real room
    doppler    the pitch shifts with how fast you and the source close in
    travel     sound takes d / 343 s to arrive (off by default; 1 = real)
  Per slot also Horse Game's tuner: volume, a random pitch range, a delay (negative = start into the clip),
  bits and sample-rate crush, mute. Slots marked `unsure` (red) have no file on purpose: a pick nobody was
  sure of. File format: sound_picks.lua (slot -> {files, src, vol, unsure, candidates, + the settings that
  differ from DEFAULTS}), sound_rooms.lua ({on3d, reverb_on, zones = {zone -> reverb}}).
]]
local TM = require('port.three.math')
local Vector3 = TM.Vector3
local sqrt, abs, min, max, floor = math.sqrt, math.abs, math.min, math.max, math.floor

-- (Lich) variants and pitch ranges come from this file's own generator, never math.random: a sound must never move
-- what the game draws next (the seeded runs, LICH_ROOM's digests)
local seed = 0x2545F491
local function rnd()     -- [0, 1)
  seed = seed ~ ((seed << 13) & 0xFFFFFFFF); seed = seed ~ (seed >> 17); seed = seed ~ ((seed << 5) & 0xFFFFFFFF)
  return (seed % 1000003)/1000003
end
-- (Lich) the game's calls give positions as Vector3s or plain {x, y, z} / {x =, y =, z =} tables
local function v3(p)
  if p == nil or p.clone then return p and p:clone() or nil end
  return Vector3.new(p.x or p[1] or 0, p.y or p[2] or 0, p.z or p[3] or 0)
end

local A = { slots = {}, sounds = {}, last = {}, loops = {}, pending = {}, events = {}, loop_set = {}, seen = {}, now = 0,
  voices = {}, last_play = {}, master = 0.8, ready = true, hooks = {}, on3d = true, reverb_on = true, zone = nil,
  last_t = {}, quiet = false, loop_end = {}, sound_ix = {}, loop_slot = {}, preview_hs = {} }   -- (Lich: a call's gap; the site's off-screen silence; when
  -- each loop last stopped, for the TAB list)
local PICKS, ROOMS = 'sound_picks.lua', 'sound_rooms.lua'
local SPEED = 343                      -- m/s
local HEAD = 0.0875 / SPEED            -- Woodworth's r / c: the ITD is HEAD * (azimuth + sin azimuth), 0.66 ms at the side
local SEND = 0.25                      -- the reverb send of a call that names none
local OCC_EVERY = 0.12                 -- seconds between a voice's wall checks

-- a slot's settings when it names none (pitch 1..1: the game's calls already jitter their pitch)
A.DEFAULTS = {
  -- (Lich, his ruling 2026-10-11: every sound 8 bits and 3x sample-rate crush unless its slot says otherwise)
  -- (Lich) a layer's: once = in a loop it plays once as the loop starts instead of looping; all = every file of it
  -- plays (that is in), not one at random
  -- fade = when the game stops a loop, it dies away over this many seconds instead of stopping at once
  vol = 1, pitch_lo = 1, pitch_hi = 1, delay = 0, bits = 8, sr = 3, mute = false, once = false, all = false, fade = 0,
  -- (Lich: the ear is at his head, turned as the camera (A.ROOM_DEFAULTS `head`, port/game.lua): ~2 m from the egg,
  -- ~17 m from the far wall. near = the fight round him and the egg at full loudness, the far wall ~9 dB down; the
  -- air a little duller with distance than a head's)
  spatial = true, curve = 'inverse', near = 6.0, far = 60, rolloff = 1.0, air = 0.5, occlusion = 1.0,
  width = 0, binaural = true, doppler = 1.0, travel = 0, lowcut = 0,
}
A.CURVES = { 'inverse', 'linear', 'exp', 'none' }

-- the rooms: the reverb the listener's zone gets (size 0..1 tail, damp 0..1, predelay s, gain, width, lowcut Hz)
A.ROOM_DEFAULTS = {
  -- (Lich) one cave, stone, 31 m across under a high dome: a long tail (size), the highs dying a little sooner
  -- than a bare hall's (rough rock, damp), the walls answering 13-20 m off (predelay 40 ms), nothing under
  -- 140 Hz sent in (the cave loop's drone and the rock slams would turn the tail to mud).
  -- head = where you hear from: 1 = his head (owner, 2026-10-11), 0 = the room camera (port/game.lua places it; a new
  -- key: round 68's `ear`, half way down the camera's line of sight, is left behind in old sound_rooms.lua files)
  cave = { size = 0.85, damp = 0.4, predelay = 0.04, gain = 0.80, width = 1, lowcut = 140, head = 1 },
}
A.rooms = {}

-- ------------------------------------------------------------------------------------------------ files
local function ser(v, ind)
  ind = ind or ''
  if type(v) == 'table' then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = { '{\n' }
    for _, k in ipairs(keys) do
      local kk = type(k) == 'number' and '' or ('[' .. string.format('%q', k) .. '] = ')
      out[#out + 1] = ind .. '  ' .. kk .. ser(v[k], ind .. '  ') .. ',\n'
    end
    out[#out + 1] = ind .. '}'
    return table.concat(out)
  elseif type(v) == 'string' then return string.format('%q', v)
  elseif type(v) == 'number' then
    if v == floor(v) and abs(v) < 1e15 then return tostring(floor(v)) end
    return (string.format('%.4f', v):gsub('0+$', ''):gsub('%.$', ''))
  else return tostring(v) end
end
A.ser = ser

local function read_lua(path)
  local s = file_read_string(path)
  if not s then return nil end
  local f = load(s, path, 't', {})
  if not f then return nil end
  local ok, t = pcall(f)
  return ok and type(t) == 'table' and t or nil
end

-- (Lich) slots renamed: a file written under the old name (an older game still running saves it so) moves over
A.RENAMED = { lens_focus = 'lens_charge' }     -- 2026-10-11: the lens's build-up
-- (Lich) slots that play another's sound, the same in everything (its files, layers and settings: tuning one tunes both)
A.SAME = {}      -- (2026-10-14: gore_land -> lift_burst was tried and taken back the same day: the burst on every landing)
-- (Lich) new slots that start as a copy of another's sound (files, layers, settings) until they have their own entry:
-- the copy is made at load, so it is saved with the rest the next time the editor saves, and is its own from then on
A.SEED = { rock_lift = 'lift_cast' }            -- 2026-10-14, owner: "what I was missing was a rock lift event"
local function deep_copy(t) if type(t) ~= 'table' then return t end; local c = {}; for k, v in pairs(t) do c[k] = deep_copy(v) end; return c end
-- (Lich) new slots with nothing picked yet: red, with suggestions to audition in the editor (seeded at load while the
-- picks name them not; saved with the rest from then on), and slots that sound while the game is muted. Both filled
-- by the game's own modules (2026-10-14: port/unlock_snd.lua, the site's unlock), so a port of this file starts empty.
A.NEW = {}
A.LOUD = {}
function A.load_picks()
  A.slots = read_lua(PICKS) or {}
  for old, new in pairs(A.RENAMED) do
    if A.slots[old] and not A.slots[new] then A.slots[new] = A.slots[old] end
    A.slots[old] = nil
  end
  for new, from in pairs(A.SEED) do
    if not A.slots[new] and A.slots[from] then A.slots[new] = deep_copy(A.slots[from]) end
  end
  for name, s in pairs(A.NEW) do if not A.slots[name] then A.slots[name] = deep_copy(s) end end
  -- (Lich) round 68f's ALL FILES AT ONCE (layer = true) and a file's ONCE -> a layer per file, ONCE on its layer
  for _, s in pairs(A.slots) do
    if s.layer then
      s.layer = nil
      for fi, path in ipairs(s.files or {}) do
        s.per = s.per or {}
        local p = s.per[path] or {}
        p.layer = fi > 1 and fi or nil
        if p.once then s.lay = s.lay or {}; s.lay[tostring(fi)] = { once = true }; p.once = nil end
        s.per[path] = next(p) and p or nil
      end
      if s.per and not next(s.per) then s.per = nil end
    end
  end
  A.sounds = {}
  for name in pairs(A.slots) do A.reload(name) end
  local r = read_lua(ROOMS) or {}
  A.on3d = r.on3d ~= false
  A.reverb_on = r.reverb_on ~= false
  A.rooms = {}
  for z, d in pairs(A.ROOM_DEFAULTS) do
    local s = r.zones and r.zones[z] or {}
    local t = {}
    for k, v in pairs(d) do t[k] = s[k] ~= nil and s[k] or v end
    A.rooms[z] = t
  end
end

function A.save_picks()
  -- only what differs from the defaults is written
  local out = {}
  for name, s in pairs(A.slots) do
    local t = {}
    for k, v in pairs(s) do
      if A.DEFAULTS[k] == nil or A.DEFAULTS[k] ~= v then t[k] = v end
    end
    if t.files and #t.files == 0 then t.files = nil; t.src = nil end
    if next(t) then out[name] = t end
  end
  file_write_string(PICKS, '-- the sound picks (written by the in-game editor, mb/soundui.lua): slot -> files (converted copies in\n'
    .. '-- assets/sfx/), src = the pack files they came from, vol, unsure = no file on purpose (red: nobody was sure of a\n'
    .. '-- pick; candidates = suggestions to audition), and every setting that differs from mb/audio.lua DEFAULTS\nreturn ' .. ser(out) .. '\n')
end

function A.save_rooms()
  file_write_string(ROOMS, '-- the rooms\' reverb and the global 3D switches (written by the in-game editor, mb/soundui.lua)\nreturn '
    .. ser({ on3d = A.on3d, reverb_on = A.reverb_on, zones = A.rooms }) .. '\n')
end

function A.assigned(name) local s = A.slots[name]; return s and s.files and #s.files > 0 end
function A.unsure(name) local s = A.slots[name]; return s and s.unsure and not (s.files and #s.files > 0) or false end
function A.muted(name) local s = A.slots[name]; return s and s.mute or false end

-- a slot's setting: its own, else the default
-- (Lich) the layers. A file's layer is per[path].layer (1 when unset); a layer's own settings are lay["n"].
function A.layer_of(name, fi)
  local s = A.slots[name]
  local path = s and s.files and s.files[fi]
  local p = path and s.per and s.per[path]
  return p and p.layer or 1
end
-- -> the layer numbers in use (ascending), and n -> its file indices
function A.layers(name)
  local s = A.slots[name]
  local by, list = {}, {}
  for fi = 1, (s and s.files and #s.files or 0) do
    local n = A.layer_of(name, fi)
    if not by[n] then by[n] = {}; list[#list + 1] = n end
    by[n][#by[n] + 1] = fi
  end
  table.sort(list)
  return list, by
end
-- a file into layer n (nil or 1 = the first)
function A.set_layer_of(name, fi, n)
  A.set_file(name, fi, 'layer', (n and n ~= 1) and n or nil)
end
-- renumber the layers 1..k in their order (after files moved or went), their own settings with them
function A.compact_layers(name)
  local s = A.slots[name]
  if not s then return end
  local list = A.layers(name)
  local map, lay = {}, {}
  for i, n in ipairs(list) do
    map[n] = i
    if s.lay and s.lay[tostring(n)] then lay[tostring(i)] = s.lay[tostring(n)] end
  end
  for fi = 1, #(s.files or {}) do A.set_layer_of(name, fi, map[A.layer_of(name, fi)]) end
  s.lay = next(lay) and lay or nil
end
-- (Lich) a file or a whole layer taken OUT (right-click in the editor): listed, never played by the game or the whole
-- sound's preview (clicking it alone still plays it)
function A.file_off(name, fi)
  local s = A.slots[name]
  local path = s and s.files and s.files[fi]
  local p = path and s.per and s.per[path]
  return p ~= nil and p.off == true
end
function A.layer_off(name, n)
  local s = A.slots[name]
  local l = s and s.lay and s.lay[tostring(n)]
  return l ~= nil and l.off == true
end
function A.set_layer(name, n, key, v)
  local s = A.slots[name]
  if not s then return end
  s.lay = s.lay or {}
  local l = s.lay[tostring(n)] or {}
  l[key] = v
  s.lay[tostring(n)] = next(l) and l or nil
  if not next(s.lay) then s.lay = nil end
end
function A.own_layer(name, n, key)
  local s = A.slots[name]
  local l = s and s.lay and s.lay[tostring(n)]
  return l ~= nil and l[key] ~= nil
end

-- (Lich) a setting: fi = one of the slot's files (its index), li = a layer (else fi's): the file's own first
-- (s.per[its path]), then its layer's (s.lay["n"]), then the slot's, then the default
function A.get(name, key, fi, li)
  local s = A.slots[name]
  local v
  if s then
    if fi and s.per and s.files then local p = s.per[s.files[fi] or false]; v = p and p[key] end
    if v == nil and s.lay then
      local n = li or (fi and A.layer_of(name, fi))
      local l = n and s.lay[tostring(n)]
      v = l and l[key]
    end
    if v == nil then v = s[key] end
  end
  if v == nil then v = A.DEFAULTS[key] end
  return v
end
-- (Lich) one file's own setting (v nil = back to the slot's); whether it has one
function A.set_file(name, fi, key, v)
  local s = A.slots[name]
  local path = s and s.files and s.files[fi]
  if not path then return end
  s.per = s.per or {}
  local p = s.per[path] or {}
  p[key] = v
  s.per[path] = next(p) and p or nil
  if not next(s.per) then s.per = nil end
end
function A.own_file(name, fi, key)
  local s = A.slots[name]
  local path = s and s.files and s.files[fi]
  local p = path and s.per and s.per[path]
  return p ~= nil and p[key] ~= nil
end
function A.set(name, key, v)
  local s = A.slots[name] or { files = {}, src = {} }
  s[key] = v
  A.slots[name] = s
end

-- (Lich, 2026-10-15, session 17: on the site the sounds come in packs after the game has started (game_file_ready, the
-- site's game host; the owner: "I want the game to be playable immediately"). A file not here yet is not loaded; its
-- slot waits in A.waiting and is loaded again once all its files are here (A.update), its loop started then.)
A.waiting = {}
local function here(f) return type(game_file_ready) ~= 'function' or game_file_ready(f) end
-- (re)load a slot's files
function A.reload(name)
  local s = A.slots[name]
  local list, ix = {}, {}
  A.waiting[name] = nil
  if s and s.files then
    for fi, f in ipairs(s.files) do
      if here(f) then
        local ok, snd = pcall(sound_load, f)    -- a pick whose file went missing stays silent instead of stopping the game
        if ok and snd then list[#list + 1] = snd; ix[#list] = fi end
      else A.waiting[name] = true end
    end
  end
  A.sounds[name] = list
  A.sound_ix[name] = ix     -- (Lich) list[k] is the slot's file ix[k]
  for _, L in ipairs(A.loops) do if L.name == name and not L.stopped then A.start_loop(L) end end
end

-- ------------------------------------------------------------------------------------------------ the log (labels)
function A.note(name, pos, delay)
  A.seen[name] = true
  local now = A.now
  for i = #A.events, max(1, #A.events - 24), -1 do
    local e = A.events[i]
    if e.name == name and now - e.t <= 0.6 then
      if (not e.pos and not pos) or (e.pos and pos and e.pos:distance_to_squared(pos) < 0.64) then
        e.count = e.count + 1; e.t = now + (delay or 0)
        return
      end
    end
  end
  A.events[#A.events + 1] = { name = name, pos = pos and pos:clone() or nil, t = now + (delay or 0), count = 1 }
  if #A.events > 400 then table.remove(A.events, 1) end   -- (Lich: 80 was a few seconds of a fight; TAB looks back 10 s)
end

-- ------------------------------------------------------------------------------------------------ the listener
local LIS = { pos = Vector3.new(), right = Vector3.new(1, 0, 0), up = Vector3.new(0, 1, 0), fwd = Vector3.new(0, 0, -1),
  vel = Vector3.new(), prev = nil }
A.listener = LIS.pos
A.lis = LIS

local function set_listener(cam, dt)
  if not cam then return end
  if cam.matrix_world then
    if cam.update_matrix_world then cam:update_matrix_world() end
    local e = cam.matrix_world.elements
    LIS.pos:set(e[13], e[14], e[15])
    LIS.right:set(e[1], e[2], e[3]):normalize()
    LIS.up:set(e[5], e[6], e[7]):normalize()
    LIS.fwd:set(-e[9], -e[10], -e[11]):normalize()
  else
    LIS.pos:copy(cam)       -- a bare position (older callers)
  end
  if dt and dt > 0 then
    if LIS.prev then
      local vx, vy, vz = (LIS.pos.x - LIS.prev.x) / dt, (LIS.pos.y - LIS.prev.y) / dt, (LIS.pos.z - LIS.prev.z) / dt
      if vx * vx + vy * vy + vz * vz > 400 then vx, vy, vz = 0, 0, 0 end     -- a teleport, not a velocity
      LIS.vel:set(LIS.vel.x + (vx - LIS.vel.x) * 0.5, LIS.vel.y + (vy - LIS.vel.y) * 0.5, LIS.vel.z + (vz - LIS.vel.z) * 0.5)
    else LIS.prev = Vector3.new() end
    LIS.prev:copy(LIS.pos)
  end
end

-- ------------------------------------------------------------------------------------------------ the 3D model
local function walls_between(pos)
  local f = A.hooks.occlusion
  if not f then return 0 end
  local ok, w = pcall(f, LIS.pos, pos)
  return ok and tonumber(w) or 0
end

-- What each ear gets for slot `name` heard from `pos` (nil = in your head). Fills and returns fx (the engine's
-- table), info (the numbers behind it, for the editor's readout) and the doppler pitch factor. `walls` = the
-- wall count to use (nil = ask the hook).
function A.spatial(name, pos, o, walls, vel, fx, info)
  fx = fx or {}
  info = info or {}
  local fi, li = o and o.fi, o and o.li     -- (Lich) the file playing (or the editor's layer): their own settings
  local get = function(k) return A.get(name, k, fi, li) end
  local send = A.get(name, 'reverb', fi, li) or (o and o.reverb) or SEND
  local room = A.reverb_on and 1 or 0
  local lowcut = get('lowcut')
  info.d, info.walls, info.x, info.z, info.itd, info.gain, info.pf = nil, 0, 0, 1, 0, 1, 1
  if not pos or not get('spatial') then
    fx.gain_l, fx.gain_r, fx.delay_l, fx.delay_r, fx.lp_l, fx.lp_r = 1, 1, 0, 0, 22000, 22000
    fx.hp, fx.width, fx.dry, fx.wet = lowcut, 1, 1, send * room
    info.wet = fx.wet
    return fx, info, 1
  end
  local dx, dy, dz = pos.x - LIS.pos.x, pos.y - LIS.pos.y, pos.z - LIS.pos.z
  local d = sqrt(dx * dx + dy * dy + dz * dz)
  info.d = d
  -- distance
  local near, far, roll = max(0.05, get('near')), max(0.1, get('far')), get('rolloff')
  local curve = get('curve')
  local dc = max(d, near)
  local g
  if curve == 'linear' then g = max(0, 1 - roll * (min(dc, far) - near) / max(0.01, far - near))
  elseif curve == 'exp' then g = (dc / near) ^ (-roll)
  elseif curve == 'none' then g = 1
  else g = near / (near + roll * (dc - near)) end
  if d >= far then g = 0 elseif d > far * 0.8 then g = g * (far - d) / (far * 0.2) end
  info.gain = g
  if not A.on3d then
    -- 3D off (the A/B switch): the old way, loudness by distance and nothing else
    fx.gain_l, fx.gain_r, fx.delay_l, fx.delay_r, fx.lp_l, fx.lp_r = 1, 1, 0, 0, 22000, 22000
    fx.hp, fx.width, fx.dry, fx.wet = lowcut, 1, g, send * room * sqrt(g)
    info.wet = fx.wet
    return fx, info, 1
  end
  -- direction, in the listener's frame (x = right, z = ahead)
  local x, z = 0, 1
  if d > 1e-4 then
    x = (dx * LIS.right.x + dy * LIS.right.y + dz * LIS.right.z) / d
    z = (dx * LIS.fwd.x + dy * LIS.fwd.y + dz * LIS.fwd.z) / d
  end
  local k = min(1, d / 0.25)      -- inside the head's own size a source has no side
  x = x * k
  info.x, info.z = x, z
  local gl, gr, dl, dr, lpl, lpr = 1, 1, 0, 0, 20000, 20000
  if get('binaural') then
    local ax = min(1, abs(x))
    local far_gain = 1 - 0.5 * ax                     -- about -6 dB at the side
    local shadow = 20000 * (2200 / 20000) ^ ax        -- the head shades the highs from the far ear
    local itd = HEAD * (math.asin(ax) + ax)
    info.itd = itd
    if x > 0 then gl, lpl, dl = far_gain, shadow, itd else gr, lpr, dr = far_gain, shadow, itd end
    if z < 0 then                                     -- behind: the outer ear dulls what comes from the back
      local b = 20000 * (7000 / 20000) ^ min(1, -z)
      lpl, lpr = min(lpl, b), min(lpr, b)
    end
  else
    local th = (x + 1) * math.pi / 4                  -- equal power, 0 dB in the middle
    gl, gr = min(1, 1.41421 * math.cos(th)), min(1, 1.41421 * math.sin(th))
  end
  -- air
  local air = get('air')
  if air > 0 then
    local a = 20000 / (1 + air * d / 8)
    lpl, lpr = min(lpl, a), min(lpr, a)
  end
  -- walls
  if walls == nil then walls = walls_between(pos) end
  info.walls = walls
  local occ = walls * get('occlusion')
  local og, owet = 1, 1
  if occ > 0 then
    og = 0.35 ^ occ                                   -- about -9 dB a wall
    local c = max(250, 20000 * 0.035 ^ occ)           -- one wall: everything above ~700 Hz goes
    lpl, lpr = min(lpl, c), min(lpr, c)
    owet = 0.6 ^ occ                                  -- the room's answer gets through better than the direct sound
  end
  fx.gain_l, fx.gain_r, fx.delay_l, fx.delay_r, fx.lp_l, fx.lp_r = gl, gr, dl, dr, lpl, lpr
  fx.hp, fx.width = lowcut, get('width')
  fx.dry = g * og
  fx.wet = send * room * sqrt(g) * owet               -- the reverb fades slower than the direct sound
  info.wet = fx.wet
  -- doppler: the speed you and the source close in at
  local pf = 1
  local dop = get('doppler')
  if dop > 0 and d > 1e-3 then
    local ux, uy, uz = dx / d, dy / d, dz / d
    local vl = LIS.vel.x * ux + LIS.vel.y * uy + LIS.vel.z * uz
    local vs = vel and (vel.x * ux + vel.y * uy + vel.z * uz) or 0
    pf = max(0.5, min(2, (SPEED + dop * vl) / max(1, SPEED + dop * vs)))
  end
  info.pf = pf
  return fx, info, pf
end

-- ------------------------------------------------------------------------------------------------ playing
-- (Lich) -> the sound and which of the slot's files it is. only = that file (nil if it isn't loaded); layer = one of
-- that layer's files at random (its variations), never the same twice running; neither = any of the slot's files
local function pick(name, only, layer)
  local v = A.sounds[name]
  if not v or #v == 0 then return nil end
  local ix = A.sound_ix[name] or {}
  if only then
    for k = 1, #v do if (ix[k] or k) == only then return v[k], only end end
    return nil
  end
  local c = {}
  for k = 1, #v do
    local fi = ix[k] or k
    if (not layer or A.layer_of(name, fi) == layer) and not A.file_off(name, fi) then c[#c + 1] = k end   -- (out = never)
  end
  if #c == 0 then return nil end
  local key = layer and (name .. '#' .. layer) or name
  local j = 1 + floor(rnd()*#c)
  if #c > 1 and v[c[j]] == A.last[key] then j = j % #c + 1 end
  local i = c[j]
  A.last[key] = v[i]
  return v[i], ix[i] or i
end
-- (Lich) the files one play plays: from each layer that is in, one of its files at random, or with ALL AT ONCE every
-- one of its files that is in. only_layer = that layer alone (the editor's, even if it is out).
function A.choose(name, only_layer)
  local layers, by = A.layers(name)
  local out = {}
  for _, n in ipairs(layers) do
    if (only_layer and n == only_layer) or (not only_layer and not A.layer_off(name, n)) then
      if A.get(name, 'all', nil, n) then
        for _, fi in ipairs(by[n]) do if not A.file_off(name, fi) then out[#out + 1] = fi end end
      else
        local _, fi = pick(name, nil, n)
        if fi then out[#out + 1] = fi end
      end
    end
  end
  return out
end

local function source_pos(o)
  if o.follow and o.follow.matrix_world then
    local e = o.follow.matrix_world.elements
    o.pos = o.pos or Vector3.new()
    o.pos:set(e[13], e[14], e[15])
  end
  return o.pos
end

-- start one voice of slot `name`; nil when the slot is silent
local function voice(name, o, loop)
  if A.muted(name) or (A.quiet and not A.LOUD[name]) then return nil end
  local snd, fi = pick(name, o.fi)
  if not snd then return nil end
  o.fi = fi       -- (Lich) the file this voice plays: its own settings, now and every frame after (refresh)
  local lo, hi = A.get(name, 'pitch_lo', fi), A.get(name, 'pitch_hi', fi)
  local base_pitch = (o.pitch or 1) * (lo + (hi - lo) * rnd())
  local pos = source_pos(o)
  local walls = pos and walls_between(pos) or 0
  local fx, info, pf = A.spatial(name, pos, o, walls, o.vel)
  local del = A.get(name, 'delay', fi)
  fx.bits, fx.sr_div, fx.start = A.get(name, 'bits', fi), A.get(name, 'sr', fi), del < 0 and -del or 0
  local vol = (o.volume or 1) * A.get(name, 'vol', fi) * A.master
  local h
  if sound_play_fx then h = sound_play_fx(snd, min(vol, 4), base_pitch * pf, fx)
  else   -- (Lich) an engine without FX voices (the site's, for now): loudness only, no ears, no room
    h = sound_play_handle(snd, min(vol * fx.dry * 0.5 * (fx.gain_l + fx.gain_r), 4), base_pitch * pf, fx.bits, fx.sr_div, fx.start)
  end
  fx.bits, fx.sr_div, fx.start = nil, nil, nil
  if not h or h < 0 then return nil end
  A.voices[#A.voices + 1] = { h = h, name = name, o = o, fx = fx, info = info, walls = walls, occ_t = 0,
    pitch = base_pitch, pf = pf, loop = loop, t0 = A.now }
  return h
end

-- the delay a play waits: the call's, the slot's (when positive) and the sound's travel time
local function wait_for(name, o)
  local w = (o.delay or 0) + max(0, A.get(name, 'delay', o.fi))
  local tr = A.get(name, 'travel', o.fi)
  if tr > 0 and o.pos and A.get(name, 'spatial', o.fi) and A.on3d then w = w + tr * o.pos:distance_to(LIS.pos) / SPEED end
  return w
end

function A.play(name, o)
  o = o or {}
  if o.gap then        -- (Lich) a slot played again sooner than `gap` s after the last: dropped (bursts of events)
    if A.last_t[name] and A.now - A.last_t[name] < o.gap then return nil end
    A.last_t[name] = A.now
  end
  name = A.SAME[name] or name     -- (Lich) a slot that is another's sound (its call's gap stays its own, above)
  o.pos = v3(o.pos)
  local fis = o.fi and { o.fi } or A.choose(name)     -- (Lich) the files this play plays, chosen now
  A.note(name, o.pos, o.delay)
  A.last_play[name] = { pos = o.pos and o.pos:clone() or nil, volume = o.volume, pitch = o.pitch, reverb = o.reverb }
  if #fis == 0 then return nil end
  if #fis > 1 then   -- (Lich) several (layers, or a layer playing all its files): each its own play
    local h1
    for _, fi in ipairs(fis) do
      local oc = {}
      for k, x in pairs(o) do oc[k] = x end
      oc.fi, oc.pos = fi, o.pos and o.pos:clone() or nil
      local w = wait_for(name, oc)
      if w > 0 then A.pending[#A.pending + 1] = { name = name, o = oc, at = A.now + w }
      else local h = voice(name, oc); h1 = h1 or h end
    end
    return h1
  end
  o.fi = fis[1]
  local w = wait_for(name, o)
  if w > 0 then
    A.pending[#A.pending + 1] = { name = name, o = o, at = A.now + w }
    return nil
  end
  return voice(name, o)
end

-- the editor's PLAY: the slot as the game last played it, from where it last played, heard from here now
-- (a new preview cuts the last one: dragging a slider replays it every quarter second)
A.rt = 0
A.pending_rt = {}
-- (Lich) only = that file alone; li = that layer alone (one of its files at random); neither = the whole sound, as
-- the game plays it (each layer, one of its files)
function A.preview(name, only, li)
  if A.preview_h then sound_handle_stop(A.preview_h); A.preview_h = nil end
  for _, h in ipairs(A.preview_hs) do sound_handle_stop(h) end
  A.preview_hs = {}
  A.pending_rt = {}
  A.preview_stop = nil
  local lp = A.last_play[name] or {}
  local looped = {}       -- (Lich) a loop's slot: its voices loop for PREVIEW_HOLD s, then stop as the game stops them
  local function one(fi)
    local o = { pos = lp.pos and lp.pos:clone() or nil, volume = lp.volume, pitch = lp.pitch, reverb = lp.reverb, fi = fi }
    local w = max(0, A.get(name, 'delay', fi))
    local tr = A.get(name, 'travel', fi)
    if tr > 0 and o.pos and A.get(name, 'spatial', fi) and A.on3d then w = w + tr * o.pos:distance_to(LIS.pos) / SPEED end
    if w > 0 then A.pending_rt[#A.pending_rt + 1] = { name = name, o = o, at = A.rt + w }; return true end
    local h = voice(name, o)
    if h then
      A.preview_hs[#A.preview_hs + 1] = h; A.preview_h = A.preview_h or h
      if A.loop_slot[name] and not A.get(name, 'once', fi) then sound_handle_set_looping(h, true); looped[#looped + 1] = h end
    end
    return h ~= nil
  end
  local any = false
  if only then any = one(only)
  else for _, fi in ipairs(A.choose(name, li)) do if one(fi) then any = true end end end
  if #looped > 0 then A.preview_stop = { at = A.rt + A.PREVIEW_HOLD, hs = looped } end
  return any
end
A.PREVIEW_HOLD = 1.5

-- loops are registered even with nothing picked yet, so a pick made later starts them in place
-- (Lich) a loop's voices stop: its main one and a layered loop's others
-- fade = the loop was stopped by the game (L.stop): a voice whose FADE OUT is set dies away over that many seconds
-- instead (it leaves the loop and refresh fades it); a restart, a mute, the site going off screen stop at once
local function loop_off(L, fade)
  local function off(h)
    if fade then
      for _, v in ipairs(A.voices) do
        if v.h == h then
          local d = A.get(v.name, 'fade', v.o.fi)
          if d > 0 then v.fade = { t = 0, dur = d }; v.loop = nil; return end
          break
        end
      end
    end
    sound_handle_stop(h)
  end
  if L.h then off(L.h); L.h = nil end
  if L.extra then for _, h in ipairs(L.extra) do off(h) end; L.extra = nil end
end
function A.loop(name, o)
  o = o or {}
  o.pos = v3(o.pos)
  local L = { name = name, opts = o, h = nil, stopped = false }
  -- (Lich: loop_end = when it stopped, so TAB still lists a loop that ended a moment ago)
  function L.stop() L.stopped = true; A.loop_end[name] = A.now; A.loop_set[L] = nil; loop_off(L, true) end
  -- (Lich) a loop that moves with what makes it, and gets louder or softer (its voice reads opts every frame)
  function L.set_pos(p) if p then if o.pos then o.pos:set(p.x or p[1] or 0, p.y or p[2] or 0, p.z or p[3] or 0) else o.pos = v3(p) end end end
  function L.set_volume(v) o.volume = v end
  L.src = { stop = L.stop }
  A.loops[#A.loops + 1] = L
  A.loop_set[L] = true
  A.seen[name] = true
  A.loop_slot[name] = true     -- (Lich: the editor offers PLAYS ONCE for its files)
  A.last_play[name] = { pos = o.pos and o.pos:clone() or nil, volume = o.volume, pitch = o.pitch, reverb = o.reverb }
  A.start_loop(L)
  return L
end
function A.start_loop(L)
  loop_off(L)
  if L.opts.max then   -- (Lich) at most `max` of this slot sounding at once; the rest stay registered, silent
    local n = 0
    for _, o in ipairs(A.loops) do if o ~= L and o.name == L.name and o.h and not o.stopped then n = n + 1 end end
    if n >= L.opts.max then return end
  end
  -- (Lich) the files chosen as for a play (each layer that is in: one at random, or all of it), each its own voice
  -- and settings; a layer marked ONCE plays once (a plain one-shot, let finish), the others loop
  for _, fi in ipairs(A.choose(L.name)) do
    local once = A.get(L.name, 'once', fi)
    local oc = setmetatable({ fi = fi }, { __index = L.opts })   -- (its position and volume follow the loop's)
    local h = voice(L.name, oc, (not once) and L or nil)
    if h and not once then
      sound_handle_set_looping(h, true)
      if L.h then L.extra = L.extra or {}; L.extra[#L.extra + 1] = h else L.h = h end
    end
  end
end

-- every live voice follows the listener (and its source); voices the engine let go are dropped
-- (Lich) a fading voice's gain: down 48 dB over its FADE OUT, even in dB (the way a sound dies away), then it stops
local function fade_gain(v) return 10^(-2.4*v.fade.t/v.fade.dur) end

-- fdt = the time fades move on by (the editor's paused previews fade too; the rest of a paused refresh is dt 0)
local function refresh(dt, fdt)
  local keep = {}
  for _, v in ipairs(A.voices) do
    if v.fade then v.fade.t = v.fade.t + (fdt or dt or 0) end
    local pos = source_pos(v.o)
    v.occ_t = v.occ_t - (dt or 0)
    if pos and v.occ_t <= 0 then v.walls = walls_between(pos); v.occ_t = OCC_EVERY end
    local fx, info, pf = A.spatial(v.name, pos, v.o, v.walls, v.o.vel, v.fx, v.info)
    fx.width = (pos and A.get(v.name, 'spatial', v.o.fi)) and A.get(v.name, 'width', v.o.fi) or 1
    local alive
    if sound_handle_set_fx then alive = sound_handle_set_fx(v.h, fx)
    else   -- (Lich) no FX voices: a loop's loudness follows; a one-shot is let go after 10 s
      alive = v.loop ~= nil or v.fade ~= nil or A.now - v.t0 < 10
      if v.loop or v.fade then
        sound_handle_set_volume(v.h, (v.o.volume or 1) * A.get(v.name, 'vol', v.o.fi) * A.master * fx.dry * 0.5 * (fx.gain_l + fx.gain_r)
          * (v.fade and fade_gain(v) or 1) * ((v.loop and A.editing == v.name) and 0 or 1))
      end
    end
    if alive and v.fade and v.fade.t >= v.fade.dur then sound_handle_stop(v.h); alive = false end   -- (Lich) faded out
    if alive then
      if abs(pf - v.pf) > 0.002 then v.pf = pf; sound_handle_set_pitch(v.h, v.pitch * pf) end
      if v.loop and sound_handle_set_fx then
        local s = A.slots[v.name]
        -- (Lich) the editor open on this slot: the game's own loop of it is hushed (its PLAY is heard alone)
        sound_handle_set_volume(v.h, (v.o.volume or 1) * A.get(v.name, 'vol', v.o.fi) * A.master * (A.editing == v.name and 0 or 1))
        if s and s.mute then loop_off(v.loop) end
      elseif v.fade and sound_handle_set_fx then      -- (Lich) dying away
        sound_handle_set_volume(v.h, (v.o.volume or 1) * A.get(v.name, 'vol', v.o.fi) * A.master * fade_gain(v))
      end
      keep[#keep + 1] = v
    elseif v.loop and v.loop.h == v.h then
      v.loop.h = nil
    end
  end
  A.voices = keep
end

-- the reverb follows the zone the listener stands in, gliding
local cur_room = nil
local function room_tick(dt)
  local z = A.hooks.zone and A.hooks.zone(LIS.pos) or nil
  A.zone = z
  local target = z and A.rooms[z]
  if not target then return end
  if not cur_room then cur_room = {}; for k, v in pairs(target) do cur_room[k] = v end end
  local k = min(1, (dt or 0) * 4)
  local changed = false
  for key, v in pairs(target) do
    local c = cur_room[key] or v
    local n = c + (v - c) * k
    if abs(n - v) < 1e-4 then n = v end
    if n ~= c then changed = true end
    cur_room[key] = n
  end
  if (changed or not A._room_sent) and sound_reverb then
    sound_reverb(cur_room)
    A._room_sent = true
  end
end
function A.room_now() return cur_room end

-- per game frame: time, delayed plays, voices, the room
function A.update(dt, cam)
  A.now = A.now + dt
  if next(A.waiting) and A.now >= (A.waiting_t or 0) then     -- (the slots whose files were still on their way)
    -- (a pack brings ~50 slots at once: loaded 3 at a time, 20 times a second, not all in one frame)
    A.waiting_t = A.now + 0.25
    local ready = {}
    for name in pairs(A.waiting) do
      local s, all = A.slots[name], true
      for _, f in ipairs(s and s.files or {}) do if not here(f) then all = false; break end end
      if all then ready[#ready + 1] = name end
    end
    table.sort(ready)
    for k = 1, math.min(3, #ready) do A.reload(ready[k]) end
    if #ready > 3 then A.waiting_t = A.now + 0.05 end
  end
  set_listener(cam, dt)
  local keep = {}
  for _, p in ipairs(A.pending) do
    if A.now >= p.at then local o = p.o; o.delay = 0; voice(p.name, o) else keep[#keep + 1] = p end
  end
  A.pending = keep
  -- stopped loops go (the hum and the TV make a new loop every time they switch on)
  local live = {}
  for _, L in ipairs(A.loops) do if not L.stopped then live[#live + 1] = L end end
  A.loops = live
  refresh(dt)
  room_tick(dt)
end

-- while the game is paused (the editor is open): game time stands still, the voices that are sounding
-- still follow the settings being edited, and the editor's previews run on their own clock
function A.paused_update(dt)
  A.rt = A.rt + dt
  LIS.vel:set(0, 0, 0)        -- you stand still while editing (no doppler left over from running)
  LIS.prev = nil
  local keep = {}
  for _, p in ipairs(A.pending_rt) do
    if A.rt >= p.at then
      local h = voice(p.name, p.o); A.preview_h = A.preview_h or h
      if h then A.preview_hs[#A.preview_hs + 1] = h end      -- (Lich: a layered preview's later voices)
    else keep[#keep + 1] = p end
  end
  A.pending_rt = keep
  -- (Lich) a loop's preview: it sounds for a moment, then stops as the game stops it (its FADE OUT)
  if A.preview_stop and A.rt >= A.preview_stop.at then
    for _, h in ipairs(A.preview_stop.hs) do
      local faded = false
      for _, v in ipairs(A.voices) do
        if v.h == h then
          local d = A.get(v.name, 'fade', v.o.fi)
          if d > 0 then v.fade = { t = 0, dur = d }; faded = true end
          break
        end
      end
      if not faded then sound_handle_stop(h) end
    end
    A.preview_stop = nil
  end
  refresh(0, dt)
  room_tick(dt)
end

-- the sounds playing right now: name -> true (live voices and loops)
function A.playing()
  local out = {}
  for _, v in ipairs(A.voices) do out[v.name] = true end
  for L in pairs(A.loop_set) do out[L.name] = true end
  return out
end

-- (Lich) the game hosted on the site goes off screen: silence, kept (its loops come back where they were)
function A.mute(on)
  on = not not on
  if on == A.quiet then return end
  A.quiet = on
  for _, L in ipairs(A.loops) do
    if on then loop_off(L)
    elseif not L.stopped then A.start_loop(L) end
  end
  if on then A.pending = {} end
end
-- (Lich) everything still sounding stops (the site drops the game)
function A.stop_all()
  for _, L in ipairs(A.loops) do L.stop() end
  for _, v in ipairs(A.voices) do sound_handle_stop(v.h) end
  A.loops, A.voices, A.pending = {}, {}, {}
end

-- the picker's audition: a raw clip, no slot, in your head
local auditioned = {}       -- path -> sound (a picking session keeps its clips, as Horse Game's picker)
function A.audition(path, volume, slot)     -- (Lich: slot = whose bits / crush)
  if A.aud then sound_handle_stop(A.aud); A.aud = nil end
  local s = auditioned[path]
  if s == nil then local ok, snd = pcall(sound_load, path); s = ok and snd or false; auditioned[path] = s end
  if not s then return false end
  local h = sound_play_handle(s, volume or 0.5, 1, slot and A.get(slot, 'bits') or A.DEFAULTS.bits,
    slot and A.get(slot, 'sr') or A.DEFAULTS.sr)
  A.aud = h and h >= 0 and h or nil
  return true
end
function A.stop_audition() if A.aud then sound_handle_stop(A.aud); A.aud = nil end end

return A
