--[[
  mesh3 module — custom 3D meshes for layer3.

  The engine holds meshes as GPU buffers behind integer handles; this module is
  everything above that: loading OBJ files, and building simple geometry in
  code. Parsing lives here rather than in C on purpose — OBJ is a trivial text
  format, it's parsed once at load, and keeping it in Lua keeps the C surface
  small.

  Vertex layout is a flat array, 8 floats per vertex:
      x, y, z,  nx, ny, nz,  u, v
  Non-indexed triangles, so the array length is always a multiple of 24.

  Usage:
    local m = mesh3_load_obj('assets/models/pump.obj')
    mesh3_set_texture(m, texture_load('assets/models/pump.png'))
    -- draw():
    layer3_mesh(scene, m, x, y, z)

  Meshes are cached by path, so loading the same file twice is free and returns
  the same handle.
]]

mesh3_cache = mesh3_cache or {}

-- ---------------------------------------------------------------------------
-- OBJ loading
-- ---------------------------------------------------------------------------

--[[
  Parse Wavefront OBJ text into a flat vertex array.

  Supports v / vt / vn / f, with faces as triangles or polygons (fan
  triangulated), and any of the f-vertex forms: `v`, `v/vt`, `v//vn`,
  `v/vt/vn`. Negative (relative) indices are handled. Materials are ignored —
  texturing is one texture per mesh, assigned by the caller.

  Missing normals are generated per-face, which matches the engine's built-in
  primitives (flat-shaded, faceted) and is the right look here anyway. Missing
  UVs become 0,0 so the mesh samples one texel — fine for untextured meshes.
]]
function mesh3_parse_obj(text)
  local px, py, pz = {}, {}, {}     -- positions
  local tu, tv = {}, {}             -- texcoords
  local nx, ny, nz = {}, {}, {}     -- normals
  local out, n_out = {}, 0

  local function emit(vi, ti, ni, fnx, fny, fnz)
    local ux, uy, uz = px[vi], py[vi], pz[vi]
    if not ux then return false end
    local vnx, vny, vnz
    if ni and nx[ni] then
      vnx, vny, vnz = nx[ni], ny[ni], nz[ni]
    else
      vnx, vny, vnz = fnx, fny, fnz
    end
    local u = (ti and tu[ti]) or 0
    local v = (ti and tv[ti]) or 0
    out[n_out + 1] = ux;  out[n_out + 2] = uy;  out[n_out + 3] = uz
    out[n_out + 4] = vnx; out[n_out + 5] = vny; out[n_out + 6] = vnz
    out[n_out + 7] = u;   out[n_out + 8] = v
    n_out = n_out + 8
    return true
  end

  -- Resolve an OBJ index: 1-based, or negative meaning "from the end".
  local function resolve(i, count)
    if not i then return nil end
    if i < 0 then return count + i + 1 end
    return i
  end

  for line in string.gmatch(text, '[^\r\n]+') do
    local tag = string.match(line, '^%s*(%S+)')
    if tag == 'v' then
      local a, b, c = string.match(line, '^%s*v%s+(%S+)%s+(%S+)%s+(%S+)')
      if a then
        px[#px + 1] = tonumber(a); py[#py + 1] = tonumber(b); pz[#pz + 1] = tonumber(c)
      end
    elseif tag == 'vt' then
      local a, b = string.match(line, '^%s*vt%s+(%S+)%s+(%S+)')
      if a then
        -- OBJ's V axis points up, GL texture space points down.
        tu[#tu + 1] = tonumber(a); tv[#tv + 1] = 1.0 - tonumber(b)
      end
    elseif tag == 'vn' then
      local a, b, c = string.match(line, '^%s*vn%s+(%S+)%s+(%S+)%s+(%S+)')
      if a then
        nx[#nx + 1] = tonumber(a); ny[#ny + 1] = tonumber(b); nz[#nz + 1] = tonumber(c)
      end
    elseif tag == 'f' then
      -- Collect the face's corners, then fan triangulate.
      local vs, ts, ns = {}, {}, {}
      for chunk in string.gmatch(line, '%S+') do
        if chunk ~= 'f' then
          local vi, ti, ni = string.match(chunk, '^(-?%d*)/(-?%d*)/(-?%d*)$')
          if not vi then
            vi, ti = string.match(chunk, '^(-?%d*)/(-?%d*)$')
          end
          if not vi then
            vi = string.match(chunk, '^(-?%d+)$')
          end
          if vi and vi ~= '' then
            vs[#vs + 1] = resolve(tonumber(vi), #px)
            ts[#ts + 1] = resolve(tonumber(ti or ''), #tu)
            ns[#ns + 1] = resolve(tonumber(ni or ''), #nx)
          end
        end
      end

      for k = 2, #vs - 1 do
        local i1, i2, i3 = vs[1], vs[k], vs[k + 1]
        -- Face normal, used only where the OBJ supplies none.
        local fnx, fny, fnz = 0, 1, 0
        if px[i1] and px[i2] and px[i3] then
          local ax, ay, az = px[i2] - px[i1], py[i2] - py[i1], pz[i2] - pz[i1]
          local bx, by, bz = px[i3] - px[i1], py[i3] - py[i1], pz[i3] - pz[i1]
          local cx, cy, cz = ay*bz - az*by, az*bx - ax*bz, ax*by - ay*bx
          local len = math.sqrt(cx*cx + cy*cy + cz*cz)
          if len > 1e-12 then fnx, fny, fnz = cx/len, cy/len, cz/len end
        end
        emit(i1, ts[1], ns[1], fnx, fny, fnz)
        emit(i2, ts[k], ns[k], fnx, fny, fnz)
        emit(i3, ts[k + 1], ns[k + 1], fnx, fny, fnz)
      end
    end
  end

  return out
end

--- Load an OBJ from disk (or the packaged zip) and upload it. Cached by path.
--- Returns the mesh handle, or nil if the file is missing or has no faces.
function mesh3_load_obj(path)
  if mesh3_cache[path] then return mesh3_cache[path] end
  local text = file_read_string(path)
  if not text then
    print('mesh3_load_obj: could not read ' .. tostring(path))
    return nil
  end
  local verts = mesh3_parse_obj(text)
  if #verts < 24 then
    print('mesh3_load_obj: no triangles in ' .. tostring(path))
    return nil
  end
  local m = mesh3_create(verts)
  mesh3_cache[path] = m
  return m
end

-- ---------------------------------------------------------------------------
-- Procedural geometry
--
-- Blockout helpers for geometry that's easier to state than to model. They
-- emit into a plain array so several can be combined into one mesh, which is
-- what you want for a tiled surface: one mesh, one draw call.
-- ---------------------------------------------------------------------------

--- Append one triangle, with an explicit normal and per-corner UVs.
function mesh3_tri(out, ax, ay, az, bx, by, bz, cx, cy, cz, nx, ny, nz, au, av, bu, bv, cu, cv)
  local i = #out
  out[i +  1] = ax; out[i +  2] = ay; out[i +  3] = az
  out[i +  4] = nx; out[i +  5] = ny; out[i +  6] = nz
  out[i +  7] = au; out[i +  8] = av
  out[i +  9] = bx; out[i + 10] = by; out[i + 11] = bz
  out[i + 12] = nx; out[i + 13] = ny; out[i + 14] = nz
  out[i + 15] = bu; out[i + 16] = bv
  out[i + 17] = cx; out[i + 18] = cy; out[i + 19] = cz
  out[i + 20] = nx; out[i + 21] = ny; out[i + 22] = nz
  out[i + 23] = cu; out[i + 24] = cv
end

--- Append a quad from 4 corners in winding order, with a normal and a UV rect.
function mesh3_quad(out, x1,y1,z1, x2,y2,z2, x3,y3,z3, x4,y4,z4, nx,ny,nz, u0,v0, u1,v1)
  u0, v0, u1, v1 = u0 or 0, v0 or 0, u1 or 1, v1 or 1
  mesh3_tri(out, x1,y1,z1, x2,y2,z2, x3,y3,z3, nx,ny,nz, u0,v1, u1,v1, u1,v0)
  mesh3_tri(out, x1,y1,z1, x3,y3,z3, x4,y4,z4, nx,ny,nz, u0,v1, u1,v0, u0,v0)
end

--- Append a horizontal tile centred at (cx, y, cz), facing up. `tile` repeats
--- the texture across the surface — the standard way to keep texel density even
--- on a long road without stretching one texture down its whole length.
function mesh3_ground_tile(out, cx, y, cz, w, d, tile)
  tile = tile or 1
  local hw, hd = w/2, d/2
  mesh3_quad(out,
    cx - hw, y, cz - hd,
    cx + hw, y, cz - hd,
    cx + hw, y, cz + hd,
    cx - hw, y, cz + hd,
    0, 1, 0,
    0, 0, tile, tile)
end

--[[
  Append a floating island: a rounded top disc and a tapering spike below it.

  That inverted-cone silhouette is the single most recognisable thing about the
  sky-continent look, and it's cheap — a radial mesh whose rim radius is
  perturbed by a repeating noise so no two islands read as the same lump.

  Top and underside go to SEPARATE output lists so they can carry different
  textures (grass above, rock below) while sharing one rim — which is the whole
  trick. Emitting both into one mesh would force one texture on both, and
  layering a second spike underneath to fix that just puts two surfaces in the
  same place to fight over the depth buffer.

  `rng` is a random_create() handle so a given island is reproducible.
  `top_uv` / `side_uv` tile the two textures independently.

  Returns the rim as {cx, cy, cz, segments, r = {...}, y = {...}} — the radius
  and height at each segment angle. Scatter needs this to place props INSIDE the
  island; without it there's no way to know where the edge is, and props end up
  hanging over the void.
]]
function mesh3_island(top_out, side_out, cx, cy, cz, radius, depth, segments, rng, top_uv, side_uv)
  segments = segments or 16
  top_uv = top_uv or 1
  side_uv = side_uv or 1

  -- Per-segment rim radius and a slight height wobble, sampled once so the top
  -- and the spike agree on where the edge is.
  local rr, ry = {}, {}
  for i = 1, segments do
    rr[i] = radius * (0.78 + random_float(0, 0.44, rng))
    ry[i] = random_float(-0.06, 0.06, rng) * radius
  end

  local tip_y = cy - depth
  for i = 1, segments do
    local j = (i % segments) + 1
    local a0 = (i - 1)/segments * math.pi*2
    local a1 = j == 1 and math.pi*2 or ((j - 1)/segments * math.pi*2)

    local x0, z0 = cx + math.cos(a0)*rr[i], cz + math.sin(a0)*rr[i]
    local x1, z1 = cx + math.cos(a1)*rr[j], cz + math.sin(a1)*rr[j]
    local y0, y1 = cy + ry[i], cy + ry[j]

    -- Top surface: fan from the centre. UVs are the unit disc mapped to 0..1
    -- so the grass texture doesn't smear radially.
    local u0 = 0.5 + math.cos(a0)*0.5*top_uv
    local v0 = 0.5 + math.sin(a0)*0.5*top_uv
    local u1 = 0.5 + math.cos(a1)*0.5*top_uv
    local v1 = 0.5 + math.sin(a1)*0.5*top_uv
    mesh3_tri(top_out, cx, cy, cz, x0, y0, z0, x1, y1, z1, 0, 1, 0, 0.5, 0.5, u0, v0, u1, v1)

    -- Underside: rim down to a single tip, so the island reads as torn free of
    -- the ground rather than sliced flat.
    local nx, ny, nz = math.cos((a0 + a1)*0.5), -0.35, math.sin((a0 + a1)*0.5)
    local nl = math.sqrt(nx*nx + ny*ny + nz*nz)
    nx, ny, nz = nx/nl, ny/nl, nz/nl
    local su0 = (i - 1)/segments * side_uv
    local su1 = i/segments * side_uv
    mesh3_tri(side_out, x1, y1, z1, x0, y0, z0, cx, tip_y, cz, nx, ny, nz,
              su1, 0, su0, 0, (su0 + su1)*0.5, 1)
  end

  return {cx = cx, cy = cy, cz = cz, segments = segments, r = rr, y = ry}
end

--[[
  Sample a point inside an island rim, or nil if the draw landed outside.

  The rim radius varies per segment, so "inside" isn't a simple circle test:
  interpolate the two neighbouring segment radii at the sampled angle. `margin`
  pulls the usable area in from the edge (0.85 keeps props off the lip, which
  matters because the lip is where the geometry starts falling away).

  Returns x, y, z — y interpolated from the rim's height wobble so props sit on
  the surface rather than through it.
]]
function mesh3_island_sample(rim, rng, margin)
  margin = margin or 0.85
  local a = random_float(0, math.pi*2, rng)
  -- sqrt biases toward the rim, which counteracts the crowding a uniform radius
  -- draw would produce at the centre.
  local frac = math.sqrt(random_float(0, 1, rng))

  local seg = a/(math.pi*2) * rim.segments
  local i0 = math.floor(seg) % rim.segments
  local i1 = (i0 + 1) % rim.segments
  local t = seg - math.floor(seg)
  local r_here = rim.r[i0 + 1]*(1 - t) + rim.r[i1 + 1]*t
  local y_here = rim.y[i0 + 1]*(1 - t) + rim.y[i1 + 1]*t

  local d = frac * r_here * margin
  return rim.cx + math.cos(a)*d,
         rim.cy + y_here*(d/math.max(r_here, 1e-4)),
         rim.cz + math.sin(a)*d
end

--[[
  Ground query for an island rim: where the top surface is at (x, z).

  Returns y, rim_radius, distance — the surface height, how far out the rim is
  along this direction, and how far out the query point is. The last two are
  what an edge constraint needs (`distance/rim_radius > 0.9` is near the lip).

  This evaluates the ACTUAL fan triangle rather than interpolating the rim
  wobble by angle the way mesh3_island_sample does. The difference matters for
  something standing on the surface: the approximation is off the true plane by
  up to a few percent of the wobble, which is centimetres of foot float or sink
  on a 34 m island. Props tolerate that; feet don't.

  The triangle is (centre, P0, P1). Solving `p = s*(P0-C) + t*(P1-C)` in the xz
  plane gives barycentric weights directly, and since P0.y-C.y is exactly the
  rim's stored wobble, height falls out as `cy + s*ry[i] + t*ry[j]`. At the rim
  s+t = 1, so 1/(s+t) also scales the point out to the edge — which is where
  rim_radius comes from, exactly, on the straight chord the geometry actually
  has rather than on an arc it doesn't.
]]
function mesh3_island_ground(rim, x, z)
  local dx, dz = x - rim.cx, z - rim.cz
  local dist = math.sqrt(dx*dx + dz*dz)
  if dist < 1e-6 then return rim.cy, rim.r[1], 0 end

  local segs = rim.segments
  local a = math.atan(dz, dx) % (math.pi*2)
  local i = math.floor(a/(math.pi*2)*segs) % segs          -- 0-based segment
  local j = (i + 1) % segs
  local a0, a1 = i/segs*math.pi*2, (i + 1)/segs*math.pi*2
  local r0, r1 = rim.r[i + 1], rim.r[j + 1]
  local v0x, v0z = math.cos(a0)*r0, math.sin(a0)*r0
  local v1x, v1z = math.cos(a1)*r1, math.sin(a1)*r1

  local det = v0x*v1z - v1x*v0z
  if math.abs(det) < 1e-9 then return rim.cy, dist, dist end
  local s = (dx*v1z - v1x*dz)/det
  local t = (v0x*dz - dx*v0z)/det
  local sum = s + t
  local rim_radius = sum > 1e-9 and dist/sum or dist
  -- Outside the rim, project radially onto the edge so the height stays the
  -- rim's rather than extrapolating the plane off into space.
  if sum > 1 then s, t = s/sum, t/sum end
  return rim.cy + s*rim.y[i + 1] + t*rim.y[j + 1], rim_radius, dist
end

--[[
  Append a tapered cylinder (a cone frustum), the building block for trunks and
  pillars. `sides` controls chunkiness — low counts are the point, not a
  limitation. Set r_top to 0 for a cone.
]]
function mesh3_taper(out, cx, cy, cz, r_bottom, r_top, height, sides, cap_top, uv_scale)
  sides = sides or 8
  uv_scale = uv_scale or 1
  local y0, y1 = cy, cy + height
  for i = 0, sides - 1 do
    local a0 = i/sides * math.pi*2
    local a1 = (i + 1)/sides * math.pi*2
    local c0, s0 = math.cos(a0), math.sin(a0)
    local c1, s1 = math.cos(a1), math.sin(a1)
    local u0, u1 = i/sides * uv_scale, (i + 1)/sides * uv_scale

    local bx0, bz0 = cx + c0*r_bottom, cz + s0*r_bottom
    local bx1, bz1 = cx + c1*r_bottom, cz + s1*r_bottom
    local tx0, tz0 = cx + c0*r_top, cz + s0*r_top
    local tx1, tz1 = cx + c1*r_top, cz + s1*r_top

    local nx, nz = math.cos((a0 + a1)*0.5), math.sin((a0 + a1)*0.5)
    if r_top > 0.001 then
      mesh3_quad(out, bx0,y0,bz0, bx1,y0,bz1, tx1,y1,tz1, tx0,y1,tz0,
                 nx, 0.25, nz, u0, 0, u1, uv_scale)
    else
      mesh3_tri(out, bx0,y0,bz0, bx1,y0,bz1, cx,y1,cz, nx, 0.35, nz,
                u0, 0, u1, 0, (u0 + u1)*0.5, uv_scale)
    end
  end
  if cap_top and r_top > 0.001 then
    for i = 0, sides - 1 do
      local a0 = i/sides * math.pi*2
      local a1 = (i + 1)/sides * math.pi*2
      mesh3_tri(out, cx, y1, cz,
                cx + math.cos(a0)*r_top, y1, cz + math.sin(a0)*r_top,
                cx + math.cos(a1)*r_top, y1, cz + math.sin(a1)*r_top,
                0, 1, 0,
                0.5, 0.5,
                0.5 + math.cos(a0)*0.5, 0.5 + math.sin(a0)*0.5,
                0.5 + math.cos(a1)*0.5, 0.5 + math.sin(a1)*0.5)
    end
  end
end

--[[
  Append a tree: a tapered trunk under stacked canopy blobs.

  Trunk and canopy go to SEPARATE output lists, for the same reason the island
  splits its top from its underside — they need different textures. Emitting
  both into one mesh forces one texture on the whole tree, which is how you end
  up with green trunks.

  Modelled rather than carded on purpose — this style is normally authored for a
  ground-locked camera, but here you can fly directly over a forest, and crossed
  billboard cards read as flat paper the moment you gain altitude.

  `style` is 'round' (soft, chibi) or 'conical' (stylised, reads better at
  distance). Mixing the two is what keeps a skyline from looking cloned.
]]
function mesh3_tree(trunk_out, canopy_out, cx, cy, cz, height, rng, style)
  style = style or 'round'
  local trunk_h = height*0.42
  local trunk_r = height*0.045
  mesh3_taper(trunk_out, cx, cy, cz, trunk_r, trunk_r*0.72, trunk_h, 6, false, 1)

  if style == 'conical' then
    -- Three tapering skirts, each starting below the last so they overlap.
    local base = cy + trunk_h*0.55
    for i = 0, 2 do
      local t = i/2
      local r = height*(0.30 - t*0.10)
      local h = height*(0.30 - t*0.06)
      mesh3_taper(canopy_out, cx, base + t*height*0.26, cz, r, r*0.12, h, 7, false, 1)
    end
  else
    -- Two or three overlapping blobs, offset so the canopy isn't symmetrical.
    local blobs = 2 + random_int(0, 1, rng)
    local base = cy + trunk_h*0.72
    for i = 0, blobs - 1 do
      local t = i/math.max(blobs - 1, 1)
      local r = height*(0.30 - t*0.13)
      local ox = random_float(-1, 1, rng)*height*0.05
      local oz = random_float(-1, 1, rng)*height*0.05
      mesh3_sphere_blob(canopy_out, cx + ox, base + t*height*0.22 + r*0.5, cz + oz, r, 7, 5)
    end
  end
end

--- Append a faceted sphere-ish blob. Deliberately coarse: the low facet count
--- is the look, and flat normals read as painted rather than shaded.
function mesh3_sphere_blob(out, cx, cy, cz, radius, slices, stacks)
  slices = slices or 8
  stacks = stacks or 6
  local function pt(i, j)
    local phi = j/stacks * math.pi
    local theta = i/slices * math.pi*2
    local sp = math.sin(phi)
    return cx + math.cos(theta)*sp*radius,
           cy + math.cos(phi)*radius,
           cz + math.sin(theta)*sp*radius,
           i/slices, j/stacks
  end
  for j = 0, stacks - 1 do
    for i = 0, slices - 1 do
      local ax, ay, az, au, av = pt(i, j)
      local bx, by, bz, bu, bv = pt(i + 1, j)
      local cx2, cy2, cz2, cu, cv = pt(i + 1, j + 1)
      local dx, dy, dz, du, dv = pt(i, j + 1)
      -- Outward normal from the face centroid; the blob is convex so this is
      -- always correct and costs nothing to compute.
      local mx = (ax + bx + cx2 + dx)*0.25 - cx
      local my = (ay + by + cy2 + dy)*0.25 - cy
      local mz = (az + bz + cz2 + dz)*0.25 - cz
      local ml = math.sqrt(mx*mx + my*my + mz*mz)
      if ml < 1e-6 then ml = 1 end
      mx, my, mz = mx/ml, my/ml, mz/ml
      mesh3_tri(out, ax,ay,az, bx,by,bz, cx2,cy2,cz2, mx,my,mz, au,av, bu,bv, cu,cv)
      mesh3_tri(out, ax,ay,az, cx2,cy2,cz2, dx,dy,dz, mx,my,mz, au,av, cu,cv, du,dv)
    end
  end
end

--- Append a lumpy boulder: a blob with per-vertex-ring radius jitter.
function mesh3_rock(out, cx, cy, cz, radius, rng)
  local slices, stacks = 6, 4
  local jitter = {}
  for j = 0, stacks do
    jitter[j] = {}
    for i = 0, slices do
      jitter[j][i] = 0.72 + random_float(0, 0.5, rng)
    end
    jitter[j][slices] = jitter[j][0]     -- close the seam
  end
  local function pt(i, j)
    local ii = i % slices
    local phi = j/stacks * math.pi
    local theta = i/slices * math.pi*2
    local sp = math.sin(phi)
    local r = radius * jitter[j][ii]
    return cx + math.cos(theta)*sp*r,
           cy + math.cos(phi)*r*0.7,
           cz + math.sin(theta)*sp*r,
           i/slices, j/stacks
  end
  for j = 0, stacks - 1 do
    for i = 0, slices - 1 do
      local ax, ay, az, au, av = pt(i, j)
      local bx, by, bz, bu, bv = pt(i + 1, j)
      local cx2, cy2, cz2, cu, cv = pt(i + 1, j + 1)
      local dx, dy, dz, du, dv = pt(i, j + 1)
      local mx = (ax + bx + cx2 + dx)*0.25 - cx
      local my = (ay + by + cy2 + dy)*0.25 - cy
      local mz = (az + bz + cz2 + dz)*0.25 - cz
      local ml = math.sqrt(mx*mx + my*my + mz*mz)
      if ml < 1e-6 then ml = 1 end
      mx, my, mz = mx/ml, my/ml, mz/ml
      mesh3_tri(out, ax,ay,az, bx,by,bz, cx2,cy2,cz2, mx,my,mz, au,av, bu,bv, cu,cv)
      mesh3_tri(out, ax,ay,az, cx2,cy2,cz2, dx,dy,dz, mx,my,mz, au,av, cu,cv, du,dv)
    end
  end
end

--[[
  Append a tiered pavilion: a base platform, a ring of pillars, and stacked
  tapering roofs with overhanging eaves.

  Three output lists, because the three materials read completely differently
  and a landmark is exactly where that matters: `stone_out` (base and pillars),
  `roof_out` (the tiers), `trim_out` (the finial and eave banding).

  The silhouette does the work — each roof is a shallow cone wider than the tier
  above it, so the profile steps outward as it descends. Deliberately few sides
  per cone: the faceting is the look.
]]
function mesh3_pavilion(stone_out, roof_out, trim_out, cx, cy, cz, radius, tiers, pillars)
  tiers = tiers or 3
  pillars = pillars or 8

  -- Base: two stacked discs, the lower one wider, so it reads as a stepped plinth.
  mesh3_taper(stone_out, cx, cy, cz, radius*1.15, radius*1.10, radius*0.10, 12, true, 2)
  mesh3_taper(stone_out, cx, cy + radius*0.10, cz, radius*1.02, radius*0.98, radius*0.09, 12, true, 2)

  local floor_y = cy + radius*0.19
  local pillar_h = radius*0.62
  local pillar_r = radius*0.055
  for i = 0, pillars - 1 do
    local a = i/pillars * math.pi*2
    local px = cx + math.cos(a)*radius*0.82
    local pz = cz + math.sin(a)*radius*0.82
    mesh3_taper(stone_out, px, floor_y, pz, pillar_r, pillar_r*0.88, pillar_h, 6, false, 1)
  end

  -- Roof tiers, each narrower and shallower than the one below.
  local y = floor_y + pillar_h
  local r = radius*1.25
  for t = 1, tiers do
    local roof_h = radius*(0.30 - (t - 1)*0.045)
    -- Eave band: a thin flared lip under each tier, which is what makes the
    -- roofline read as layered rather than as a stack of plain cones.
    mesh3_taper(trim_out, cx, y, cz, r, r*0.94, radius*0.045, 10, false, 3)
    mesh3_taper(roof_out, cx, y + radius*0.045, cz, r*0.94, r*0.12, roof_h, 10, false, 2)
    y = y + radius*0.045 + roof_h*0.72
    r = r*0.70
  end

  -- Finial.
  mesh3_taper(trim_out, cx, y, cz, radius*0.05, radius*0.02, radius*0.16, 6, true, 1)
  mesh3_sphere_blob(trim_out, cx, y + radius*0.20, cz, radius*0.055, 6, 4)
end

--- Append an axis-aligned box. UVs are per-face 0..1 unless `tile` is given.
function mesh3_box_geo(out, cx, cy, cz, w, h, d, tile)
  tile = tile or 1
  local x0, x1 = cx - w/2, cx + w/2
  local y0, y1 = cy - h/2, cy + h/2
  local z0, z1 = cz - d/2, cz + d/2
  local t = tile
  -- +Y (top) and -Y (bottom)
  mesh3_quad(out, x0,y1,z0, x1,y1,z0, x1,y1,z1, x0,y1,z1,  0, 1, 0, 0,0,t,t)
  mesh3_quad(out, x0,y0,z1, x1,y0,z1, x1,y0,z0, x0,y0,z0,  0,-1, 0, 0,0,t,t)
  -- +Z / -Z
  mesh3_quad(out, x0,y0,z1, x1,y0,z1, x1,y1,z1, x0,y1,z1,  0, 0, 1, 0,0,t,t)
  mesh3_quad(out, x1,y0,z0, x0,y0,z0, x0,y1,z0, x1,y1,z0,  0, 0,-1, 0,0,t,t)
  -- +X / -X
  mesh3_quad(out, x1,y0,z1, x1,y0,z0, x1,y1,z0, x1,y1,z1,  1, 0, 0, 0,0,t,t)
  mesh3_quad(out, x0,y0,z0, x0,y0,z1, x0,y1,z1, x0,y1,z0, -1, 0, 0, 0,0,t,t)
end
