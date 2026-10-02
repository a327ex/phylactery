// layout.mjs -- the walk through the cave, as data: where it runs, how wide and high it is,
// which biome each stretch belongs to, the chambers where the six objects are found, the shafts
// of daylight, and where each object waits.
//
// Owner, 2026-10-02: "For each item, imagine a scene (inside a cave) that fits how the item might
// be acquired ... a walking simulator ... the camera style of Resident Evil games, static cameras
// from different angles per scene ... connections between them, all inside a cave ... varied
// with cave biomes ... ~5 minutes and then we reach the final room with the egg."
//
// The order is a progression of light, from none to the sun on the egg:
//   0 THE WAKING   a small dark chamber of the final room's own brown rock; a warm glow ahead
//   1 FIRE         basalt and ash; lava still glowing in the cracks; the burned mask on a column
//                  where whoever wore it burned
//   2 LIFT         a limestone cathedral under a ceiling of glow-worms; snakes' skeletons hang
//                  from it where they were lifted and burst; the hand rises on a stalagmite, raised
//                  toward them in its gesture
//   3 ROCK         rust-red iron rock; a thin shaft of sun on the lodestone, which floats, and
//                  stones float around it in its field, drifting in and out of the light
//   4 LEAKAGE      a grotto the leakage warped: swollen, twisted rock, pale fungi glowing, a still
//                  black pool; the orbs circle over it and the air bends around them
//   5 BEAM         a crystal grotto; the sun falls through the crystals onto the gem, set in a
//                  cluster, and its colours are thrown over the walls
//   6 LENS         layered sandstone; the lens lies level in a ring of stone in a shaft of sun,
//                  focusing it to a point that has burned the sand to black glass
//   then a passage of the final room's brown rock, its tunnel, the egg.
//
// Coordinates: the final room's (egg at the origin, its tunnel along -z ending at z = -47.5).
// The walk lies beyond, z < -47, its floor descending from the tunnel; it joins the tunnel at
// (0, -47) heading +z. Path nodes: x, z, h (floor height), w (half width at the floor), H (ceiling
// above the floor), area. Chambers are ellipsoids on the path.

export const SUN_DIR = (() => { const x = 0.11, y = 1, z = 0.05, l = Math.hypot(x, y, z); return [x/l, y/l, z/l]; })();
export const SUN_XZ = [SUN_DIR[0]/SUN_DIR[1], SUN_DIR[2]/SUN_DIR[1]];

export const AREAS = [
  { id: 'waking', name: 'THE WAKING', biome: 'brown' },
  { id: 'fire', name: 'THE BURNING', biome: 'basalt', item: 0 },
  { id: 'lift', name: 'THE CATHEDRAL', biome: 'limestone', item: 1 },
  { id: 'rock', name: 'THE FIELD', biome: 'iron', item: 2 },
  { id: 'leak', name: 'THE WARPED POOL', biome: 'warped', item: 3 },
  { id: 'beam', name: 'THE CRYSTALS', biome: 'crystal', item: 4 },
  { id: 'lens', name: 'THE BURNING GLASS', biome: 'sandstone', item: 5 },
  { id: 'approach', name: 'THE APPROACH', biome: 'brown' },
];

