"""port_soundui.py -- megablock's sound UI and 3D audio into Lich Survivors (2026-10-10, "Lich Survivors 13").

megablock's session "Megablock 2" wrote mb/audio.lua (slots placed in 3D on the engine's FX voices) and mb/soundui.lua
(the names on screen, the TAB list, the slot editor, the pack picker) to be shared; this copies them into port/ with
Lich's few differences. Re-run after megablock changes them (its commit is printed into the files' headers).

  python tools/port_soundui.py
"""
import json, os, re, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
MB = os.path.join(GAME, '..', 'megablock')


def rep(s, old, new, count=1):
    n = s.count(old)
    if n != count:
        raise SystemExit(f'expected {count} of {old[:70]!r}, found {n}')
    return s.replace(old, new)


def main():
    commit = subprocess.run(['git', '-C', MB, 'log', '-1', '--format=%h', '--', 'mb/audio.lua', 'mb/soundui.lua'],
                            capture_output=True, text=True).stdout.strip()
    stamp = f'  PORTED from megablock\'s mb/{{}} (megablock {commit}) by tools/port_soundui.py: edit there, or here and say so.\n'

    # ---------------------------------------------------------------- soundui
    s = open(os.path.join(MB, 'mb', 'soundui.lua'), encoding='utf-8').read()
    s = rep(s, "  mb/soundui.lua -- sounds as words", stamp.format('soundui.lua') + "  soundui.lua -- sounds as words")
    s = rep(s, "local GX = require('mb.gfx')\nlocal AU = require('mb.audio')\n", "local AU = require('port.audio')\n")
    s = rep(s, "  The game calls (mb/game.lua):", "  The game calls (port/game.lua):")
    s = rep(s, "local HUD                -- mb/hud.lua, handed in by draw", "local HUD                -- port/hud.lua, handed in by draw")
    # Lich's slots (tools/sfx_spec.py), in the order they were written there
    spec = open(os.path.join(HERE, 'sfx_spec.py'), encoding='utf-8').read()
    names = re.findall(r"^    '([a-z0-9_]+)': dict\(", spec, re.M)
    known = 'M.KNOWN = {\n' + ''.join(
        '  ' + ', '.join(f"'{n}'" for n in names[i:i + 8]) + ',\n' for i in range(0, len(names), 8)) + '}\n'
    s = re.sub(r"M\.KNOWN = \{\n.*?\n\}\n", lambda m: known, s, count=1, flags=re.S)
    # labels: Lich projects with the world camera (no mb.gfx); the HUD frame is 640x360 as megablock's
    s = rep(s, """local function project(pos, lim, near)
  _v:copy(pos)
  local p = GX.project(_v, _p)
  local nx, ny = p.x / (GX.W * 0.5) - 1, 1 - p.y / (GX.H * 0.5)
  if p.z > 1 or (near and p.z < -1) or math.abs(nx) > lim or math.abs(ny) > lim then return nil end
  return p.x, p.y
end""", """local CAM = nil           -- the world camera, from the last draw (Lich: no mb.gfx)
local function project(pos, lim, near)
  if not CAM then return nil end
  _v:copy(pos):project(CAM)
  if _v.z > 1 or (near and _v.z < -1) or math.abs(_v.x) > lim or math.abs(_v.y) > lim then return nil end
  return (_v.x*0.5 + 0.5)*640, (0.5 - _v.y*0.5)*360
end""")
    s = rep(s, "function M.draw(hud, camera)\n", "function M.draw(hud, camera)\n  CAM = camera\n")
    open(os.path.join(GAME, 'port', 'soundui.lua'), 'w', encoding='utf-8', newline='\n').write(s)

    # ---------------------------------------------------------------- audio
    a = open(os.path.join(MB, 'mb', 'audio.lua'), encoding='utf-8').read()
    a = rep(a, "  mb/audio.lua -- sound slots, placed in 3D", stamp.format('audio.lua') + "  audio.lua -- sound slots, placed in 3D")
    a = rep(a, "  folder, written by the editor in mb/soundui.lua;", "  folder, written by the editor in port/soundui.lua;")
    a = lich_audio(a)
    open(os.path.join(GAME, 'port', 'audio.lua'), 'w', encoding='utf-8', newline='\n').write(a)
    print(f'ported megablock {commit}: port/soundui.lua ({len(names)} slots known), port/audio.lua')


