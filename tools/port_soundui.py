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
    # RETIRED 2026-10-11 (round 68g): port/audio.lua and port/soundui.lua are Lich's own since then (layers, undo, the
    # picker that only adds); running this would overwrite them with megablock's + the patches below. Kept as the
    # record of what Lich changed up to the fork; megablock's later changes come over by hand.
    import sys
    if '--force' not in sys.argv:
        raise SystemExit('retired: port/audio.lua and port/soundui.lua are Lich\'s own since round 68g (2026-10-11); '
                         'bring megablock changes over by hand (--force overwrites them)')
    commit =subprocess.run(['git', '-C', MB, 'log', '-1', '--format=%h', '--', 'mb/audio.lua', 'mb/soundui.lua'],
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
    spec = spec[spec.index('\nSPEC = {'):]
    spec = spec[:spec.index('\n}\n')]           # (the SPEC table only: CAVE below it names the same slots)
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
    # (Lich, 2026-10-11) loops named while playing too: megablock's loops are a room's hum, a TV; Lich's are the game's
    # actions (the lens cutting through the floor, the beam held, a snake burning, the sweep, a rock or snake held up),
    # and they went unseen in play ("a sound that's not showing up anywhere ... the lens laser going through the ground")
    s = rep(s, """    -- loops: shown while stopped, where they play from
    if paused then
      local loops = {}""", """    -- loops: where they play from; while stopped all of them, while playing those sounding now (Lich: its loops are
    -- the game's actions, the lens cutting through the floor, the beam, a burning snake, and went unseen in play)
    do
      local loops = {}""")
    s = rep(s, """        if p then
          local x, y = project(p, 1, false)
          if x then
            local txt = '~' .. L.name
            local w = tw(txt) + 4
            local rr = { x = round(x - w / 2), y = round(y), w = w, h = 11 }
            if fits(rr) then
              placed[#placed + 1] = rr
              local name = L.name
              label(txt, x, y, status_color(name), clickable and function() M.open_edit(name) end or nil, 0.9)
            end""", """        if p and (paused or L.h) then
          local x, y = project(p, 1, false)
          if x then
            local txt = '~' .. L.name
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
            end""")
    # (Lich, 2026-10-11) one file of a slot alone: his "how do I play that sound separately while testing and editing?"
    # A click on a file in the editor's PLAYS row makes it the only one the editor plays (PLAY, SPACE, every slider's
    # replay, RESET) until it is clicked again; the game itself still picks among all of them. And in the picker,
    # Shift + the second click adds a variant (as Shift+Enter, and as Shift+click on a red slot's suggestions).
    s = rep(s, "its files (X removes one; a red slot",
            "its files (X removes one; (Lich) a click on one: only it plays in the editor, every replay, until\n"
            "             clicked again; a red slot")
    s = rep(s, "Enter (or a second click) to use, Shift+Enter to add a variant,",
            "Enter (or a second click) to use, Shift+Enter (Lich: or Shift + the second click) to add a variant,")
    s = rep(s, "local function changed(name, room)\n",
            "-- (Lich) the editor's replays: the file he clicked alone, else the slot as the game plays it\n"
            "local function preview(name) return AU.preview(name, ui.solo_slot == name and ui.solo or nil) end\n"
            "local function changed(name, room)\n")
    s = rep(s, "  HUD.text(state .. (is_loop(name) and '  (A LOOP)' or ''), ",
            "  if ui.solo_slot == name and ui.solo then state = state .. '  ONLY FILE ' .. ui.solo end   -- (Lich)\n"
            "  HUD.text(state .. (is_loop(name) and '  (A LOOP)' or ''), ")
    s = rep(s, "AU.preview(name)", "preview(name)", count=3)
    s = rep(s, "AU.preview(ui.slot)", "preview(ui.slot)")
    s = rep(s, """      if x + tw(short) + 20 > 628 then HUD.text('+' .. (#files - i + 1), x, y, DIM); break end
      x = button('X', x, y - 2, function() remove_pick(name, i) end, ORANGE)
      HUD.text(short, x, y, GREEN)
      x = x + tw(short) + 8""", """      if x + tw(short) + 20 > 628 then   -- (Lich) another row, up to three (the settings start at 64), then +n
        if y >= 52 then HUD.text('+' .. (#files - i + 1), x, y, DIM); break end
        y, x = y + 11, 46
      end
      x = button('X', x, y - 2, function() remove_pick(name, i); if ui.solo_slot == name then ui.solo = nil end end, ORANGE)
      -- (Lich) a click on a file: only it plays in the editor until clicked again (highlighted while it is the one)
      local fi, fw = i, tw(short)
      local solo = ui.solo_slot == name and ui.solo == i
      local hot = ui.mx >= x - 2 and ui.mx < x + fw + 2 and ui.my >= y - 2 and ui.my < y + 8
      if hot or solo then HUD.rect(x - 2, y - 2, fw + 4, 10, solo and 'rgba(80,72,40,0.95)' or 'rgba(50,50,60,0.9)') end
      HUD.text(short, x, y, GREEN)
      hits[#hits + 1] = { id = 'file_' .. i, x = x - 2, y = y - 2, w = fw + 4, h = 10, act = function()
        if solo then ui.solo = nil else ui.solo_slot, ui.solo = name, fi end
        preview(name)
      end }
      x = x + fw + 8""")
    s = rep(s, "        if ui.sel == ri and ui.heard == ri then save_pick(name, r.rel, false) else listen(ri) end",
            "        if ui.sel == ri and ui.heard == ri then save_pick(name, r.rel, key_is_down('lshift') or key_is_down('rshift')) else listen(ri) end")
    # (Lich) auditions in the picker and of a red slot's suggestions: crushed as that slot (port/audio.lua A.audition)
    s = rep(s, "pcall(AU.audition, ROOT .. '/' .. r.rel, 0.5)", "pcall(AU.audition, ROOT .. '/' .. r.rel, 0.5, ui.slot)")
    s = rep(s, "pcall(AU.audition, ROOT .. '/' .. rel, 0.5)", "pcall(AU.audition, ROOT .. '/' .. rel, 0.5, name)")
    # TAB and the ESC panel also count a loop that ended a moment ago (the lens's cut lasts about a second)
    s = rep(s, """  for n in pairs(playing) do if not seen[n] then loops[#loops + 1] = n end end
""", """  for n in pairs(playing) do if not seen[n] then loops[#loops + 1] = n end end
  for n, t in pairs(AU.loop_end) do if not seen[n] and not playing[n] and now - t <= 1.5 then loops[#loops + 1] = n end end   -- (Lich)
""")
    s = rep(s, """  for L in pairs(AU.loop_set) do looping[L.name] = true end
  local names = M.all_slots()""", """  for L in pairs(AU.loop_set) do looping[L.name] = true end
  for n, t in pairs(AU.loop_end) do if now - t < 4 then recent[n] = true end end   -- (Lich: a loop that just ended)
  local names = M.all_slots()""")
    # the cave's EAR row (Lich: where you hear from, placed by port/game.lua): kept with the room's reverb
    s = rep(s, "    { key = 'lowcut', label = 'LOW CUT', lo = 0, hi = 1000, map = 'sq', q = 5, fmt = '%dHZ' },\n  },\n}",
            "    { key = 'lowcut', label = 'LOW CUT', lo = 0, hi = 1000, map = 'sq', q = 5, fmt = '%dHZ' },\n"
            "    { key = 'ear', label = 'EAR', lo = 0, hi = 1, map = 'lin', q = 0.01, fmt = '%d%% IN', mul = 100 },   -- (Lich)\n"
            "  },\n}")
    s = lich_layers_ui(lich_per_file_ui(s))
    open(os.path.join(GAME, 'port', 'soundui.lua'), 'w', encoding='utf-8', newline='\n').write(s)

    # ---------------------------------------------------------------- audio
    a = open(os.path.join(MB, 'mb', 'audio.lua'), encoding='utf-8').read()
    a = rep(a, "  mb/audio.lua -- sound slots, placed in 3D", stamp.format('audio.lua') + "  audio.lua -- sound slots, placed in 3D")
    a = rep(a, "  folder, written by the editor in mb/soundui.lua;", "  folder, written by the editor in port/soundui.lua;")
    a = lich_audio(a)
    open(os.path.join(GAME, 'port', 'audio.lua'), 'w', encoding='utf-8', newline='\n').write(a)
    print(f'ported megablock {commit}: port/soundui.lua ({len(names)} slots known), port/audio.lua')


def lich_per_file_ui(s):
    """(Lich, 2026-10-11) the editor's side of lich_per_file: while a file is clicked (PLAYS row), every slider, toggle
    and the curve are that file's own (shown as the slot's until it has its own; right-click = back to the slot's),
    RESET clears that file's own only, and the readout is that file's. A file with settings of its own reads NAME*."""
    s = rep(s, """function draw_edit()
  local name = ui.slot
  local s = AU.slots[name] or { files = {}, src = {} }
  local files, src = s.files or {}, s.src or {}
""", """function draw_edit()
  local name = ui.slot
  local s = AU.slots[name] or { files = {}, src = {} }
  local files, src = s.files or {}, s.src or {}
  -- (Lich) a file clicked: the sliders are that file's own (over the slot's); else the slot's
  local fi = ui.solo_slot == name and ui.solo or nil
  if fi and not files[fi] then ui.solo, fi = nil, nil end
  local function get(k) return AU.get(name, k, fi) end
  local function set(k, v) if fi then AU.set_file(name, fi, k, v) else AU.set(name, k, v) end end
  local function is_own(k) if fi then return AU.own_file(name, fi, k) end return s[k] ~= nil end
""")
    s = rep(s, "  if ui.solo_slot == name and ui.solo then state = state .. '  ONLY FILE ' .. ui.solo end   -- (Lich)\n",
            "  if fi then state = state .. '  FILE ' .. fi .. ': ITS OWN SETTINGS' end   -- (Lich)\n")
    s = rep(s, "    local v = AU.get(name, sp.key)\n    local own = s[sp.key] ~= nil\n",
            "    local v = get(sp.key)\n    local own = is_own(sp.key)\n")
    s = rep(s, """        if sp.key == 'pitch_lo' and nv > AU.get(name, 'pitch_hi') then AU.set(name, 'pitch_hi', nv) end
        if sp.key == 'pitch_hi' and nv < AU.get(name, 'pitch_lo') then AU.set(name, 'pitch_lo', nv) end
        if nv ~= v then AU.set(name, sp.key, nv); changed(name) end
""", """        if sp.key == 'pitch_lo' and nv > get('pitch_hi') then set('pitch_hi', nv) end
        if sp.key == 'pitch_hi' and nv < get('pitch_lo') then set('pitch_lo', nv) end
        if nv ~= v then set(sp.key, nv); changed(name) end
""")
    s = rep(s, "function() AU.set(name, sp.key, nil); ui.dirty = true; flush_saves(); changed(name) end)",
            "function() set(sp.key, nil); ui.dirty = true; flush_saves(); changed(name) end)", count=2)
    s = rep(s, "    local on = AU.get(name, key)\n", "    local on = get(key)\n")
    s = rep(s, "      AU.set(name, key, not on); ui.dirty = true;", "      set(key, not on); ui.dirty = true;")
    s = rep(s, "  local curve = AU.get(name, 'curve')\n", "  local curve = get('curve')\n")
    s = rep(s, "    AU.set(name, 'curve', AU.CURVES[i % #AU.CURVES + 1]);", "    set('curve', AU.CURVES[i % #AU.CURVES + 1]);")
    s = rep(s, "    if sp.key == 'reverb' then v, own = send_of(name) else v = AU.get(name, sp.key); own = s[sp.key] ~= nil end\n",
            "    if sp.key == 'reverb' then v, own = send_of(name, fi) else v = get(sp.key); own = is_own(sp.key) end\n")
    s = rep(s, "      function(nv) if nv ~= v or not own then AU.set(name, sp.key, nv); changed(name) end end,\n",
            "      function(nv) if nv ~= v or not own then set(sp.key, nv); changed(name) end end,\n")
    s = rep(s, """local function send_of(name)
  local s = AU.slots[name]
  if s and s.reverb then return s.reverb, true end
""", """local function send_of(name, fi)
  if fi and AU.own_file(name, fi, 'reverb') then return AU.get(name, 'reverb', fi), true end   -- (Lich) the file's own
  local s = AU.slots[name]
  if s and s.reverb then return s.reverb, not fi end
""")
    s = rep(s, "  local fx, info = AU.spatial(name, lp and lp.pos, lp, nil, nil, _fx, _inf)",
            "  local fx, info = AU.spatial(name, lp and lp.pos, lp and { reverb = lp.reverb, fi = fi }, nil, nil, _fx, _inf)")
    s = rep(s, "  HUD.text('DRAG A SLIDER (RIGHT-CLICK = DEFAULT). EVERY CHANGE REPLAYS IT FROM WHERE IT LAST PLAYED. SAVES ITSELF.', 12, 342, DIM)",
            "  if fi then HUD.text(\"FILE \" .. fi .. \" CLICKED: THE SLIDERS ARE ITS OWN (RIGHT-CLICK = THE WHOLE SOUND'S). CLICK IT AGAIN: ALL.\", 12, 342, YELLOW)\n"
            "  else HUD.text('DRAG A SLIDER (RIGHT-CLICK = DEFAULT). EVERY CHANGE REPLAYS IT FROM WHERE IT LAST PLAYED. SAVES ITSELF.', 12, 342, DIM) end")
    # the PLAYS row: NAME* = a file with settings of its own
    s = rep(s, "      local fi, fw = i, tw(short)\n",
            "      local mine = s.per and s.per[files[i]] and '*' or ''     -- (* = settings of its own)\n"
            "      local fk, fw = i, tw(short .. mine)\n")
    s = rep(s, "      HUD.text(short, x, y, GREEN)\n      hits[#hits + 1] = { id = 'file_' .. i,",
            "      HUD.text(short .. mine, x, y, GREEN)\n      hits[#hits + 1] = { id = 'file_' .. i,")
    s = rep(s, "        if solo then ui.solo = nil else ui.solo_slot, ui.solo = name, fi end",
            "        if solo then ui.solo = nil else ui.solo_slot, ui.solo = name, fk end")
    # RESET with a file clicked clears only its own; without, the slot and every file's own
    s = rep(s, """  if not s then return end
  for k in pairs(AU.DEFAULTS) do if k ~= 'vol' then s[k] = nil end end
  s.reverb = nil
""", """  if not s then return end
  if ui.solo_slot == name and ui.solo and s.files and s.files[ui.solo] then   -- (Lich) a file clicked: its own only
    if s.per then s.per[s.files[ui.solo]] = nil; if not next(s.per) then s.per = nil end end
    ui.dirty = true; flush_saves(); preview(name); return
  end
  for k in pairs(AU.DEFAULTS) do if k ~= 'vol' then s[k] = nil end end
  s.reverb = nil
  s.per = nil      -- (Lich) and every file's own
""")
    # a file's own settings go with it
    s = rep(s, "  table.remove(s.files, i)\n",
            "  if s.per and s.files[i] then s.per[s.files[i]] = nil; if not next(s.per) then s.per = nil end end   -- (Lich)\n"
            "  table.remove(s.files, i)\n")
    s = rep(s, "    s.files = { out }; s.src = { rel }\n",
            "    s.files = { out }; s.src = { rel }; s.per = nil     -- (Lich: the old files' own settings go with them)\n")
    return s


def lich_layers(a):
    """(Lich, 2026-10-11) a slot's files all at once: his "For lens fire I have two sounds but only one plays at a time,
    I believe because one is looping and the other shouldn't loop". layer (the slot's) = every file plays on every play,
    each with its own settings (its own delay too); once (a file's own) = in a loop, that file plays once as the loop
    starts instead of looping. A layered loop keeps its first looping voice as L.h and the others in L.extra."""
    a = rep(a, "sound_ix = {} }", "sound_ix = {}, loop_slot = {}, preview_hs = {} }")
    a = rep(a, "  vol = 1, pitch_lo = 1, pitch_hi = 1, delay = 0, bits = 8, sr = 3, mute = false,\n",
            "  -- (Lich) layer = every file at once, each with its own settings (not one at random); once = a file's own: in a\n"
            "  -- loop, it plays once as the loop starts instead of looping\n"
            "  vol = 1, pitch_lo = 1, pitch_hi = 1, delay = 0, bits = 8, sr = 3, mute = false, layer = false, once = false,\n")
    # a play: one file at random, or (layered) every file, each its own play
    a = rep(a, "  if not o.fi then local _, fi = pick(name); o.fi = fi end   -- (Lich) its file, chosen now\n",
            "  local layered = not o.fi and A.get(name, 'layer')\n"
            "  if not o.fi and not layered then local _, fi = pick(name); o.fi = fi end   -- (Lich) its file, chosen now\n")
    a = rep(a, """  local w = wait_for(name, o)
  if w > 0 then
    A.pending[#A.pending + 1] = { name = name, o = o, at = A.now + w }
    return nil
  end
  return voice(name, o)
end""", """  if layered then      -- (Lich) every file at once, each its own play (its own delay and settings)
    local s, h1 = A.slots[name], nil
    for fi = 1, (s and s.files and #s.files or 0) do
      local oc = {}
      for k, x in pairs(o) do oc[k] = x end
      oc.fi, oc.pos = fi, o.pos and o.pos:clone() or nil
      local w = wait_for(name, oc)
      if w > 0 then A.pending[#A.pending + 1] = { name = name, o = oc, at = A.now + w }
      else local h = voice(name, oc); h1 = h1 or h end
    end
    return h1
  end
  local w = wait_for(name, o)
  if w > 0 then
    A.pending[#A.pending + 1] = { name = name, o = o, at = A.now + w }
    return nil
  end
  return voice(name, o)
end""")
    # the editor's preview of a layered slot: every file (a file clicked: that one alone)
    a = rep(a, "  if A.preview_h then sound_handle_stop(A.preview_h); A.preview_h = nil end\n  A.pending_rt = {}\n",
            "  if A.preview_h then sound_handle_stop(A.preview_h); A.preview_h = nil end\n"
            "  for _, h in ipairs(A.preview_hs) do sound_handle_stop(h) end\n"
            "  A.preview_hs = {}     -- (Lich) a layered preview's voices\n"
            "  A.pending_rt = {}\n")
    a = rep(a, "  local o = { pos = lp.pos and lp.pos:clone() or nil, volume = lp.volume, pitch = lp.pitch, reverb = lp.reverb, fi = only }\n",
            """  local o = { pos = lp.pos and lp.pos:clone() or nil, volume = lp.volume, pitch = lp.pitch, reverb = lp.reverb, fi = only }
  local s = A.slots[name]
  if not only and A.get(name, 'layer') and s and s.files and #s.files > 1 then   -- (Lich) layered: every file
    local any = false
    for fi = 1, #s.files do
      local oc = { pos = o.pos and o.pos:clone() or nil, volume = o.volume, pitch = o.pitch, reverb = o.reverb, fi = fi }
      local w = max(0, A.get(name, 'delay', fi))
      if w > 0 then A.pending_rt[#A.pending_rt + 1] = { name = name, o = oc, at = A.rt + w }; any = true
      else local h = voice(name, oc); if h then A.preview_hs[#A.preview_hs + 1] = h; any = true end end
    end
    return any
  end
""")
    a = rep(a, "    if A.rt >= p.at then A.preview_h = voice(p.name, p.o) else keep[#keep + 1] = p end",
            "    if A.rt >= p.at then\n"
            "      local h = voice(p.name, p.o); A.preview_h = A.preview_h or h\n"
            "      if h then A.preview_hs[#A.preview_hs + 1] = h end      -- (Lich: a layered preview's later voices)\n"
            "    else keep[#keep + 1] = p end")
    # loops: all their voices stop together
    a = rep(a, "function A.loop(name, o)\n",
            "-- (Lich) a loop's voices stop: its main one and a layered loop's others\n"
            "local function loop_off(L)\n"
            "  if L.h then sound_handle_stop(L.h); L.h = nil end\n"
            "  if L.extra then for _, h in ipairs(L.extra) do sound_handle_stop(h) end; L.extra = nil end\n"
            "end\n"
            "function A.loop(name, o)\n")
    a = rep(a, "A.loop_set[L] = nil; if L.h then sound_handle_stop(L.h); L.h = nil end end", "A.loop_set[L] = nil; loop_off(L) end")
    a = rep(a, "  A.loop_set[L] = true\n  A.seen[name] = true\n",
            "  A.loop_set[L] = true\n  A.seen[name] = true\n  A.loop_slot[name] = true     -- (Lich: the editor offers PLAYS ONCE for its files)\n")
    a = rep(a, "function A.start_loop(L)\n  if L.h then sound_handle_stop(L.h); L.h = nil end\n", "function A.start_loop(L)\n  loop_off(L)\n")
    a = rep(a, """  local h = voice(L.name, L.opts, L)
  if h then sound_handle_set_looping(h, true); L.h = h end
end""", """  -- (Lich) layered: every file, each its own voice and settings; a file marked ONCE plays once (a plain one-shot,
  -- let finish), the others loop
  local s = A.slots[L.name]
  if A.get(L.name, 'layer') and s and s.files and #s.files > 1 then
    for fi = 1, #s.files do
      local once = A.get(L.name, 'once', fi)
      local oc = setmetatable({ fi = fi }, { __index = L.opts })   -- (its position and volume follow the loop's)
      local h = voice(L.name, oc, (not once) and L or nil)
      if h and not once then
        sound_handle_set_looping(h, true)
        if L.h then L.extra = L.extra or {}; L.extra[#L.extra + 1] = h else L.h = h end
      end
    end
    return
  end
  L.opts.fi = nil      -- (Lich) a loop (re)started picks its file again (the one it had may be gone)
  local h = voice(L.name, L.opts, L)
  if h and A.get(L.name, 'once', L.opts.fi) then return end    -- (Lich) a ONCE file picked: it plays once
  if h then sound_handle_set_looping(h, true); L.h = h end
end""")
    a = rep(a, "    if on then if L.h then sound_handle_stop(L.h); L.h = nil end\n", "    if on then loop_off(L)\n")
    a = rep(a, "        if s and s.mute then sound_handle_stop(v.h); v.loop.h = nil end", "        if s and s.mute then loop_off(v.loop) end")
    return a


def lich_layers_ui(s):
    """(Lich) the editor's switches for lich_layers, on the SOUND line: ONE FILE AT RANDOM / ALL FILES AT ONCE (the
    slot's, with two files or more), and with a file clicked in a loop's slot, FILE n LOOPS / PLAYS ONCE (that file's)."""
    s = rep(s, "  HUD.text('SOUND', lx, sp_y, YELLOW)\n", """  HUD.text('SOUND', lx, sp_y, YELLOW)
  -- (Lich) the whole sound: one file at random each play, or every file at once; a loop's file: loops or plays once
  if #files > 1 then
    local lay = AU.get(name, 'layer')
    local bx2 = button(lay and 'ALL FILES AT ONCE' or 'ONE FILE AT RANDOM', lx + 40, sp_y - 2, function()
      AU.set(name, 'layer', (not lay) or nil); ui.dirty = true; flush_saves(); changed(name)
    end, lay and GREEN or GREY, lay)
    if fi and AU.loop_slot[name] then
      local once = AU.get(name, 'once', fi)
      button('FILE ' .. fi .. (once and ' PLAYS ONCE' or ' LOOPS'), bx2, sp_y - 2, function()
        AU.set_file(name, fi, 'once', (not once) or nil); ui.dirty = true; flush_saves(); changed(name)
      end, once and YELLOW or GREY, once)
    end
  end
""")
    return s


def lich_per_file(a):
    """(Lich, 2026-10-11) each FILE of a slot can have its own settings: his "it doesn't look like I can change the
    settings for each individual sound in an event, only for both at the same time". A slot's files stay variants (one
    per play, at random); s.per[file path] = that file's own values, over the slot's, over DEFAULTS. Every play picks
    its file first (o.fi), so its own delay, pitch, volume, crush and 3D settings all apply, every frame. The editor
    (soundui) edits a file's own while that file is clicked, and plays that file alone."""
    a = rep(a, "quiet = false, loop_end = {} }", "quiet = false, loop_end = {}, sound_ix = {} }")
    a = rep(a, """function A.get(name, key)
  local s = A.slots[name]
  local v = s and s[key]
  if v == nil then v = A.DEFAULTS[key] end
  return v
end
""", """-- (Lich) fi = one of the slot's files (its index): that file's own setting first (s.per[its path], set in the editor
-- while that file is clicked), then the slot's, then the default
function A.get(name, key, fi)
  local s = A.slots[name]
  local v
  if fi and s and s.per and s.files then local p = s.per[s.files[fi] or false]; v = p and p[key] end
  if v == nil then v = s and s[key] end
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
""")
    # the loaded sounds remember which file each is (one that fails to load is skipped)
    a = rep(a, """  local list = {}
  if s and s.files then
    for _, f in ipairs(s.files) do
      local ok, snd = pcall(sound_load, f)      -- a pick whose file went missing stays silent instead of stopping the game
      if ok and snd then list[#list + 1] = snd end
    end
  end
  A.sounds[name] = list
""", """  local list, ix = {}, {}
  if s and s.files then
    for fi, f in ipairs(s.files) do
      local ok, snd = pcall(sound_load, f)      -- a pick whose file went missing stays silent instead of stopping the game
      if ok and snd then list[#list + 1] = snd; ix[#list] = fi end
    end
  end
  A.sounds[name] = list
  A.sound_ix[name] = ix     -- (Lich) list[k] is the slot's file ix[k]
""")
    a = rep(a, """local function pick(name)
  local v = A.sounds[name]
  if not v or #v == 0 then return nil end
  local i = 1 + floor(rnd()*#v)
  if #v > 1 and v[i] == A.last[name] then i = i % #v + 1 end
  A.last[name] = v[i]
  return v[i]
end""", """local function pick(name, only)     -- (Lich) -> the sound and which of the slot's files it is; only = that file
  local v = A.sounds[name]
  if not v or #v == 0 then return nil end
  local ix = A.sound_ix[name] or {}
  if only then for k = 1, #v do if (ix[k] or k) == only then return v[k], only end end end
  local i = 1 + floor(rnd()*#v)
  if #v > 1 and v[i] == A.last[name] then i = i % #v + 1 end
  A.last[name] = v[i]
  return v[i], ix[i] or i
end""")
    a = rep(a, """  local snd = pick(name)
  if not snd then return nil end
  local lo, hi = A.get(name, 'pitch_lo'), A.get(name, 'pitch_hi')""", """  local snd, fi = pick(name, o.fi)
  if not snd then return nil end
  o.fi = fi       -- (Lich) the file this voice plays: its own settings, now and every frame after (refresh)
  local lo, hi = A.get(name, 'pitch_lo', fi), A.get(name, 'pitch_hi', fi)""")
    a = rep(a, """  local del = A.get(name, 'delay')
  fx.bits, fx.sr_div, fx.start = A.get(name, 'bits'), A.get(name, 'sr'), del < 0 and -del or 0
  local vol = (o.volume or 1) * A.get(name, 'vol') * A.master""", """  local del = A.get(name, 'delay', fi)
  fx.bits, fx.sr_div, fx.start = A.get(name, 'bits', fi), A.get(name, 'sr', fi), del < 0 and -del or 0
  local vol = (o.volume or 1) * A.get(name, 'vol', fi) * A.master""")
    a = rep(a, """  local get = function(k) return A.get(name, k) end
  local s = A.slots[name]
  local send = (s and s.reverb) or (o and o.reverb) or SEND""", """  local fi = o and o.fi      -- (Lich) the file playing: its own settings
  local get = function(k) return A.get(name, k, fi) end
  local send = A.get(name, 'reverb', fi) or (o and o.reverb) or SEND""")
    # the wait (a play's and the editor's preview): the chosen file's own delay and travel
    a = rep(a, "  local w = (o.delay or 0) + max(0, A.get(name, 'delay'))\n", "  local w = (o.delay or 0) + max(0, A.get(name, 'delay', o.fi))\n")
    a = rep(a, "  local w = max(0, A.get(name, 'delay'))\n", "  local w = max(0, A.get(name, 'delay', o.fi))\n")
    a = rep(a, "  local tr = A.get(name, 'travel')\n", "  local tr = A.get(name, 'travel', o.fi)\n", count=2)
    a = rep(a, "and A.get(name, 'spatial') and A.on3d then", "and A.get(name, 'spatial', o.fi) and A.on3d then", count=2)
    # a play picks its file now (so that file's own delay counts); the editor's preview names it
    a = rep(a, "  o.pos = v3(o.pos)\n  A.note(name, o.pos, o.delay)\n",
            "  o.pos = v3(o.pos)\n  if not o.fi then local _, fi = pick(name); o.fi = fi end   -- (Lich) its file, chosen now\n"
            "  A.note(name, o.pos, o.delay)\n")
    a = rep(a, "function A.preview(name)\n", "function A.preview(name, only)     -- (Lich: only = that file of the slot alone)\n")
    a = rep(a, "  local o = { pos = lp.pos and lp.pos:clone() or nil, volume = lp.volume, pitch = lp.pitch, reverb = lp.reverb }\n",
            "  local o = { pos = lp.pos and lp.pos:clone() or nil, volume = lp.volume, pitch = lp.pitch, reverb = lp.reverb, fi = only }\n")
    # every frame: the live voice's own file
    a = rep(a, "    fx.width = (pos and A.get(v.name, 'spatial')) and A.get(v.name, 'width') or 1\n",
            "    fx.width = (pos and A.get(v.name, 'spatial', v.o.fi)) and A.get(v.name, 'width', v.o.fi) or 1\n")
    a = rep(a, "A.get(v.name, 'vol') * A.master", "A.get(v.name, 'vol', v.o.fi) * A.master", count=2)
    return a


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
            "  last_t = {}, quiet = false, loop_end = {} }   -- (Lich: a call's gap; the site's off-screen silence; when\n"
            "  -- each loop last stopped, for the TAB list)")
    a = rep(a, "  spatial = true, curve = 'inverse', near = 1.0, far = 60, rolloff = 1.0, air = 1.0, occlusion = 1.0,",
            "  -- (Lich: the ear hangs on the room camera's line of sight, `ear` of the way in (A.ROOM_DEFAULTS, port/game.lua):\n"
            "  -- ~6.5 m from the egg, ~4 m from him, ~20 m from the far wall. near = the fight round the egg at full\n"
            "  -- loudness, the far wall ~10 dB down; the air a little duller with distance than a head's)\n"
            "  spatial = true, curve = 'inverse', near = 6.0, far = 60, rolloff = 1.0, air = 0.5, occlusion = 1.0,")
    a = re.sub(r"A\.ROOM_DEFAULTS = \{\n.*?\n\}\n",
               "A.ROOM_DEFAULTS = {\n"
               "  -- (Lich) one cave, stone, 31 m across under a high dome: a long tail (size), the highs dying a little sooner\n"
               "  -- than a bare hall's (rough rock, damp), the walls answering 13-20 m off (predelay 40 ms), nothing under\n"
               "  -- 140 Hz sent in (the cave loop's drone and the rock slams would turn the tail to mud).\n"
               "  -- ear = where you hear from: 0 = the room camera, 1 = what it looks at (port/game.lua places the listener)\n"
               "  cave = { size = 0.85, damp = 0.4, predelay = 0.04, gain = 0.80, width = 1, lowcut = 140, ear = 0.5 },\n"
               "}\n", a, count=1, flags=re.S)
    a = rep(a, "  local i = math.random(1, #v)", "  local i = 1 + floor(rnd()*#v)")
    # (Lich, his ruling 2026-10-11: "By default apply 8 bits and 3x crush to every sound") -- a slot's own BITS / SR CRUSH
    # still win; right-click on those sliders comes back here
    a = rep(a, "  vol = 1, pitch_lo = 1, pitch_hi = 1, delay = 0, bits = 16, sr = 1, mute = false,\n",
            "  -- (Lich, his ruling 2026-10-11: every sound 8 bits and 3x sample-rate crush unless its slot says otherwise)\n"
            "  vol = 1, pitch_lo = 1, pitch_hi = 1, delay = 0, bits = 8, sr = 3, mute = false,\n")
    # the picker's auditions crushed as the slot being picked for will be (else he picks by a sound the game never plays)
    a = rep(a, "function A.audition(path, volume)\n", "function A.audition(path, volume, slot)     -- (Lich: slot = whose bits / crush)\n")
    a = rep(a, "  local h = sound_play_handle(s, volume or 0.5, 1)\n",
            "  local h = sound_play_handle(s, volume or 0.5, 1, slot and A.get(slot, 'bits') or A.DEFAULTS.bits,\n"
            "    slot and A.get(slot, 'sr') or A.DEFAULTS.sr)\n")
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
  -- (Lich: loop_end = when it stopped, so TAB still lists a loop that ended a moment ago)
  function L.stop() L.stopped = true; A.loop_end[name] = A.now; A.loop_set[L] = nil; if L.h then sound_handle_stop(L.h); L.h = nil end end
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
    return lich_layers(lich_per_file(a))


if __name__ == '__main__':
    main()
