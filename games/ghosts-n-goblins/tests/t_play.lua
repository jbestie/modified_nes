-- Long scripted play session: walk right, jump, fire constantly.
-- Measures, from the game's own code paths:
--   * damage events per weapon slot ($F5D0: INC $0647,X after a weapon hit)
--   * enemy-contact events and damage-routine entries (invincibility)
--   * partition violations (non-weapon object in $0F-$13, weapon outside)
--   * enemy-slot exhaustion ($DA24: FindFreeEnemySlot failed)
--   * progress (Arthur world X), deaths, stage number, crashes/hangs
-- GNG_FRAMES (default 10800 = 3 min) controls the length.
-- Harness interventions (logged), as in t_area.lua: lives topped up when they
-- reach 1 and the stage timer reset every 60 s, so the whole session is
-- gameplay (no game over / title screen).  Deaths are still counted.
local g = dofile(os.getenv("GAME_DIR") .. "/tests/gng.lua")
local function bit(v, m) return math.floor(v / m) % 2 == 1 end
local FRAMES = tonumber(g.env("GNG_FRAMES", "10800"))
local FIRST, LAST = 0x0F, 0x13
local spread = g.env("GNG_MODE", "patched") ~= "vanilla"
if not spread then FIRST, LAST = 0x11, 0x13 end

local hits_by_slot, hit_types = {}, {}
for s = 0, 0x18 do hits_by_slot[s] = 0 end
memory.registerexec(0xF5D0, 1, function()
  local y, x = memory.getregister("y"), memory.getregister("x")
  hits_by_slot[y] = hits_by_slot[y] + 1
  local t = memory.readbyte(g.TYPE + x)
  hit_types[t] = (hit_types[t] or 0) + 1
end)
local contact = g.counter(0xF5E8)
-- Slowdown: the scheduler finishes a full round of all tasks at $C395; fewer
-- rounds than frames means game logic overran a frame.
local rounds = g.counter(0xC395)
-- Sprite pressure: the game keeps the same sprites in OAM pages $02 and $03
-- (reverse order on alternate frames = its flicker rotation); scan page $02.
-- Unused sprites are parked at Y=$FF.  8x8 sprites.
local function oam_overflow()
  local oam = memory.readbyterange(0x200, 256)
  local lines = {}
  local maxl = 0
  for i = 0, 63 do
    local y = oam:byte(i * 4 + 1)
    if y < 0xEF then
      for l = y + 1, y + 8 do
        lines[l] = (lines[l] or 0) + 1
        if lines[l] > maxl then maxl = lines[l] end
      end
    end
  end
  local over = 0
  for _, c in pairs(lines) do if c > 8 then over = over + 1 end end
  return maxl, over
end
local ovf_frames, ovf_max = 0, 0
-- damage routine entered for an enemy hit (timer expiry also enters it, with $BD set)
local damage = {n = 0}
local timeouts = 0
memory.registerexec(0xE171, 1, function()
  if memory.readbyte(g.TIMEUP) == 0 then damage.n = damage.n + 1 else timeouts = timeouts + 1 end
end)
local alloc_fail = g.counter(0xDA24)
local polls = g.counter(0xE014)
local deaths = 0
local last_lives = nil
local interventions = 0

