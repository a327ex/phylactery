# Lich Survivors: look references, 22 images

You are working under a brief written by Claude (Opus 5.5), directing this session for the
owner. Where the brief is silent, choose; where it is wrong or a step reaches outside the
frame, stop and report. Do not commit, push, or touch files outside your output folder.
End with the report format given.

## What this is

A 3D game's final scene: a dark cave, a single narrow shaft of sunlight falling from a hole
in the ceiling onto a pale egg on the floor, a floating lich before it, and snakes coming out
of the dark toward the egg. We are about to build the 3D models and the lighting, and the
owner wants them realistic and aesthetic, not cartoonish or "videogamey". These images are
LOOK REFERENCES the owner will choose from; they are not final art. Photographic realism is
the goal in every image (as if photographed, or a high-end film still), with natural light
only.

The attached image is the owner's existing cover for this scene. Use it for colour and mood
only: near-black rock with warm bronze where light grazes it, a cream-yellow shaft, a pale
egg in a pool of light, dark snakes. Do not copy its composition.

## Set 1: the lich, `lich/01.png` .. `lich/08.png`

A realistic, anatomically accurate human skeleton, complete (skull with jaw and teeth, full
ribcage, spine, pelvis, arms with hands and fingers, legs with feet), floating upright a
little above the ground, leaning slightly forward, arms reaching gently forward. No robe, no
cloth, no crown, no flesh: bones only. Its bones are PRISMATIC LIKE A GEM: where light
strikes them they throw spectral colour the way a diamond, opal or cut quartz does, and
which parts glow changes with how the light hits them. Away from the light they are quiet
and pale, never neon, never uniformly rainbow-coloured. Setting: the dark cave, lit by the
warm shaft from above.

Vary the reading of "prismatic bone" across the eight:
1. Pale ivory bone; diamond-like spectral glints (fire) only on edges and ridges the light
   strikes.
2. Bones of translucent clear quartz, refracting the shaft into small rainbows inside them.
3. Opal bone: milky white with play-of-colour flashes that shift with angle.
4. Mother-of-pearl / nacre bone: soft iridescent sheen, pink-green-blue where lit.
5. White bone with a faint rainbow glow inside the thin parts (ribs, fingers) where light
   passes through them.
6. Faceted gem bone: very subtly faceted surfaces, each facet flashing a different spectral
   colour where lit.
7. The lich half inside the shaft of light and half outside: show how the lit half fires with
   colour and the shadowed half stays pale and dim (any material from 1-6 you judge best).
8. Close-up of the skull and shoulders in the light (same material as 7).

## Set 2: the snakes, `snake/01.png` .. `snake/08.png`

Realistic snakes in that dark cave, lit only by the warm shaft (and the light it bounces off
the floor). One species per image, whole body and head visible, part of the body still
emerging from shadow, the head raised or approaching:
1. Reticulated python  2. Burmese python, dark morph  3. Black mamba  4. King cobra, hood
lowered  5. Gaboon viper  6. Eastern diamondback rattlesnake  7. Black rat snake
8. A large dark boa constrictor.
Nature-documentary realism: correct scale patterns, eyes, head shape, body thickness.

## Set 3: the cave, `cave/01.png` .. `cave/06.png`

Real cave interiors lit by ONE shaft of sunlight through a narrow opening in the ceiling onto
the floor, with soft light bounced from that bright pool revealing the surrounding rock,
falling to darkness at the edges. Rough floors with rock formations, not flat ground.
1. A dry cenote-like chamber.  2. A limestone cavern with stalagmites and rock formations
across the floor.  3. A lava tube lit through a skylight.  4. A chamber of dark fractured
rock with broken slabs and boulders.  5. Scene 2 seen from high above, looking steeply down
at the pool of light (about 60 degrees down).  6. A close view of the beam with dust in it
and the lit floor.
No egg, no creatures, no people in this set.

## Constraints

- No people, no text or lettering, no gore, nothing explicit.
- Landscape aspect (3:2 or 16:9), whatever sizes the tool offers.
- If a generation is refused, rephrase ONCE toward a less literal version, then move on and
  record it.

## Frame

**Do not search the filesystem.** No `find`, no `grep`, no recursive `ls`, no globbing
outside your output folder. Read nothing but this brief and the attached image. Use only the
image generation tool: no other network activity, no downloads, no drawing images with
code. Write everything under `reference/astra-r02/` (relative to your working directory),
copying each image there as soon as it is generated. Also write
`reference/astra-r02/prompts.md` (the exact prompt of every generation, retries included) and
`reference/astra-r02/captions.json` (a JSON object mapping `"lich/01"` etc. to one sentence on
what the image shows).

## Report format

Your final message: every file with its pixel size; which generations were refused or
failed after the retry; nothing else.
