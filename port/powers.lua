--[[
  powers.lua -- the port to Anchor: web/src/powers.js. The lich's six powers and what decides when
  they act: a snake becomes a target within ENGAGE of the egg; he casts one gestured power at a
  time (head to the spot, arm up, a beat, it goes off, hold, lower), the least used first (the
  rotation), each power growing as others are removed (power = 6 / powers left); something within
  URGENT of the egg forces a cast now. Fire, lift and beam are gestured; the lens and the rock are
  his mind alone; leakage happens by itself.
  JS's stable sorts are kept (ties broken by the original order).
  Round 50 (owner, 2026-10-05: "the order of attacks that the lich does repeats predictably"): with
  ctx.varied (the game's default; LICH_ROOM=1 keeps the old rotation, the three.js build's) the snakes
  near the egg are handled in bouts, each drawn one of four ways: ALL ONE (one attack takes every snake
  there, waiting for the group to come in), MIX OF 2, MIX OF 3 (those attacks in turn), ROTATION (any
  attack each time, repeats and all). Three or more snakes taken by one attack get its group version:
  the beam as revolver shots (he turns to each and fires), the fire as one sweep of his arm, the lift
  pulled into one knot and burst at once (lift.lua), the rocks circling him then loosed together
  (rock.lua), the lens as one long cut through them all (lens.lua). Something within URGENT still forces
  a cast now, whatever the bout.
  2026-10-15 (owner: "you get moments of burst of activity where the lich uses 3+ skills at the same time ... not like
  this where you have the lich doing 3+ skills at exactly the same time, since it both sounds weird but the animations
  also tend to not look the best they could"): in the game's flow no attack starts while two others are at work, nor
  within START_GAP of another starting (room_for); only the guarantee passes (the urgent casts, the rushes, the last
  resort). The lens is a familiar (lens.lua): between the bouts' casts it takes a snake of its own now and then, and
  every snake when the lens is the only attack or one of two.
]]
local TM = require('port.three.math')
local U = require('port.util')
local LIFT = require('port.lift')
local ROCK = require('port.rock')
local BEAM = require('port.beam')
local LENS = require('port.lens')
local LEAK = require('port.leak')
local AU = require('port.audio')     -- 2026-10-10: the sounds
local Vector3 = TM.Vector3
local sqrt, abs, sin, cos, atan2, floor, ceil, min, max, huge, pi = math.sqrt, math.abs, math.sin, math.cos, math.atan, math.floor, math.ceil, math.min, math.max, math.huge, math.pi

local PW = {}
PW.PLANS = { 'ALL ONE', 'MIX OF 2', 'MIX OF 3', 'ROTATION' }
PW.FORCES = { 'AUTO', 'ALL FIRE', 'ALL LIFT', 'ALL BEAM', 'ALL ROCK', 'ALL LENS', 'MIX OF 2', 'MIX OF 3', 'ROTATION' }
PW.ENGAGE, PW.URGENT, PW.LENS_ENGAGE = 3.4, 2.6, 6.0
local ENGAGE, URGENT, LENS_ENGAGE = PW.ENGAGE, PW.URGENT, PW.LENS_ENGAGE
local ON_T, HOLD, LOWER = 0.08, 0.45, 0.3
local ARRIVE, BEAT, AIM_MAX, QUICK_ARRIVE, QUICK_BEAT, QUICK_MAX = 0.7, 0.15, 1.2, 1.6, 0.08, 0.45
local SOON = 1.5
local HOLD_CHAIN = 0.2
PW.FACINGS = { 'TURNS TO KEEP IT IN FRONT', 'LETS GO OF IT' }
local FRONT = pi/2
local ARM_UP, FIRE_IN = 1.66, 1.4
local function jround(x) return floor(x + 0.5) end
local hyp = js_hypot
local function stable_sort(list, key)
  local dec = {}
  for i, v in ipairs(list) do dec[i] = { v = v, k = key(v), i = i } end
  table.sort(dec, function(a, b) if a.k ~= b.k then return a.k < b.k end; return a.i < b.i end)
  local out = {}
  for i, d in ipairs(dec) do out[i] = d.v end
  return out
end
local function includes(list, x) for _, v in ipairs(list) do if v == x then return true end end; return false end

function PW.create(ctx)
  local snakes, fire, lich, mover, egg, get_L, rng = ctx.snakes, ctx.fire, ctx.lich, ctx.mover, ctx.egg, ctx.get_L, ctx.rng
  local N = snakes.RINGS
  local later = {}
  local clock, power = 0, 1
  local FIRE = { name = 'FIRE', gesture = true, cooldown = 5.0, beat = 0.05 }
  function FIRE.capacity(p) return ceil(p/2) end
  function FIRE.aim_ring() return jround(N*rng.float(0.15, 0.75)) end
  function FIRE.cast(targets, from, ring)
    AU.play('fire_cast', { pos = from })
    for k, s in ipairs(targets) do
      if k == 1 then snakes.ignite(s, ring) else later[#later + 1] = { at = clock + (k - 1)*0.12, s = s } end
    end
  end
  function FIRE.update() end
  local lift = LIFT.create(ctx)
  local rock = ROCK.create(ctx)
  local beam = BEAM.create(ctx)
  local lens = LENS.create(ctx)
  local leak = LEAK.create(ctx)
  local ALL = { FIRE, lift, rock, leak, beam, lens }
  local on, nxt, last, uses, took, fair = {}, {}, {}, {}, {}, {}
  for i, a in ipairs(ALL) do on[a] = true; nxt[a] = 1.0; last[a] = -10 + (i - 1); uses[a] = 0; took[a] = 0; fair[a] = 0 end
  local function count(a, n) uses[a] = uses[a] + 1; took[a] = took[a] + n; fair[a] = fair[a] + 1 end
  local function reset_fair() for _, a in ipairs(ALL) do fair[a] = 0 end end
  local quick_lens = 0
  local function d_egg(s) return hyp(s.x - egg.x, s.z - egg.z) end
  local function unclaimed(s) return snakes.free(s) and not (s.claim and s.claim_until > clock) end
  local function claim(s, who, secs) s.claim = who; s.claim_until = clock + secs end
  local function threats(Rr)
    local out = {}
    for _, s in ipairs(snakes.S) do if unclaimed(s) and d_egg(s) < Rr then out[#out + 1] = s end end
    return stable_sort(out, d_egg)
  end
  lens.use_claims(function(s) return unclaimed(s) end, function(s) claim(s, 'LENS', 2.0) end)

  -- ------------------------------------------------------------------ round 50: the bouts
  local varied = ctx.varied or false
  local prng = U.run_rng(4111)                 -- the bouts' own draws (the old rotation's untouched)
  local fire_fx, cave = ctx.fire, ctx.cave
  local CHOOSE = { FIRE, lift, beam, rock, lens }
  local plan, force_plan, used_at, plans_log = nil, 0, {}, {}
  local groups = { BEAM = 0, FIRE = 0, LIFT = 0, ROCK = 0, LENS = 0 }   -- group casts so far
  local aborts = {}                                                      -- (why a gesture lost its aim)
  local APPROACH, ALL_R, ALL_TAKE, PLAN_QUIET, PLAN_CD = 7.5, ENGAGE + 1.6, ENGAGE + 2.8, 1.2, 1.5
  -- (round 55: a gesture with a target this near the egg goes off at once; one still free this near is taken
  -- by the last resort; a snake reaches the egg at 1.1 m, up to ~1.35 m/s)
  local FIRE_NOW, LAST = 1.6, 1.35
  local last_resorts = 0
  local VOLLEY_MIN, VOLLEY_MAX, SWEEP_W, SWEEP_V, SWEEP_SEG, SWEEP_LEAD = 0.17, 0.4, 2.6, 6.0, 0.12, 0.5
  -- (a group coming in makes one attack for all of it likelier; a lone snake, a mix or a rotation)
  local MODE_W, MODE_W_GROUP = { 0.18, 0.3, 0.25, 0.27 }, { 0.6, 0.15, 0.1, 0.15 }
  local function choosable() local out = {}; for _, a in ipairs(CHOOSE) do if on[a] and not (a == lens and lens.resting()) then out[#out + 1] = a end end; return out end
  -- how likely an attack is to be drawn: those unused longest a little likelier, and (round 55, owner,
  -- 2026-10-07: "prismatic beam and lens are also being used less than the other attacks"; measured over
  -- 5 min: lens 10 casts to the others' 16-17 standing, beam 12 to 13-19 moving) those cast fewer times
  -- so far much likelier, up to x3.4, so every attack keeps up with the most used one
  local function weight(a, top)
    return (1 + min(3, (clock - (used_at[a] or -30))/8))*(1 + 0.6*min(4, top - uses[a]))
  end
  local function top_uses(pool) local m = 0; for _, a in ipairs(pool) do m = max(m, uses[a]) end; return m end
  local function weighted(pool)
    local top, tot, w = top_uses(pool), 0, {}
    for i, a in ipairs(pool) do w[i] = weight(a, top); tot = tot + w[i] end
    local r, pick = prng.next()*tot, #pool
    for i = 1, #pool do r = r - w[i]; if r <= 0 then pick = i; break end end
    return pick
  end
  -- k of them
  local function draw(pool, k)
    local set = {}
    for _ = 1, min(k, #pool) do set[#set + 1] = table.remove(pool, weighted(pool)) end
    return set
  end
  local function new_plan()
    local av = choosable()
    if #av == 0 then plan = nil; return end
    local coming_n = 0
    for _, q in ipairs(snakes.S) do if unclaimed(q) and d_egg(q) < APPROACH + 2.5 then coming_n = coming_n + 1 end end
    local mode, set
    if force_plan >= 1 and force_plan <= 5 then
      local a = CHOOSE[force_plan]
      mode = 1; set = { on[a] and a or av[1] }
    elseif force_plan >= 6 then mode = force_plan - 4
    else
      local W = coming_n >= 3 and MODE_W_GROUP or MODE_W
      local r = prng.next()
      mode = 4
      for k = 1, 4 do r = r - W[k]; if r <= 0 then mode = k; break end end
    end
    if not set then
      if (mode == 2 or mode == 4) and #av < 2 then mode = 1 end
      if mode == 3 and #av < 3 then mode = #av >= 2 and 2 or 1 end
      set = mode == 4 and av or draw(av, mode == 1 and 1 or mode)
    end
    local most = mode == 1 and prng.int(1, 2) or (mode == 4 and prng.int(3, 5) or prng.int(2, 4))
    plan = { mode = mode, set = set, casts = 0, max = most, uses = {}, next = nil, quiet = 0, t0 = clock, group_seen = coming_n >= 3 }
    local names = {}
    for k, a in ipairs(set) do names[k] = a.name end
    plans_log[#plans_log + 1] = { t = clock, mode = PW.PLANS[mode], set = table.concat(names, '+') }
    if #plans_log > 60 then table.remove(plans_log, 1) end
  end
  -- the bout's next attack (kept until it is cast)
  local function plan_pick()
    if not plan then return nil end
    if plan.next and on[plan.next] and not (plan.next == lens and lens.resting() and #plan.set > 1) then return plan.next end
    local set = {}
    for _, a in ipairs(plan.set) do if on[a] and not (a == lens and lens.resting() and #plan.set > 1) then set[#set + 1] = a end end
    plan.set = set
    if #set == 0 then plan = nil; return nil end
    local a
    if plan.mode == 1 then a = set[1]
    elseif plan.mode == 4 or prng.next() < 0.3 then a = set[weighted(set)]
    else
      local low = huge
      for _, x in ipairs(set) do low = min(low, plan.uses[x] or 0) end
      local c = {}
      for _, x in ipairs(set) do if (plan.uses[x] or 0) == low then c[#c + 1] = x end end
      a = c[prng.int(1, #c)]
    end
    plan.next = a
    return a
  end
  -- round 52 (owner, 2026-10-06: "Sometimes some attacks will cut off other attacks and attacks will be
  -- cancelled or the animation will play wrong in some way, make sure those kinds of things can't
  -- happen"): what holds a snake now (a claim still running), for the other attacks to respect: a
  -- snake a gesture (fire, lift, beam) has chosen is left alone by the rocks, the lens's cut, the
  -- leakage and the lift's neighbours; one a rock is already flying at is left to it
  local GESTURE = { FIRE = true, LIFT = true, BEAM = true }
  local function taken_by(s) if s.claim and s.claim_until > clock then return s.claim end end
  if varied then
    snakes.taken_by = taken_by
    snakes.guarded = function(s) local c = taken_by(s); return c ~= nil and GESTURE[c] == true end
    -- an attack still on its way keeps its snake (a short claim, renewed each tick while it is)
    snakes.reclaim = function(s, who)
      local c = taken_by(s)
      if c == nil then s.claim = who; s.claim_until = clock + 0.3
      elseif string.sub(c, 1, 4) == who then s.claim_until = max(s.claim_until, clock + 0.3) end     -- (its name kept: 'LENS-QUICK' stays quick)
    end
    -- held by an attack other than `mine` ('ROCK', 'LENS'; nil: by any)
    snakes.held_by_other = function(s, mine) local c = taken_by(s); return c ~= nil and (mine == nil or string.sub(c, 1, 4) ~= mine) end
  end
  local function rocks_own(s) local c = taken_by(s); return c ~= nil and string.sub(c, 1, 4) == 'ROCK' and d_egg(s) > 1.5 end
  local function lens_own(s) local c = taken_by(s); return c ~= nil and string.sub(c, 1, 4) == 'LENS' and d_egg(s) > 2.0 end
  local function lens_has(s) local c = taken_by(s); return c ~= nil and string.sub(c, 1, 4) == 'LENS' end
  local function plan_done(a)
    used_at[a] = clock
    if not plan then return end
    plan.uses[a] = (plan.uses[a] or 0) + 1; plan.casts = plan.casts + 1
    if plan.next == a then plan.next = nil end
  end
  local function reach_of(a) return a == lens and LENS_ENGAGE or (a.engage or ENGAGE) end
  -- the snakes this cast takes now (nil: not yet)
  local function want_targets(a, quick)
    local all_one = plan and plan.mode == 1
    local Rr = reach_of(a)
    if all_one then Rr = max(Rr, ALL_TAKE) end
    local th = threats(Rr)
    if #th == 0 then return nil end
    local cap
    if all_one then
      -- every snake there at once: wait while the group is still coming in (until the first is close
      -- or all of it is within ALL_R), then take it, stragglers and all
      if not quick and d_egg(th[1]) > ENGAGE and #th < 5 then
        local coming, inside = 0, 0
        for _, q in ipairs(snakes.S) do if unclaimed(q) and d_egg(q) < APPROACH then coming = coming + 1 end end
        for _, q in ipairs(th) do if d_egg(q) < ALL_R then inside = inside + 1 end end
        if coming > inside then return nil end
      end
      cap = 6
    elseif plan and (plan.mode == 2 or plan.mode == 3) then cap = max(a.capacity(power), 2)
    else cap = max(1, a.capacity(power)) end
    if a == rock then cap = min(cap, rock.free_rocks()) end
    if a == lens and varied then
      if lens.slots() <= 0 then return nil end
      if cap < 3 then cap = min(cap, lens.slots()) end
    elseif a == lens and cap < 3 then cap = min(cap, lens.free_lenses()) end
    if cap <= 0 then return nil end
    local out = {}
    for k = 1, min(cap, #th) do out[k] = th[k] end
    return out
  end
  local G = { phase = 'idle', ab = nil, targets = {}, t = 0, on_t = 0, arm = 1, ring = 0, primary = nil, quick = false, w = 0, pw = 0, point = Vector3.new(), must_turn = false, still = 0 }
  -- 2026-10-15: at most AT_ONCE attacks at work, starts at least START_GAP apart (the game's flow). At work: the hand's
  -- gesture (aiming, firing, holding), a lens forming or cutting (a familiar floating is not), a rock in play, the
  -- lift's knot. A gesture that follows the hand's last one (chained from its hold) takes its place
  local START_GAP, AT_ONCE = 0.4, 2
  local last_start = -10
  local function started() last_start = clock end
  local function room_for(a)
    if not varied then return true end
    if clock - last_start < START_GAP then return false end
    local hand = (G.phase == 'aim' or G.phase == 'volley' or G.phase == 'sweep' or G.phase == 'hold') and G.ab or nil
    if hand and a.gesture and G.phase == 'hold' then hand = nil end
    local n = 0
    if hand and hand ~= a then n = n + 1 end
    if a ~= lens and lens.working() then n = n + 1 end
    if a ~= rock and rock.busy_count() > 0 then n = n + 1 end
    if a ~= lift and hand ~= lift and lift.held_count() > 0 then n = n + 1 end
    return n < AT_ONCE
  end
  local facing, drops, test_old = 0, 0, false
  local function rel_yaw(c) local L = get_L(); local a = atan2(c.x - L.x, c.z - L.z) - mover.yaw(); return atan2(sin(a), cos(a)) end
  local function behind(c) return abs(rel_yaw(c)) > FRONT end
  local TIP = Vector3.new()
  local LOOK = { p = Vector3.new(), t = 9 }

  local function gaze_to(c)
    local L = get_L()
    local a = atan2(c.x - L.x, c.z - L.z) - mover.yaw()
    return atan2(sin(a), cos(a)), atan2(L.y + 0.75 - c.y, max(0.3, hyp(c.x - L.x, c.z - L.z)))
  end
  local function pick_arm(c)
    local L, yw = get_L(), mover.yaw()
    local x = (c.x - L.x)*cos(yw) - (c.z - L.z)*sin(yw)
    local z = (c.x - L.x)*sin(yw) + (c.z - L.z)*cos(yw)
    return x > -0.25*abs(z) and 1 or 0
  end

  -- round 50: the group versions go one way round him, from the end nearer where he faces, across
  -- the rest (starting after the widest empty gap between them)
  local function order_round(targets)
    local L = get_L()
    local list = {}
    for k, s in ipairs(targets) do local p = s.spine[jround(N*0.3) + 1]; list[k] = { s = s, a = atan2(p.x - L.x, p.z - L.z), k = k } end
    table.sort(list, function(p, q) if p.a ~= q.a then return p.a < q.a end; return p.k < q.k end)
    local n = #list
    local gi, gap = 1, -1
    for k = 1, n do
      local a, b = list[k].a, list[k % n + 1].a
      local g = k == n and b + 2*pi - a or b - a
      if g > gap then gap = g; gi = k end
    end
    local out = {}
    for k = 1, n do out[k] = list[(gi + k - 1) % n + 1].s end
    local function off(q) return abs(rel_yaw(q.spine[jround(N*0.3) + 1])) end
    if off(out[n]) < off(out[1]) then local rev = {}; for k = n, 1, -1 do rev[#rev + 1] = out[k] end; out = rev end
    return out
  end
  local function group_of(ab, n) return varied and n >= 3 and (ab == beam or ab == FIRE) end

  local function start_gesture(ab, targets, quick)
    if group_of(ab, #targets) and not quick then targets = order_round(targets) end
    local secs = (varied and #targets >= 3) and 2.0 + 0.45*#targets or 2.0
    for _, s in ipairs(targets) do claim(s, ab.name, secs) end
    G.phase = 'aim'; G.ab = ab; G.targets = targets; G.t = 0; G.on_t = 0; G.still = 0; G.quick = quick
    started()
    G.primary = targets[1]; G.ring = ab.aim_ring()
    G.point:copy(G.primary.spine[G.ring + 1])
    -- round 50: the fire's sweep starts a little before the first (the way it will go)
    G.lead = nil
    if group_of(ab, #targets) and ab == FIRE then
      local L = get_L()
      local p, q = targets[1].spine[G.ring + 1], targets[2].spine[G.ring + 1]      -- (the way its first step goes)
      local a0, a1 = atan2(p.x - L.x, p.z - L.z), atan2(q.x - L.x, q.z - L.z)
      local w = atan2(sin(a1 - a0), cos(a1 - a0))
      G.sw_dir = w < 0 and -1 or 1
      G.lead = SWEEP_LEAD
      local a = a0 - G.sw_dir*SWEEP_LEAD
      local d = hyp(p.x - L.x, p.z - L.z)
      G.point:set(L.x + sin(a)*d, p.y, L.z + cos(a)*d)
    end
    G.arm = pick_arm(G.point)
    G.must_turn = behind(G.point)
  end

  local function tick(t, dt)
    clock = clock + dt
    if G.snd then if G.phase == 'sweep' then G.snd.set_pos(G.point) else G.snd.stop(); G.snd = nil end end
    local actives = {}
    for _, a in ipairs(ALL) do if on[a] then actives[#actives + 1] = a end end
    power = #actives > 0 and 6/#actives or 1
    leak.scale(power, ENGAGE)
    for _, a in ipairs(ALL) do nxt[a] = nxt[a] - dt end
    for i = #later, 1, -1 do if clock >= later[i].at then snakes.ignite(later[i].s); table.remove(later, i) end end

    local urgent, urgent_set = {}, {}
    for _, s in ipairs(snakes.S) do if snakes.free(s) and d_egg(s) < URGENT then urgent[#urgent + 1] = s; urgent_set[s] = true end end
    local gestured = {}
    for _, a in ipairs(actives) do if a.gesture then gestured[#gestured + 1] = a end end
    lift.update(dt)
    local low = huge
    for _, a in ipairs(actives) do
      if a ~= leak and nxt[a] < SOON and (a ~= lens or lens.free_lenses() > 0) then low = min(low, fair[a]) end
    end
    local function turn(a) return fair[a] <= low end

    -- round 50: the bout decides which gesture and how many; the guarantee still forces one now
    local function try_gesture_v()
      if #gestured == 0 then return false end
      local quick = #urgent > 0
      local ab = plan_pick()
      if quick then
        if not (ab and ab.gesture) then
          ab = nil
          for _, a in ipairs(gestured) do if nxt[a] <= 0 and (not ab or (used_at[a] or -30) < (used_at[ab] or -30)) then ab = a end end
          if not ab then
            ab = gestured[1]
            for k = 2, #gestured do local y = gestured[k]; if not (nxt[ab] <= nxt[y]) then ab = y end end
          end
        end
        nxt[ab] = 0
      elseif not (ab and ab.gesture) or nxt[ab] > 0 or not room_for(ab) then return false end
      local sel = want_targets(ab, quick)
      if quick then
        local ur = {}
        for _, q in ipairs(urgent) do if not rocks_own(q) and not lens_own(q) then ur[#ur + 1] = q end end
        if #ur == 0 then return false end
        local first = stable_sort(ur, d_egg)
        local cap = max(#first, sel and #sel or 0, ab.capacity(power))
        local out = {}
        for _, q in ipairs(first) do out[#out + 1] = q end
        if sel then for _, q in ipairs(sel) do if not urgent_set[q] and #out < cap then out[#out + 1] = q end end end
        sel = out
      elseif sel and facing == 1 then
        local keep = {}
        for _, q in ipairs(sel) do if not behind(q.spine[jround(N*0.3) + 1]) then keep[#keep + 1] = q end end
        sel = keep
      end
      if not sel or #sel == 0 then return false end
      start_gesture(ab, sel, quick)
      plan_done(ab)
      return true
    end

    local function try_gesture()
      if varied then return try_gesture_v() end
      local far = ENGAGE
      for _, a in ipairs(gestured) do far = max(far, a.engage or ENGAGE) end
      local th_all = threats(far)
      if not (#th_all > 0 or #urgent > 0) or #gestured == 0 then return false end
      local quick = #urgent > 0
      local function has(a)
        if quick then return true end
        for _, s in ipairs(th_all) do if d_egg(s) < (a.engage or ENGAGE) then return true end end
        return false
      end
      local ready = {}
      for _, a in ipairs(gestured) do if nxt[a] <= 0 and (quick or turn(a)) and has(a) then ready[#ready + 1] = a end end
      if #ready == 0 and quick then
        local a = gestured[1]
        for k = 2, #gestured do local y = gestured[k]; if not (nxt[a] <= nxt[y]) then a = y end end
        nxt[a] = 0; ready = { a }
      end
      if #ready == 0 then return false end
      local ab = ready[1]
      for k = 2, #ready do
        local y = ready[k]
        if not (fair[ab] < fair[y] or (fair[ab] == fair[y] and last[ab] <= last[y])) then ab = y end
      end
      local th = {}
      for _, s in ipairs(th_all) do if d_egg(s) < (ab.engage or ENGAGE) then th[#th + 1] = s end end
      local first = quick and stable_sort(urgent, d_egg) or {}
      local notur = {}
      for _, s in ipairs(th) do if not urgent_set[s] then notur[#notur + 1] = s end end
      local ahead = stable_sort(notur, function(s) return (not test_old and behind(s.spine[jround(N*0.3) + 1])) and 1 or 0 end)
      local pick = {}
      for _, s in ipairs(first) do pick[#pick + 1] = s end
      for _, s in ipairs(ahead) do
        if facing ~= 1 or not behind(s.spine[jround(N*0.3) + 1]) then pick[#pick + 1] = s end
      end
      if #pick == 0 then return false end
      local n = max(1, ab.capacity(power))
      local sel = {}
      for k = 1, min(n, #pick) do sel[k] = pick[k] end
      start_gesture(ab, sel, quick)
      return true
    end

    if varied and (G.phase == 'aim' or G.phase == 'volley' or G.phase == 'sweep') then
      -- (round 52: a gesture under way keeps the snakes it has yet to strike)
      for k = (G.phase == 'aim' and 1 or G.vi), #G.targets do
        local q = G.targets[k]
        if q and snakes.free(q) then snakes.reclaim(q, G.ab.name) end
      end
    end
    if varied then
      local near = false
      for _, q in ipairs(snakes.S) do if snakes.free(q) and d_egg(q) < APPROACH then near = true; break end end
      if plan then
        plan.quiet = near and 0 or plan.quiet + dt
        if plan.quiet > PLAN_QUIET or plan.casts >= plan.max then plan = nil end
      end
      -- a group coming in (three or more not yet taken) begins a bout of its own, once this one has acted
      if plan and plan.casts >= 1 and plan.mode ~= 1 and not plan.group_seen then
        local coming = 0
        for _, q in ipairs(snakes.S) do if unclaimed(q) and d_egg(q) < APPROACH + 2.5 then coming = coming + 1 end end
        if coming >= 3 then plan = nil end
      end
      if not plan and near then new_plan() end
    end

    if G.phase == 'idle' then
      try_gesture()
    elseif G.phase == 'aim' then
      G.t = G.t + dt
      local s = G.primary
      if varied and on[G.ab] and not snakes.free(s) then
        -- (round 52: its snake gone to something else: aim at the next of its own, or another near)
        local nx
        for _, q in ipairs(G.targets) do if snakes.free(q) then nx = q; break end end
        if not nx then
          local th = threats(reach_of(G.ab) + 0.6)
          if #th == 0 then th = threats(APPROACH + 2.5) end      -- (one further out rather than the arm dropping)
          nx = th[1]
          if nx then claim(nx, G.ab.name, 2.0); G.targets = { nx } end
        end
        if nx then G.primary = nx; s = nx end
      end
      if not on[G.ab] or not snakes.free(s) or (facing == 1 and not G.must_turn and behind(s.spine[G.ring + 1])) then
        if on[G.ab] and snakes.free(s) then drops = drops + 1 end
        if varied then
          aborts[#aborts + 1] = string.format('%s on %s free %s by %s claim %s', G.ab.name, tostring(on[G.ab]), tostring(snakes.free(s)),
            tostring(s.fx and s.fx.by or (s.burn and 'burn') or (s.coil and 'coil') or (s.delay > 0 and 'gone') or '-'), tostring(s.claim))
          if #aborts > 30 then table.remove(aborts, 1) end
        end
        for _, q in ipairs(G.targets) do q.claim = nil end
        G.phase = 'lower'; G.t = 0
      else
        G.point:copy(s.spine[G.ring + 1])
        -- (round 50: a group can take a while; one of it nearing the egg hurries the gesture)
        if varied and not G.quick then
          for _, q in ipairs(G.targets) do if snakes.free(q) and d_egg(q) < URGENT then G.quick = true; break end end
        end
        if G.lead then
          local L = get_L()
          local a = atan2(G.point.x - L.x, G.point.z - L.z) - G.sw_dir*G.lead
          local d = hyp(G.point.x - L.x, G.point.z - L.z)
          G.point:set(L.x + sin(a)*d, G.point.y, L.z + cos(a)*d)
        end
        local gy = gaze_to(G.point)
        local S = lich.springs
        local reach = max(-1.45, min(1.45, gy))
        G.on_t = abs(reach - (S.hy.x + S.cy.x)) < 0.12 and G.on_t + dt or 0
        local arrived = G.pw >= 1 and G.on_t >= ON_T and lich.arm_speed(G.arm) < (G.quick and QUICK_ARRIVE or ARRIVE) and (test_old or abs(rel_yaw(G.point)) < FIRE_IN)
        G.still = arrived and G.still + dt or 0
        local beat = min(G.ab.beat or BEAT, G.quick and QUICK_BEAT or 9)
        -- (round 55, owner: a snake reached the egg with all six held: an urgent gesture still took up to
        -- QUICK_MAX to raise the arm and fire, longer than a snake within ~1.5 m needs. One of its targets
        -- that close: it goes off now, the arm where it is)
        local now = false
        if varied then for _, q in ipairs(G.targets) do if snakes.free(q) and d_egg(q) < FIRE_NOW then now = true; break end end end
        if now or G.still >= beat or G.t >= (G.quick and QUICK_MAX or AIM_MAX) then
          local targets = {}
          for _, q in ipairs(G.targets) do if snakes.free(q) then targets[#targets + 1] = q end end
          lich.fingertip(G.arm, TIP)
          if group_of(G.ab, #targets) then
            -- round 50: the first shot / the first to catch fire; the rest in turn (volley / sweep below)
            G.targets = targets; G.vi = 2; G.on_t = 0; G.tail = nil
            groups[G.ab.name] = groups[G.ab.name] + 1
            if G.ab == beam then beam.shot(targets[1], G.ring, G.arm); G.phase = 'volley'
            else
              -- from the lead-in, through each (each catches as it passes), and on a little past the last
              local L = get_L()
              G.vi = 1; G.tail = nil
              G.sw_a = atan2(G.point.x - L.x, G.point.z - L.z); G.sw_d = hyp(G.point.x - L.x, G.point.z - L.z); G.sw_y = G.point.y; G.sf = 0
              G.phase = 'sweep'
              AU.play('fire_cast', { pos = TIP })
              G.snd = AU.loop('fire_sweep', { pos = G.point })      -- (follows the point; stops when the sweep does)
            end
          else
            G.ab.cast(targets, TIP, G.ring, G.arm, G.quick)
            G.phase = 'hold'
          end
          count(G.ab, #targets); started()     -- (its release: the others' starts keep their distance from it too)
          nxt[G.ab] = (varied and PLAN_CD or G.ab.cooldown)/power; last[G.ab] = clock
          G.t = 0
        end
      end
    elseif G.phase == 'volley' or G.phase == 'sweep' then
      G.t = G.t + dt
      -- the next one still there (one about to reach the egg goes first)
      local s
      for k = G.vi, #G.targets do
        local q = G.targets[k]
        if snakes.free(q) then
          if not s then s = q; if k ~= G.vi then G.targets[G.vi], G.targets[k] = G.targets[k], G.targets[G.vi] end end
          if G.phase == 'volley' and d_egg(q) < 1.9 and d_egg(q) < d_egg(s) then
            G.targets[G.vi], G.targets[k] = G.targets[k], G.targets[G.vi]; s = q
          end
        end
      end
      if G.phase == 'sweep' and not s and not G.tail then
        G.tail = G.sw_a + G.sw_dir*SWEEP_LEAD
      end
      -- the guarantee inside a group: one of it nearing the egg hurries the rest, and one about to reach
      -- it is taken now (the next shot goes to it at once; the sweep's fire leaps to it)
      local close = nil
      for k = G.vi, #G.targets do
        local q = G.targets[k]
        if snakes.free(q) then
          local d = d_egg(q)
          if d < URGENT then G.quick = true end
          if d < 1.6 and (not close or d < d_egg(close)) then close = q end
        end
      end
      if close and G.phase == 'sweep' and on[G.ab] then snakes.ignite(close, G.ring) end
      if not on[G.ab] then
        for _, q in ipairs(G.targets) do q.claim = nil end
        G.phase = 'lower'; G.t = 0; G.tail = nil
      elseif G.tail then
        -- the follow-through: the arm runs on past the last, the floor still catching
        local L = get_L()
        local da = atan2(sin(G.tail - G.sw_a), cos(G.tail - G.sw_a))
        local step = SWEEP_W*dt
        local a0 = G.sw_a
        if abs(da) <= step then G.sw_a = G.tail; G.tail = nil; G.phase = 'hold'; G.t = 0
        else G.sw_a = G.sw_a + (da > 0 and step or -step) end
        for k = 1, 3 do
          local a = a0 + (G.sw_a - a0)*k/3
          local x, z = L.x + sin(a)*G.sw_d, L.z + cos(a)*G.sw_d
          fire_fx.lick(x, cave.ground_y(x, z), z)
        end
        G.point:set(L.x + sin(G.sw_a)*G.sw_d, G.sw_y, L.z + cos(G.sw_a)*G.sw_d)
      elseif not s then G.phase = 'hold'; G.t = 0
      elseif G.phase == 'volley' then
        -- the revolver: turn to it, and fire
        G.point:copy(s.spine[G.ring + 1])
        local gy = gaze_to(G.point)
        local S = lich.springs
        local reach = max(-1.45, min(1.45, gy))
        G.on_t = abs(reach - (S.hy.x + S.cy.x)) < 0.2 and G.on_t + dt or 0
        local lo, hi = G.quick and 0.1 or VOLLEY_MIN, G.quick and 0.25 or VOLLEY_MAX
        if (close == s) or (G.t >= lo and ((G.on_t >= 0.03 and lich.arm_speed(G.arm) < 3.5 and abs(rel_yaw(G.point)) < FIRE_IN) or G.t >= hi)) then
          beam.shot(s, G.ring, G.arm)
          G.vi = G.vi + 1; G.t = 0; G.on_t = 0
          if G.vi > #G.targets then G.phase = 'hold' end
        end
      else
        -- the sweep: the point runs round him to the next, setting the floor alight on its way
        local L = get_L()
        local b = s.spine[G.ring + 1]
        local a1, d1 = atan2(b.x - L.x, b.z - L.z), hyp(b.x - L.x, b.z - L.z)
        local da = atan2(sin(a1 - G.sw_a), cos(a1 - G.sw_a))
        local sw = G.quick and 1.8 or 1
        local need = max(abs(da)/(SWEEP_W*sw), abs(d1 - G.sw_d)/(SWEEP_V*sw), SWEEP_SEG*(1 - G.sf)/sw)
        local f = min(1, dt/max(dt, need))
        local a0, d0, y0 = G.sw_a, G.sw_d, G.sw_y
        G.sw_a = G.sw_a + da*f; G.sw_d = G.sw_d + (d1 - G.sw_d)*f; G.sw_y = G.sw_y + (b.y - G.sw_y)*f
        G.sf = min(1, G.sf + dt/SWEEP_SEG)
        for k = 1, 3 do
          local u = k/3
          local a, d = a0 + (G.sw_a - a0)*u, d0 + (G.sw_d - d0)*u
          local x, z = L.x + sin(a)*d, L.z + cos(a)*d
          fire_fx.lick(x, cave.ground_y(x, z), z)
        end
        G.point:set(L.x + sin(G.sw_a)*G.sw_d, G.sw_y, L.z + cos(G.sw_a)*G.sw_d)
        if f >= 1 then
          snakes.ignite(s, G.ring)
          G.vi = G.vi + 1; G.sf = 0
          if G.vi > #G.targets then G.tail = G.sw_a + G.sw_dir*SWEEP_LEAD end
        end
      end
    elseif G.phase == 'hold' then
      G.t = G.t + dt
      local channel = G.ab.busy and G.ab.busy() or false
      if channel then G.t = 0; local p = G.ab.aim_point(); if p then G.point:copy(p) end end
      if facing == 1 and not G.must_turn and behind(G.point) then
        if channel and G.ab.let_go then G.ab.let_go() end
        drops = drops + 1; G.phase = 'lower'; G.t = 0; channel = false
      end
      if #urgent > 0 then
        if channel and G.ab.extend then
          local ul = {}
          for k, s in ipairs(urgent) do ul[k] = s end
          if varied then
            -- (round 52: not one a rock is already flying at, or the lens already burning toward)
            local keep = {}
            for _, s in ipairs(ul) do if not rocks_own(s) and not lens_own(s) then keep[#keep + 1] = s end end
            ul = keep
          end
          if not G.ab.extend(ul, G.arm) then
            if varied and G.ab == beam then
              -- (round 52: the beams already out finish from where they were fired; the hand is free)
              beam.detach(); G.phase = 'idle'; G.t = 0; G.ab = nil
            elseif G.ab.cut then G.ab.cut() end
          end
        elseif not channel then G.phase = 'idle'; G.t = 0; G.ab = nil end
      end
      if G.phase == 'hold' and not channel and G.t >= HOLD_CHAIN and try_gesture() then
      elseif G.phase == 'hold' and G.t >= HOLD then G.phase = 'lower'; G.t = 0 end
    elseif G.phase == 'lower' then
      G.t = G.t + dt
      if try_gesture() then
      elseif G.t >= LOWER or #urgent > 0 then G.phase = 'idle'; G.t = 0; G.ab = nil end
    end
    if G.phase == 'aim' then
      G.w = min(1, G.w + dt/0.12)
      if test_old or abs(rel_yaw(G.point)) < ARM_UP then G.pw = min(1, G.pw + dt/(G.quick and 0.12 or 0.22))
      else G.pw = max(0, G.pw - dt/0.2) end
    elseif G.phase == 'hold' or G.phase == 'volley' or G.phase == 'sweep' then
      G.w = 1
      if test_old or abs(rel_yaw(G.point)) < ARM_UP then G.pw = min(1, G.pw + dt/0.15)
      else G.pw = max(0.2, G.pw - dt/0.15) end
    else G.w = max(0, G.w - dt/LOWER); G.pw = max(0, G.pw - dt/LOWER) end
    local pointing = G.phase == 'aim' or G.phase == 'hold' or G.phase == 'volley' or G.phase == 'sweep'
    mover.face.on = not test_old and pointing and (facing == 0 or G.must_turn)
    if varied then mover.face.boost = (G.phase == 'volley' and 1.7) or (G.phase == 'sweep' and 1.3) or nil end
    if mover.face.on then local L = get_L(); mover.face.yaw = atan2(G.point.x - L.x, G.point.z - L.z) end
    local m = mover.motion
    m.gaze_w = G.w
    if G.w > 0 then m.gaze, m.gaze_p = gaze_to(G.point) end
    LOOK.t = LOOK.t + dt
    if G.w < 0.05 and LOOK.t < 1.1 then
      m.gaze_w = 0.85*min(1, LOOK.t/0.15)*(1 - max(0, (LOOK.t - 0.8)/0.3))
      m.gaze, m.gaze_p = gaze_to(LOOK.p)
    end
    m.point = G.pw > 0 and { w = G.pw*G.pw*(3 - 2*G.pw), arm = G.arm, x = G.point.x, y = G.point.y, z = G.point.z } or nil

    -- the lens
    -- (2026-10-15) one familiar, or (the lens all he has) as many as it could cast at once, each staying. 2026-10-16
    -- (owner: "When there's only the lens and another attack it tends to be overactive and thus only the lens attacks"):
    -- this was "the lens one of two", and with one other attack the familiar, resting 0.15 s and reaching 6 m, took
    -- nearly every snake before the other could (3 min each: the lift 9 to its 76, the beam 14 to 73). Now strong
    -- only when no other attack takes snakes (the leakage only wears them down)
    local strong = false
    if varied then
      local takers = 0
      for _, a in ipairs(actives) do if a ~= leak then takers = takers + 1 end end
      strong = takers <= 1
      lens.set_familiars(strong and lens.capacity(power) or 1, strong)
      if not on[lens] then lens.dismiss() end
    end
    if on[lens] then
      local lone = #gestured == 0
      local busy_hand = G.phase == 'aim' or G.phase == 'volley' or G.phase == 'sweep'
      local rush = nil
      if lone or busy_hand then
        rush = {}
        for _, s in ipairs(urgent) do
          if not (s.claim and s.claim_until > clock and string.find(s.claim, 'QUICK', 1, true)) and not (busy_hand and includes(G.targets, s))
            and not (varied and (rocks_own(s) or (lens_has(s) and lens.hurry(s) and d_egg(s) > 1.8) or (busy_hand and snakes.guarded(s)))) then rush[#rush + 1] = s end
        end
      end
      if rush and #rush > 0 then
        local targets = {}
        for k = 1, min(#rush, lens.free_lenses()) do targets[k] = rush[k] end
        for _, s in ipairs(targets) do claim(s, 'LENS-QUICK', 1.2) end
        lens.cast(targets, true)
        if #targets > 0 then count(lens, #targets); quick_lens = quick_lens + 1; started() end
      elseif varied then
        if plan_pick() == lens and nxt[lens] <= 0 and lens.slots() > 0 and room_for(lens) then
          local targets = want_targets(lens)
          if targets then
            local grp = #targets >= 3
            for _, s in ipairs(targets) do claim(s, 'LENS', grp and 4.5 or 2.6) end
            local at = grp and lens.cast_group(targets) or lens.cast(targets)
            if grp then groups.LENS = groups.LENS + 1 end
            count(lens, #targets); plan_done(lens); started()
            if #at > 0 then LOOK.p:copy(at[1]); LOOK.t = 0 end
            nxt[lens] = PLAN_CD/power; last[lens] = clock
          end
        else
          -- (2026-10-15) the familiar, between the bouts' casts: a snake of its own when it has rested its while
          -- (every one there is when the lens is all he has: a long cut through three or more)
          local f = lens.idle_familiar()
          if f and f.idle_t >= (strong and 0.15 or f.cd) and room_for(lens) then
            local th = threats(LENS_ENGAGE)
            if #th > 0 then
              local targets = { th[1] }
              if strong and #th >= 3 then targets = {}; for k = 1, min(6, #th) do targets[k] = th[k] end end
              local grp = #targets >= 3
              for _, s in ipairs(targets) do claim(s, 'LENS', grp and 4.5 or 2.6) end
              local at = grp and lens.cast_group(targets) or lens.cast(targets)
              if #at > 0 then
                if grp then groups.LENS = groups.LENS + 1 end
                count(lens, #targets); started(); used_at[lens] = clock
                LOOK.p:copy(at[1]); LOOK.t = 0
              else for _, s in ipairs(targets) do s.claim = nil end end
            end
          end
        end
      elseif nxt[lens] <= 0 and turn(lens) then
        local th = threats(LENS_ENGAGE)
        local n = min(lens.capacity(power), lens.free_lenses(), #th)
        if n > 0 then
          local targets = {}
          for k = 1, n do targets[k] = th[k] end
          for _, s in ipairs(targets) do claim(s, 'LENS', 2.6) end
          local at = lens.cast(targets)
          count(lens, #targets)
          if #at > 0 then LOOK.p:copy(at[1]); LOOK.t = 0 end
          nxt[lens] = lens.cooldown/power; last[lens] = clock
        end
      end
    end
    -- the rock
    if on[rock] then
      local busy_hand = G.phase == 'aim' or G.phase == 'volley' or G.phase == 'sweep'
      local rush = nil
      if #gestured == 0 or busy_hand then
        rush = {}
        for _, s in ipairs(urgent) do
          if not (s.claim and s.claim_until > clock and string.find(s.claim, 'QUICK', 1, true)) and not (busy_hand and includes(G.targets, s))
            and not (varied and (rocks_own(s) or lens_own(s) or (busy_hand and snakes.guarded(s)))) then rush[#rush + 1] = s end
        end
      end
      if rush and #rush > 0 and rock.free_rocks() > 0 then
        local targets = {}
        for k = 1, min(#rush, min(2, rock.free_rocks())) do targets[k] = rush[k] end
        for _, s in ipairs(targets) do claim(s, 'ROCK-QUICK', 1.2) end
        rock.cast(targets, nil, 0, 1, true)
        count(rock, #targets); started()
      elseif varied then
        if plan_pick() == rock and nxt[rock] <= 0 and rock.free_rocks() > 0 and room_for(rock) then
          local targets = want_targets(rock)
          if targets then
            local grp = #targets >= 3
            for _, s in ipairs(targets) do claim(s, 'ROCK', grp and 4.0 or 2.6) end
            rock.cast(targets, nil, 0, 1, false, grp)
            if grp then groups.ROCK = groups.ROCK + 1 end
            count(rock, #targets); plan_done(rock); started()
            nxt[rock] = PLAN_CD/power; last[rock] = clock
            local p = rock.hold_at()
            if p and G.w < 0.05 then LOOK.p:copy(p); LOOK.t = 0 end
          end
        end
      elseif nxt[rock] <= 0 and turn(rock) and rock.free_rocks() > 0 then
        local th = threats(rock.engage)
        local n = min(rock.capacity(power), rock.free_rocks(), #th)
        if n > 0 then
          local targets = {}
          for k = 1, n do targets[k] = th[k] end
          for _, s in ipairs(targets) do claim(s, 'ROCK', 2.6) end
          rock.cast(targets)
          count(rock, #targets)
          nxt[rock] = rock.cooldown/power; last[rock] = clock
          local p = rock.hold_at()
          if p and G.w < 0.05 then LOOK.p:copy(p); LOOK.t = 0 end
        end
      end
    end
    -- round 55, the last resort (owner, 2026-10-07: a snake reached the egg with all six held; traced: a snake a
    -- rock or a lens had claimed was left to it until 1.5 / 2.0 m out, and they don't always arrive in time, then
    -- the urgent gesture was too slow): anything still free this near is taken now by whatever takes at once,
    -- whatever the hand is doing: the fire leaps to it, or a lift takes it, or a beam shot
    if varied then
      for _, s in ipairs(snakes.S) do
        if snakes.free(s) and d_egg(s) < LAST then
          local a = (on[FIRE] and FIRE) or (on[lift] and lift) or (on[beam] and beam) or nil
          if a then
            if a == FIRE then snakes.ignite(s)
            elseif a == lift then lich.fingertip(G.arm or 1, TIP); lift.cast({ s }, TIP, jround(N*0.5), G.arm or 1)
            else beam.shot(s, jround(N*0.3), G.arm or 1) end
            count(a, 1); used_at[a] = clock; started()
            last_resorts = last_resorts + 1
          end
        end
      end
    end
    local urg = nil
    if not (#gestured > 0 or on[lens] or on[rock]) then urg = urgent_set end
    leak.update(t, dt, on[leak], urg)
    beam.update(t, dt)
    rock.update(t, dt)
    lens.update(t, dt)
  end

  local P = { ALL = ALL, tick = tick, beam = beam, lens = lens, rock = rock, lift = lift, leak = leak }
  function P.after_pose(t) beam.after_pose(t) end
  function P.power() return power end
  function P.is_on(a) return on[a] end
  function P.glance(p) LOOK.p:copy(p); LOOK.t = 0 end
  function P.toggle(i)
    local a = ALL[i + 1]
    if a then on[a] = not on[a]; reset_fair() end
    return a and on[a]
  end
  function P.set(i, v)
    local a = ALL[i + 1]
    if a and on[a] ~= (not not v) then on[a] = not not v; reset_fair() end
  end
  function P.state()
    local names, nx = {}, {}
    for _, a in ipairs(ALL) do if on[a] then names[#names + 1] = a.name end; nx[#nx + 1] = nxt[a] end
    local us, tk = {}, {}
    for _, a in ipairs(ALL) do us[a.name] = a == leak and snakes.dissolved or uses[a]; tk[a.name] = a == leak and snakes.dissolved or took[a] end
    return { phase = G.phase, ab = G.ab and G.ab.name, t = G.t, power = power, on = names, next = nx, leak_reach = leak.reach(), uses = us, took = tk }
  end
  function P.quick_lens() return quick_lens end
  -- round 50: the bouts (testing: force one way; what the bout is now; the last ones)
  P.varied = varied
  function P.force_plan(i) local n = #PW.FORCES; force_plan = ((i % n) + n) % n; plan = nil; return PW.FORCES[force_plan + 1] end
  function P.get_force() return force_plan end
  function P.plan()
    if not plan then return nil end
    local names = {}
    for k, a in ipairs(plan.set) do names[k] = a.name end
    return { mode = PW.PLANS[plan.mode], set = names, casts = plan.casts, max = plan.max, next = plan.next and plan.next.name }
  end
  function P.plans_log() return plans_log end
  function P.aborts() return aborts end
  function P.groups() groups.LIFT = lift.knots(); return groups end
  function P.gesture_phase() return G.phase, G.ab and G.ab.name, #G.targets end
  function P.last_resorts() return last_resorts end
  function P.gesture_debug() return { t = G.t, quick = G.quick, still = G.still, pw = G.pw, on_t = G.on_t, primary = G.primary, targets = G.targets } end
  function P.get_facing() return facing end
  function P.set_facing(i) local n = #PW.FACINGS; facing = ((i % n) + n) % n end
  function P.drops() return drops end
  function P.set_test_old(v) test_old = not not v end
  function P.reset_uses() for _, a in ipairs(ALL) do uses[a] = 0; took[a] = 0 end end
  function P.force(i, x, z)
    local a = ALL[i + 1]
    local lv = {}
    for _, s in ipairs(snakes.S) do if unclaimed(s) then lv[#lv + 1] = s end end
    lv = stable_sort(lv, function(p) return hyp(p.x - x, p.z - z) end)
    if #lv == 0 or not a then return -1 end
    local function index_of(s) for k, q in ipairs(snakes.S) do if q == s then return k - 1 end end; return -1 end
    if a == lens then lens.cast({ lv[1] }); return index_of(lv[1]) end
    if a.gesture and G.phase == 'idle' then
      local n = max(1, a.capacity(power))
      local sel = {}
      for k = 1, min(n, #lv) do sel[k] = lv[k] end
      start_gesture(a, sel, false)
      return index_of(lv[1])
    end
    return -1
  end
  return P
end

return PW
