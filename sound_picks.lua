-- the sound picks (written by the in-game editor, mb/soundui.lua): slot -> files (converted copies in
-- assets/sfx/), src = the pack files they came from, vol, unsure = no file on purpose (red: nobody was sure of a
-- pick; candidates = suggestions to audition), and every setting that differs from mb/audio.lua DEFAULTS
return {
  ["beam_bite"] = {
    ["files"] = {
      "assets/sfx/beam_bite_1.ogg",
      "assets/sfx/beam_bite_2.ogg",
    },
    ["mute"] = true,
    ["reverb"] = 0.2,
    ["src"] = {
      "Ultimate SFX Bundle - HD Remaster/Gore Sounds Pro/Needle piercing flesh/Needle piercing flesh 1.wav",
      "Ultimate SFX Bundle - HD Remaster/Gore Sounds Pro/Needle piercing flesh/Needle piercing flesh 2.wav",
    },
    ["vol"] = 0.55,
  },
  ["beam_cast"] = {
    ["files"] = {
      "assets/sfx/beam_cast_14.ogg",
    },
    ["reverb"] = 0.35,
    ["sr"] = 4,
    ["src"] = {
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Light Magic/RPG3_LightMagicEpic_Impact02.wav",
    },
    ["vol"] = 0.75,
  },
  ["beam_channel"] = {
    ["files"] = {
      "assets/sfx/beam_channel_1.ogg",
    },
    ["reverb"] = 0.3,
    ["src"] = {
      "SFX_Collection/WAV/Farm/Event_PreciousCrystalRinging_Loop.wav",
    },
    ["vol"] = 3,
  },
  ["beam_petals"] = {
    ["files"] = {
      "assets/sfx/beam_petals_1.ogg",
      "assets/sfx/beam_petals_2.ogg",
      "assets/sfx/beam_petals_3.ogg",
      "assets/sfx/beam_petals_4.ogg",
    },
    ["reverb"] = 0.4,
    ["src"] = {
      "Universal Sound FX/GLASS/GLASS_Fragment_01_mono.wav",
      "Universal Sound FX/GLASS/GLASS_Fragment_04_mono.wav",
      "Universal Sound FX/GLASS/GLASS_Fragment_10_mono.wav",
      "Universal Sound FX/GLASS/GLASS_Fragment_13_mono.wav",
    },
    ["vol"] = 0.3,
  },
  ["beam_shatter"] = {
    ["files"] = {
      "assets/sfx/beam_shatter_7.ogg",
      "assets/sfx/beam_shatter_8.ogg",
      "assets/sfx/beam_shatter_9.ogg",
    },
    ["per"] = {
      ["assets/sfx/beam_shatter_7.ogg"] = {
        ["sr"] = 4,
      },
      ["assets/sfx/beam_shatter_8.ogg"] = {
        ["sr"] = 4,
      },
      ["assets/sfx/beam_shatter_9.ogg"] = {
        ["sr"] = 4,
      },
    },
    ["reverb"] = 0.35,
    ["src"] = {
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Light Magic/RPG3_LightMagic_Cast02.wav",
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Light Magic/RPG3_LightMagic_Cast02v2.wav",
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Light Magic/RPG3_LightMagic_Cast01.wav",
    },
    ["vol"] = 0.75,
  },
  ["beam_shot"] = {
    ["files"] = {
      "assets/sfx/beam_shot_1.ogg",
      "assets/sfx/beam_shot_2.ogg",
      "assets/sfx/beam_shot_3.ogg",
    },
    ["reverb"] = 0.35,
    ["src"] = {
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Light Magic/RPG3_LightMagic2_LightImpact01.wav",
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Light Magic/RPG3_LightMagic2_LightImpact02.wav",
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Light Magic/RPG3_LightMagic2_LightImpact03.wav",
    },
    ["vol"] = 0.8,
  },
  ["cave_amb"] = {
    ["files"] = {
      "assets/sfx/cave_amb_1.ogg",
    },
    ["reverb"] = 0,
    ["src"] = {
      "Gamemaster Audio - Pro Sound Collection/Animals_Nature_Ambiences/cave_ambience_loop_04.wav",
    },
    ["vol"] = 0.55,
  },
  ["coil_grip"] = {
    ["candidates"] = {
      "Ultimate SFX Bundle (2020)/Ultimate Animal Sounds/Snake/Snake Attacks/Snake Attacks 3.wav",
      "Universal Sound FX/BREAKS_SNAPS/BREAK_Squishy_stereo.wav",
    },
    ["reverb"] = 0.25,
    ["unsure"] = true,
  },
  ["coil_squeeze"] = {
    ["files"] = {
      "assets/sfx/coil_squeeze_1.ogg",
    },
    ["reverb"] = 0.1,
    ["src"] = {
      "Ultimate SFX Bundle (2020)/Ultimate Animal Sounds/Snake/Snake Crawling/Snake Crawling 4.wav",
    },
    ["vol"] = 0.7,
    ["width"] = 0.4,
  },
  ["coil_win"] = {
    ["candidates"] = {
    },
    ["reverb"] = 0.6,
    ["unsure"] = true,
    ["width"] = 0.6,
  },
  ["egg_crack"] = {
    ["files"] = {
      "assets/sfx/egg_crack_1.ogg",
      "assets/sfx/egg_crack_2.ogg",
      "assets/sfx/egg_crack_3.ogg",
    },
    ["reverb"] = 0.35,
    ["src"] = {
      "soundeffect-lab/various/egg-break1__crack-egg-open.ogg",
      "Universal Sound FX/BREAKS_SNAPS/CRACK_Bright_Crisp_01_mono.wav",
      "Universal Sound FX/BREAKS_SNAPS/CRACK_Bright_Crisp_02_mono.wav",
    },
    ["vol"] = 0.9,
  },
  ["egg_knock"] = {
    ["files"] = {
      "assets/sfx/egg_knock_1.ogg",
    },
    ["reverb"] = 0.3,
    ["src"] = {
      "soundeffect-lab/various/egg-konkon1__tap-egg-crack.ogg",
    },
    ["vol"] = 0.9,
  },
  ["egg_open"] = {
    ["files"] = {
      "assets/sfx/egg_open_1.ogg",
      "assets/sfx/egg_open_2.ogg",
    },
    ["reverb"] = 0.5,
    ["src"] = {
      "Universal Sound FX/BREAKS_SNAPS/BREAK_Hollow_stereo.wav",
      "Universal Sound FX/BREAKS_SNAPS/BREAK_Crack_stereo.wav",
    },
    ["width"] = 0.4,
  },
  ["egg_piece_land"] = {
    ["candidates"] = {
      "soundeffect-lab/various/cup-put1__set-down-ceramic-bowl.ogg",
      "Universal Sound FX/GLASS/GLASS_Fragment_03_mono.wav",
    },
    ["reverb"] = 0.15,
    ["unsure"] = true,
  },
  ["egg_shiver"] = {
    ["candidates"] = {
      "soundeffect-lab/various/egg-konkon1__tap-egg-crack.ogg",
      "Universal Sound FX/BREAKS_SNAPS/BREAK_Subtle_stereo.wav",
    },
    ["reverb"] = 0.2,
    ["unsure"] = true,
  },
  ["ending_begin"] = {
    ["candidates"] = {
      "Universal Sound FX/CHARGE_UPS_DOWNS/CHARGE_Complex_Wet_12_Semi_Down_8000ms_stereo.wav",
    },
    ["reverb"] = 0.6,
    ["unsure"] = true,
  },
  ["fire_burn"] = {
    ["files"] = {
      "assets/sfx/fire_burn_1.ogg",
    },
    ["per"] = {
      ["assets/sfx/fire_burn_1.ogg"] = {
        ["vol"] = 0.55,
      },
    },
    ["reverb"] = 0.1,
    ["src"] = {
      "Ultimate SFX Bundle - HD Remaster/Fire N Flame Sounds/General Fire Loop 6.wav",
    },
    ["vol"] = 0.5,
  },
  ["fire_cast"] = {
    ["files"] = {
      "assets/sfx/fire_cast_1.ogg",
      "assets/sfx/fire_cast_2.ogg",
      "assets/sfx/fire_cast_3.ogg",
    },
    ["reverb"] = 0.3,
    ["src"] = {
      "Ultimate SFX Bundle - HD Remaster/Fire N Flame Sounds/Flame Whoosh.wav",
      "Ultimate SFX Bundle - HD Remaster/Fire N Flame Sounds/Flame Whoosh 2.wav",
      "Ultimate SFX Bundle - HD Remaster/Fire N Flame Sounds/Flame Whoosh 10.wav",
    },
    ["vol"] = 0.9,
  },
  ["fire_ignite"] = {
    ["files"] = {
      "assets/sfx/fire_ignite_1.ogg",
      "assets/sfx/fire_ignite_2.ogg",
      "assets/sfx/fire_ignite_3.ogg",
    },
    ["reverb"] = 0.3,
    ["src"] = {
      "Ultimate SFX Bundle - HD Remaster/Fire N Flame Sounds/Fire Burst 2.wav",
      "Ultimate SFX Bundle - HD Remaster/Fire N Flame Sounds/Fire Burst 3.wav",
      "Ultimate SFX Bundle - HD Remaster/Fire N Flame Sounds/Fire Burst 4.wav",
    },
    ["vol"] = 0.8,
  },
  ["fire_sweep"] = {
    ["fade"] = 5,
    ["files"] = {
      "assets/sfx/fire_sweep_1.ogg",
    },
    ["reverb"] = 0.2,
    ["sr"] = 4,
    ["src"] = {
      "Pixel Magic Sound Effects Pack/PM_ELEM_Fire08_Flamethrower_Loop.wav",
    },
    ["vol"] = 0.7,
    ["width"] = 0.5,
  },
  ["gore_crush"] = {
    ["files"] = {
      "assets/sfx/gore_crush_1.ogg",
      "assets/sfx/gore_crush_2.ogg",
      "assets/sfx/gore_crush_3.ogg",
      "assets/sfx/gore_crush_4.ogg",
    },
    ["reverb"] = 0.3,
    ["sr"] = 4,
    ["src"] = {
      "Ultimate SFX Bundle - HD Remaster/Gore Sounds Pro/Bloody Axe Impact/Bloody Axe Impact 2.wav",
      "Ultimate SFX Bundle - HD Remaster/Gore Sounds Pro/Bloody Axe Impact/Bloody Axe Impact 3.wav",
      "Ultimate SFX Bundle - HD Remaster/Gore Sounds Pro/Bloody Axe Impact/Bloody Axe Impact 5.wav",
      "Ultimate SFX Bundle - HD Remaster/Gore Sounds Pro/Bloody Axe Impact/Bloody Axe Impact 8.wav",
    },
  },
  ["gore_land"] = {
    ["files"] = {
      "assets/sfx/gore_land_1.ogg",
      "assets/sfx/gore_land_2.ogg",
      "assets/sfx/gore_land_3.ogg",
    },
    ["reverb"] = 0.15,
    ["src"] = {
      "Universal Sound FX/GORE_SPLATS/GORE_Splat_L_Ground_01_mono.wav",
      "Universal Sound FX/GORE_SPLATS/GORE_Splat_L_Ground_02_mono.wav",
      "Universal Sound FX/GORE_SPLATS/GORE_Splat_Hit_Short_mono.wav",
    },
    ["vol"] = 0.45,
  },
  ["item_land_gem"] = {
    ["files"] = {
      "assets/sfx/item_land_gem_1.ogg",
      "assets/sfx/item_land_gem_2.ogg",
      "assets/sfx/item_land_gem_3.ogg",
    },
    ["reverb"] = 0.2,
    ["src"] = {
      "SFX_Collection/WAV/Farm/Hit_CrystalMineral_01.wav",
      "SFX_Collection/WAV/Farm/Hit_CrystalMineral_02.wav",
      "SFX_Collection/WAV/Farm/Hit_CrystalMineral_03.wav",
    },
    ["vol"] = 0.6,
  },
  ["item_land_hand"] = {
    ["files"] = {
      "assets/sfx/item_land_hand_1.ogg",
    },
    ["reverb"] = 0.2,
    ["src"] = {
      "SFX_Collection/WAV/Inventory_SFX/Armour_Plate_Equipment_Drop.wav",
    },
    ["vol"] = 0.7,
  },
  ["item_land_lens"] = {
    ["files"] = {
      "assets/sfx/item_land_lens_1.ogg",
    },
    ["reverb"] = 0.2,
    ["src"] = {
      "Universal Sound FX/GLASS/GLASS_Tap_mono.wav",
    },
    ["vol"] = 0.7,
  },
  ["item_land_lodestone"] = {
    ["files"] = {
      "assets/sfx/item_land_lodestone_1.ogg",
      "assets/sfx/item_land_lodestone_2.ogg",
      "assets/sfx/item_land_lodestone_3.ogg",
    },
    ["reverb"] = 0.2,
    ["src"] = {
      "Gamemaster Audio - Pro Sound Collection/Impacts_Smashable/rock_impact_small_hit_01.wav",
      "Gamemaster Audio - Pro Sound Collection/Impacts_Smashable/rock_impact_small_hit_02.wav",
      "Gamemaster Audio - Pro Sound Collection/Impacts_Smashable/rock_impact_small_hit_03.wav",
    },
    ["vol"] = 0.8,
  },
  ["item_land_mask"] = {
    ["files"] = {
      "assets/sfx/item_land_mask_1.ogg",
      "assets/sfx/item_land_mask_2.ogg",
    },
    ["reverb"] = 0.2,
    ["src"] = {
      "soundeffect-lab/various/cup-put1__set-down-ceramic-bowl.ogg",
      "SFX_Collection/WAV/Inventory_SFX/Ceramic_Barrel_Close.wav",
    },
    ["vol"] = 0.8,
  },
  ["item_land_orbs"] = {
    ["files"] = {
      "assets/sfx/item_land_orbs_1.ogg",
      "assets/sfx/item_land_orbs_2.ogg",
    },
    ["reverb"] = 0.2,
    ["src"] = {
      "Universal Sound FX/GLASS/GLASS_Tap_mono.wav",
      "soundeffect-lab/various/glass1__clink-glasses-toast.ogg",
    },
    ["vol"] = 0.6,
  },
  ["item_pickup"] = {
    ["files"] = {
      "assets/sfx/item_pickup_1.ogg",
      "assets/sfx/item_pickup_2.ogg",
    },
    ["reverb"] = 0.1,
    ["src"] = {
      "SFX_Collection/WAV/Inventory_SFX/Items_Random_Item_Grab_01.wav",
      "SFX_Collection/WAV/Inventory_SFX/Items_Random_Item_Grab_02.wav",
    },
    ["vol"] = 0.7,
  },
  ["item_throw"] = {
    ["files"] = {
      "assets/sfx/item_throw_1.ogg",
      "assets/sfx/item_throw_2.ogg",
      "assets/sfx/item_throw_3.ogg",
    },
    ["reverb"] = 0.15,
    ["src"] = {
      "Universal Sound FX/WHOOSHES/Air/WHOOSH_Air_Blade_RR1_mono.wav",
      "Universal Sound FX/WHOOSHES/Air/WHOOSH_Air_Blade_RR2_mono.wav",
      "Universal Sound FX/WHOOSHES/Air/WHOOSH_Air_Blade_RR3_mono.wav",
    },
    ["vol"] = 0.7,
  },
  ["leak_ripple"] = {
    ["candidates"] = {
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Wind Magic/RPG3_WindMagicMisc_LowGust01.wav",
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Wind Magic/RPG3_WindMagicMisc_LowGust02.wav",
    },
    ["files"] = {
      "assets/sfx/leak_ripple_1.ogg",
    },
    ["reverb"] = 0.45,
    ["src"] = {
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Wind Magic/RPG3_WindMagic_Drone01_LowSubtleLoop.wav",
    },
    ["vol"] = 0.4,
    ["width"] = 0.6,
  },
  ["leak_snake"] = {
    ["candidates"] = {
      "Ultimate SFX Bundle - HD Remaster/Fire N Flame Sounds/Sizzle 6.wav",
      "Ultimate SFX Bundle - HD Remaster/Fire N Flame Sounds/Sizzle 2.wav",
    },
    ["reverb"] = 0.2,
    ["unsure"] = true,
  },
  ["leak_whisper"] = {
    ["candidates"] = {
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Wind Magic/RPG3_WindMagicMisc_Dark01.wav",
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Wind Magic/RPG3_WindMagicMisc_Dark02.wav",
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Wind Magic/RPG3_WindMagicMisc_Dark03_Loop.wav",
      "Pixel Magic Sound Effects Pack/PM_ELEM_Dark04_Absorb_P3_Drone.wav",
    },
    ["reverb"] = 0.2,
    ["unsure"] = true,
  },
  ["lens_charge"] = {
    ["candidates"] = {
      "Universal Sound FX/CHARGE_UPS_DOWNS/CHARGE_Complex_Wet_12_Semi_Up_2000ms_stereo.wav",
    },
    ["reverb"] = 0.2,
    ["sr"] = 4,
    ["vol"] = 0.7,
  },
  ["lens_cut"] = {
    ["files"] = {
      "assets/sfx/lens_cut_1.ogg",
      "assets/sfx/lens_cut_2.ogg",
      "assets/sfx/lens_cut_3.ogg",
    },
    ["reverb"] = 0.2,
    ["sr"] = 4,
    ["src"] = {
      "Ultimate SFX Bundle - HD Remaster/Gore Sounds Pro/Ripping flesh/Ripping flesh 1.wav",
      "Ultimate SFX Bundle - HD Remaster/Gore Sounds Pro/Ripping flesh/Ripping flesh 3.wav",
      "Ultimate SFX Bundle - HD Remaster/Gore Sounds Pro/Ripping flesh/Ripping flesh 8.wav",
    },
    ["vol"] = 0.8,
  },
  ["lens_dissolve"] = {
    ["candidates"] = {
      "Universal Sound FX/GLASS/GLASS_Rattle_Many_Fragments_01_stereo.wav",
    },
    ["files"] = {
      "assets/sfx/lens_dissolve_2.ogg",
      "assets/sfx/lens_dissolve_3.ogg",
      "assets/sfx/lens_dissolve_4.ogg",
      "assets/sfx/lens_dissolve_5.ogg",
    },
    ["lay"] = {
      ["1"] = {
        ["vol"] = 0.75,
      },
    },
    ["reverb"] = 0.2,
    ["sr"] = 5,
    ["src"] = {
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Ice Magic/RPG3_IceMagic2_IceBreak03.wav",
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Ice Magic/RPG3_IceMagic2_IceBreak01.wav",
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Ice Magic/RPG3_IceMagic2_IceBreak02.wav",
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Ice Magic/RPG3_IceMagic2_IceBreak04Crit.wav",
    },
    ["vol"] = 0.71,
  },
  ["lens_fire"] = {
    ["fade"] = 0.8,
    ["files"] = {
      "assets/sfx/lens_fire_6.ogg",
      "assets/sfx/lens_fire_11.ogg",
      "assets/sfx/lens_fire_12.ogg",
    },
    ["lay"] = {
      ["2"] = {
        ["all"] = true,
        ["once"] = true,
      },
    },
    ["per"] = {
      ["assets/sfx/lens_fire_11.ogg"] = {
        ["layer"] = 2,
        ["reverb"] = 0.1,
        ["sr"] = 5,
        ["vol"] = 0.8,
      },
      ["assets/sfx/lens_fire_12.ogg"] = {
        ["delay"] = 0.1,
        ["layer"] = 2,
        ["reverb"] = 0.1,
        ["sr"] = 5,
        ["vol"] = 0.9,
      },
      ["assets/sfx/lens_fire_6.ogg"] = {
        ["air"] = 3.1,
        ["doppler"] = 1,
        ["fade"] = 5,
        ["reverb"] = 0.19,
        ["rolloff"] = 0.85,
        ["travel"] = 0,
        ["vol"] = 0.7,
      },
    },
    ["reverb"] = 0.15,
    ["sr"] = 4,
    ["src"] = {
      "Ultimate SFX Bundle - HD Remaster/Fire N Flame Sounds/Flamethrower Fire Loop 2.wav",
      "soundeffect-lab/battle/magic-flame1__fireball-cast.ogg",
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Fire Magic/RPG3_FireMagicBall_Projectile04.wav",
    },
    ["vol"] = 0.75,
  },
  ["lens_form"] = {
    ["files"] = {
      "assets/sfx/lens_form_10.ogg",
    },
    ["per"] = {
      ["assets/sfx/lens_form_10.ogg"] = {
        ["vol"] = 0.65,
      },
    },
    ["reverb"] = 0.45,
    ["sr"] = 5,
    ["src"] = {
      "soundeffect-lab/battle/magic-ice2__freeze.ogg",
    },
    ["vol"] = 0.71,
  },
  ["lich_die"] = {
    ["files"] = {
      "assets/sfx/lich_die_2.ogg",
      "assets/sfx/lich_die_3.ogg",
    },
    ["lay"] = {
      ["1"] = {
        ["all"] = true,
      },
    },
    ["reverb"] = 0.5,
    ["sr"] = 4,
    ["src"] = {
      "soundeffect-lab/battle/blow3__heavy-thud-hit.ogg",
      "soundeffect-lab/button/decision11__heavy-thud.ogg",
    },
    ["vol"] = 0.75,
    ["width"] = 0.3,
  },
  ["lich_hover"] = {
    ["candidates"] = {
      "Pixel Magic Sound Effects Pack/PM_ELEM_Dark04_Absorb_P3_Drone.wav",
      "Universal Sound FX/CHARGE_UPS_DOWNS/CHARGE_Complex_Wet_12_Semi_Low_Loop_loop_stereo.wav",
    },
    ["reverb"] = 0.1,
    ["unsure"] = true,
  },
  ["lich_hurt"] = {
    ["files"] = {
      "assets/sfx/lich_hurt_1.ogg",
      "assets/sfx/lich_hurt_2.ogg",
      "assets/sfx/lich_hurt_3.ogg",
    },
    ["reverb"] = 0.3,
    ["sr"] = 4,
    ["src"] = {
      "Gamemaster Audio - Pro Sound Collection/Foley/bone_break_neck_snap_crack_01.wav",
      "Gamemaster Audio - Pro Sound Collection/Foley/bone_break_neck_snap_crack_03.wav",
      "Gamemaster Audio - Pro Sound Collection/Foley/bone_break_neck_snap_crack_04.wav",
    },
    ["vol"] = 0.75,
  },
  ["lich_hurt_pose"] = {
    ["candidates"] = {
      "sounddictionary/battle/creaking-muscles-1__creaking-muscles-bone-break.ogg",
    },
    ["reverb"] = 0.15,
    ["unsure"] = true,
  },
  ["lich_thud"] = {
    ["candidates"] = {
      "Gamemaster Audio - Pro Sound Collection/Impacts_Smashable/rock_impact_small_hit_01.wav",
      "soundeffect-lab/various/cup-put1__set-down-ceramic-bowl.ogg",
    },
    ["reverb"] = 0.3,
    ["unsure"] = true,
  },
  ["lift_ball_burst"] = {
    ["files"] = {
      "assets/sfx/lift_ball_burst_2.ogg",
      "assets/sfx/lift_ball_burst_3.ogg",
      "assets/sfx/lift_ball_burst_4.ogg",
    },
    ["reverb"] = 0.39,
    ["sr"] = 4,
    ["src"] = {
      "Ultimate SFX Bundle - HD Remaster/Impacts & Sweeps - HD Remake/Impact Blood 2.wav",
      "Ultimate SFX Bundle - HD Remaster/Impacts & Sweeps - HD Remake/Impact Blood 3.wav",
      "Ultimate SFX Bundle - HD Remaster/Impacts & Sweeps - HD Remake/Impact Blood.wav",
    },
    ["vol"] = 0.75,
    ["width"] = 0.7,
  },
  ["lift_burst"] = {
    ["files"] = {
      "assets/sfx/mass_burst_1.ogg",
      "assets/sfx/mass_burst_2.ogg",
      "assets/sfx/lift_burst_7.ogg",
      "assets/sfx/lift_burst_8.ogg",
      "assets/sfx/lift_burst_9.ogg",
      "assets/sfx/lift_burst_10.ogg",
      "assets/sfx/lift_burst_11.ogg",
      "assets/sfx/lift_burst_12.ogg",
    },
    ["lay"] = {
      ["1"] = {
        ["reverb"] = 0.4,
        ["sr"] = 5,
        ["vol"] = 1.21,
      },
    },
    ["per"] = {
      ["assets/sfx/lift_burst_12.ogg"] = {
        ["layer"] = 2,
        ["reverb"] = 0.4,
        ["sr"] = 4,
        ["vol"] = 1.25,
      },
    },
    ["reverb"] = 0.6,
    ["src"] = {
      "Ultimate SFX Bundle - HD Remaster/Gore Sounds Pro/Head exploding/Head exploding 1.wav",
      "Ultimate SFX Bundle - HD Remaster/Gore Sounds Pro/Head exploding/Head exploding 2.wav",
      "Ultimate SFX Bundle (2020)/Gore Sounds Pro/Popping bloody Sac/Popping bloody Sac 2.wav",
      "Ultimate SFX Bundle (2020)/Gore Sounds Pro/Popping bloody Sac/Popping bloody Sac 1.wav",
      "Ultimate SFX Bundle - HD Remaster/Gore Sounds Pro/Head exploding/Head exploding 5.wav",
      "Ultimate SFX Bundle - HD Remaster/Gore Sounds Pro/Head exploding/Head exploding 4.wav",
      "Ultimate SFX Bundle - HD Remaster/Gore Sounds Pro/Head exploding/Head exploding 3.wav",
      "SFX_Collection/WAV/Blood/Blood_Fall_After_Wound_03.wav",
    },
    ["vol"] = 1.6,
    ["width"] = 0.7,
  },
  ["lift_cast"] = {
    ["files"] = {
      "assets/sfx/lift_cast_1.ogg",
      "assets/sfx/lift_cast_4.ogg",
    },
    ["lay"] = {
      ["1"] = {
        ["all"] = true,
      },
    },
    ["per"] = {
      ["assets/sfx/lift_cast_4.ogg"] = {
        ["sr"] = 3,
        ["vol"] = 0.5,
      },
    },
    ["reverb"] = 0.35,
    ["src"] = {
      "Pixel Magic Sound Effects Pack/PM_ELEM_Dark06_Gravity_P1_Cast.wav",
      "Pixel Magic Sound Effects Pack/PM_SPELL_Cast14_Gravity_Ball.wav",
    },
    ["vol"] = 0.6,
  },
  ["lift_fist"] = {
    ["files"] = {
      "assets/sfx/lift_fist_1.ogg",
      "assets/sfx/lift_fist_2.ogg",
    },
    ["reverb"] = 0.15,
    ["src"] = {
      "Gamemaster Audio - Pro Sound Collection/Foley/bone_break_neck_snap_crack_02.wav",
      "Gamemaster Audio - Pro Sound Collection/Foley/bone_break_neck_snap_crack_04.wav",
    },
    ["vol"] = 0.5,
  },
  ["lift_hold"] = {
    ["candidates"] = {
      "Universal Sound FX/CHARGE_UPS_DOWNS/CHARGE_Complex_Wet_12_Semi_Low_Loop_loop_stereo.wav",
      "Pixel Magic Sound Effects Pack/PM_ELEM_Dark04_Absorb_P3_Drone.wav",
    },
    ["reverb"] = 0.2,
    ["unsure"] = true,
  },
  ["lift_knot"] = {
    ["files"] = {
      "assets/sfx/lift_knot_1.ogg",
      "assets/sfx/lift_knot_2.ogg",
    },
    ["reverb"] = 0.25,
    ["src"] = {
      "Ultimate SFX Bundle - HD Remaster/Gore Sounds Pro/Ripping guts out of body/Ripping guts out of body 2.wav",
      "Ultimate SFX Bundle - HD Remaster/Gore Sounds Pro/Ripping guts out of body/Ripping guts out of body 3.wav",
    },
    ["vol"] = 0.8,
  },
  ["lift_swell"] = {
    ["candidates"] = {
      "Universal Sound FX/CHARGE_UPS_DOWNS/CHARGE_Complex_Wet_12_Semi_Up_1000ms_stereo.wav",
    },
    ["reverb"] = 0.45,
    ["unsure"] = true,
    ["width"] = 0.5,
  },
  ["mask_drop"] = {
    ["files"] = {
      "assets/sfx/mask_drop_1.ogg",
      "assets/sfx/mask_drop_2.ogg",
    },
    ["reverb"] = 0.35,
    ["src"] = {
      "soundeffect-lab/various/cup-put1__set-down-ceramic-bowl.ogg",
      "SFX_Collection/WAV/Inventory_SFX/Ceramic_Barrel_Close.wav",
    },
    ["vol"] = 0.8,
  },
  ["mass_burst"] = {
    ["files"] = {
      "assets/sfx/mass_burst_1.ogg",
      "assets/sfx/mass_burst_2.ogg",
    },
    ["reverb"] = 0.6,
    ["src"] = {
      "Ultimate SFX Bundle - HD Remaster/Gore Sounds Pro/Head exploding/Head exploding 1.wav",
      "Ultimate SFX Bundle - HD Remaster/Gore Sounds Pro/Head exploding/Head exploding 2.wav",
    },
    ["vol"] = 1.6,
    ["width"] = 0.7,
  },
  ["orb_clack"] = {
    ["files"] = {
      "assets/sfx/orb_clack_1.ogg",
    },
    ["reverb"] = 0.3,
    ["src"] = {
      "soundeffect-lab/various/glass1__clink-glasses-toast.ogg",
    },
    ["vol"] = 0.35,
  },
  ["orb_hover"] = {
    ["candidates"] = {
      "Gamemaster Audio - Pro Sound Collection/Backgrounds/background_wind_chimes_loop.wav",
    },
    ["reverb"] = 0.15,
    ["unsure"] = true,
  },
  ["power_lost"] = {
    ["candidates"] = {
      "Pixel Magic Sound Effects Pack/PM_ELEM_Dark03_Dispel.wav",
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Light Magic/RPG3_LightMagic_Debuff01.wav",
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Light Magic/RPG3_LightMagic_Debuff02.wav",
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Light Magic/RPG3_LightMagic_Debuff03.wav",
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Light Magic/RPG3_LightMagic_Debuff04.wav",
    },
    ["reverb"] = 0.4,
    ["unsure"] = true,
  },
  ["rock_hit"] = {
    ["files"] = {
      "assets/sfx/rock_hit_1.ogg",
      "assets/sfx/rock_hit_2.ogg",
      "assets/sfx/rock_hit_3.ogg",
      "assets/sfx/rock_hit_4.ogg",
    },
    ["per"] = {
      ["assets/sfx/rock_hit_1.ogg"] = {
        ["sr"] = 4,
        ["vol"] = 0.65,
      },
      ["assets/sfx/rock_hit_2.ogg"] = {
        ["sr"] = 4,
        ["vol"] = 0.65,
      },
      ["assets/sfx/rock_hit_3.ogg"] = {
        ["sr"] = 4,
        ["vol"] = 0.65,
      },
      ["assets/sfx/rock_hit_4.ogg"] = {
        ["sr"] = 4,
        ["vol"] = 0.65,
      },
    },
    ["reverb"] = 0.45,
    ["rolloff"] = 0.7,
    ["src"] = {
      "Gamemaster Audio - Pro Sound Collection/Impacts_Smashable/rock_impact_heavy_slam_01.wav",
      "Gamemaster Audio - Pro Sound Collection/Impacts_Smashable/rock_impact_heavy_slam_02.wav",
      "Gamemaster Audio - Pro Sound Collection/Impacts_Smashable/rock_impact_heavy_slam_03.wav",
      "Gamemaster Audio - Pro Sound Collection/Impacts_Smashable/rock_impact_heavy_slam_04.wav",
    },
    ["vol"] = 0.75,
  },
  ["rock_hold"] = {
    ["candidates"] = {
      "Gamemaster Audio - Pro Sound Collection/Impacts_Smashable/rock_avalanche_landslide_debris_01.wav",
      "Pixel Magic Sound Effects Pack/PM_ELEM_Earth01_Boulder_Impact_Heavy.wav",
    },
    ["reverb"] = 0.15,
    ["unsure"] = true,
  },
  ["rock_land"] = {
    ["files"] = {
      "assets/sfx/rock_land_1.ogg",
      "assets/sfx/rock_land_2.ogg",
      "assets/sfx/rock_land_3.ogg",
    },
    ["reverb"] = 0.4,
    ["src"] = {
      "Gamemaster Audio - Pro Sound Collection/Impacts_Smashable/rock_smashable_hit_impact_01.wav",
      "Gamemaster Audio - Pro Sound Collection/Impacts_Smashable/rock_smashable_hit_impact_02.wav",
      "Gamemaster Audio - Pro Sound Collection/Impacts_Smashable/rock_smashable_hit_impact_03.wav",
    },
    ["vol"] = 0.64,
  },
  ["rock_lift"] = {
    ["files"] = {
      "assets/sfx/lift_cast_4.ogg",
    },
    ["lay"] = {
      ["1"] = {
        ["all"] = true,
      },
    },
    ["per"] = {
      ["assets/sfx/lift_cast_4.ogg"] = {
        ["sr"] = 3,
        ["vol"] = 0.5,
      },
    },
    ["reverb"] = 0.35,
    ["src"] = {
      "Pixel Magic Sound Effects Pack/PM_SPELL_Cast14_Gravity_Ball.wav",
    },
    ["vol"] = 0.6,
  },
  ["rock_rip"] = {
    ["files"] = {
      "assets/sfx/rock_rip_1.ogg",
      "assets/sfx/rock_rip_2.ogg",
    },
    ["reverb"] = 0.4,
    ["rolloff"] = 0.7,
    ["src"] = {
      "Gamemaster Audio - Pro Sound Collection/Impacts_Smashable/rock_smashable_falling_debris_02.wav",
      "Gamemaster Audio - Pro Sound Collection/Impacts_Smashable/rock_smashable_falling_debris_03.wav",
    },
    ["vol"] = 0.65,
  },
  ["rock_throw"] = {
    ["files"] = {
      "assets/sfx/rock_throw_1.ogg",
      "assets/sfx/rock_throw_2.ogg",
      "assets/sfx/rock_throw_3.ogg",
      "assets/sfx/rock_throw_4.ogg",
    },
    ["reverb"] = 0.3,
    ["src"] = {
      "Gamemaster Audio - Pro Sound Collection/Whooshes/whoosh_slow_deep_01.wav",
      "Gamemaster Audio - Pro Sound Collection/Whooshes/whoosh_slow_deep_02.wav",
      "Gamemaster Audio - Pro Sound Collection/Whooshes/whoosh_slow_deep_04.wav",
      "Gamemaster Audio - Pro Sound Collection/Whooshes/whoosh_slow_deep_08.wav",
    },
    ["vol"] = 0.8,
  },
  ["shaft_hum"] = {
    ["candidates"] = {
      "Gamemaster Audio - Pro Sound Collection/Animals_Nature_Ambiences/cave_ambience_loop_03.wav",
      "Ultimate SFX Bundle (2020)/Magic Sounds Pro/Magical Ambiance/Magical Ambiance Loop 1.wav",
      "Ultimate SFX Bundle (2020)/Magic Sounds Pro/Magical Ambiance/Magical Ambiance Loop 2.wav",
      "Ultimate SFX Bundle (2020)/Magic Sounds Pro/Magical Ambiance/Magical Ambiance Loop 3.wav",
      "Ultimate SFX Bundle (2020)/Magic Sounds Pro/Magical Ambiance/Magical Ambiance Loop 4.wav",
    },
    ["reverb"] = 0.4,
    ["rolloff"] = 0.6,
    ["unsure"] = true,
    ["width"] = 0.6,
  },
  ["snake_ash"] = {
    ["candidates"] = {
      "Ultimate SFX Bundle - HD Remaster/Fire N Flame Sounds/Fire put out 7.wav",
    },
    ["reverb"] = 0.3,
    ["unsure"] = true,
  },
  ["snake_dissolve"] = {
    ["candidates"] = {
      "Pixel Magic Sound Effects Pack/PM_ELEM_Dark06_Gravity_P3_Disappear.wav",
      "Pixel Magic Sound Effects Pack/PM_ELEM_Dark10_P3_Disappear.wav",
      "Universal Sound FX/GLASS/GLASS_Rattle_Many_Fragments_01_stereo.wav",
    },
    ["files"] = {
      "assets/sfx/snake_dissolve_2.ogg",
      "assets/sfx/snake_dissolve_3.ogg",
      "assets/sfx/snake_dissolve_4.ogg",
      "assets/sfx/snake_dissolve_5.ogg",
    },
    ["reverb"] = 0.19,
    ["sr"] = 4,
    ["src"] = {
      "RPG Magic SFX/Basic_Attacks_Impacts/Fire_Swoosh_01.wav",
      "RPG Magic SFX/Basic_Attacks_Impacts/Fire_Swoosh_02.wav",
      "RPG Magic SFX/Basic_Attacks_Impacts/Fire_Swoosh_03.wav",
      "RPG Magic SFX/Basic_Attacks_Impacts/Fire_Swoosh_04.wav",
    },
    ["vol"] = 0.74,
  },
  ["snake_hiss"] = {
    ["files"] = {
      "assets/sfx/snake_hiss_1.ogg",
      "assets/sfx/snake_hiss_2.ogg",
      "assets/sfx/snake_hiss_3.ogg",
      "assets/sfx/snake_hiss_4.ogg",
    },
    ["reverb"] = 0.35,
    ["rolloff"] = 0.6,
    ["src"] = {
      "Ultimate SFX Bundle (2020)/Ultimate Animal Sounds/Snake/Snake Hiss/Snake Hiss 1.wav",
      "Ultimate SFX Bundle (2020)/Ultimate Animal Sounds/Snake/Snake Hiss/Snake Hiss 2.wav",
      "Ultimate SFX Bundle (2020)/Ultimate Animal Sounds/Snake/Snake Hiss/Snake Hiss 4.wav",
      "Ultimate SFX Bundle (2020)/Ultimate Animal Sounds/Snake/Snake Hiss/Snake Hiss 5.wav",
    },
    ["vol"] = 0.55,
  },
  ["snake_slither"] = {
    ["files"] = {
      "assets/sfx/snake_slither_1.ogg",
    },
    ["reverb"] = 0.1,
    ["sr"] = 4,
    ["src"] = {
      "Ultimate SFX Bundle (2020)/Ultimate Animal Sounds/Snake/Snake Crawling/Snake Crawling 2.wav",
    },
    ["vol"] = 0.6,
    ["width"] = 0.5,
  },
  ["snake_strike"] = {
    ["files"] = {
      "assets/sfx/snake_strike_1.ogg",
      "assets/sfx/snake_strike_2.ogg",
      "assets/sfx/snake_strike_3.ogg",
    },
    ["per"] = {
      ["assets/sfx/snake_strike_3.ogg"] = {
        ["sr"] = 4,
        ["vol"] = 0.65,
      },
    },
    ["reverb"] = 0.25,
    ["src"] = {
      "Ultimate SFX Bundle (2020)/Ultimate Animal Sounds/Snake/Snake Attacks/Snake Attacks 1.wav",
      "Ultimate SFX Bundle (2020)/Ultimate Animal Sounds/Snake/Snake Attacks/Snake Attacks 2.wav",
      "Ultimate SFX Bundle (2020)/Ultimate Animal Sounds/Snake/Snake Attacks/Snake Attacks 4.wav",
    },
    ["vol"] = 0.75,
  },
  ["ui_click"] = {
    ["files"] = {
      "assets/sfx/ui_click_5.ogg",
    },
    ["per"] = {
      ["assets/sfx/ui_click_5.ogg"] = {
        ["sr"] = 4,
        ["vol"] = 0.6,
      },
    },
    ["reverb"] = 0,
    ["src"] = {
      "Ultimate SFX Bundle (2020)/Magic Sounds Pro/Magical UI Sounds/Click.wav",
    },
    ["vol"] = 0.5,
  },
  ["ui_hover"] = {
    ["reverb"] = 0,
    ["sr"] = 4,
    ["vol"] = 0.55,
  },
  ["unlock_burst"] = {
    ["candidates"] = {
      "Universal Sound FX/GLASS/GLASS_Rattle_Many_Fragments_01_stereo.wav",
      "Gamemaster Audio - Pro Sound Collection/Magic_Spells/ice_spell_impact_shatter_01.wav",
      "Gamemaster Audio - Pro Sound Collection/Impacts_Smashable/glass_smashable_small_break_01.wav",
      "Gamemaster Audio - Pro Sound Collection/Collectibles_Items_Powerup/collect_item_sparkle_pop_08.wav",
      "Gamemaster Audio - Pro Sound Collection/Collectibles_Items_Powerup/coin_bag_ring_gemstone_item_01.wav",
      "Gamemaster Audio - Pro Sound Collection/Collectibles_Items_Powerup/chime_bell_positive_ring_01.wav",
    },
    ["unsure"] = true,
  },
  ["unlock_final"] = {
    ["candidates"] = {
      "SFX_Collection/WAV/Interface Musical Sounds/OrchestralCasual_Accomplishment_01.wav",
      "Gamemaster Audio - Pro Sound Collection/Collectibles_Items_Powerup/collect_item_jingle_04.wav",
      "SFX_Collection/WAV/Interface Musical Sounds/HarpSounds_HarpPoints_02.wav",
      "Ultimate SFX Bundle (2020)/UI & Item Sounds/Win sound/Win sound 5.wav",
      "SFX_Collection/WAV/Interface Musical Sounds/OrchestralFantasy_FantasyWin_01.wav",
    },
    ["unsure"] = true,
  },
  ["unlock_lift"] = {
    ["candidates"] = {
      "Pixel Magic Sound Effects Pack/PM_ELEM_Dark06_Gravity_P1_Cast.wav",
      "Pixel Magic Sound Effects Pack/PM_SPELL_Cast14_Gravity_Ball.wav",
      "Gamemaster Audio - Pro Sound Collection/Magic_Spells/casting_charge_whoosh_buildup3.wav",
      "Gamemaster Audio - Pro Sound Collection/Magic_Spells/casting_charge_whoosh_buildup6.wav",
      "Gamemaster Audio - Pro Sound Collection/Magic_Spells/magic_shinny_high_tone_05.wav",
    },
    ["unsure"] = true,
  },
  ["unlock_pour"] = {
    ["candidates"] = {
      "Gamemaster Audio - Pro Sound Collection/Magic_Spells/magic_shine_light_spell_05.wav",
      "SFX_Collection/WAV/Coins & Chest/Chest_Gems_Opening_02.wav",
      "Gamemaster Audio - Pro Sound Collection/Magic_Spells/chimes_magical_bells_02.wav",
      "Ultimate SFX Bundle (2020)/UI & Item Sounds/Prize wheel spin/Prize wheel spin 3.wav",
      "SFX_Collection/WAV/Interface Musical Sounds/Magical_MagicDiscovery_01.wav",
      "Gamemaster Audio - Pro Sound Collection/Magic_Spells/magic_pop_open_01.wav",
    },
    ["unsure"] = true,
  },
  ["unlock_sweep"] = {
    ["candidates"] = {
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Wind Magic/RPG3_WindMagicMisc_LowGust01.wav",
      "Pixel Magic Sound Effects Pack/PM_ELEM_Wind01_Gust.wav",
      "RPG Magic Sound Effects Pack 3 [ELEMENTAL]/Wind Magic/RPG3_WindMagicMisc_Dark01.wav",
      "Gamemaster Audio - Pro Sound Collection/Magic_Spells/nature_spell_vines_whoosh_01.wav",
    },
    ["unsure"] = true,
  },
  ["viewer_close"] = {
    ["files"] = {
      "assets/sfx/viewer_close_4.ogg",
    },
    ["reverb"] = 0.05,
    ["sr"] = 4,
    ["src"] = {
      "Ultimate SFX Bundle (2020)/Magic Sounds Pro/Magical UI Sounds/Switch 3.wav",
    },
    ["vol"] = 0.55,
  },
  ["viewer_next"] = {
    ["files"] = {
      "assets/sfx/viewer_next_1.ogg",
    },
    ["reverb"] = 0.05,
    ["src"] = {
      "SFX_Collection/WAV/Inventory_SFX/UI_Magic_Click.wav",
    },
    ["vol"] = 0.4,
  },
  ["viewer_open"] = {
    ["files"] = {
      "assets/sfx/viewer_open_3.ogg",
    },
    ["reverb"] = 0.05,
    ["sr"] = 4,
    ["src"] = {
      "SFX_Collection/WAV/Cute Magic Spells Sounds/Whoosh_01.wav",
    },
    ["vol"] = 0.5,
  },
  ["viewer_throw"] = {
    ["candidates"] = {
      "Ultimate SFX Bundle (2020)/Magic Sounds Pro/Magical Swooshes/Magical Swoosh 2.wav",
      "Pixel Magic Sound Effects Pack/PM_ELEM_Dark03_Dispel.wav",
    },
    ["reverb"] = 0.35,
    ["unsure"] = true,
  },
}
