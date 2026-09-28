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
