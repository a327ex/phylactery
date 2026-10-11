--[[
  PORTED from megablock's mb/audio.lua (megablock 012a1f1) by tools/port_soundui.py: edit there, or here and say so.
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
  last_t = {}, quiet = false, loop_end = {} }   -- (Lich: a call's gap; the site's off-screen silence; when
  -- each loop last stopped, for the TAB list)
local PICKS, ROOMS = 'sound_picks.lua', 'sound_rooms.lua'
local SPEED = 343                      -- m/s
local HEAD = 0.0875 / SPEED            -- Woodworth's r / c: the ITD is HEAD * (azimuth + sin azimuth), 0.66 ms at the side
local SEND = 0.25                      -- the reverb send of a call that names none
local OCC_EVERY = 0.12                 -- seconds between a voice's wall checks

-- a slot's settings when it names none (pitch 1..1: the game's calls already jitter their pitch)
A.DEFAULTS = {
  vol = 1, pitch_lo = 1, pitch_hi = 1, delay = 0, bits = 16, sr = 1, mute = false,
  -- (Lich: the ear hangs on the room camera's line of sight, `ear` of the way in (A.ROOM_DEFAULTS, port/game.lua):
  -- ~6.5 m from the egg, ~4 m from him, ~20 m from the far wall. near = the fight round the egg at full
  -- loudness, the far wall ~10 dB down; the air a little duller with distance than a head's)
  spatial = true, curve = 'inverse', near = 6.0, far = 60, rolloff = 1.0, air = 0.5, occlusion = 1.0,
  width = 0, binaural = true, doppler = 1.0, travel = 0, lowcut = 0,
}
A.CURVES = { 'inverse', 'linear', 'exp', 'none' }

-- the rooms: the reverb the listener's zone gets (size 0..1 tail, damp 0..1, predelay s, gain, width, lowcut Hz)
A.ROOM_DEFAULTS = {
  -- (Lich) one cave, stone, 31 m across under a high dome: a long tail (size), the highs dying a little sooner
  -- than a bare hall's (rough rock, damp), the walls answering 13-20 m off (predelay 40 ms), nothing under
  -- 140 Hz sent in (the cave loop's drone and the rock slams would turn the tail to mud).
  -- ear = where you hear from: 0 = the room camera, 1 = what it looks at (port/game.lua places the listener)
  cave = { size = 0.85, damp = 0.4, predelay = 0.04, gain = 0.80, width = 1, lowcut = 140, ear = 0.5 },
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

function A.load_picks()
  A.slots = read_lua(PICKS) or {}
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
function A.get(name, key)
  local s = A.slots[name]
  local v = s and s[key]
  if v == nil then v = A.DEFAULTS[key] end
  return v
end
function A.set(name, key, v)
  local s = A.slots[name] or { files = {}, src = {} }
  s[key] = v
  A.slots[name] = s
end

-- (re)load a slot's files
function A.reload(name)
  local s = A.slots[name]
  local list = {}
  if s and s.files then
    for _, f in ipairs(s.files) do
      local ok, snd = pcall(sound_load, f)      -- a pick whose file went missing stays silent instead of stopping the game
      if ok and snd then list[#list + 1] = snd end
    end
  end
  A.sounds[name] = list
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
  if #A.events > 80 then table.remove(A.events, 1) end
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
  local get = function(k) return A.get(name, k) end
  local s = A.slots[name]
  local send = (s and s.reverb) or (o and o.reverb) or SEND
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
local function pick(name)
  local v = A.sounds[name]
  if not v or #v == 0 then return nil end
  local i = 1 + floor(rnd()*#v)
  if #v > 1 and v[i] == A.last[name] then i = i % #v + 1 end
  A.last[name] = v[i]
  return v[i]
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
  if A.muted(name) or A.quiet then return nil end
  local snd = pick(name)
  if not snd then return nil end
  local lo, hi = A.get(name, 'pitch_lo'), A.get(name, 'pitch_hi')
  local base_pitch = (o.pitch or 1) * (lo + (hi - lo) * rnd())
  local pos = source_pos(o)
  local walls = pos and walls_between(pos) or 0
  local fx, info, pf = A.spatial(name, pos, o, walls, o.vel)
  local del = A.get(name, 'delay')
  fx.bits, fx.sr_div, fx.start = A.get(name, 'bits'), A.get(name, 'sr'), del < 0 and -del or 0
  local vol = (o.volume or 1) * A.get(name, 'vol') * A.master
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
  local w = (o.delay or 0) + max(0, A.get(name, 'delay'))
  local tr = A.get(name, 'travel')
  if tr > 0 and o.pos and A.get(name, 'spatial') and A.on3d then w = w + tr * o.pos:distance_to(LIS.pos) / SPEED end
  return w
end

function A.play(name, o)
  o = o or {}
  if o.gap then        -- (Lich) a slot played again sooner than `gap` s after the last: dropped (bursts of events)
    if A.last_t[name] and A.now - A.last_t[name] < o.gap then return nil end
    A.last_t[name] = A.now
  end
  o.pos = v3(o.pos)
  A.note(name, o.pos, o.delay)
  A.last_play[name] = { pos = o.pos and o.pos:clone() or nil, volume = o.volume, pitch = o.pitch, reverb = o.reverb }
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
function A.preview(name)
  if A.preview_h then sound_handle_stop(A.preview_h); A.preview_h = nil end
  A.pending_rt = {}
  local lp = A.last_play[name] or {}
  local o = { pos = lp.pos and lp.pos:clone() or nil, volume = lp.volume, pitch = lp.pitch, reverb = lp.reverb }
  local w = max(0, A.get(name, 'delay'))
  local tr = A.get(name, 'travel')
  if tr > 0 and o.pos and A.get(name, 'spatial') and A.on3d then w = w + tr * o.pos:distance_to(LIS.pos) / SPEED end
  if w > 0 then A.pending_rt[#A.pending_rt + 1] = { name = name, o = o, at = A.rt + w }; return true end
  A.preview_h = voice(name, o)
  return A.preview_h ~= nil
end

-- loops are registered even with nothing picked yet, so a pick made later starts them in place
function A.loop(name, o)
  o = o or {}
  o.pos = v3(o.pos)
  local L = { name = name, opts = o, h = nil, stopped = false }
  -- (Lich: loop_end = when it stopped, so TAB still lists a loop that ended a moment ago)
  function L.stop() L.stopped = true; A.loop_end[name] = A.now; A.loop_set[L] = nil; if L.h then sound_handle_stop(L.h); L.h = nil end end
  -- (Lich) a loop that moves with what makes it, and gets louder or softer (its voice reads opts every frame)
  function L.set_pos(p) if p then if o.pos then o.pos:set(p.x or p[1] or 0, p.y or p[2] or 0, p.z or p[3] or 0) else o.pos = v3(p) end end end
  function L.set_volume(v) o.volume = v end
  L.src = { stop = L.stop }
  A.loops[#A.loops + 1] = L
  A.loop_set[L] = true
  A.seen[name] = true
  A.last_play[name] = { pos = o.pos and o.pos:clone() or nil, volume = o.volume, pitch = o.pitch, reverb = o.reverb }
  A.start_loop(L)
  return L
end
function A.start_loop(L)
  if L.h then sound_handle_stop(L.h); L.h = nil end
  if L.opts.max then   -- (Lich) at most `max` of this slot sounding at once; the rest stay registered, silent
    local n = 0
    for _, o in ipairs(A.loops) do if o ~= L and o.name == L.name and o.h and not o.stopped then n = n + 1 end end
    if n >= L.opts.max then return end
  end
  local h = voice(L.name, L.opts, L)
  if h then sound_handle_set_looping(h, true); L.h = h end
end

-- every live voice follows the listener (and its source); voices the engine let go are dropped
local function refresh(dt)
  local keep = {}
  for _, v in ipairs(A.voices) do
    local pos = source_pos(v.o)
    v.occ_t = v.occ_t - (dt or 0)
    if pos and v.occ_t <= 0 then v.walls = walls_between(pos); v.occ_t = OCC_EVERY end
    local fx, info, pf = A.spatial(v.name, pos, v.o, v.walls, v.o.vel, v.fx, v.info)
    fx.width = (pos and A.get(v.name, 'spatial')) and A.get(v.name, 'width') or 1
    local alive
    if sound_handle_set_fx then alive = sound_handle_set_fx(v.h, fx)
    else   -- (Lich) no FX voices: a loop's loudness follows; a one-shot is let go after 10 s
      alive = v.loop ~= nil or A.now - v.t0 < 10
      if v.loop then sound_handle_set_volume(v.h, (v.o.volume or 1) * A.get(v.name, 'vol') * A.master * fx.dry * 0.5 * (fx.gain_l + fx.gain_r)) end
    end
    if alive then
      if abs(pf - v.pf) > 0.002 then v.pf = pf; sound_handle_set_pitch(v.h, v.pitch * pf) end
      if v.loop and sound_handle_set_fx then
        local s = A.slots[v.name]
        sound_handle_set_volume(v.h, (v.o.volume or 1) * A.get(v.name, 'vol') * A.master)
        if s and s.mute then sound_handle_stop(v.h); v.loop.h = nil end
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
    if A.rt >= p.at then A.preview_h = voice(p.name, p.o) else keep[#keep + 1] = p end
  end
  A.pending_rt = keep
  refresh(0)
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
    if on then if L.h then sound_handle_stop(L.h); L.h = nil end
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
function A.audition(path, volume)
  if A.aud then sound_handle_stop(A.aud); A.aud = nil end
  local s = auditioned[path]
  if s == nil then local ok, snd = pcall(sound_load, path); s = ok and snd or false; auditioned[path] = s end
  if not s then return false end
  local h = sound_play_handle(s, volume or 0.5, 1)
  A.aud = h and h >= 0 and h or nil
  return true
end
function A.stop_audition() if A.aud then sound_handle_stop(A.aud); A.aud = nil end end

return A
