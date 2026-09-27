--[[
  Anchor 2 — framework initialization.

  Loads all framework modules in dependency order, then returns a function
  that takes config and initializes the engine + global state. The game's
  main.lua is expected to define `update(dt)` and `draw()` as globals; the
  C engine calls these directly each frame.

  Usage (from a game's main.lua):
    require('anchor')({
      width = 480,
      height = 270,
      title = "My Game",
      scale = 3,
      vsync = true,
      filter = "rough",
      -- render_uncapped = true,   -- opt out of the 60Hz render cap; let
                                   -- vsync pace render. Use for non-pixel-
                                   -- art games where the cap shows judder.
    })

    function update(dt)
      sync_engine_globals()          -- refresh time/frame/etc. mirrors
      -- your game update (physics is stepped by the engine automatically
      -- before update() is called; you just consume collision events here)
      process_destroy_queue()        -- drain deferred destruction
    end

    function draw()
      -- ... your game draw
    end

  Framework modules are loaded in this order (dependency-driven):
    class -> math -> array -> color -> object -> helpers -> input -> timer -> spring ->
    animation -> font -> image -> spritesheet -> layer -> shake -> camera -> collider

  After initialization, the following globals are available:
    - width, height                - game resolution
    - dt, unscaled_dt              - frame delta time
    - time, frame_num              - engine time/frame counters
    - platform, headless           - platform info
    - layers                       - named layer table (populated by layer_new)
    - images, fonts, sounds, shaders, spritesheets - resource tables
    - rgb/rgba classes, color class
    - class(), make_entity(), process_destroy_queue()
    - collection_update()  (see anchor/helpers.lua)
    - bind(), input_down(), input_pressed(), input_released()
    - timer_new(), timer_update(), ...
    - spring_new(), spring_update(), ...
    - camera_new(), camera_update(), ...
    - collider (class)
    - layer_* (procedural wrappers; see anchor/layer.lua — many shadow engine layer_*)
    - All other engine C functions (physics_*, sound_*, key_is_*, input_*, …)
]]

-- Load framework modules (order matters for module dependencies)
require('anchor.class')
require('anchor.math')
require('anchor.array')
require('anchor.color')
require('anchor.object')
require('anchor.helpers')
require('anchor.input')
require('anchor.timer')
require('anchor.spring')
require('anchor.animation')
require('anchor.font')
require('anchor.image')
require('anchor.spritesheet')
require('anchor.layer')
require('anchor.shake')
require('anchor.camera')
require('anchor.collider')
require('anchor.joint')
require('anchor.physics')
require('anchor.math3')
require('anchor.layer3')
require('anchor.mesh3')
require('anchor.agent')     -- the agent kit: helpers driven through the eval channel (docs/AGENT.md)
require('anchor.collider3')
require('anchor.camera3')
require('anchor.physics3')
require('anchor.memory')

-- Global resource tables. Game code populates these via the resource loaders.
layers = layers or {}
images = images or {}
fonts = fonts or {}
shaders = shaders or {}
sounds = sounds or {}
sound_paths = sound_paths or {}
music_tracks = music_tracks or {}
spritesheets = spritesheets or {}

--[[
  sync_engine_globals()
  Refreshes global mirrors of engine state. Call once at the top of your
  update function to ensure `time`, `frame_num`, `fps`, etc. reflect the
  current frame. `width`, `height`, `platform`, `headless` are set at init
  time and don't change during normal play.

  Note on dt: the `dt` parameter passed to your `update(dt)` function is
  the UNSCALED fixed physics timestep (PHYSICS_RATE). If you want scaled
  dt (e.g. during hitstop / slow-mo), compute `dt * time_scale` locally,
  or call `engine_get_dt()` which returns the scaled version. We
  deliberately do NOT set a global `dt` here to avoid shadowing the
  function parameter inside update.
]]
function sync_engine_globals()
  frame_num = engine_get_frame()
  step_num = engine_get_step()
  time = engine_get_time()
  unscaled_dt = engine_get_unscaled_dt()
  window_width, window_height = engine_get_window_size()
  width = engine_get_width()
  height = engine_get_height()
  scale = engine_get_scale()
  fullscreen = engine_is_fullscreen()
  fps = engine_get_fps()
  draw_calls = engine_get_draw_calls()
end

--[[
  set_time_scale(scale)
  Sets the engine-level time scale. Affects dt but not unscaled_dt.
  Use unscaled_dt for things that should ignore slow-mo (UI, etc.).
]]
function set_time_scale(s)
  time_scale = s
  engine_set_time_scale(s)
end

-- The framework initialization function returned by require('anchor').
-- Called with a config table by the game's main.lua.
return function(config)
  -- Idempotent: the entry file re-runs on a code reload (engine_reload), and
  -- its `require('anchor')({...})` line must then be a no-op — the engine is
  -- already up. ANCHOR_BOOTED is the flag; everything below runs exactly once.
  if ANCHOR_BOOTED then return end
  config = config or {}

  -- Apply engine configuration before engine_init
  if config.width and config.height then
    engine_set_game_size(config.width, config.height)
  end
  if config.title then engine_set_title(config.title) end
  if config.scale then engine_set_scale(config.scale) end
  if config.vsync ~= nil then engine_set_vsync(config.vsync) end
  if config.fullscreen ~= nil then engine_set_fullscreen(config.fullscreen) end
  if config.resizable ~= nil then engine_set_resizable(config.resizable) end
  if config.web_native_resolution ~= nil and engine_set_web_native_resolution then engine_set_web_native_resolution(config.web_native_resolution) end
  if config.render_uncapped ~= nil then engine_set_render_uncapped(config.render_uncapped) end
  if config.display ~= nil then engine_set_display(config.display) end
  if config.filter then set_filter_mode(config.filter) end
  -- Code reload (docs/AGENT.md): the files that do one-time work (assets,
  -- layers, binds, state tables) never reload; everything else re-runs on save.
  if config.boot and engine_set_boot_files then engine_set_boot_files(config.boot) end
  -- Recording (docs/REPLAY.md): desktop dev runs and agent instances record by
  -- default; `record = false` opts a game out, `record = true` forces it on.
  -- record_start() / record_stop() change it at any moment.
  if config.record ~= nil and engine_set_record_default then engine_set_record_default(config.record) end

  -- Initialize the engine (creates window, GL context, loads shaders)
  engine_init()
  ANCHOR_BOOTED = true

  -- Set up static global state (these don't change during normal play)
  width = engine_get_width()
  height = engine_get_height()
  platform = engine_get_platform()

  -- Set up dynamic global state (initial values; refreshed by sync_engine_globals)
  unscaled_dt = engine_get_unscaled_dt()
  time = 0
  frame_num = 0
  step_num = 0
  time_scale = 1.0

  -- Set up default random number generator (global_rng is provided by the C engine,
  -- accessible by passing nil or omitting the rng argument to random_* functions).
  -- If you want a seeded rng for determinism, create one with random_create(seed).

  -- Physics is not initialized automatically. Games that need physics should call
  -- physics_init() themselves, then register tags and collision pairs:
  --   physics_init()
  --   physics_register_tag('player')
  --   physics_register_tag('enemy')
  --   physics_enable_collision('player', 'enemy')
end
