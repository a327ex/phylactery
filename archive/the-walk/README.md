# The walk through the cave (round 39, set aside)

Built 2026-10-02 (session "Lich Survivors 7"): a walk through six cave chambers gathering the six
objects before the final room, Resident Evil fixed cameras, generated offline. The owner set it
aside the same day ("I don't like it") for a game that starts with every object in the lich's
inventory (RECORD.md round 40). Kept here, not deleted:

- `tools/walk/` -- the generator (node + three.js from npm): layout, the cave volume + surface
  nets, formations, textures, the light bake, nav, the camera search. `node build.mjs` wrote
  `assets/port/walk/` + `assets/port/walk.lua` (now under `assets/port/` here).
- `port/walk.lua`, `port/walknav.lua` -- the Anchor side (areas' light, cameras, taking objects).
- `port/game_with_walk.lua.txt` -- game.lua as it was with the walk wired in.
- The whole working state is the git tag `walk-round39` (commit 480c1a8); `rounds/39-walk/` is its page.

To run it again: check out the tag (`git checkout walk-round39`), or move these files back to their
old paths (dropping the .txt the Lua files carry here, so the static check skips them) and restore game.lua from `game_with_walk.lua.txt`.
