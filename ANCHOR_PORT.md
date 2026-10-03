# Porting Lich Survivors to Anchor -- what Anchor needs

Written 2026-09-28 at the end of "Lich Survivors 2" (owner: "when we finish all attacks and this
portion of the cave, the next instances can port the game to Anchor and we can finish it there").
The game is built in three.js first (owner's call, like Brutal Behavior); this is the assessment of
what Anchor needs so it can be used the way three.js was used here, both to build the game and to
test it mid-turn. Anchor capabilities below are read from `Anchor/engine/docs/` (SURFACE.md,
AGENT.md, ENGINE_API_QUICK.md, 3D_API.md) on that date: **verify each gap against the current
engine before building anything**, the engine moves fast.

Read `RECORD.md` first for what the game is; this file is only about the port.

## 1. Testing and checking mid-turn

How every change was checked here (three.js): a headless Chrome harness (`tools/shoot.mjs`)
driving the game's `window.GAME` test API at a fixed 60 Hz, only when told to step; numbers traced
over time (springs, phases), sweeps of invariants (the "no snake reaches the egg" guarantee: 20
cases x 90 s, simulated without drawing via `GAME.until`), measurements read back from the rendered
image (`GAME.gem_probe()`: light arriving on the bones per unit albedo from the linear HDR target, a
debug pass marking the lich's pixels, screen brightness / saturation / hue spread, and the rock
around him), and stills / contact sheets looked at directly.

| Used in three.js | Anchor today | Status |
|---|---|---|
| Hidden, externally paced instance | agent instance (`anchor drive start`), `engine_step(n)` | **better**: persistent between calls, real GPU (headless Chrome's software WebGL loaded his PC enough that he asked what was happening), hot reload (`engine_reload()`), every run recorded for him to watch |
| A test API in the game (`window.GAME`) | Lua eval over the channel, `agent_*` functions in the game | equivalent |
| Simulate without drawing (`GAME.until`) | `engine_set_draw(false)` + `agent_wait_until` | equivalent |
| Screenshots | `engine_snapshot(path)` (final 8-bit frame) | equivalent |
| **Numbers from the render**: read pixels back (a region's statistics), and read the linear/HDR target before post-processing | nothing Lua can call (glReadPixels exists only inside frame capture) | **MISSING**. Rounds 7-8 (how prismatic / how bright he is in and out of the light) were tuned from these numbers |
| **Per-object masks**: which pixels are one mesh (a marker/ID pass) | none | **MISSING** (needed for "the lich's brightness vs the rock around him") |
| **World -> screen projection in 3D** (`Vector3.project`) | only screen -> ray (`layer3_unproject`, `camera3_mouse_ray`); the 2D camera has `camera_to_screen` | **MISSING**. Used for: the walkable map (cells the room camera can't see are blocked: `main.js` projects every cell), the mouse-goal marker, cropping stills on an object |
| An inspection camera aimed at any point (`GAME.view_at`) | the game can set its camera over eval | fine as a game-level `agent_view_at`; promote to the kit if a second game wants it |

## 2. What the game renders, and whether layer3 can

The look is the Sun Court recipe (`retro-shooter/STYLE.md`: 640x360, hard texel-snapped sun
shadows, the shaft marched through the shadow map, 64-level quantize, dither 0.3) plus everything
built on it here. layer3 today (docs): one faceted 3D shader with `layer3_set_shade` knobs (wrap,
bands, rim, spec), directional light + 16 point lights (smooth falloff, no shadows), linear fog,
billboards (add / alpha / cutout, textured, UVs), 1 px lines, `mesh3` (8 floats per vertex: pos,
normal, uv; textured; skinned with morphs; `mesh3_set_transparent` = depth-tested, not
depth-written), instancing up to 4096 per mesh type per frame, a fixed-size backing layer ('rough'
= nearest) composited and post-processed with 2D layer shaders.

In order of what blocks the port most:

1. **Custom shaders on 3D meshes, with per-mesh uniforms and extra vertex attributes.** Almost
   everything distinctive is a shader: the gem bone (`gem.js`: prism strength from the light
   arriving, the SOFT pattern, the glow, per-bone ids), the snakes' char / ember / prismatic glow
   (per-vertex `aBurn`), the lens glass rim and shimmer, the beam cross-sections (`fx.js` ribbons:
   PRISM, FIRE LASER, PRISM IN FIRE), the cone and floor patch of the lens's focusing light, the
   baked GI on static geometry (per-vertex) and on moving things (probe lookups). layer3 has one
   fixed shader. MISSING: a material = shader + uniforms per mesh (or per draw), and vertex
   formats beyond pos/normal/uv (colour, extra floats).
2. **An HDR 3D target and its depth, readable by post shaders.** The final pass fogs by depth,
   marches the shaft, blooms HDR values (fire, beams, sparks are 2-9x white), then exposes, grades,
   dithers and quantizes. layer3 renders into a layer FBO (8-bit?) and post shaders get its colour
   only. MISSING: a half-float backing option for layer3, its depth as a texture for layer shaders,
   and the camera matrices as uniforms (reconstructing positions from depth).
3. **Directional shadow maps, and the map as a texture for post.** The room's whole light is one
   sun down a shaft: the pool on the floor and the column are the shadow map's (soft-edged: PCSS in
   `soft_shadows.js`, blur growing with distance to the caster), the lens casts its shadow into the
   shaft, the lich and snakes cast shadows in the pool. layer3: no shadows. MISSING: a directional
   shadow pass (configurable bounds / resolution, casters and receivers), soft filtering, and the
   map + its matrix exposed to post shaders for the shaft.
4. **Meshes rebuilt every frame.** Each snake is one tube (72 rings x 12 sides) rewritten every
   tick along its trail, with per-vertex burn/glow; the lens's light cone is rebuilt each tick.
   `mesh3_create` makes a new mesh; no in-place update is listed. MISSING: `mesh3_update(mesh,
   vertices)` (same size, re-upload), ideally indexed. (Alternative for the snakes: `mesh3_skin`
   with <= 64 bones along the body; the burn attributes would still need item 1.)
5. **A copy of the scene's colour after the opaque pass (a "grab pass")** for refraction: the lens
   is real transmissive glass (MeshPhysicalMaterial transmission, ior 1.52, dispersion; three.js
   renders the opaque scene into a texture and the glass samples it bent). With item 1 plus a grab
   texture the glass is a small shader. Also: the glass must not write depth (`mesh3_set_transparent`
   covers that), otherwise the shaft's haze stops at it (round 14's "dark stone").
   Round 23 adds a second use: **the warp layer** (`web/src/warp.js`, `render.js`): leakage, the
   rock's telekinesis and its wake are air that bends the light. Streaks and puffs are drawn with
   the world camera into their own half-float target as *signed* screen-space shifts (additive,
   ONE/ONE, negative values allowed), each fragment tested by hand against the world's depth
   texture; the final pass samples the world at the shifted position, the three channels shifted
   by different amounts (the prismatic split). Anchor needs: a float target with signed additive
   blending, the world depth readable in a custom shader, and the final pass able to read both.
6. **3D textures (or probe arrays as uniforms)** for the baked bounce light on moving things (the
   lich, the snakes, the chunks sample an up/down irradiance probe grid). Static geometry carries
   its bake per vertex (item 1's vertex colours). A cheaper port: a handful of probes as uniforms.
7. **Particles at this volume.** Pools of ~1600 additive motes, ~400 shards, ~600 alpha puffs,
   ~900 flame tongues, sized in metres, HDR colours. Billboards probably cover it (textures for the
   flame / shard shapes, add and alpha blends); check whether the 4096-per-type budget counts
   billboards, and whether billboards take HDR colour (item 2).
8. **Beams with a width.** `layer3_line` is 1 px and unlit; the beams are camera-facing ribbons
   with a width in metres and a pixel minimum, and a cross-section shader. With item 1 this is a
   camera-facing strip mesh (item 4 to update it) or a billboard strip.
9. **Physical light falloff.** Point lights here are inverse-square (three.js physical); Anchor's
   are a smoothstep to a radius. Fine, but every light (fire, lens spot, beam tip) will need
   retuning by eye.

Not blockers: 16 point lights per layer is enough (the game uses up to 8, pooled); instanced
chunks are fine; the skeleton (210k triangles sculpted at load by `sdf.js`) and the cave (merged
static geometry + the GI bake) can be generated once and loaded as meshes (export from the
three.js build); the scene graph (lich joint hierarchy) becomes matrices computed in Lua, drawn
with `layer3_mesh` per bone; no physics is used (movement is a nav grid, `nav.js`).

## 3. What changed since the first assessment (same session, before rounds 12-17)

The first answer (asked mid-session: what I use to test, and what Anchor lacks) named only the
testing gaps: numeric readback, per-object masks, 3D world -> screen projection, and an
inspection-camera helper. Building the beams and the lens afterwards added the rendering side:
the glass needs a grab pass and depth-write control (item 5); the beams need width, custom
cross-sections and per-frame updates (items 1, 4, 8); the lens's focusing cone and floor patch are
per-frame meshes with additive custom shaders (items 1, 4); the guarantee sweeps confirmed that
simulating without drawing matters (Anchor has it). And one cost learned the hard way: headless
Chrome renders WebGL in software, so parallel clip renders slowed his PC; Anchor's agent instance
on the GPU removes that.

## 4. Suggested order

1. Engine: custom 3D shaders + vertex attributes + per-mesh uniforms (unblocks most items).
2. Engine: HDR layer3 target + depth texture + camera matrices to post shaders.
3. Engine: directional shadow map (+ soft filter, + exposed to post).
4. Engine: `mesh3_update`; then the grab pass; then probes (uniforms first, 3D textures if needed).
5. Engine (testing): pixel readback to Lua (region stats; linear target), a mask pass, `layer3_project`.
6. Port: renderer first (reproduce round 17's cave, light and lich by numbers against the three.js
   build: the same `gem_probe`-style measurements on both), then the lich and his float, the
   snakes, then the powers one by one, re-running the guarantee sweep after each.

⚠ The live site's wasm builds from `Anchor/engine/engine`: every engine change above can reach
production; run `replay-test/check.sh` after each (APR recordings must still play).

## 5. The port (started 2026-09-30): the plan, and where it stands

Owner, 2026-09-30: port now (the browser build loads slowly); **the port must be 100% the same as
the three.js build**, he tests them side by side. The three.js build of 2026-09-30 (round 37 + the
instant cut) is the reference; it stays runnable (`web/`) for the comparison.

**The construction (my call, for exactness):** three.js is not reimplemented from memory. The
Anchor build runs **the very GLSL programs three.js compiled** for this game (dumped from the
running renderer: `web/src/devtrace.js`, `GAME.trace_programs()`; 65 programs as of the inventory,
`scratch/port_programs/`), fed the same uniforms, in the same passes, in the same order:
1. **Engine: a generic GPU layer** (`gpu_*` in anchor.c, beside layer3, which stays untouched):
   programs from source (three.js's GLSL ES 3.00 header swapped for 330 core on desktop), meshes
   with any vertex attributes (+ instanced, + updated in place), index buffers, 2D / 3D / float
   textures, render targets (RGBA8 / RGBA16F colour, depth as a texture, mipmaps), draw state
   (blending, depth, culling, points / lines / triangles), clears, and **pixel readback to Lua**
   (8-bit and linear HDR: the testing gap of section 1). The final image is a gpu target whose
   texture is drawn into an ordinary layer, so the window, the upscale and `engine_snapshot`
   are Anchor's own. HUD: Anchor layers (the pixel font drawn with rectangles, as hud_font.js does).
2. **Lua: a small three.js** (the subset the game uses, same API shape so the game code
   translates line by line): Vector3 / Quaternion / Matrix4 / Euler, Object3D graph, cameras,
   BufferGeometry, materials (their uniform refresh as three.js does it), the renderer (render
   lists and sorting, the shadow pass, the transmission pass for the glass, light uniforms), and
   render.js's post chain with its own GLSL.
3. **Assets exported from the three.js build once** (also what makes loading fast): the sculpted
   skeleton and objects, the cave and its GI bake, the canvas textures, the environment maps.
4. **The game logic, module by module** (same seeds, same fixed 60 Hz step: the simulations
   should stay in step), checked against the three.js build's state at the same tick.
5. **Verification by numbers:** a frame's whole scene state dumped from three.js renders in
   Anchor and is pixel-compared with three.js's own frame (the renderer is right before any game
   logic moves); then the same scripted play in both, frames compared at the same ticks.

**Recordings (closed 2026-10-01, APR v13).** The gpu layer records its own command stream
(Anchor/engine/docs/REPLAY.md "The gpu layer"): every run records like any Anchor game again,
`record = false` is gone from main.lua, and the recordings play back byte-identical on the desktop
and play in the browser. Busiest scene ~1.1 MB/s.

**Recordings smaller (2026-10-03, APR v15).** boot.lua sets `gpu_precision(14)`: matrix uniforms,
dynamic attributes and gpu_tube's rings reach the GPU rounded to 14 mantissa bits (game state is
not touched, the digests stay identical). Against the three.js build this adds sub-pixel
differences (a dust mote one pixel over; dither levels in the haze), on top of the GPU floor below.
Recordings went from ~1.9 MB/s to ~0.6 MB/s.

### Progress (2026-09-30)
- **Engine: the gpu layer** (`gpu_*` in anchor.c, section "GPU"): programs from source, meshes
  of named float attributes (+ instanced, updated in place), 16/32-bit indices, 2D / 3D textures
  (rgba8, srgba8, rgba16f, rgba32f, ...; from files; updated; mipmaps), render targets (colour,
  depth as a texture, multisampled + `gpu_blit` to resolve), per-draw state, clears, pixel
  readback (`gpu_read`, 8-bit or float), a layer's texture as a sampler (`gpu_layer_texture`),
  `gpu_end` to hand the 2D pipeline its state back. Built to `build/anchor-port.exe` by
  `tools/build_engine_port.bat` (another session's agent instance held anchor.exe); drive with
  `ANCHOR_ENGINE_BIN=.../build/anchor-port.exe anchor drive start .`. Not yet: the web build,
  recording.
- **Proof 1, the GL replay:** a three.js frame captured at the GL level (`web/src/glcapture.js`,
  `?glcapture`, `GAME.glcap(dir)`) replayed on the gpu layer (`port/replay.lua`) matches three.js's
  own frame to the floor set by software vs hardware GL (glass and transmission included):
  ~6-10% of pixels off by >1 level (dither flips), ~0.3% by >16 (`tools/glcap_compare.py`).
- **Proof 2, the Lua renderer:** the empty cave from the room camera, rendered by the Lua three.js
  (`port/three/`: math, core, materials, renderer; `port/post.lua` = render.js;
  `port/cave.lua` = cave.js on exported assets) matches three.js at the same tick: every uniform
  both sides set agrees within 1e-5 (`tools/port_compare.py` against a capture, draw by draw),
  pixels at the same floor (6.8% >1, 0.31% >16).
- Tools: `GAME.program_map_start()/program_map_write(dir)` + `tools/port_programs.py` (the program
  library, assets/port/programs); `GAME.port_export(dir, what)` (`web/src/port_export.js`) +
  `tools/port_assets.py` (assets/port/<group>); `?manual` starts the web build paused (ticks line
  up with the Anchor build); `port_trace_frame(path)` in the Anchor build.
- Every three.js material now has a name (`named()`, util.js); scenes too (render.js, inspect.js).
- Then (same session): everything else; see the status below.

### Status: the port is complete (2026-09-30, same session)
Everything main.js runs now runs in the Anchor build (`main.lua`, `boot.lua`, `port/*.lua`): the
cave; the lich (pose, springs, recoil, hurt); nav, mover, the five cameras, keys and mouse as
main.js reads them; the snakes with the coil, the coverage and the win; fire, fx, gore, warp; the
six powers and their director; the six objects (the drop from his hand, their rigid bodies, the
orbs as balls, the hand's two materials, the floor sizes); the inspect view; the HUD; the ending
(instant cut, the message fading in). Load to first frame: ~0.7 s (every program compiled at boot).

**Same numbers, not just the same look.** The port computes what Chrome computes, bit for bit:
- the engine's `js_sin/cos/tan/asin/acos/atan/exp` are correctly rounded (Chrome's V8 takes these
  from LLVM libc, which rounds correctly; the C library's differ in the last bit 3-7% of the time),
  `js_hypot` is V8's own formula, `js_fround` is Math.fround (boot.lua points math.* at them);
  `pow`/`sqrt` already agreed (20000 samples each);
- where the JS keeps numbers in Float32Arrays that the game reads back (the snakes' radii, the
  coil's per-ring arrays), the port rounds to float32 at the same stores;
- JS's `a += b - c` is `a + (b - c)`; RNG draws happen in the JS's evaluation order.
Verified with full-precision state digests (`tools/port_digest.js` / `.lua` / `_cmp.py`): every
2 s for 2 minutes of play, a scripted WASD + mouse-goal run, and the ending (T: all six objects
dropped and settled, the coil, the win at 44.30 s with 12 coiled, black at tick 2766): identical
to 15 significant digits. This caught real bugs (a Lua `x and nil or y`; float32 radii; operator
association) and one tie in the game itself: coil.js picks a band's winding (sigma) by comparing
two dot products that are equal in exact arithmetic, so the browser's rounding decides it (the
port now rounds the same way; noted, not changed).
Pictures (`scratch/port_visual/sheet.png`, room camera at five moments, the four other cameras,
the end screen): ~0.3-0.5% of pixels off by >16 levels (dither and GPU float noise, the floor the
GL replay set), the end screen identical; the inspect view per object <=0.01%, the traced gem
1.7% (its internal reflections amplify GPU float differences).

**Engine additions** (`anchor.c`, all generic; `anchor.exe` and `anchor-port.exe` rebuilt;
`replay-test/check.sh` passes; the web engine build is NOT verified on this machine: no emsdk,
the new code is guarded for it):
`gpu_buffer(n)` (+ `gpu_buffer_set`, `gpu_buffer_fill`; float arrays a mesh uploads by copy),
`gpu_tube` (elliptical sections along a spine into gpu buffers: the snakes),
`gpu_texture_cube` (cube maps from faces; seamless), `anisotropy` for 2D textures,
`js_*` math as above, `noise_value3` / `noise_fbm3` (the cave's value noise, same bits as
cave.js: the floor height went from 17 us to 0.7 us).
**Performance:** a 60 Hz tick + a frame costs ~12 ms at the busiest moments (the six objects
falling; ten snakes coiled late in the ending), ~8 ms in play. The renderer sends a material's
uniforms only when the program or material changes, as three.js does, culls by frustum (view and
shadow), and caches still objects' matrices.
**Known differences:** GPU float differences (the gem's sparkle, the skeleton's prism up close);
the window is 1280x720 at x2 (the browser fills its window); the dither's time phase follows
each build's own clock; the mouse wheel steps 100 per notch. (Runs record since APR v13, 2026-10-01.) The web build's warp randomness is now seeded (it was
Math.random) so both draw the same air: the reference for the side-by-side is
`rounds/38-port-reference/index.html` (round 37 + the instant cut + the seeded warp), not the
round 37 page.
**Run:** `run.bat` (the Anchor build). Drive it: `ANCHOR_ENGINE_BIN=...build/anchor.exe anchor
drive start .`, `GAME.*` in `port/game.lua` mirrors `window.GAME` (step, state, cam, drop,
inspect, remove_all, ending, until, ...); exports: `GAME.port_export(dir, ['cave' | 'lich' |
'statics' | 'items'])` + `tools/port_assets.py`.
