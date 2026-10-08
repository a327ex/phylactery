--[[
  eggphys.lua -- round 61 (owner, 2026-10-08: "The egg breaking should be a physics object that breaks and collides
  with the floor, and should also behave realistically when doing so. The egg itself should also be one, and it's
  shaking should be a mix of actual physical forces applied to it, with a general shake-like juice, this shake juice
  should use something similar to the every_increasing tween call ... where it does something over a duration but
  with increasing frequency. So one shake, another shake, then it starts faster faster and so on").

  Box3D (the engine's physics3) from his death on; the engine steps it at its fixed 120 Hz.
  - THE GROUND: a prism down from each of the cave floor's drawn triangles round the egg (things rest on the floor
    you see), and a hull for each stone lying there.
  - THE EGG: one body whose origin is its base (the egg group's): a hull of its shell, light, and a heavy core low
    inside (what is in it is heavy and low), so it rocks on its base and rights itself.
  - THE KNOCKS (knocks(duration)): one now, then timer_every_step's, their delays shrinking from KN.first to KN.last
    (quad_out) over the duration: a knock, a while, another, then faster and faster until it opens. Each is a push
    from inside at a point on the shell's upper half (an impulse there, outward and, late, up) and the juice: the
    squash spring pulled and a jitter (the framework's shake_shake), both on the drawn egg about its base; each
    stronger than the last.
  - THE BREAK (open(o)): the shell comes apart along the crack's band (silhouette.lua crack_lo .. crack_hi): the
    bottom below it, the cap above it and the band itself as shards (BAND.n pieces of uneven widths, cut on slants),
    each a body in the egg's frame moving as the egg was; the burst from inside throws the cap up, back and away from
    him (pushed under its front edge, so it tips open toward the camera) and the shards out; they fall, bounce, slide
    and settle on the floor, the stones and each other.
]]
local T = require('port.three.core')
local MAT = require('port.three.materials')
local TM = require('port.three.math')
local SL = require('port.silhouette')
local U = require('port.util')
local Vector3, Quaternion = TM.Vector3, TM.Quaternion
local sin, cos, sqrt, abs, acos, atan2, floor, ceil, min, max, pi = math.sin, math.cos, math.sqrt, math.abs, math.acos, math.atan, math.floor, math.ceil, math.min, math.max, math.pi
local clamp, smoothstep = U.clamp, U.smoothstep

local EP = {}
local H = 0.4                     -- the shell's half height: its centre is H above the egg's base
-- the egg: kg in its shell and in the core (a ball of `core_r` m, `core_y` m up from its base); its friction and
-- bounce on the stone; how fast its rocking dies away
-- (Box3D's hulls hold ~40 vertices at most, 255 half edges: the whole egg is three spheres inside its shell, the
-- lowest with the bottom's curvature (0.258 m) so that it rolls on it smoothly as it rocks: { radius, height of the
-- centre above the base })
EP.EGG = { shell_kg = 3, core_kg = 45, core_r = 0.08, core_y = 0.09, friction = 0.7, restitution = 0.05, damping = 0.8,
  spheres = { { 0.25, 0.25 }, { 0.30, 0.40 }, { 0.20, 0.58 } } }
-- the knocks: the first delay and the last (s); the push (N s) at strength 0 and added at 1, the lift added at 1
-- (times s^2); the juice: the squash spring's pull and the jitter (rad), both at strength 1. Round 62 (owner: "Make
-- the egg movement slightly more constrained as it's about to hatch, and make the juice shaking appear slightly
-- earlier"): the juice's strength rises as progress^juice_pow (earlier than the push's), its jitter lasting longer,
-- so the knocks' shivers run together sooner; over the last `calm_t` s before it opens the push eases off by up to
-- `calm` and the rocking is damped up to `damp_late` more
EP.KN = { first = 1.0, last = 0.06, j0 = 2.8, j1 = 2.0, up = 14, squash = 0.09, jitter = 0.045,
  juice_pow = 0.5, calm_t = 3.0, calm = 0.55, damp_late = 3.0 }
-- the break: the band in `n` shards `thick` m thick; the pieces' kg, their friction and bounce; how long the egg's
-- pieces pass through each other (s, so the burst can part them)
EP.BREAK = { n = 18, thick = 0.007, cap_kg = 4, bottom_kg = 9, shard_density = 1200, friction = 0.6, restitution = 0.25, apart = 0.12 }
-- the burst (m/s given to each piece): the cap up, back (away from the camera) and to the side away from him, pushed
-- `lever` m in front of its centre; the shards out and up (ranges), spun up to `spin` rad/s
EP.BURST = { cap_up = 2.3, cap_back = 0.45, cap_side = 0.55, lever = 0.12, out = { 0.8, 1.9 }, up = { 0.7, 1.9 }, back = 0.25, spin = 14 }
-- the ground: within `fine` m of the egg a grid of `cell` m prisms on the drawn floor (its triangles' heights), with
-- the egg's nest pressed into it (level within `flat` m of where it stands, then rising `k` per m^2 until it meets the
-- floor: it sat 3 cm into the floor on the mound's top, where a round bottom would roll off the facets); beyond, out to
-- `r`, a prism down from each drawn triangle; all `depth` m deep; friction
EP.GROUND = { r = 4.5, fine = 2.0, cell = 0.1, flat = 0.12, k = 0.6, depth = 0.6, friction = 0.8 }

-- ------------------------------------------------------------------ the shell's surface (its own space)
-- web/src/cave.js: a sphere of 0.5 (24 x 16) scaled across by 0.78 x taper x 0.8 and up by 0.8; a point is at angle
-- th round it (atan2(z, x), as the crack's) and height y (-H .. H)
local function radius_at(y)
  local c = clamp(y/H, -1, 1)
  local taper = 1 - 0.14*max(c, 0) + 0.03*max(-c, 0)
  return 0.5*sqrt(max(0, 1 - c*c))*0.78*taper*0.8
end
local function surf(th, y) local r = radius_at(y); return r*cos(th), y, r*sin(th) end
local function normal_at(th, y)
  local e = 0.002
  local dr = (radius_at(min(H, y + e)) - radius_at(max(-H, y - e)))/(min(H, y + e) - max(-H, y - e))
  local nx, ny, nz = cos(th), -dr, sin(th)
  local l = sqrt(nx*nx + ny*ny + nz*nz)
  return nx/l, ny/l, nz/l
end
-- the texture's place (SphereGeometry's uv: u = phi/2pi with x = -cos phi, z = sin phi; v from the top), unwrapped
local function uv_at(th, y) return (pi - th)/(2*pi), 1 - acos(clamp(y/H, -1, 1))/pi end

-- the shell's baked bounce light (its 'gi' attribute) on its 24 x 16 grid, read back bilinearly anywhere
local function gi_grid(shell)
  local g = shell.geometry
  local P, GI = g.attributes.position:ensure_array(), g.attributes.gi:ensure_array()
  local grid = {}
  for i = 0, #P//3 - 1 do
    local x, y, z = P[i*3 + 1], P[i*3 + 2], P[i*3 + 3]
    local ring = floor(acos(clamp(y/H, -1, 1))/pi*16 + 0.5)
    local seg = floor(((atan2(z, -x)/(2*pi)) % 1)*24 + 0.5) % 24
    grid[ring] = grid[ring] or {}
    grid[ring][seg] = { GI[i*3 + 1], GI[i*3 + 2], GI[i*3 + 3] }
  end
  -- (the poles: one value for every segment)
  for _, ring in ipairs({ 0, 16 }) do
    local any
    for s = 0, 23 do any = any or (grid[ring] and grid[ring][s]) end
    grid[ring] = grid[ring] or {}
    for s = 0, 23 do grid[ring][s] = grid[ring][s] or any end
  end
  return function(th, y)
    local v = acos(clamp(y/H, -1, 1))/pi*16
    local u = (((pi - th)/(2*pi)) % 1)*24
    local i0, j0 = min(15, floor(v)), floor(u)
    local fv, fu = v - i0, u - j0
    local a, b = grid[i0][j0 % 24], grid[i0][(j0 + 1) % 24]
    local c, d = grid[i0 + 1][j0 % 24], grid[i0 + 1][(j0 + 1) % 24]
    local out = {}
    for k = 1, 3 do
      local top = a[k] + (b[k] - a[k])*fu
      local bot = c[k] + (d[k] - c[k])*fu
      out[k] = top + (bot - top)*fv
    end
    return out[1], out[2], out[3]
  end
end

-- opts: R, egg (the cave's egg group), shell (its mesh), floor_geo, rock_geo, ground_y(x, z), rng
function EP.create(opts)
  local egg, shell = opts.egg, opts.shell
  local rng = opts.rng or U.run_rng(61)
  local api = { started = false, pieces = {}, roots = {}, knocks_done = 0 }
  local body                                        -- the whole egg, until it breaks
  local tm = timer_new()
  local spr = spring_new()                          -- (main: the squash, 1 at rest)
  local shk = shake_new()
  local QB, QJ, QJ2 = Quaternion.new(), Quaternion.new(), Quaternion.new()
  local AX1, AX2, V = Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), Vector3.new()

  -- a body's point (x, y, z in its own frame) and direction in the world
  local function to_world(b, x, y, z)
    local px, py, pz = physics3_get_position(b)
    QB:set(physics3_get_rotation(b))
    V:set(x, y, z):apply_quaternion(QB)
    return V.x + px, V.y + py, V.z + pz
  end
  local function dir_world(b, x, y, z)
    QB:set(physics3_get_rotation(b))
    V:set(x, y, z):apply_quaternion(QB)
    return V.x, V.y, V.z
  end
  local function centre(b) return to_world(b, physics3_get_local_center(b)) end

  -- ---------------------------------------------------------------- the ground
  local function build_ground(cx, cz, base)
    physics3_register_tag('ground'); physics3_register_tag('shell')
    physics3_enable_collision('shell', 'ground'); physics3_enable_collision('shell', 'shell')
    local gb = physics3_create_body('static', 0, 0, 0)
    local GR = EP.GROUND
    local R2, F2, D = GR.r^2, GR.fine^2, GR.depth
    local f = opts.floor_geo.attributes.position:ensure_array()
    local nf, ns = 0, 0
    local function add(pts) local ok, sh = pcall(physics3_add_hull, gb, 'ground', pts); if ok then physics3_shape_set_friction(sh, GR.friction); nf = nf + 1 end end
    -- the drawn triangles: those reaching past `fine` as prisms; those near enough to sample for the grid
    local near = {}
    for t = 0, #f//9 - 1 do
      local b = t*9
      local inside, outside, close = false, false, false
      for k = 0, 2 do
        local dx, dz = f[b + k*3 + 1] - cx, f[b + k*3 + 3] - cz
        local d2 = dx*dx + dz*dz
        if d2 < R2 then inside = true end
        if d2 >= F2 then outside = true end
        if d2 < (GR.fine + 1.5)^2 then close = true end
      end
      if close then near[#near + 1] = b end
      if inside and outside then
        local pts = {}
        for k = 0, 2 do pts[#pts + 1] = f[b + k*3 + 1]; pts[#pts + 1] = f[b + k*3 + 2]; pts[#pts + 1] = f[b + k*3 + 3] end
        for k = 0, 2 do pts[#pts + 1] = f[b + k*3 + 1]; pts[#pts + 1] = f[b + k*3 + 2] - D; pts[#pts + 1] = f[b + k*3 + 3] end
        add(pts)
      end
    end
    -- the grid inside `fine`: the drawn floor's height, the nest pressed into it
    local function drawn_h(x, z)
      for _, b in ipairs(near) do
        local ax, ay, az, bx, by, bz, qx, qy, qz = f[b + 1], f[b + 2], f[b + 3], f[b + 4], f[b + 5], f[b + 6], f[b + 7], f[b + 8], f[b + 9]
        local d = (bz - qz)*(ax - qx) + (qx - bx)*(az - qz)
        if d ~= 0 then
          local l1 = ((bz - qz)*(x - qx) + (qx - bx)*(z - qz))/d
          local l2 = ((qz - az)*(x - qx) + (ax - qx)*(z - qz))/d
          local l3 = 1 - l1 - l2
          if l1 >= -1e-6 and l2 >= -1e-6 and l3 >= -1e-6 then return l1*ay + l2*by + l3*qy end
        end
      end
      return opts.ground_y(x, z)
    end
    local N, C = ceil(GR.fine/GR.cell), GR.cell
    local h = {}
    for i = -N, N do
      h[i] = {}
      for j = -N, N do
        local x, z = cx + i*C, cz + j*C
        local r = sqrt((x - cx)^2 + (z - cz)^2)
        h[i][j] = min(drawn_h(x, z), base + (r > GR.flat and GR.k*(r - GR.flat)^2 or 0))
      end
    end
    for i = -N, N - 1 do
      for j = -N, N - 1 do
        local corner_in = false
        for _, c in ipairs({ { i, j }, { i + 1, j }, { i, j + 1 }, { i + 1, j + 1 } }) do
          if (c[1]*C)^2 + (c[2]*C)^2 < F2 then corner_in = true end
        end
        if corner_in then
          local pts = {}
          for _, c in ipairs({ { i, j }, { i + 1, j }, { i, j + 1 }, { i + 1, j + 1 } }) do
            local x, z, y = cx + c[1]*C, cz + c[2]*C, h[c[1]][c[2]]
            pts[#pts + 1] = x; pts[#pts + 1] = y; pts[#pts + 1] = z
            pts[#pts + 1] = x; pts[#pts + 1] = y - D; pts[#pts + 1] = z
          end
          add(pts)
        end
      end
    end
    -- the stones: each connected piece of the rocks' mesh near the egg that shows above the floor, as a hull
    local r = opts.rock_geo.attributes.position:ensure_array()
    local key_of, pos_of, parent = {}, {}, {}
    local function vid(i)
      local x, y, z = r[i*3 + 1], r[i*3 + 2], r[i*3 + 3]
      local k = floor(x*1e4 + 0.5) .. ',' .. floor(y*1e4 + 0.5) .. ',' .. floor(z*1e4 + 0.5)
      local id = key_of[k]
      if not id then id = #pos_of + 1; key_of[k] = id; pos_of[id] = { x, y, z }; parent[id] = id end
      return id
    end
    local function root(a) while parent[a] ~= a do parent[a] = parent[parent[a]]; a = parent[a] end; return a end
    local R2s = (EP.GROUND.r + 1)^2
    for t = 0, #r//9 - 1 do
      local b = t*9
      local mx, mz = (r[b + 1] + r[b + 4] + r[b + 7])/3 - cx, (r[b + 3] + r[b + 6] + r[b + 9])/3 - cz
      if mx*mx + mz*mz < R2s then
        local a, c, d = vid(t*3), vid(t*3 + 1), vid(t*3 + 2)
        parent[root(c)] = root(a); parent[root(d)] = root(a)
      end
    end
    local groups = {}
    for id = 1, #pos_of do local g = root(id); groups[g] = groups[g] or {}; local L = groups[g]; L[#L + 1] = pos_of[id] end
    for _, L in pairs(groups) do
      local up, sx, sz = false, 0, 0
      for _, p in ipairs(L) do
        sx, sz = sx + p[1], sz + p[3]
        if p[2] > opts.ground_y(p[1], p[3]) + 0.005 then up = true end
      end
      sx, sz = sx/#L - cx, sz/#L - cz
      if up and #L >= 4 and sx*sx + sz*sz < R2 then
        local pts, step = {}, max(1, ceil(#L/36))
        for i = 1, #L, step do local p = L[i]; pts[#pts + 1] = p[1]; pts[#pts + 1] = p[2]; pts[#pts + 1] = p[3] end
        local ok, sh = pcall(physics3_add_hull, gb, 'ground', pts)
        if ok then physics3_shape_set_friction(sh, EP.GROUND.friction); ns = ns + 1 end
      end
    end
    api.ground = { floor = nf, stones = ns }
  end

  -- ---------------------------------------------------------------- bodies
  -- a dynamic body at (x, y, z, q) made of `parts` ({ hull = points in its frame } or { r =, y = }: a sphere that far
  -- up from its base), `kg` in all (each part its share by volume) or of `density`; a sphere part's own `kg` is its
  -- own (ballast, a core)
  local shapes_of = {}
  local function piece_body(x, y, z, q, parts, kg, density, friction, restitution)
    local b = physics3_create_body('dynamic', x, y, z)
    physics3_set_rotation(b, q[1], q[2], q[3], q[4])
    local list, own = {}, {}
    for _, p in ipairs(parts) do
      local sh = p.hull and physics3_add_hull(b, 'shell', p.hull) or physics3_add_sphere(b, 'shell', p.r, { offset_y = p.y })
      physics3_shape_set_friction(sh, friction); physics3_shape_set_restitution(sh, restitution)
      if p.kg then own[#own + 1] = { sh, p.kg/(4/3*pi*p.r^3) }; physics3_shape_set_density(sh, 0.001)
      else list[#list + 1] = sh end
    end
    local d = kg and 1000*kg/physics3_get_mass(b) or density
    for _, sh in ipairs(list) do physics3_shape_set_density(sh, d) end
    for _, o in ipairs(own) do physics3_shape_set_density(o[1], o[2]); list[#list + 1] = o[1] end
    shapes_of[b] = list
    return b
  end
  -- (a piece's shapes into a filter group: pieces in the same one pass through each other; 0 = collides again)
  local function set_group(b, g) for _, sh in ipairs(shapes_of[b]) do physics3_shape_set_filter_group(sh, g) end end
  -- hull points (flat, the egg's frame: its base at 0) from shell-space { th, y } pairs, on the surface and, with
  -- `thick`, that far in too
  local function hull_of(list, thick)
    local pts = {}
    for _, p in ipairs(list) do
      local x, y, z = surf(p[1], p[2])
      pts[#pts + 1] = x; pts[#pts + 1] = y + H; pts[#pts + 1] = z
      if thick then
        local nx, ny, nz = normal_at(p[1], p[2])
        pts[#pts + 1] = x - nx*thick; pts[#pts + 1] = y + H - ny*thick; pts[#pts + 1] = z - nz*thick
      end
    end
    return pts
  end

  function api.start()
    if api.started then return end
    api.started = true
    physics3_init()
    local p = egg.position
    -- (it sits in its nest where it was drawn)
    build_ground(p.x, p.z, p.y)
    local y = p.y + 0.002
    local E = EP.EGG
    local parts = {}
    for _, sp in ipairs(E.spheres) do parts[#parts + 1] = { r = sp[1], y = sp[2] } end
    parts[#parts + 1] = { r = E.core_r, y = E.core_y, kg = E.core_kg }          -- (the core: heavy, low)
    body = piece_body(p.x, y, p.z, { 0, 0, 0, 1 }, parts, E.shell_kg, nil, E.friction, E.restitution)
    physics3_set_angular_damping(body, E.damping)
    egg.user_data.phys = true
    shell.rotation.x = 0; shell.rotation.z = 0
    api.sync()
  end

  -- ---------------------------------------------------------------- the knocks
  local knock_n, knock_i = 1, 0
  local function knock()
    if not body then return end
    knock_i = knock_i + 1
    local K = EP.KN
    local p = clamp(knock_i/knock_n, 0, 1)
    local s, sj = p^0.9, p^K.juice_pow
    local calm = 1 - K.calm*api.late()
    -- a push from inside: the wall on its upper half outward, what pushes (the core, at the centre of mass) back: it
    -- turns the egg and does not move it; late, what pushes down on the bottom lifts it off the floor (`up`)
    local th = rng.float(0, 2*pi)
    local x, y, z = surf(th, rng.float(-0.05, 0.22))
    local px, py, pz = to_world(body, x, y + H, z)
    local nx, ny, nz = dir_world(body, cos(th), 0, sin(th))
    local cx, cy, cz = centre(body)
    local j = (K.j0 + K.j1*s)*calm*rng.float(0.75, 1.25)
    local up = K.up*s*s*calm*rng.float(0.4, 1.0)
    physics3_apply_impulse_at(body, nx*j, ny*j, nz*j, px, py, pz)
    physics3_apply_impulse_at(body, -nx*j, -ny*j + up, -nz*j, cx, cy, cz)
    -- the juice: the squash spring and a jitter, on the drawn egg about its base
    spring_pull(spr, 'main', K.squash*(0.35 + 0.65*sj), 8, 0.5)
    shake_shake(shk, K.jitter*(0.35 + 0.65*sj), 0.15 + 0.2*sj, 40)
    api.knocks_done = knock_i
  end
  -- one knock now, then `n` more whose delays shrink from KN.first to KN.last (quad_out), as many as fit in `duration`
  -- (0 until `calm_t` s before it opens, then up to 1 as it does)
  local kt, kdur
  function api.late() return kdur and smoothstep(kdur - EP.KN.calm_t, kdur, kt) or 0 end
  function api.knocks(duration)
    local K = EP.KN
    kt, kdur = 0, duration
    local function total(n)
      local sum = 0
      for i = 1, n do sum = sum + math.lerp(math.quad_out((i - 1)/(n - 1)), K.first, K.last) end
      return sum
    end
    local n = 2
    while total(n + 1) <= duration do n = n + 1 end
    knock_n, knock_i = n + 1, 0
    knock()
    timer_every_step(tm, K.first, K.last, n, 'knock', knock, math.quad_out)
  end

  -- ---------------------------------------------------------------- the break
  -- the band's shards: n cuts round it at uneven spacing, each slanted (its top this much further round than its foot)
  local function shard_geometry(a0, s0, a1, s1, gap, gi_at)
    local cols = clamp(ceil((a1 - a0)*0.31/0.01), 4, 40)
    local O, I, N = {}, {}, {}
    for c = 0, cols - 1 do
      local w = c/(cols - 1)
      local thb, tht = a0 + (a1 - a0)*w, (a0 + s0) + ((a1 + s1) - (a0 + s0))*w
      local yb, yt = SL.crack_lo(thb, gap), SL.crack_hi(tht, gap)
      local rows = { { thb, yb }, { 0.5*(thb + tht), 0.5*(yb + yt) }, { tht, yt } }
      O[c], I[c], N[c] = {}, {}, {}
      for r = 0, 2 do
        local th, y = rows[r + 1][1], rows[r + 1][2]
        local x, yy, z = surf(th, y)
        local nx, ny, nz = normal_at(th, y)
        local T_ = EP.BREAK.thick
        O[c][r] = { x, yy, z, th, y }
        I[c][r] = { x - nx*T_, yy - ny*T_, z - nz*T_, th, y }
        N[c][r] = { nx, ny, nz }
      end
    end
    local pos, nor, uv, gi = {}, {}, {}, {}
    local function vert(p, n)
      pos[#pos + 1] = p[1]; pos[#pos + 1] = p[2]; pos[#pos + 1] = p[3]
      nor[#nor + 1] = n[1]; nor[#nor + 1] = n[2]; nor[#nor + 1] = n[3]
      local u, v = uv_at(p[4], p[5]); uv[#uv + 1] = u; uv[#uv + 1] = v
      local g1, g2, g3 = gi_at(p[4], p[5]); gi[#gi + 1] = g1; gi[#gi + 1] = g2; gi[#gi + 1] = g3
    end
    local function tri(a, na, b, nb, c, nc) vert(a, na); vert(b, nb); vert(c, nc) end
    for c = 0, cols - 2 do
      for r = 0, 1 do
        local A, B, C, D = O[c][r], O[c + 1][r], O[c][r + 1], O[c + 1][r + 1]
        tri(A, N[c][r], C, N[c][r + 1], B, N[c + 1][r])
        tri(B, N[c + 1][r], C, N[c][r + 1], D, N[c + 1][r + 1])
        -- (the inside, wound the same way: seen from inside it is a back face, the inside's colour)
        A, B, C, D = I[c][r], I[c + 1][r], I[c][r + 1], I[c + 1][r + 1]
        tri(A, N[c][r], C, N[c][r + 1], B, N[c + 1][r]); tri(B, N[c + 1][r], C, N[c][r + 1], D, N[c + 1][r + 1])
      end
    end
    -- the edges round it (bottom, far side, top, near side), each a quad from the outside to the inside
    local loop = {}
    for c = 0, cols - 1 do loop[#loop + 1] = { c, 0 } end
    for r = 1, 2 do loop[#loop + 1] = { cols - 1, r } end
    for c = cols - 2, 0, -1 do loop[#loop + 1] = { c, 2 } end
    loop[#loop + 1] = { 0, 1 }
    for k = 1, #loop do
      local p, q = loop[k], loop[k % #loop + 1]
      local o0, o1, i0, i1 = O[p[1]][p[2]], O[q[1]][q[2]], I[p[1]][p[2]], I[q[1]][q[2]]
      local ex, ey, ez = o1[1] - o0[1], o1[2] - o0[2], o1[3] - o0[3]
      local fx, fy, fz = i1[1] - o0[1], i1[2] - o0[2], i1[3] - o0[3]
      local nx, ny, nz = ey*fz - ez*fy, ez*fx - ex*fz, ex*fy - ey*fx
      local l = sqrt(nx*nx + ny*ny + nz*nz)
      local n = l > 0 and { nx/l, ny/l, nz/l } or { 0, 1, 0 }
      tri(o0, n, o1, n, i1, n); tri(o0, n, i1, n, i0, n)
    end
    local g = T.BufferGeometry.new()
    g:set_attribute('position', T.BufferAttribute.new(pos, 3))
    g:set_attribute('normal', T.BufferAttribute.new(nor, 3))
    g:set_attribute('uv', T.BufferAttribute.new(uv, 2))
    g:set_attribute('gi', T.BufferAttribute.new(gi, 3))
    -- its hull (the egg's frame: the base at 0): its ends and middle, outside and in (18 points)
    local pts = {}
    for _, c in ipairs({ 0, (cols - 1)//2, cols - 1 }) do for r = 0, 2 do
      for _, p in ipairs({ O[c][r], I[c][r] }) do pts[#pts + 1] = p[1]; pts[#pts + 1] = p[2] + H; pts[#pts + 1] = p[3] end
    end end
    return g, pts, 0.5*(a0 + a1 + 0.5*(s0 + s1))
  end

  -- a piece of shell drawn where its body is: a group (the body's place) holding the mesh at the shell's place in it
  local function add_piece(b, mesh, kind)
    local root = T.Group.new()
    mesh.position:set(0, H, 0)
    mesh.cast_shadow = true; mesh.receive_shadow = true
    root:add(mesh)
    opts.R.world_scene:add(root)
    local pc = { body = b, root = root, mesh = mesh, kind = kind }
    api.pieces[#api.pieces + 1] = pc
    api.roots[#api.roots + 1] = root
    return pc
  end

  -- o: em (the egg's material, patched), cap (the cap's mesh: the shell's geometry, cut above the band), back = {x,
  -- z} (level, away from the camera), side = {x, z} (level, away from him)
  function api.open(o)
    if not body then return end
    timer_cancel(tm, 'knock')
    local B, BR = EP.BREAK, EP.BURST
    local gap = SL.CRACK.gap
    local x, y, z = physics3_get_position(body)
    local q = { physics3_get_rotation(body) }
    local vx, vy, vz = physics3_get_velocity(body)
    local wx, wy, wz = physics3_get_angular_velocity(body)
    local ex, ey, ez = centre(body)
    local made = {}
    -- the bottom: the egg as drawn (its program cuts it below the band): the egg's lowest ball to roll on, its wall in
    -- 8 pieces (each a hull through the shell, from near the base up to the band's lower edge), and half its weight
    -- low, as a half shell carries it
    local sp = EP.EGG.spheres[1]
    local parts = { { r = sp[1], y = sp[2] }, { r = 0.06, y = 0.08, kg = 0.5*B.bottom_kg } }
    for k = 0, 7 do
      local list = {}
      for c = 0, 2 do
        local th = 2*pi*(k + c/2)/8
        local top = SL.crack_lo(th, gap)
        for _, yy in ipairs({ -0.36, -0.2, 0.5*(top - 0.2), top }) do list[#list + 1] = { th, yy } end
      end
      parts[#parts + 1] = { hull = hull_of(list, B.thick) }
    end
    local bb = piece_body(x, y, z, q, parts, 0.5*B.bottom_kg, nil, EP.EGG.friction, EP.EGG.restitution)
    physics3_set_angular_damping(bb, 1.5)
    api.bottom = bb
    made[#made + 1] = bb
    -- the cap: a hull through the lowest point of the band's upper edge in each of 20 sectors (what it lands on,
    -- rim down), two rings and its top
    local list = {}
    for k = 0, 19 do
      local best, bth = H, 0
      for i = 0, 5 do local th = 2*pi*(k + i/6)/20; local hi = SL.crack_hi(th, gap); if hi < best then best, bth = hi, th end end
      list[#list + 1] = { bth, best }
    end
    for k = 0, 9 do list[#list + 1] = { 2*pi*k/10, 0.27 } end
    for k = 0, 5 do list[#list + 1] = { 2*pi*k/6 + 0.3, 0.35 } end
    list[#list + 1] = { 0, H }
    local cb = piece_body(x, y, z, q, { { hull = hull_of(list) } }, B.cap_kg, nil, B.friction, B.restitution)
    o.cap.visible = true
    if o.cap.parent then o.cap.parent:remove(o.cap) end
    local cap = add_piece(cb, o.cap, 'cap')
    made[#made + 1] = cb
    -- the shards: the egg's material, as a loose piece (uClip 3: its inside on its back faces)
    local em = o.em
    local sm = MAT.MeshLambertMaterial.new({ name = em.name, map = em.map, side = MAT.DoubleSide, flat_shading = em.flat_shading })
    sm.color:copy(em.color)
    sm.custom = {}
    for k, u in pairs(em.custom) do sm.custom[k] = u end
    sm.custom.uClip = { value = 3 }; sm.custom.uCrackGrow = { value = 0 }
    sm.custom.uInner = { value = TM.Vector3.new(0.42, 0.30, 0.17) }        -- (a shard's inside: warm, unlit)
    local gi_at = gi_grid(shell)
    local cuts, wsum, a = {}, 0, rng.float(0, 2*pi)
    for i = 1, B.n do cuts[i] = rng.float(0.5, 1.6); wsum = wsum + cuts[i] end
    local starts, slants = {}, {}
    for i = 1, B.n do starts[i] = a; slants[i] = rng.spread(0.09); a = a + 2*pi*cuts[i]/wsum end
    local shards = {}
    for i = 1, B.n do
      local j = i % B.n + 1
      local a1 = j == 1 and starts[1] + 2*pi or starts[j]
      local geo, pts, th = shard_geometry(starts[i], slants[i], a1, slants[j], gap, gi_at)
      local sb = piece_body(x, y, z, q, { { hull = pts } }, nil, B.shard_density, B.friction, B.restitution)
      local pc = add_piece(sb, T.Mesh.new(geo, sm), 'shard')
      pc.th = th
      shards[#shards + 1] = pc
      made[#made + 1] = sb
    end
    -- each moves as the egg did at its centre; the egg's pieces pass through each other for a moment
    for _, b in ipairs(made) do
      local cx, cy, cz = centre(b)
      local rx, ry, rz = cx - ex, cy - ey, cz - ez
      physics3_set_velocity(b, vx + (wy*rz - wz*ry), vy + (wz*rx - wx*rz), vz + (wx*ry - wy*rx))
      physics3_set_angular_velocity(b, wx, wy, wz)
    end
    api.shapes_apart = made
    for _, b in ipairs(made) do set_group(b, 61) end
    api.apart_t = B.apart
    physics3_destroy_body(body)
    body = nil
    -- the burst from inside
    local bx, bz = o.back[1], o.back[2]
    local sx, sz = o.side[1], o.side[2]
    local m = physics3_get_mass(cb)
    local cx, cy, cz = centre(cb)
    physics3_apply_impulse_at(cb, m*(bx*BR.cap_back + sx*BR.cap_side), m*BR.cap_up, m*(bz*BR.cap_back + sz*BR.cap_side),
      cx - bx*BR.lever, cy, cz - bz*BR.lever)
    for _, pc in ipairs(shards) do
      local b = pc.body
      local ms = physics3_get_mass(b)
      local ox, _, oz = dir_world(b, cos(pc.th), 0, sin(pc.th))
      local out, up = rng.float(BR.out[1], BR.out[2]), rng.float(BR.up[1], BR.up[2])
      physics3_apply_impulse(b, ms*(ox*out + bx*BR.back), ms*up, ms*(oz*out + bz*BR.back))
      local w1, w2, w3 = physics3_get_angular_velocity(b)
      physics3_set_angular_velocity(b, w1 + rng.spread(BR.spin), w2 + rng.spread(BR.spin), w3 + rng.spread(BR.spin))
    end
    -- the egg (the bottom) as it is, the juice gone
    spr.main.x, spr.main.v = 1, 0
    shk.shake_instances = {}
    api.cap = cap
    api.opened = true
    api.sync()
  end

  -- ---------------------------------------------------------------- each tick
  local function place(root, b)
    local px, py, pz = physics3_get_position(b)
    root.position:set(px, py, pz)
    root.quaternion:set(physics3_get_rotation(b))
  end
  function api.sync()
    local b = body or api.bottom
    if b then
      place(egg, b)
      if body then
        -- (the juice on the whole egg: the jitter as two small turns about its base, the squash keeping its volume)
        local ox, oy = shake_get_effects(shk)
        QJ:set_from_axis_angle(AX1, oy); QJ2:set_from_axis_angle(AX2, ox)
        egg.quaternion:multiply(QJ):multiply(QJ2)
        local sy = max(0.6, spr.main.x)
        local sxz = 1/sqrt(sy)
        egg.scale:set(sxz, sy, sxz)
      else
        egg.scale:set(1, 1, 1)
      end
    end
    for _, pc in ipairs(api.pieces) do place(pc.root, pc.body) end
  end
  function api.tick(dt)
    if not api.started then return end
    timer_update(tm, dt)
    if kt and body then
      kt = kt + dt
      physics3_set_angular_damping(body, EP.EGG.damping + EP.KN.damp_late*api.late())
    end
    spring_update(spr, dt)
    shake_update(shk, dt)
    if api.apart_t then
      api.apart_t = api.apart_t - dt
      if api.apart_t <= 0 then api.apart_t = nil; for _, b in ipairs(api.shapes_apart) do set_group(b, 0) end end
    end
    api.sync()
  end
  -- (for probes: the egg's tilt from upright in degrees, its base's place, its speed; the pieces at rest)
  function api.state()
    local b = body or api.bottom
    if not b then return nil end
    local qx, qy, qz, qw = physics3_get_rotation(b)
    local upy = 1 - 2*(qx*qx + qz*qz)                    -- (the body's up axis, its y)
    local px, py, pz = physics3_get_position(b)
    local vx, vy, vz = physics3_get_velocity(b)
    local resting = 0
    for _, pc in ipairs(api.pieces) do if not physics3_is_awake(pc.body) then resting = resting + 1 end end
    return { tilt = acos(clamp(upy, -1, 1))*180/pi, x = px, y = py, z = pz, speed = sqrt(vx*vx + vy*vy + vz*vz),
      knocks = knock_i, of = knock_n, pieces = #api.pieces, resting = resting, ground = api.ground, squash = spr.main.x }
  end
  return api
end

return EP
