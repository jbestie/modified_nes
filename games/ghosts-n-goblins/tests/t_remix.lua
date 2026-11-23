-- Remix ROM gameplay checks, one per run (GNG_CHECK):
--   rainbow  RAINBOW shot: each burst = lance, dagger, torch, axe, cross in
--            slots $0F-$13 with the fan directions (2..6 right, 10..14
--            left); the held weapon is unchanged afterwards.
--   cycle    5-WAY SPREAD: Select cycles lance > dagger > torch > axe >
--            cross > lance (held weapon, per-player copy $C5, HUD palette
--            $0553); bursts use the selected weapon; it survives a death.
--   classic  NORMAL shot + NORMAL armor: original single shots in $11-$13
--            only, Select does nothing, EnemyEnd = $11, enemies hurt Arthur.
--   armor4   4 HITS EACH: standing in the stage-1 zombie crowd, every hit
--            that reaches the damage routine follows exactly 3 absorbed hits
--            on that armor piece; each absorbed hit starts the engine's
--            post-hit invulnerability (bit 6), which ends within 3 s with
--            Arthur visible; lives are lost only after 8 hits; a timer
--            expiry still kills.
local g = dofile(os.getenv("GAME_DIR") .. "/tests/gng.lua")
local CHECK = g.env("GNG_CHECK", "rainbow")
local SHOT, ARMOR, ENEMY_END = 0x071A, 0x071B, 0xBE
local HELD, P_WEAPON, HUD_ATTR = 0x053A, 0x00C5, 0x0553
local TYPE_OF = {[0x40] = 0x23, [0x42] = 0x24, [0x44] = 0x25, [0x36] = 0x26, [0x46] = 0x27}
local function bit(v, m) return math.floor(v / m) % 2 == 1 end