local t0 = g.start_game()
if not t0 then g.finish(false, "gameplay not reached") end
last_lives = g.rd(g.LIVES)
local violations, stray, max_enemies, max_weapons = 0, 0, 0, 0
local maxx, last_poll, hang = 0, 0, 0
local stage0 = g.rd(0x00CF)
local stages = {[stage0] = true}
for i = 1, FRAMES do
  local phase = i % 240
  local fire = (i % 8) < 4
  local jump = (i % 90) < 10
  local dir = (phase < 200) and {right = true} or {left = true}
  dir.B = fire
  dir.A = jump
  g.hold(dir)
  g.frame(1)
  -- object table audit
  local en, wp = 0, 0
  for s = 1, 0x15 do
    local f, t = g.rd(g.FLAGS + s), g.rd(g.TYPE + s)
    local weapon = f ~= 0 and t >= 0x23 and t <= 0x27
    if s >= FIRST and s <= LAST then
      if f ~= 0 and not weapon then violations = violations + 1 end
      if weapon then wp = wp + 1 end
    elseif weapon then
      stray = stray + 1
    elseif s < FIRST and bit(f, 0x80) then
      en = en + 1
    end
  end
  if en > max_enemies then max_enemies = en end
  local ml, over = oam_overflow()
  if over > 0 then ovf_frames = ovf_frames + 1 end
  if ml > ovf_max then ovf_max = ml end
  if wp > max_weapons then max_weapons = wp end
  local x = g.arthur_x()
  if x > maxx then maxx = x end
  local lv = g.rd(g.LIVES)
  if lv < last_lives then deaths = deaths + 1 end
  if lv <= 1 then g.wr(g.LIVES, 3); interventions = interventions + 1; lv = 3 end
  if i % 3600 == 0 then g.wr(0x06F6, 3); interventions = interventions + 1 end
  last_lives = lv
  stages[g.rd(0x00CF)] = true
  if polls.n == last_poll then hang = hang + 1 else hang = 0 end
  last_poll = polls.n
  if hang > 600 and i > 600 then
    -- no Arthur state code for 10 s: count it but don't stop (death/stage
    -- transitions legitimately pause Arthur's task for a while)
  end
  if i % 1200 == 0 then
    g.shot(string.format("%s_%05d", g.tag, i))
    local hs = {}
    for s = FIRST, LAST do hs[#hs + 1] = string.format("%02X:%d", s, hits_by_slot[s]) end
    g.log(string.format("t=%3ds x=%d maxx=%d lives=%d deaths=%d enemies_max=%d weapons_max=%d hits[%s] contact=%d damage=%d allocfail=%d viol=%d stray=%d stage=%d",
      math.floor(i / 60), x, maxx, lv, deaths, max_enemies, max_weapons, table.concat(hs, " "), contact.n, damage.n,
      alloc_fail.n, violations, stray, g.rd(0x00CF)))
  end
end
g.hold({})
local types = {}
for t, n in pairs(hit_types) do types[#types + 1] = string.format("%02X:%d", t, n) end
table.sort(types)
g.log("enemy types hit:", table.concat(types, " "))
g.log(string.format("scheduler rounds %d / %d frames (%.1f%% logic frames; lower = slowdown)",
      rounds.n, FRAMES, 100 * rounds.n / FRAMES))
g.log(string.format("frames with >8 sprites on a scanline: %d / %d (%.1f%%), max sprites on one line: %d",
      ovf_frames, FRAMES, 100 * ovf_frames / FRAMES, ovf_max))
local st = {}
for s, _ in pairs(stages) do st[#st + 1] = s end
table.sort(st)
g.log("stage values seen ($CF):", table.concat(st, ","), "timer deaths:", timeouts, "total deaths:", deaths,
      "harness interventions:", interventions)
local fails = {}
for s = FIRST, LAST do
  if hits_by_slot[s] == 0 then fails[#fails + 1] = string.format("slot %02X never damaged an enemy", s) end
end
if violations > 0 then fails[#fails + 1] = "non-weapon object in weapon slots: " .. violations end
if stray > 0 then fails[#fails + 1] = "weapon object outside weapon slots: " .. stray end
if max_weapons > LAST - FIRST + 1 then fails[#fails + 1] = "weapon cap exceeded" end
if polls.n < FRAMES / 6 then fails[#fails + 1] = "Arthur logic stalled (possible hang)" end
if spread and damage.n > 0 then fails[#fails + 1] = "damage routine ran " .. damage.n .. " times" end
g.finish(#fails == 0, table.concat(fails, "; "))