// [x, z, h, w, H, area]
export const NODES = [
  // 0 THE WAKING: he wakes against its back wall
  [-81, -199.5, -12.0, 2.6, 4.2, 0],
  [-76, -200.5, -12.0, 3.2, 4.6, 0],
  [-70, -200.0, -12.1, 3.0, 4.4, 0],
  // the first passage: down toward the glow
  [-64, -202.5, -12.6, 2.3, 3.6, 0],
  [-58, -206.0, -13.4, 2.2, 3.5, 0],
  [-52, -207.0, -14.3, 2.3, 3.6, 1],
  [-46, -204.5, -15.3, 2.5, 3.8, 1],
  // 1 FIRE
  [-39, -202.5, -16.0, 3.0, 5.0, 1],
  [-31, -202.0, -16.0, 3.0, 6.0, 1],
  [-23, -203.0, -16.0, 3.0, 5.0, 1],
  // up into the limestone
  [-16, -205.5, -15.6, 2.4, 3.8, 1],
  [-9, -205.0, -14.6, 2.3, 3.6, 1],
  [-2, -201.5, -13.4, 2.4, 3.7, 2],
  [5, -199.0, -12.2, 2.6, 4.0, 2],
  // 2 LIFT
  [12, -199.5, -11.5, 3.0, 6.0, 2],
  [20, -201.0, -11.2, 3.0, 9.0, 2],
  [27, -200.0, -11.0, 3.0, 9.0, 2],
  [32, -194.0, -11.0, 3.0, 6.0, 2],
  // north, climbing into the iron
  [35, -186.0, -10.4, 2.4, 3.8, 2],
  [37, -178.0, -9.6, 2.3, 3.6, 2],
  [39, -170.0, -8.7, 2.3, 3.6, 3],
  [41, -162.0, -7.8, 2.5, 3.9, 3],
  // 3 ROCK
  [42, -155.0, -7.0, 3.0, 5.0, 3],
  [42, -147.0, -7.0, 3.0, 6.0, 3],
  [38, -140.5, -7.0, 3.0, 5.0, 3],
  // west, down toward the pool
  [30, -137.0, -7.4, 2.4, 3.8, 3],
  [22, -137.5, -8.0, 2.3, 3.6, 3],
  [14, -140.0, -8.6, 2.3, 3.6, 4],
  [6, -141.0, -9.0, 2.5, 3.9, 4],
  // 4 LEAKAGE
  [-1, -141.0, -9.0, 3.0, 5.0, 4],
  [-9, -139.5, -9.0, 3.0, 6.0, 4],
  [-17, -136.5, -9.0, 3.0, 5.0, 4],
  // north-west, climbing into the crystals
  [-25, -133.0, -8.4, 2.4, 3.8, 4],
  [-33, -130.5, -7.4, 2.3, 3.6, 4],
  [-41, -129.0, -6.4, 2.3, 3.6, 5],
  [-48, -127.0, -5.6, 2.5, 3.9, 5],
  // 5 BEAM
  [-54, -123.0, -5.0, 3.0, 5.0, 5],
  [-58, -117.0, -5.0, 3.0, 6.0, 5],
  [-57, -110.0, -5.0, 3.0, 5.0, 5],
  // north-east, up into the sandstone
  [-53, -103.0, -4.5, 2.4, 3.8, 5],
  [-47, -97.0, -3.8, 2.3, 3.6, 5],
  [-41, -92.0, -3.1, 2.3, 3.6, 6],
  [-35, -88.5, -2.5, 2.5, 3.9, 6],
  // 6 LENS
  [-29, -85.0, -2.0, 3.0, 5.0, 6],
  [-23, -80.0, -2.0, 3.0, 6.0, 6],
  [-17, -74.0, -2.0, 3.0, 5.0, 6],
  // the approach: the sandstone gives way to the final room's brown rock
  [-11, -68.0, -1.6, 2.4, 3.8, 6],
  [-6, -62.0, -1.1, 2.3, 3.6, 7],
  [-2, -56.0, -0.6, 2.5, 4.0, 7],
  [0, -51.0, null, 2.9, 4.6, 7],     // h = the room's floor (lib room_ground_y)
  [0, -46.5, null, 3.2, 4.8, 7],
];

// chambers: c = [x, z], h = floor, r = [rx, rz], rot (radians, about y), H = dome height
export const CHAMBERS = [
  { area: 0, c: [-75, -200], h: -12.0, r: [7.5, 6.0], rot: 0.1, H: 5.5 },
  { area: 1, c: [-31, -202], h: -16.0, r: [14, 11], rot: -0.05, H: 10 },
  { area: 2, c: [22, -199], h: -11.0, r: [13, 15], rot: 0.3, H: 24 },
  { area: 3, c: [41, -148], h: -7.0, r: [12, 11], rot: 0.5, H: 11 },
  { area: 4, c: [-9, -139], h: -9.0, r: [16, 12], rot: -0.15, H: 9 },
  { area: 5, c: [-57, -117], h: -5.0, r: [13, 13], rot: 0.2, H: 14 },
  { area: 6, c: [-23, -80], h: -2.0, r: [12, 11], rot: 0.7, H: 11 },
];