local fails = {}
local function check(cond, what)
  g.log((cond and "ok   " or "FAIL ") .. what)
  if not cond then fails[#fails + 1] = what end
end

-- bursts counted at spawn time in bank 8
local spawned, bursts = 0, {}
g.exec_in(g.sym("Fire@spawned"), 8, function() spawned = spawned + 1 end)
g.exec_in(g.sym("Fire@fired"), 8, function() bursts[#bursts + 1] = spawned; spawned = 0 end)
local absorbs, absorb_frames = 0, {}
g.exec_in(g.sym("ArthurTick@absorb"), 8, function()
  absorbs = absorbs + 1
  absorb_frames[#absorb_frames + 1] = emu.framecount()
end)
-- Arthur's flags, sampled inside his own task (see t_invincible.lua)
local aflags, polls = 0, 0
memory.registerexec(0xE014, 1, function() aflags = memory.readbyte(g.FLAGS); polls = polls + 1 end)

-- title: set the modes with A/B, then start
local sessions = 0
memory.registerexec(0xC424, 1, function() sessions = sessions + 1 end)
local function start(shot, armor)
  emu.speedmode("maximum")
  for _ = 1, 600 do g.frame(1) if sessions > 0 then break end end
  g.frame(10)
  for _ = 1, 3 do if g.rd(SHOT) ~= shot then g.press({A = true}, 3, 3) end end
  for _ = 1, 3 do if g.rd(ARMOR) ~= armor then g.press({B = true}, 3, 3) end end
  g.log("modes", g.rd(SHOT), g.rd(ARMOR), "EnemyEnd", g.hex(g.rd(ENEMY_END)))
  g.press({start = true}, 4, 4)
  for _ = 1, 1500 do
    g.frame(1)
    if emu.framecount() > 900 and g.rd(g.FLAGS) == 0x80 then g.frame(20) return true end
  end
  return false
end

local function weapons_free(first)
  for _ = 1, 150 do
    local busy = false
    for s = first or 0x0F, 0x13 do if g.rd(g.FLAGS + s) ~= 0 then busy = true end end
    if not busy then return true end
    g.frame(1)
  end
  return false
end
local function burst()
  weapons_free()
  g.press({B = true}, 4, 0)
  local types, dirs = {}, {}
  for s = 0x0F, 0x13 do
    types[#types + 1] = string.format("%02X", g.rd(g.TYPE + s))
    dirs[#dirs + 1] = tostring(g.rd(g.DIR + s))
  end
  g.frame(2)
  return table.concat(types, ","), table.concat(dirs, ",")
end

if CHECK == "rainbow" then
  check(start(1, 0), "gameplay reached (RAINBOW / INVINCIBLE)")
  local held = g.rd(HELD)
  local t, d = burst()
  check(t == "23,24,25,26,27" and d == "2,3,4,5,6", "right burst types " .. t .. " dirs " .. d)
  g.frame(4); g.shot(g.tag .. "_right")
  check(g.rd(HELD) == held and g.rd(P_WEAPON) == held, string.format("held weapon kept ($%02X)", g.rd(HELD)))
  g.press({left = true}, 6, 4)
  t, d = burst()
  check(t == "23,24,25,26,27" and d == "10,11,12,13,14", "left burst types " .. t .. " dirs " .. d)
  g.frame(4); g.shot(g.tag .. "_left")
  g.press({right = true}, 6, 4)
  local n0 = #bursts
  for _ = 1, 6 do burst() end
  local sizes = {}
  for i = n0 + 1, #bursts do sizes[#sizes + 1] = tostring(bursts[i]) end
  check(#bursts - n0 == 6 and table.concat(sizes, ",") == "5,5,5,5,5,5", "six bursts of 5: " .. table.concat(sizes, ","))
  check(g.rd(HELD) == held, "held weapon still kept after 8 bursts")

elseif CHECK == "cycle" then
  check(start(0, 0), "gameplay reached (5-WAY SPREAD / INVINCIBLE)")
  local seq = {0x42, 0x44, 0x36, 0x46, 0x40, 0x42}
  local attr = {[0x40] = 0, [0x42] = 0, [0x44] = 2, [0x36] = 1, [0x46] = 0}
  for i, want in ipairs(seq) do
    g.press({select = true}, 4, 4)
    local h = g.rd(HELD)
    check(h == want and g.rd(P_WEAPON) == want and g.rd(HUD_ATTR) == attr[want],
          string.format("Select %d: held $%02X, $C5 $%02X, HUD palette %d (want $%02X/%d)",
                        i, h, g.rd(P_WEAPON), g.rd(HUD_ATTR), want, attr[want]))
    local t = burst()
    local tt = string.format("%02X", TYPE_OF[want])
    check(t == table.concat({tt, tt, tt, tt, tt}, ","), "  burst types " .. t)
  end
  g.press({select = true}, 4, 4)   -- torch
  local before = g.rd(HELD)
  g.wr(0x06F6, 0); g.wr(0x06FA, 0); g.wr(0x06FC, 1)   -- forced timeout: lose a life
  local lives = g.rd(g.LIVES)
  local back = false
  for _ = 1, 2400 do
    g.frame(1)
    if g.rd(g.LIVES) < lives and g.rd(g.FLAGS) == 0x80 then back = true break end
  end
  g.frame(30)
  check(back and g.rd(HELD) == before and g.rd(HUD_ATTR) == attr[before],
        string.format("weapon kept after a death: $%02X palette %d (was $%02X)", g.rd(HELD), g.rd(HUD_ATTR), before))

elseif CHECK == "classic" then
  check(start(2, 2), "gameplay reached (NORMAL / NORMAL)")
  check(g.rd(ENEMY_END) == 0x11, string.format("EnemyEnd $%02X", g.rd(ENEMY_END)))
  local held = g.rd(HELD)
  for _ = 1, 3 do g.press({select = true}, 4, 4) end
  check(g.rd(HELD) == held, string.format("Select does not change the weapon ($%02X)", g.rd(HELD)))
  local stray, maxw, damage = 0, 0, 0
  memory.registerexec(0xE171, 1, function() if g.rd(g.TIMEUP) == 0 then damage = damage + 1 end end)
  local lives0 = g.rd(g.LIVES)
  for i = 1, 2400 do
    local b = {}
    if i % 8 < 4 then b.B = true end
    if i > 1200 and i % 200 < 100 then b.right = true end
    g.hold(b); g.frame(1)
    local n = 0
    for s = 1, 0x15 do
      local t = g.rd(g.TYPE + s)
      if g.rd(g.FLAGS + s) ~= 0 and t >= 0x23 and t <= 0x27 then
        if s < 0x11 or s > 0x13 then stray = stray + 1 else n = n + 1 end
      end
    end
    if n > maxw then maxw = n end
  end
  g.hold({})
  local single = 0
  for _, s in ipairs(bursts) do if s == 0 then single = single + 1 end end
  check(stray == 0, "no weapon object outside $11-$13 (" .. stray .. " frames)")
  check(maxw >= 1 and maxw <= 2, "at most 2 lances at once (saw " .. maxw .. ")")
  check(#bursts > 10 and single == #bursts, string.format("%d shots, all single (no five-way spawns)", #bursts))
  check(damage > 0, string.format("enemies damage Arthur (damage routine %d x, lives %d -> %d)", damage, lives0, g.rd(g.LIVES)))

elseif CHECK == "armor4" then
  check(start(0, 1), "gameplay reached (5-WAY SPREAD / 4 HITS EACH)")
  local damage, deaths = {}, 0
  memory.registerexec(0xE171, 1, function()
    if g.rd(g.TIMEUP) == 0 then damage[#damage + 1] = absorbs end
  end)
  local death_hit = g.counter(0xE1AC)
  local lives0 = g.rd(g.LIVES)
  -- per absorbed hit: frames until bit 6 clears, and visibility then
  local pending, pending_polls, inv_frames, invisible_end, seen_absorbs = nil, 0, {}, 0, 0
  local last_lives, first_life_loss_hits = lives0, nil
  for i = 1, 3600 do
    local b = {}
    if i > 2400 and i % 90 < 20 then b.A = true end   -- last 20 s: jump in place
    g.hold(b); g.frame(1)
    if absorbs > seen_absorbs then
      seen_absorbs = absorbs
      pending, pending_polls = emu.framecount(), polls   -- judge from the next poll on
    end
    if pending and polls > pending_polls and not bit(aflags, 0x40) then
      inv_frames[#inv_frames + 1] = emu.framecount() - pending
      if not bit(aflags, 0x80) then invisible_end = invisible_end + 1 end
      pending = nil
    end
    if g.rd(g.LIVES) < last_lives then
      deaths = deaths + 1
      if not first_life_loss_hits then first_life_loss_hits = absorbs + #damage end
      last_lives = g.rd(g.LIVES)
    end
    if i == 600 then g.shot(g.tag .. "_crowd") end
  end
  g.hold({})
  -- absorbs between consecutive damage events
  local gaps, prev = {}, 0
  for _, a in ipairs(damage) do gaps[#gaps + 1] = a - prev; prev = a end
  local gap_ok = #damage > 0
  for _, gp in ipairs(gaps) do if gp ~= 3 then gap_ok = false end end
  local maxinv = 0
  for _, f in ipairs(inv_frames) do if f > maxinv then maxinv = f end end
  g.log("absorbed", absorbs, "damage events", #damage, "absorbs before each:", table.concat(gaps, ","),
        "deaths", deaths, "death_by_hit", death_hit.n, "lives", lives0, "->", g.rd(g.LIVES))
  check(absorbs >= 6, "absorbed hits: " .. absorbs)
  check(gap_ok, "every damage event follows exactly 3 absorbed hits (" .. table.concat(gaps, ",") .. ")")
  check(first_life_loss_hits == nil or first_life_loss_hits >= 8,
        "first life lost after " .. tostring(first_life_loss_hits) .. " hits (want >= 8)")
  check(#inv_frames >= absorbs - 1 and maxinv <= 180,
        string.format("invulnerability ended after each absorb (%d/%d, max %d frames)", #inv_frames, absorbs, maxinv))
  check(invisible_end == 0, "Arthur visible when invulnerability ends (" .. invisible_end .. " invisible)")
  -- timer expiry still kills (harness: wait until Arthur is in control, 3 lives)
  for _ = 1, 1200 do g.frame(1) if g.rd(g.FLAGS) == 0x80 then break end end
  g.wr(g.LIVES, 3)
  local l = g.rd(g.LIVES)
  g.wr(0x06F6, 0); g.wr(0x06FA, 0); g.wr(0x06FC, 1)
  local died = false
  for _ = 1, 600 do g.frame(1) if g.rd(g.LIVES) < l then died = true break end end
  check(died, "timer expiry still kills")
else
  fails[#fails + 1] = "unknown GNG_CHECK " .. CHECK
end

g.finish(#fails == 0, #fails > 0 and (#fails .. " checks failed: " .. fails[1]) or nil)
