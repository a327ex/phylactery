"""sfx_spec.py -- my first sound picks for Lich Survivors (2026-10-10, "Lich Survivors 13"), resolved into
tools/sfx_picks.json for tools/sfx_bake.py.

How I picked, since I can't hear (megablock 1's way, which held up): names first (his packs are labelled
precisely), one source family per kind of thing so its sounds belong together, and numbers for the rest
(scratch/snd/measure.py: length, attack, decay, brightness, low end, noise, loop seam). Where nothing in the packs
is named for the moment (the abstract powers: the leak's warped air, the lift's hold, his floating presence, the
sacrifice in the viewer...), the slot gets NO file: `unsure`, shown red in the game, with `candidates` for him to
audition in the editor.

Each entry: files = substring patterns, each matching exactly one path in scratch/snd/index.txt (checked);
vol evens out the packs' levels (they peak anywhere from 0 to -33 dBFS); why = the reason, kept in the json.

  python tools/sfx_spec.py     # writes tools/sfx_picks.json (fails on a pattern that matches 0 or 2+ files)
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
INDEX = os.path.join(HERE, '..', 'scratch', 'snd', 'index.txt')

UA = 'Ultimate SFX Bundle - HD Remaster/'
U20 = 'Ultimate SFX Bundle (2020)/'
GM = 'Gamemaster Audio - Pro Sound Collection/'
UNI = 'Universal Sound FX/'
PM = 'Pixel Magic Sound Effects Pack/'
R3 = 'RPG Magic Sound Effects Pack 3 [ELEMENTAL]/'
SFX = 'SFX_Collection/WAV/'

SPEC = {
    # ---------------------------------------------------------------- the cave
    'cave_amb': dict(files=[GM + 'Animals_Nature_Ambiences/cave_ambience_loop_04.wav'], vol=0.55,
        why='a designed cave loop: a low drone (half its energy under 200 Hz), seam 0.7 dB'),
    'shaft_hum': dict(unsure=True, candidates=[GM + 'Animals_Nature_Ambiences/cave_ambience_loop_03.wav',
        U20 + 'Magic Sounds Pro/Magical Ambiance/'],
        why='the sun shaft has no sound of its own; nothing in the packs is named for it'),
    'egg_shiver': dict(unsure=True, candidates=['soundeffect-lab/various/egg-konkon1__tap-egg-crack.ogg',
        UNI + 'BREAKS_SNAPS/BREAK_Subtle_stereo.wav'],
        why='the egg trembling now and then: no recording of a trembling egg'),
    # ---------------------------------------------------------------- the lich
    'lich_hover': dict(unsure=True, candidates=[PM + 'PM_ELEM_Dark04_Absorb_P3_Drone.wav',
        UNI + 'CHARGE_UPS_DOWNS/CHARGE_Complex_Wet_12_Semi_Low_Loop_loop_stereo.wav'],
        why='his floating presence: the drones in the packs are named for spells, not a floating body'),
    'lich_hurt': dict(files=[GM + 'Foley/bone_break_neck_snap_crack_01.wav', GM + 'Foley/bone_break_neck_snap_crack_03.wav',
        GM + 'Foley/bone_break_neck_snap_crack_04.wav'], vol=0.45,
        why='a skeleton jolted as a snake grips the egg: bone cracks (short, bright)'),
    'lich_hurt_pose': dict(unsure=True, candidates=['sounddictionary/battle/creaking-muscles-1__creaking-muscles-bone-break.ogg'],
        why='a held strain while he is hurt: unsure a creak reads right under everything else'),
    'lich_die': dict(files=['sounddictionary/battle/skeleton-warrior-bones-1__skeleton-bones-rattle.ogg'], vol=0.9,
        why='he collapses: a skeleton\'s bones rattling'),
    'lich_thud': dict(unsure=True, candidates=[GM + 'Impacts_Smashable/rock_impact_small_hit_01.wav',
        'soundeffect-lab/various/cup-put1__set-down-ceramic-bowl.ogg'],
        why='his bones landing on stone: nothing recorded for bones falling'),
    'mask_drop': dict(files=['soundeffect-lab/various/cup-put1__set-down-ceramic-bowl.ogg',
        SFX + 'Inventory_SFX/Ceramic_Barrel_Close.wav'], vol=0.8,
        why='his mask is porcelain: ceramic set down / closed'),
    # ---------------------------------------------------------------- the snakes
    'snake_hiss': dict(files=[U20 + 'Ultimate Animal Sounds/Snake/Snake Hiss/Snake Hiss 1.wav',
        U20 + 'Ultimate Animal Sounds/Snake/Snake Hiss/Snake Hiss 2.wav', U20 + 'Ultimate Animal Sounds/Snake/Snake Hiss/Snake Hiss 4.wav',
        U20 + 'Ultimate Animal Sounds/Snake/Snake Hiss/Snake Hiss 5.wav'], vol=0.55,
        why='a snake comes into the room: real snake hisses (not the voice impersonations)'),
    'snake_slither': dict(files=[U20 + 'Ultimate Animal Sounds/Snake/Snake Crawling/Snake Crawling 2.wav'], vol=0.6,
        why='scales over stone, one shared loop at the nearest crawling snake: real crawling, the seam is clean (-0.1 dB)'),
    'snake_strike': dict(files=[U20 + 'Ultimate Animal Sounds/Snake/Snake Attacks/Snake Attacks 1.wav',
        U20 + 'Ultimate Animal Sounds/Snake/Snake Attacks/Snake Attacks 2.wav', U20 + 'Ultimate Animal Sounds/Snake/Snake Attacks/Snake Attacks 4.wav'],
        vol=0.75, why='a snake reaches the egg: real snake strikes'),
    'coil_grip': dict(unsure=True, candidates=[U20 + 'Ultimate Animal Sounds/Snake/Snake Attacks/Snake Attacks 3.wav',
        UNI + 'BREAKS_SNAPS/BREAK_Squishy_stereo.wav'],
        why='its head takes hold of the shell: a grip has no clear recording'),
    'coil_squeeze': dict(files=[U20 + 'Ultimate Animal Sounds/Snake/Snake Crawling/Snake Crawling 4.wav'], vol=0.7,
        why='the coils turning round the egg, louder as they cover it: scales rubbing (crawling, seam -3 dB)'),
    'coil_win': dict(unsure=True, candidates=[],
        why='the egg is covered: the turn of the whole game; what it should sound like is his'),
    'snake_dissolve': dict(unsure=True, candidates=[PM + 'PM_ELEM_Dark06_Gravity_P3_Disappear.wav',
        PM + 'PM_ELEM_Dark10_P3_Disappear.wav', UNI + 'GLASS/GLASS_Rattle_Many_Fragments_01_stereo.wav'],
        why='the leak takes a snake apart into warped air with a glassy edge: nothing is named for it'),
    'snake_ash': dict(unsure=True, candidates=[UA + 'Fire N Flame Sounds/Fire put out 7.wav'],
        why='a burned snake falling to ash'),
    # ---------------------------------------------------------------- fire
    'fire_cast': dict(files=[UA + 'Fire N Flame Sounds/Flame Whoosh.wav', UA + 'Fire N Flame Sounds/Flame Whoosh 2.wav',
        UA + 'Fire N Flame Sounds/Flame Whoosh 10.wav'], vol=0.9,
        why='the gesture throws fire: low flame whooshes (70-86% under 200 Hz)'),
    'fire_ignite': dict(files=[UA + 'Fire N Flame Sounds/Fire Burst 2.wav', UA + 'Fire N Flame Sounds/Fire Burst 3.wav',
        UA + 'Fire N Flame Sounds/Fire Burst 4.wav'], vol=0.8, why='a snake catches fire: fire bursts'),
    'fire_burn': dict(files=[UA + 'Fire N Flame Sounds/General Fire Loop 6.wav'], vol=0.5,
        why='a snake burning, up to 4 at once: a seamless fire loop with crackle'),
    'fire_sweep': dict(files=[PM + 'PM_ELEM_Fire08_Flamethrower_Loop.wav'], vol=0.7,
        why='the group version: one arm sweep of fire along the floor, a flamethrower loop (seam 0.9 dB)'),
    # ---------------------------------------------------------------- lift
    'lift_cast': dict(files=[PM + 'PM_ELEM_Dark06_Gravity_P1_Cast.wav'], vol=0.6,
        why='he takes hold of snakes from afar: named gravity magic, a pull on the air'),
    'lift_hold': dict(unsure=True, candidates=[UNI + 'CHARGE_UPS_DOWNS/CHARGE_Complex_Wet_12_Semi_Low_Loop_loop_stereo.wav',
        PM + 'PM_ELEM_Dark04_Absorb_P3_Drone.wav'],
        why='a snake held up in the air: a strain without a source; synth loops may not fit the look'),
    'lift_knot': dict(files=[UA + 'Gore Sounds Pro/Ripping guts out of body/Ripping guts out of body 2.wav',
        UA + 'Gore Sounds Pro/Ripping guts out of body/Ripping guts out of body 3.wav'], vol=0.8,
        why='the group curls into a wet ball: guts squelching'),
    'lift_swell': dict(unsure=True, candidates=[UNI + 'CHARGE_UPS_DOWNS/CHARGE_Complex_Wet_12_Semi_Up_1000ms_stereo.wav'],
        why='the pressure just before the burst: the risers in the packs are synth, maybe not this game'),
    'lift_fist': dict(files=[GM + 'Foley/bone_break_neck_snap_crack_02.wav', GM + 'Foley/bone_break_neck_snap_crack_04.wav'],
        vol=0.5, why='his bone hand curls into a fist: knuckle cracks'),
    'lift_burst': dict(files=[UA + 'Gore Sounds Pro/Head exploding/Head exploding 1.wav', UA + 'Gore Sounds Pro/Head exploding/Head exploding 2.wav',
        UA + 'Gore Sounds Pro/Head exploding/Head exploding 3.wav', UA + 'Gore Sounds Pro/Head exploding/Head exploding 4.wav'], vol=1.2,
        why='the lifted snakes burst: wet and low (70-83% under 200 Hz), about a second'),
    # ---------------------------------------------------------------- gore
    'gore_crush': dict(files=[UA + 'Gore Sounds Pro/Bloody Axe Impact/Bloody Axe Impact 2.wav', UA + 'Gore Sounds Pro/Bloody Axe Impact/Bloody Axe Impact 3.wav',
        UA + 'Gore Sounds Pro/Bloody Axe Impact/Bloody Axe Impact 5.wav', UA + 'Gore Sounds Pro/Bloody Axe Impact/Bloody Axe Impact 8.wav'], vol=0.8,
        why='a rock crushes a snake: wet heavy impacts'),
    'gore_land': dict(files=[UNI + 'GORE_SPLATS/GORE_Splat_L_Ground_01_mono.wav', UNI + 'GORE_SPLATS/GORE_Splat_L_Ground_02_mono.wav',
        UNI + 'GORE_SPLATS/GORE_Splat_Hit_Short_mono.wav'], vol=0.45,
        why='torn pieces landing on the floor (a few per burst): splats on the ground'),
    'mass_burst': dict(files=[UA + 'Gore Sounds Pro/Head exploding/Head exploding 1.wav', UA + 'Gore Sounds Pro/Head exploding/Head exploding 2.wav'],
        vol=1.6, why='every snake on the egg bursts as he dies: the biggest wet bursts, once'),
    # ---------------------------------------------------------------- rock
    'rock_rip': dict(files=[GM + 'Impacts_Smashable/rock_smashable_falling_debris_02.wav', GM + 'Impacts_Smashable/rock_smashable_falling_debris_03.wav'],
        vol=0.65, why='a rock torn out of the floor by his mind: cracking stone and debris'),
    'rock_hold': dict(unsure=True, candidates=[GM + 'Impacts_Smashable/rock_avalanche_landslide_debris_01.wav',
        PM + 'PM_ELEM_Earth01_Boulder_Impact_Heavy.wav'],
        why='a stone held up by a mind: a grinding hum, nothing named for it'),
    'rock_throw': dict(files=[GM + 'Whooshes/whoosh_slow_deep_01.wav', GM + 'Whooshes/whoosh_slow_deep_02.wav',
        GM + 'Whooshes/whoosh_slow_deep_04.wav', GM + 'Whooshes/whoosh_slow_deep_08.wav'], vol=0.8,
        why='the rock is thrown: slow deep whooshes (about a second)'),
    'rock_hit': dict(files=[GM + 'Impacts_Smashable/rock_impact_heavy_slam_01.wav', GM + 'Impacts_Smashable/rock_impact_heavy_slam_02.wav',
        GM + 'Impacts_Smashable/rock_impact_heavy_slam_03.wav', GM + 'Impacts_Smashable/rock_impact_heavy_slam_04.wav'], vol=0.85,
        why='the rock hits a snake: heavy stone slams (93-98% under 200 Hz)'),
    'rock_land': dict(files=[GM + 'Impacts_Smashable/rock_smashable_hit_impact_01.wav', GM + 'Impacts_Smashable/rock_smashable_hit_impact_02.wav',
        GM + 'Impacts_Smashable/rock_smashable_hit_impact_03.wav'], vol=0.6, why='the rock lands and bounces: stone on stone'),
    # ---------------------------------------------------------------- leak
    'leak_whisper': dict(unsure=True, candidates=[R3 + 'Wind Magic/RPG3_WindMagicMisc_Dark', PM + 'PM_ELEM_Dark04_Absorb_P3_Drone.wav'],
        why='the leak around his skull while it is his: warped air, nothing named for it'),
    'leak_ripple': dict(unsure=True, candidates=[R3 + 'Wind Magic/RPG3_WindMagicMisc_LowGust'],
        why='a ring of warped air rolling out from him every two seconds'),
    'leak_snake': dict(unsure=True, candidates=[UA + 'Fire N Flame Sounds/Sizzle 6.wav', UA + 'Fire N Flame Sounds/Sizzle 2.wav'],
        why='a snake coming apart ring by ring: a sizzle may read as fire'),
    # ---------------------------------------------------------------- beam
    'beam_cast': dict(files=[R3 + 'Light Magic/RPG3_LightMagic2_Projectile01.wav', R3 + 'Light Magic/RPG3_LightMagic2_Projectile02.wav',
        R3 + 'Light Magic/RPG3_LightMagic2_Projectile03.wav'], vol=0.75,
        why='the prismatic beam leaves his finger: light-magic projectiles'),
    'beam_channel': dict(files=[SFX + 'Farm/Event_PreciousCrystalRinging_Loop.wav'], vol=3.0,
        why='while the beam is held: a ringing crystal loop (seam -0.4 dB; quiet in the pack, -33 dBFS)'),
    'beam_shot': dict(files=[R3 + 'Light Magic/RPG3_LightMagic2_LightImpact01.wav', R3 + 'Light Magic/RPG3_LightMagic2_LightImpact02.wav',
        R3 + 'Light Magic/RPG3_LightMagic2_LightImpact03.wav'], vol=0.8,
        why='the group version, revolver shots: shorter, harder light-magic hits'),
    'beam_bite': dict(files=[UA + 'Gore Sounds Pro/Needle piercing flesh/Needle piercing flesh 1.wav',
        UA + 'Gore Sounds Pro/Needle piercing flesh/Needle piercing flesh 2.wav'], vol=0.55,
        why='the beam bites into a snake: flesh pierced'),
    'beam_shatter': dict(files=[GM + 'Impacts_Smashable/glass_smashable_small_break_01.wav', GM + 'Impacts_Smashable/glass_smashable_small_break_02.wav',
        GM + 'Impacts_Smashable/glass_smashable_small_break_03.wav'], vol=0.75,
        why='a beamed snake bursts into streaks and glass petals: small glass breaks'),
    'beam_petals': dict(files=[UNI + 'GLASS/GLASS_Fragment_01_mono.wav', UNI + 'GLASS/GLASS_Fragment_04_mono.wav',
        UNI + 'GLASS/GLASS_Fragment_10_mono.wav', UNI + 'GLASS/GLASS_Fragment_13_mono.wav'], vol=0.3,
        why='glass petals rising: single glass fragments, quiet'),
    # ---------------------------------------------------------------- lens
    'lens_form': dict(files=['RPG Magic SFX 2/Se-uk_Jeong_Spells_SFX_[Video_Demo_3]/Ice_Crystal_Buff_Cast.wav',
        PM + 'PM_ELEM_Ice05_Crystal_Buff.wav'], vol=0.7, why='the glass lens forms high in the shaft: crystal forming'),
    'lens_charge': dict(unsure=True, candidates=[UNI + 'CHARGE_UPS_DOWNS/CHARGE_Complex_Wet_12_Semi_Up_2000ms_stereo.wav'],
        why='(was lens_focus) the lens charging, right after it forms, while its light gathers: a riser; the packs\' are synth'),
    'lens_fire': dict(files=[UA + 'Fire N Flame Sounds/Blow Torch Loop.wav'], vol=2.0,
        why='the focused light cutting: a blowtorch loop (seam -0.5 dB)'),
    'lens_cut': dict(files=[UA + 'Gore Sounds Pro/Ripping flesh/Ripping flesh 1.wav', UA + 'Gore Sounds Pro/Ripping flesh/Ripping flesh 3.wav',
        UA + 'Gore Sounds Pro/Ripping flesh/Ripping flesh 8.wav'], vol=0.65, why='the cut goes through a snake: flesh ripping'),
    'lens_dissolve': dict(unsure=True, candidates=[UNI + 'GLASS/GLASS_Rattle_Many_Fragments_01_stereo.wav'],
        why='the lens fading back into light'),
    # ---------------------------------------------------------------- the objects
    'item_throw': dict(files=[UNI + 'WHOOSHES/Air/WHOOSH_Air_Blade_RR1_mono.wav', UNI + 'WHOOSHES/Air/WHOOSH_Air_Blade_RR2_mono.wav',
        UNI + 'WHOOSHES/Air/WHOOSH_Air_Blade_RR3_mono.wav'], vol=0.7, why='an object thrown from his hand: air whooshes'),
    'item_land_mask': dict(files=['soundeffect-lab/various/cup-put1__set-down-ceramic-bowl.ogg', SFX + 'Inventory_SFX/Ceramic_Barrel_Close.wav'],
        vol=0.8, why='the burned mask (sooted porcelain) lands: ceramic'),
    'item_land_hand': dict(files=[SFX + 'Inventory_SFX/Armour_Plate_Equipment_Drop.wav'], vol=0.7,
        why='the bronze votive hand lands: metal dropped'),
    'item_land_lodestone': dict(files=[GM + 'Impacts_Smashable/rock_impact_small_hit_01.wav', GM + 'Impacts_Smashable/rock_impact_small_hit_02.wav',
        GM + 'Impacts_Smashable/rock_impact_small_hit_03.wav'], vol=0.8, why='the lodestone lands: small stone hits'),
    'item_land_orbs': dict(files=[UNI + 'GLASS/GLASS_Tap_mono.wav', 'soundeffect-lab/various/glass1__clink-glasses-toast.ogg'], vol=0.6,
        why='the glass orbs land: glass taps'),
    'item_land_gem': dict(files=[SFX + 'Farm/Hit_CrystalMineral_01.wav', SFX + 'Farm/Hit_CrystalMineral_02.wav',
        SFX + 'Farm/Hit_CrystalMineral_03.wav'], vol=0.6, why='the gem lands: a crystal mineral struck'),
    'item_land_lens': dict(files=[UNI + 'GLASS/GLASS_Tap_mono.wav'], vol=0.7, why='the lens lands: glass tapped'),
    'orb_clack': dict(files=['soundeffect-lab/various/glass1__clink-glasses-toast.ogg'], vol=0.35,
        why='the orbs knock into each other: glasses clinking'),
    'item_pickup': dict(files=[SFX + 'Inventory_SFX/Items_Random_Item_Grab_01.wav', SFX + 'Inventory_SFX/Items_Random_Item_Grab_02.wav'], vol=0.7,
        why='he takes an object back: an item grabbed'),
    'orb_hover': dict(unsure=True, candidates=[GM + 'Backgrounds/background_wind_chimes_loop.wav'],
        why='the orbs circling him: a quiet glassy presence, unsure anything fits'),
    # ---------------------------------------------------------------- the interface
    'ui_hover': dict(files=[UA + 'Modern UI Sounds - HD Remake/Clicks Sound (button hover) 1.wav',
        UA + 'Modern UI Sounds - HD Remake/Clicks Sound (button hover) 2.wav'], vol=0.35,
        why='the cursor over an object in the inventory or a button: named button-hover clicks'),
    'ui_click': dict(files=[SFX + 'Inventory_SFX/UI_Magic_Click'], vol=0.5, why='an object in the inventory clicked'),
    'viewer_open': dict(files=[U20 + 'Magic Sounds Pro/Magical Swooshes/Magical Swoosh 1.wav', U20 + 'Magic Sounds Pro/Magical Swooshes/Magical Swoosh 10.wav'],
        vol=0.5, why='the viewer comes up: magical swooshes'),
    'viewer_close': dict(files=[U20 + 'Magic Sounds Pro/Magical Swooshes/Magical Swoosh 11.wav', U20 + 'Magic Sounds Pro/Magical Swooshes/Magical Swoosh 12.wav'],
        vol=0.4, why='the viewer goes away: magical swooshes'),
    'viewer_next': dict(files=[SFX + 'Inventory_SFX/UI_Magic_Click'], vol=0.4, why='the next object in the viewer'),
    'viewer_throw': dict(unsure=True, candidates=[U20 + 'Magic Sounds Pro/Magical Swooshes/Magical Swoosh 2.wav',
        PM + 'PM_ELEM_Dark03_Dispel.wav'], why='THROW: giving up a power for good; what that should sound like is his'),
    'power_lost': dict(unsure=True, candidates=[PM + 'PM_ELEM_Dark03_Dispel.wav', R3 + 'Light Magic/RPG3_LightMagic_Debuff'],
        why='a power gone from him (its slot goes dark)'),
    # ---------------------------------------------------------------- the ending
    'ending_begin': dict(unsure=True, candidates=[UNI + 'CHARGE_UPS_DOWNS/CHARGE_Complex_Wet_12_Semi_Down_8000ms_stereo.wav'],
        why='the first grip: control ends, the world darkens; his call'),
    'egg_knock': dict(files=['soundeffect-lab/various/egg-konkon1__tap-egg-crack.ogg'], vol=0.9,
        why='knocks from inside the egg, faster and faster: an egg tapped (short, so the fast ones don\'t smear)'),
    'egg_crack': dict(files=['soundeffect-lab/various/egg-break1__crack-egg-open.ogg', UNI + 'BREAKS_SNAPS/CRACK_Bright_Crisp_01_mono.wav',
        UNI + 'BREAKS_SNAPS/CRACK_Bright_Crisp_02_mono.wav'], vol=0.9, why='the crack spreads round it: an egg cracked open, crisp cracks'),
    'egg_open': dict(files=[UNI + 'BREAKS_SNAPS/BREAK_Hollow_stereo.wav', UNI + 'BREAKS_SNAPS/BREAK_Crack_stereo.wav'], vol=1.0,
        why='it breaks open, the cap flying: hollow breaks'),
    'egg_piece_land': dict(unsure=True, candidates=['soundeffect-lab/various/cup-put1__set-down-ceramic-bowl.ogg', UNI + 'GLASS/GLASS_Fragment_03_mono.wav'],
        why='shell pieces landing on stone: nothing recorded for eggshell falling'),
}

# The cave's levers per slot (2026-10-11, "Lich Survivors 14"; the editor's 3D fields, written into sound_picks.lua
# with the pick). The ear sits half way down the room camera's line of sight (sound_rooms' cave.ear), ~6.5 m from the
# egg and ~20 m from the far wall, in one stone cave with a long dark tail. What is set here, and why:
#   reverb  how much of it the cave answers (0.25 when unset). Big and hard things ring out (rock, bursts, the egg
#           opening, glass and crystal); loops that run for seconds keep little, or the tail turns to mud under the
#           fight; the inventory and the viewer are not in the cave at all (0); the cave loop is a recording made in a
#           cave, its room already in it (0).
#   width   0 = a point (the default); a big or spread-out thing keeps some of the recording's stereo: every snake
#           bursting at once, the ring of warped air rolling out, the one loop that stands for all crawling snakes.
#   rolloff how fast it fades with distance (1 when unset): the hiss of a snake coming in, and stone slamming, carry
#           across the room (a warning from the far wall must still be heard).
CAVE = {
    # the cave
    'cave_amb': dict(reverb=0),
    'shaft_hum': dict(reverb=0.4, width=0.6, rolloff=0.6),
    'egg_shiver': dict(reverb=0.2),
    # him
    'lich_hover': dict(reverb=0.1),
    'lich_hurt': dict(reverb=0.3),
    'lich_hurt_pose': dict(reverb=0.15),
    'lich_die': dict(reverb=0.5, width=0.3),
    'lich_thud': dict(reverb=0.3),
    'mask_drop': dict(reverb=0.35),
    # the snakes
    'snake_hiss': dict(reverb=0.35, rolloff=0.6),
    'snake_slither': dict(reverb=0.1, width=0.5),
    'snake_strike': dict(reverb=0.25),
    'coil_grip': dict(reverb=0.25),
    'coil_squeeze': dict(reverb=0.1, width=0.4),
    'coil_win': dict(reverb=0.6, width=0.6),
    'snake_ash': dict(reverb=0.3),
    'snake_dissolve': dict(reverb=0.35),
    # fire
    'fire_cast': dict(reverb=0.3),
    'fire_ignite': dict(reverb=0.3),
    'fire_burn': dict(reverb=0.1),
    'fire_sweep': dict(reverb=0.2, width=0.5),
    # gore
    'gore_crush': dict(reverb=0.3),
    'gore_land': dict(reverb=0.15),
    'mass_burst': dict(reverb=0.6, width=0.7),
    # the beam
    'beam_cast': dict(reverb=0.35),
    'beam_channel': dict(reverb=0.3),
    'beam_bite': dict(reverb=0.2),
    'beam_shatter': dict(reverb=0.35),
    'beam_shot': dict(reverb=0.35),
    'beam_petals': dict(reverb=0.4),
    # the objects
    'item_land_gem': dict(reverb=0.2), 'item_land_hand': dict(reverb=0.2), 'item_land_lens': dict(reverb=0.2),
    'item_land_lodestone': dict(reverb=0.2), 'item_land_mask': dict(reverb=0.2), 'item_land_orbs': dict(reverb=0.2),
    'item_pickup': dict(reverb=0.1),
    'item_throw': dict(reverb=0.15),
    'orb_clack': dict(reverb=0.3),
    'orb_hover': dict(reverb=0.15),
    # the leak
    'leak_whisper': dict(reverb=0.2),
    'leak_ripple': dict(reverb=0.45, width=0.6),
    'leak_snake': dict(reverb=0.2),
    # the lens
    'lens_form': dict(reverb=0.45),
    'lens_charge': dict(reverb=0.35),
    'lens_fire': dict(reverb=0.2),
    'lens_cut': dict(reverb=0.2),
    'lens_dissolve': dict(reverb=0.45),
    # the lift
    'lift_cast': dict(reverb=0.35),
    'lift_hold': dict(reverb=0.2),
    'lift_knot': dict(reverb=0.25),
    'lift_swell': dict(reverb=0.45, width=0.5),
    'lift_burst': dict(reverb=0.5, width=0.5),
    'lift_fist': dict(reverb=0.15),
    # the rock
    'rock_rip': dict(reverb=0.4, rolloff=0.7),
    'rock_hold': dict(reverb=0.15),
    'rock_throw': dict(reverb=0.3),
    'rock_hit': dict(reverb=0.45, rolloff=0.7),
    'rock_land': dict(reverb=0.4),
    # the inventory and the viewer (not in the cave)
    'ui_hover': dict(reverb=0), 'ui_click': dict(reverb=0),
    'viewer_open': dict(reverb=0.05), 'viewer_close': dict(reverb=0.05), 'viewer_next': dict(reverb=0.05),
    'viewer_throw': dict(reverb=0.35),
    'power_lost': dict(reverb=0.4),
    # the ending
    'ending_begin': dict(reverb=0.6),
    'egg_knock': dict(reverb=0.3),
    'egg_crack': dict(reverb=0.35),
    'egg_open': dict(reverb=0.5, width=0.4),
    'egg_piece_land': dict(reverb=0.15),
}
CAVE_KEYS = {'reverb', 'width', 'rolloff', 'near', 'far', 'air', 'occlusion', 'doppler', 'travel', 'lowcut'}


def main():
    index = [l.rstrip('\n') for l in open(INDEX, encoding='utf-8')]
    low = [p.lower() for p in index]

    def resolve(pat):
        pl = pat.lower()
        hits = [index[i] for i, p in enumerate(low) if p == pl] or [index[i] for i, p in enumerate(low) if pl in p]
        return hits

    out, bad = {}, []
    for slot, e in SPEC.items():
        rec = {'vol': e.get('vol', 1.0), 'why': e['why']}
        if e.get('unsure'):
            rec['unsure'] = True
            rec['files'] = []
            cands = []
            for pat in e.get('candidates', []):
                hits = resolve(pat)
                if not hits:
                    bad.append(f'{slot}: candidate {pat!r} matches nothing')
                cands.extend(hits[:4])
            rec['candidates'] = cands
        else:
            files = []
            for pat in e['files']:
                hits = resolve(pat)
                if len(hits) != 1:
                    bad.append(f'{slot}: {pat!r} matches {len(hits)} files' + (': ' + '; '.join(hits[:3]) if hits else ''))
                else:
                    files.append(hits[0])
            rec['files'] = files
        for k, v in CAVE.get(slot, {}).items():
            if k not in CAVE_KEYS:
                bad.append(f'{slot}: {k!r} is not a 3D setting')
            rec[k] = v
        out[slot] = rec
    bad += [f'CAVE names {s!r}, which is no slot' for s in CAVE if s not in SPEC]
    if bad:
        print('\n'.join(bad))
        sys.exit(1)
    with open(os.path.join(HERE, 'sfx_picks.json'), 'w', encoding='utf-8') as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    n_unsure = sum(1 for r in out.values() if r.get('unsure'))
    print(f'{len(out)} slots ({len(out) - n_unsure} picked, {n_unsure} unsure), '
          f'{sum(len(r["files"]) for r in out.values())} files')


if __name__ == '__main__':
    main()