def lich_audio(a):
    """Lich's differences from megablock's audio: its own random generator, the room-sized listener (the fixed camera
    ~15 m off), one cave, the calls' extras (gap, max, set_pos/set_volume, plain {x,y,z} positions), muting for the
    site, and engines without the FX voices (the site's, until it gets them)."""
    a = rep(a, "local sqrt, abs, min, max, floor = math.sqrt, math.abs, math.min, math.max, math.floor\n",
            """local sqrt, abs, min, max, floor = math.sqrt, math.abs, math.min, math.max, math.floor

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
""")
    a = rep(a, "  voices = {}, last_play = {}, master = 0.8, ready = true, hooks = {}, on3d = true, reverb_on = true, zone = nil }",
            "  voices = {}, last_play = {}, master = 0.8, ready = true, hooks = {}, on3d = true, reverb_on = true, zone = nil,\n"
            "  last_t = {}, quiet = false }      -- (Lich: a call's gap; the site's off-screen silence)")
    a = rep(a, "  spatial = true, curve = 'inverse', near = 1.0, far = 60, rolloff = 1.0, air = 1.0, occlusion = 1.0,",
            "  -- (Lich: the ear is the room's fixed camera, ~15 m from the egg and the fight, not a head in it: near is\n"
            "  -- room-sized and the air gentle, or the whole room would come out 23 dB down and dull)\n"
            "  spatial = true, curve = 'inverse', near = 12.0, far = 60, rolloff = 1.0, air = 0.3, occlusion = 1.0,")
    a = re.sub(r"A\.ROOM_DEFAULTS = \{\n.*?\n\}\n",
               "A.ROOM_DEFAULTS = {\n  cave = { size = 0.85, damp = 0.35, predelay = 0.035, gain = 0.80, width = 1, lowcut = 120 },   "
               "-- (Lich) one cave, stone, high\n}\n", a, count=1, flags=re.S)
    a = rep(a, "  local i = math.random(1, #v)", "  local i = 1 + floor(rnd()*#v)")
    a = rep(a, "  local base_pitch = (o.pitch or 1) * (lo + (hi - lo) * math.random())",
            "  local base_pitch = (o.pitch or 1) * (lo + (hi - lo) * rnd())")
    a = rep(a, """local function voice(name, o, loop)
  if A.muted(name) then return nil end""", """local function voice(name, o, loop)
  if A.muted(name) or A.quiet then return nil end""")
    a = rep(a, "  local h = sound_play_fx(snd, min(vol, 4), base_pitch * pf, fx)",
            """  local h
  if sound_play_fx then h = sound_play_fx(snd, min(vol, 4), base_pitch * pf, fx)
  else   -- (Lich) an engine without FX voices (the site's, for now): loudness only, no ears, no room
    h = sound_play_handle(snd, min(vol * fx.dry * 0.5 * (fx.gain_l + fx.gain_r), 4), base_pitch * pf, fx.bits, fx.sr_div, fx.start)
  end""")
    a = rep(a, """function A.play(name, o)
  o = o or {}
  A.note(name, o.pos, o.delay)""", """function A.play(name, o)
  o = o or {}
  if o.gap then        -- (Lich) a slot played again sooner than `gap` s after the last: dropped (bursts of events)
    if A.last_t[name] and A.now - A.last_t[name] < o.gap then return nil end
    A.last_t[name] = A.now
  end
  o.pos = v3(o.pos)
  A.note(name, o.pos, o.delay)""")
    a = rep(a, """function A.loop(name, o)
  o = o or {}
  local L = { name = name, opts = o, h = nil, stopped = false }
  function L.stop() L.stopped = true; A.loop_set[L] = nil; if L.h then sound_handle_stop(L.h); L.h = nil end end""",
            """function A.loop(name, o)
  o = o or {}
  o.pos = v3(o.pos)
  local L = { name = name, opts = o, h = nil, stopped = false }
  function L.stop() L.stopped = true; A.loop_set[L] = nil; if L.h then sound_handle_stop(L.h); L.h = nil end end
  -- (Lich) a loop that moves with what makes it, and gets louder or softer (its voice reads opts every frame)
  function L.set_pos(p) if p then if o.pos then o.pos:set(p.x or p[1] or 0, p.y or p[2] or 0, p.z or p[3] or 0) else o.pos = v3(p) end end end
  function L.set_volume(v) o.volume = v end""")
    a = rep(a, """function A.start_loop(L)
  if L.h then sound_handle_stop(L.h); L.h = nil end
  local h = voice(L.name, L.opts, L)""", """function A.start_loop(L)
  if L.h then sound_handle_stop(L.h); L.h = nil end
  if L.opts.max then   -- (Lich) at most `max` of this slot sounding at once; the rest stay registered, silent
    local n = 0
    for _, o in ipairs(A.loops) do if o ~= L and o.name == L.name and o.h and not o.stopped then n = n + 1 end end
    if n >= L.opts.max then return end
  end
  local h = voice(L.name, L.opts, L)""")
    a = rep(a, """    if sound_handle_set_fx(v.h, fx) then""",
            """    local alive
    if sound_handle_set_fx then alive = sound_handle_set_fx(v.h, fx)
    else   -- (Lich) no FX voices: a loop's loudness follows; a one-shot is let go after 10 s
      alive = v.loop ~= nil or A.now - v.t0 < 10
      if v.loop then sound_handle_set_volume(v.h, (v.o.volume or 1) * A.get(v.name, 'vol') * A.master * fx.dry * 0.5 * (fx.gain_l + fx.gain_r)) end
    end
    if alive then""")
    a = rep(a, """      if v.loop then
        local s = A.slots[v.name]
        sound_handle_set_volume(v.h, (v.o.volume or 1) * A.get(v.name, 'vol') * A.master)""",
            """      if v.loop and sound_handle_set_fx then
        local s = A.slots[v.name]
        sound_handle_set_volume(v.h, (v.o.volume or 1) * A.get(v.name, 'vol') * A.master)""")
    a = rep(a, """  if changed or not A._room_sent then
    sound_reverb(cur_room)""", """  if (changed or not A._room_sent) and sound_reverb then
    sound_reverb(cur_room)""")
    a = rep(a, "-- the picker's audition: a raw clip, no slot, in your head\n",
            """-- (Lich) the game hosted on the site goes off screen: silence, kept (its loops come back where they were)
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
""")
    a = rep(a, """  A.pending = keep
  refresh(dt)
  room_tick(dt)
end""", """  A.pending = keep
  refresh(dt)
  room_tick(dt)
  -- (Lich) stopped loops leave the list (a game of burns, beams and leaks made one each, and kept them all)
  local live = {}
  for _, L in ipairs(A.loops) do if not L.stopped then live[#live + 1] = L end end
  A.loops = live
end""")
    return a


if __name__ == '__main__':
    main()
