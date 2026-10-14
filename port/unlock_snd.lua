--[[
  unlock_snd.lua -- the sounds of the site's unlock (2026-10-14, "Lich Survivors 15"). Owner: "the sounds are pretty
  much all correct, we just need to settle sounds for the actual unlocking effects, how can we test those they're
  different executables?"

  The unlock (a327ex-site/renderer/unlock_fx.lua: the letters pouring out of the opened egg, each post's lock lifted,
  held and bursting as glass, a sweep of warped air along its row) is the site's, but its sounds are slots of THIS
  game's sound system, so they are picked and tuned in the game's own editor (TAB) and saved in sound_picks.lua with
  the rest:
    unlock_pour    the letters leave the egg (once)
    unlock_land    a letter reaches its place (every 4th of the 673 letters the posts held on 2026-10-15, kept as a
                   pace: more text, a smaller share; the site's UNLOCK_FX.land_every / land_pace, L in the test)
    unlock_lift    a post's lock is lifted (each post)
    unlock_burst   its glass bursts (each post; pitched up a pentatonic octave across the posts, as a gacha's run)
    unlock_sweep   the warped air sweeps its row (each post, with the burst)
    unlock_final   the last post is open (once, with its burst)
  On the site the unlock calls game_unlock_sound(event, i, n) through the host at the real moments (the game is off
  screen then: these slots play through its mute, unplaced). Here, run on its own, the game plays the same events
  itself when the egg opens, on the site's schedule (US.SITE mirrors unlock_fx.lua's constants for 16 posts), so they
  can be tuned with TAB while watching the egg (run-egg.bat starts there).
]]
local AU = require('port.audio')
local US = {}

US.SLOTS = { 'unlock_pour', 'unlock_land', 'unlock_lift', 'unlock_burst', 'unlock_sweep', 'unlock_final' }
-- each starts red, with suggestions to audition in the editor (the sound sets round 73 tried, the game's own glass,
-- gravity and wind): AU.NEW seeds it while the picks have no entry; AU.LOUD lets it sound through the game's mute
local SEEDS = {
  unlock_pour = { unsure = true, candidates = { 'Gamemaster Audio - Pro Sound Collection/Magic_Spells/magic_shine_light_spell_05.wav', 'SFX_Collection/WAV/Coins & Chest/Chest_Gems_Opening_02.wav', 'Gamemaster Audio - Pro Sound Collection/Magic_Spells/chimes_magical_bells_02.wav', 'Ultimate SFX Bundle (2020)/UI & Item Sounds/Prize wheel spin/Prize wheel spin 3.wav', 'SFX_Collection/WAV/Interface Musical Sounds/Magical_MagicDiscovery_01.wav', 'Gamemaster Audio - Pro Sound Collection/Magic_Spells/magic_pop_open_01.wav' } },
  -- (2026-10-15, owner: "I need an event that plays for every letter, or every other letter as it connects to its
  -- final position so I can attach sounds to that.") short ones: a key, a sparkle, a tinkle, a tick
  unlock_land = { unsure = true, candidates = { 'Gamemaster Audio - Pro Sound Collection/Miscellaneous/Typing/typing_keystroke_single_soft_01.wav', 'Gamemaster Audio - Pro Sound Collection/Miscellaneous/Typing/typing_keystroke_single_hard_03.wav', 'Gamemaster Audio - Pro Sound Collection/Collectibles_Items_Powerup/collect_item_sparkle_pop_03.wav', 'Gamemaster Audio - Pro Sound Collection/Collectibles_Items_Powerup/chime_tinkle_wood_bell_positive_02.wav', 'Gamemaster Audio - Pro Sound Collection/Miscellaneous/Clock/clock_tick_02.wav', 'Gamemaster Audio - Pro Sound Collection/Collectibles_Items_Powerup/points_ticker_bonus_score_reward_single_01.wav' } },
  unlock_lift = { unsure = true, candidates = { 'Pixel Magic Sound Effects Pack/PM_ELEM_Dark06_Gravity_P1_Cast.wav', 'Pixel Magic Sound Effects Pack/PM_SPELL_Cast14_Gravity_Ball.wav', 'Gamemaster Audio - Pro Sound Collection/Magic_Spells/casting_charge_whoosh_buildup3.wav', 'Gamemaster Audio - Pro Sound Collection/Magic_Spells/casting_charge_whoosh_buildup6.wav', 'Gamemaster Audio - Pro Sound Collection/Magic_Spells/magic_shinny_high_tone_05.wav' } },
  unlock_burst = { unsure = true, candidates = { 'Universal Sound FX/GLASS/GLASS_Rattle_Many_Fragments_01_stereo.wav', 'Gamemaster Audio - Pro Sound Collection/Magic_Spells/ice_spell_impact_shatter_01.wav', 'Gamemaster Audio - Pro Sound Collection/Impacts_Smashable/glass_smashable_small_break_01.wav', 'Gamemaster Audio - Pro Sound Collection/Collectibles_Items_Powerup/collect_item_sparkle_pop_08.wav', 'Gamemaster Audio - Pro Sound Collection/Collectibles_Items_Powerup/coin_bag_ring_gemstone_item_01.wav', 'Gamemaster Audio - Pro Sound Collection/Collectibles_Items_Powerup/chime_bell_positive_ring_01.wav' } },
  unlock_sweep = { unsure = true, candidates = { 'RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Wind Magic/RPG3_WindMagicMisc_LowGust01.wav', 'Pixel Magic Sound Effects Pack/PM_ELEM_Wind01_Gust.wav', 'RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Wind Magic/RPG3_WindMagicMisc_Dark01.wav', 'Gamemaster Audio - Pro Sound Collection/Magic_Spells/nature_spell_vines_whoosh_01.wav' } },
  unlock_final = { unsure = true, candidates = { 'SFX_Collection/WAV/Interface Musical Sounds/OrchestralCasual_Accomplishment_01.wav', 'Gamemaster Audio - Pro Sound Collection/Collectibles_Items_Powerup/collect_item_jingle_04.wav', 'SFX_Collection/WAV/Interface Musical Sounds/HarpSounds_HarpPoints_02.wav', 'Ultimate SFX Bundle (2020)/UI & Item Sounds/Win sound/Win sound 5.wav', 'SFX_Collection/WAV/Interface Musical Sounds/OrchestralFantasy_FantasyWin_01.wav' } },
}
local function copy(t) if type(t) ~= 'table' then return t end; local c = {}; for k, v in pairs(t) do c[k] = copy(v) end; return c end
for name, s in pairs(SEEDS) do
  AU.NEW[name] = s
  AU.LOUD[name] = true
  if AU.slots and not AU.slots[name] then AU.slots[name] = copy(s) end   -- (picks already loaded: seeded now)
end
local PENTA = { 0, 2, 4, 7, 9, 12 }

-- event: 'pour' | 'land' | 'lift' | 'burst' | 'sweep' | 'final'; i of n: the post (land: the letter's post; lift, burst, sweep)
function US.play(event, i, n)
  local o = {}
  if event == 'burst' and i and n then
    local d = PENTA[math.min(#PENTA, math.floor((i - 1)*#PENTA/math.max(1, n)) + 1)]
    o.pitch = 2^(d/12)
  end
  return AU.play('unlock_' .. tostring(event), o)
end

-- The site's schedule (a327ex-site/renderer/unlock_fx.lua, the accepted look of 2026-10-14): rows 0.2 s apart, a
-- row's letters leaving over 0.35 s and flying 1.0 s (cubic out), so a row is real 1.35 s after its turn; its lock
-- held 0.12 s, lifted 0.46 s (rise, hold, swell), then the burst and the sweep; the final with the last burst.
-- The letters' landings: ~42 a row (673 over the 16 measured 2026-10-15), each at its row's turn + a random part of the
-- spread + the flight, every `land_every`th of them sounding (the site's UNLOCK_FX.land_every).
US.SITE = { rows = 16, row_dt = 0.2, spread = 0.35, flight = 1.0, hold = 0.12, lift = 0.46, final = 0,
            letters = 42, land_every = 4 }
-- a fixed 0..1 for letter j of row i (never the game's rngs)
local function frac(i, j) local x = math.sin(i*12.9898 + j*78.233)*43758.5453; return x - math.floor(x) end
local sim = nil
function US.start(rows)
  local S = US.SITE
  local n = rows or S.rows
  local ev = { { t = 0, e = 'pour' } }
  local last = 0
  for i = 1, n do
    for j = 1, S.letters do ev[#ev + 1] = { t = (i - 1)*S.row_dt + frac(i, j)*S.spread + S.flight, e = 'land', i = i } end
    local lift = (i - 1)*S.row_dt + S.spread + S.flight + S.hold
    ev[#ev + 1] = { t = lift, e = 'lift', i = i }
    ev[#ev + 1] = { t = lift + S.lift, e = 'burst', i = i }
    ev[#ev + 1] = { t = lift + S.lift, e = 'sweep', i = i }
    last = lift + S.lift
  end
  ev[#ev + 1] = { t = last + S.final, e = 'final' }
  table.sort(ev, function(a, b) return a.t < b.t end)
  sim = { t = 0, k = 1, ev = ev, n = n, landed = 0 }
end
function US.tick(dt)
  if not sim then return end
  sim.t = sim.t + dt
  while sim.ev[sim.k] and sim.ev[sim.k].t <= sim.t do
    local e = sim.ev[sim.k]
    if e.e ~= 'land' then US.play(e.e, e.i, sim.n)
    else
      sim.landed = sim.landed + 1
      if (sim.landed - 1) % US.SITE.land_every == 0 then US.play(e.e, e.i, sim.n) end
    end
    sim.k = sim.k + 1
  end
  if not sim.ev[sim.k] then sim = nil end
end

return US
