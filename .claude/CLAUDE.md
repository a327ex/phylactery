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
