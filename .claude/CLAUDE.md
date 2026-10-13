# lich-survivors

Guidelines for Claude Code instances working in this project.

**Read `RECORD.md` first** (purpose, owner's settled decisions, rounds, pending choices).

**The Anchor port is done (2026-09-30)**: `main.lua` + `boot.lua` + `port/*.lua` run the whole
game, bit-exact with the three.js build (`ANCHOR_PORT.md` "Status": how, what was checked, the
engine additions, the known differences). Any change to the game logic must keep the two builds
identical until he decides the web build is retired: change both, then compare full-state
digests (`tools/port_digest.js` via shoot.mjs evals, `tools/port_digest.lua` via anchor drive
eval, `tools/port_digest_cmp.py`). Rules that keep it exact: math.* is the engine's js_* (boot.lua),
Math.hypot is `js_hypot`, float32 stores go through `js_fround`, JS `a += b - c` is `a + (b - c)`,
never `x and nil or y`, random draws in the JS's evaluation order. Drive it with
`ANCHOR_ENGINE_BIN=<Anchor>/engine/engine/build/anchor.exe` set if another session holds the default.

**Round 40 (2026-10-02)** lives in the Anchor build only: the game starts in the final room's tunnel
(its own camera and grid) with every object in an inventory; removing one goes through the model
viewer's question. `LICH_ROOM=1` in the environment starts in the room exactly as before (keep that
path identical: `tools/digest_run.lua` runs with it). The walk of round 39 is set aside in
`archive/the-walk/` (tag `walk-round39`). Round 50's waves and bouts (snakes.lua `opts.varied`,
powers.lua `ctx.varied`, the group versions in beam/lift/rock/lens/fire) are on only without
LICH_ROOM; with it, the old respawn timers and fair rotation run exactly as before.

**Sounds (2026-10-10, RECORD.md round 67)**: every sound is a SLOT (`AU.play(name, {pos, volume, gap})`, `AU.loop`)
in port/audio.lua + port/soundui.lua, LICH'S OWN since round 68g (2026-10-11): forked from megablock's
mb/audio.lua + mb/soundui.lua (012a1f1); `tools/port_soundui.py` is retired (it records the changes up to the fork);
bring megablock's later changes over by hand. Since 2026-10-12 the flow runs the other way too: megablock's
`tools/port_lich_sound.py` (megablock 3b34d95) takes Lich's port/audio.lua + port/soundui.lua as UPSTREAM and reapplies
megablock's differences with asserted replacements, so renaming code it anchors on here makes its sync fail loudly
(tell the megablock session, or keep the anchors). A slot's files sit in LAYERS (each play = every layer, one of its files
at random; settings file -> layer -> slot -> DEFAULTS). His picks: `sound_picks.lua` (the in-game editor writes it:
TAB / ESC, not on the site); mine came from `tools/sfx_spec.py` -> `tools/sfx_bake.py` (his edits win). Red =
`unsure` on purpose. Sound code never draws from the game's rngs. Round 68 (2026-10-11): the ear is not the camera but
at his head, turned as the camera (port/game.lua `ear_of`; the cave's EAR row = sound_rooms.lua `head`, 68j); each slot's cave
levers (reverb, width, rolloff) live in tools/sfx_spec.py `CAVE`. ⚠ An agent instance reads AND WRITES the real
`sound_picks.lua` / `sound_rooms.lua` (he edits them in his running game at the same time): a probe that drives the
editor snapshots them with file_read_string first and writes them back at the end (scratch/s14/solo_probe.lua), and
clicks by `SU.hit_by_id`, never by sweeping the mouse (that hit the X buttons once).

**three.js first (owner, 2026-09-27)**, like Brutal Behavior: the game lives in `web/`
(`index.html` + `src/*.js`, three.js 0.170 from jsdelivr, local modules import each other only
as `game/<file>.js`), reusing the Sun Court renderer (`web/src/render.js`, from
`retro-shooter/final/src`; recipe in `retro-shooter/STYLE.md`). Run it only headlessly:
`node tools/shoot.mjs web <script.json> scratch/<dir> --size 1280x720` (never a visible
browser, never the browser pane). A round's page is `node tools/bundle.mjs web
rounds/<nn>/index.html`; delivered round folders are never edited again. The Anchor scaffold
below is for the port once the game is settled.

An Anchor 3 game, scaffolded by `anchor new`.

## Read first

`Anchor/engine/docs/SURFACE.md` — how a game is run, driven, recorded and
reloaded, on one page. Then `docs/FRAMEWORK_API_QUICK.md` and
`docs/ENGINE_API_QUICK.md` for signatures, and
`reference_anchor_gotchas` territory before any draw or input code. Look
functions up; never guess a signature.

## Running it

Never run the game yourself — `run.bat` and feel are the owner's. Run it as
an agent instance instead (hidden window, externally paced, recorded), from
this folder:

    anchor drive start .
    anchor drive eval  . 'engine_step(60) return box_x'
    anchor drive stop  .

Static check before every handover:

    anchor check .

## Layout

- `main.lua` — definitions only (it reloads on save); the init table names
  `boot.lua` and the last line requires it
- `boot.lua` — one-time work: layers, fonts, binds, state (never reloads)
- `anchor/` — THIS GAME'S OWN copy of the framework. Port framework changes
  in per file with `anchor framework status|diff|upgrade`; never overwrite it
  wholesale
- `assets/` — images, fonts, sounds

Every turn spent here is snapshotted onto the `ai/journal` branch by the Stop
hook and carded in the session log; the branch is pushed at `anchor continue`.