// shafts of daylight: the point on the floor the sun's centre falls on, its radius, and the
// height of the opening (the sky disc); the column leans with the sun (SUN_XZ per metre)
export const SHAFTS = [
  { area: 0, at: [-79.2, -199.7], r: 0.85, top: 22 },        // a crack of daylight where he wakes
  { area: 0, at: [-59.5, -205.4], r: 0.8, top: 22 },         // and one in the passage down
  { area: 3, at: [38.6, -171.0], r: 0.85, top: 22 },         // the climb from the cathedral
  { area: 4, at: [-31.5, -131.0], r: 0.8, top: 22 },         // the climb out of the warped grotto
  { area: 5, at: [-47.5, -97.5], r: 0.85, top: 22 },         // the climb from the crystals
  { area: 7, at: [-5.2, -60.5], r: 0.8, top: 22 },           // the approach
  { area: 3, at: [43.0, -147.2], r: 1.3, top: 22 },
  { area: 5, at: [-58.6, -116.0], r: 1.7, top: 24 },
  { area: 6, at: [-22.4, -79.6], r: 1.25, top: 22 },
];

// where each object waits (x, z on the floor; the lift above the floor its centre is held at),
// in powers.ALL's order: FIRE (mask), LIFT (hand), ROCK (lodestone), LEAKAGE (orbs), BEAM (gem), LENS
export const ITEMS = [
  { power: 0, area: 1, at: [-31.0, -200.4], lift: 1.25, stand: 'basalt_column' },
  { power: 1, area: 2, at: [22.4, -200.0], lift: 1.45, stand: 'stalagmite' },
  { power: 2, area: 3, at: [43.0, -147.2], lift: 1.35, stand: 'float' },
  { power: 3, area: 4, at: [-9.5, -137.6], lift: 1.30, stand: 'pool' },
  { power: 4, area: 5, at: [-58.6, -116.0], lift: 1.15, stand: 'crystal_cluster' },
  { power: 5, area: 6, at: [-22.4, -79.6], lift: 1.40, stand: 'stone_ring' },
];

// where he wakes, and the way he faces
export const START = { x: -80.0, z: -199.6, yaw: Math.PI/2 };

// The plan above, spread out: every horizontal distance from where the walk meets the tunnel
// scaled by SPREAD (the walk's length; owner: about five minutes to the egg). Heights stay.
export const SPREAD = 1.2;
{
  const ox = 0, oz = -47;
  const sx = x => ox + (x - ox)*SPREAD, sz = z => oz + (z - oz)*SPREAD;
  for (const n of NODES) { n[0] = sx(n[0]); n[1] = sz(n[1]); }
  for (const c of CHAMBERS) c.c = [sx(c.c[0]), sz(c.c[1])];
  for (const s of SHAFTS) s.at = [sx(s.at[0]), sz(s.at[1])];
  for (const it of ITEMS) it.at = [sx(it.at[0]), sz(it.at[1])];
  START.x = sx(START.x); START.z = sz(START.z);
}

// hand-placed cameras that replace the search for a stretch: { item: power } or { s }; either
// eye/tgt in world space, or relative to the object: from = the angle round it measured from the
// way ahead (deg, + to the left), dist and height (above the object's floor) of the eye, look =
// the target's offset from the object (x along the way, y up, z to the left), fov
export const CAMERAS = [
  // the burned mask on its column: from ahead and to the side, low over the lava, the column in
  // front and him coming on behind it
  { item: 0, from: 35, dist: 6.0, height: 2.4, look: [-1.2, 0.9, 0], fov: 50 },
  // the hand raised on its stalagmite: from low, looking up past it at the hanging dead
  { item: 1, from: -40, dist: 4.2, height: 0.7, look: [-0.3, 2.3, 0], fov: 62 },
  // the lodestone in its column of sun, the stones hanging round it
  { item: 2, from: 150, dist: 5.0, height: 2.2, look: [0.6, 1.1, 0], fov: 52 },
  // the orbs over the pool's edge: from across the water
  { item: 3, from: 70, dist: 7.0, height: 1.8, look: [0, 1.0, 0], fov: 50 },
  // the gem in its cluster, in the sun
  { item: 4, from: -150, dist: 6.0, height: 2.8, look: [0.8, 0.8, 0], fov: 50 },
  // the lens level in its ring of stone over the burned point
  { item: 5, from: 40, dist: 5.5, height: 3.6, look: [-0.6, 0.6, 0], fov: 50 },
];
