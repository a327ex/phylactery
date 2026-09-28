# lich-survivors

Guidelines for Claude Code instances working in this project.

**Read `RECORD.md` first** (purpose, owner's settled decisions, rounds, pending choices).

**Porting to Anchor** (planned once the attacks and this part of the cave are done, owner
2026-09-28): read `ANCHOR_PORT.md` first -- what Anchor lacks for this game (testing and
rendering), in the order to build it, and the port order.

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
