-- Warp to an area with the game's own stage select, then run an aiming bot.
--   GNG_AREA   area 0-13 (0-2:stage1 3-6:stage2 7-8:stage3 9-10:stage4
--              11:stage5 12:stage6 13:final)
--   GNG_FRAMES length of the run (default 10800 = 3 min)
-- Warp: when the stage-start code reaches $D058, set $A7=$0F (unlocks the
-- built-in stage select, same as the cheat) and $AC=area; the bot then
-- presses Start on the select screen.  Graphics load through the normal path.
-- Harness interventions (logged): lives topped up when they reach 1 and the
-- stage timer reset every 60 s, so the bot can keep playing.  Pit deaths,
-- timer deaths and enemy damage are still counted.
-- Bot: face and shoot the nearest active enemy; otherwise walk right; jump
-- periodically; fire constantly.
local g = dofile(os.getenv("GAME_DIR") .. "/tests/gng.lua")
local AREA = tonumber(g.env("GNG_AREA", "0"))
local FRAMES = tonumber(g.env("GNG_FRAMES", "10800"))
local FIRST = tonumber(g.env("GNG_WFIRST", "15"))   -- $0F (spread) or $11 (vanilla)
-- GNG_BANK_AUDIT=1 (remix ROM): every mapper write must select bank 0-6 or 8
-- (bank 7 is the unused copy of the fixed bank; 9-14 are empty)
local AUDIT = g.env("GNG_BANK_AUDIT", "0") == "1"
local bank_writes, bad_banks = {}, 0
if AUDIT then
  memory.registerwrite(0x8000, 0x8000, function(a, sz, v)
    local val = v or memory.getregister("a")
    bank_writes[val] = (bank_writes[val] or 0) + 1
    if val == 7 or val > 8 then bad_banks = bad_banks + 1 end
  end)
end
local function bit(v, m) return math.floor(v / m) % 2 == 1 end

local warped, select_seen = false, 0
memory.registerexec(0xD058, 1, function()
  if not warped then
    memory.writebyte(0xA7, 0x0F)
    memory.writebyte(0xAC, AREA)
    warped = true
  end
end)
memory.registerexec(0xD089, 1, function() select_seen = emu.framecount() end)

local hits_by_slot, hit_types = {}, {}
for s = 0, 0x18 do hits_by_slot[s] = 0 end
memory.registerexec(0xF5D0, 1, function()
  local y, x = memory.getregister("y"), memory.getregister("x")
  hits_by_slot[y] = hits_by_slot[y] + 1
  local t = memory.readbyte(g.TYPE + x)
  hit_types[t] = (hit_types[t] or 0) + 1
end)
local damage, timeouts = 0, 0
memory.registerexec(0xE171, 1, function()
  if memory.readbyte(g.TIMEUP) == 0 then damage = damage + 1 else timeouts = timeouts + 1 end
end)
local bigkill = g.counter(0xF7A5)      -- big-enemy/boss death jingle + score
local finalkill = g.counter(0xF70F)    -- type $1F (final boss) death: $BF = $FF
local hazard = g.counter(0xE1BA)       -- death entry used by the fall/jump states (pits, water)
local hazard_x = {}
hazard.on_hit = function()
  hazard_x[#hazard_x + 1] = string.format("%d@f%d", memory.readbyte(0x0583) * 256 + memory.readbyte(0x05AF), emu.framecount())
end
local contact = g.counter(0xF5E8)
-- contacts by the touching object's slot: $14-$15 are enemy projectiles
local shot_contacts, shot_types = 0, {}
contact.on_hit = function()
  local x = memory.getregister("x")
  if x == 0x14 or x == 0x15 then
    shot_contacts = shot_contacts + 1
    local t = memory.readbyte(g.TYPE + x)
    shot_types[t] = (shot_types[t] or 0) + 1
  end
end
-- liveness: the task scheduler completes rounds at $C395 even while Arthur
-- is dead / respawning; a long gap means the game hung.
local last_round, max_gap = 0, 0
memory.registerexec(0xC395, 1, function()
  local f = emu.framecount()
  if last_round > 0 and f - last_round > max_gap then max_gap = f - last_round end
  last_round = f
end)
local facing_left = false
local polls = 0
memory.registerexec(0xE014, 1, function()
  polls = polls + 1
  facing_left = bit(memory.readbyte(g.FLAGS), 4)
end)

-- boot: title -> start -> stage select -> start
emu.speedmode("maximum")
g.frame(120)
g.press({start = true}, 4, 4)
local pressed_select = false
local ready = nil
for _ = 1, 3000 do
  g.frame(1)
  if select_seen > 0 and not pressed_select and emu.framecount() - select_seen < 3 then
    g.frame(30)
    g.press({start = true}, 4, 4)
    pressed_select = true
    g.wr(0xA7, 0)   -- lock the stage select again so later stage starts are normal
  end
  if pressed_select and g.rd(g.FLAGS) == 0x80 then ready = emu.framecount() break end
end
if not ready then g.finish(false, "could not reach gameplay via stage select") end
local area0, stage0 = g.rd(0xAC), g.rd(0xCF)
g.log("warp area", AREA, "-> $AC", area0, "$CF", stage0, "frame", ready, "lives", g.rd(g.LIVES))
g.shot(string.format("%s_start", g.tag))

local function wxs(s) return g.rd(g.XHI + s) * 256 + g.rd(g.XLO + s) end
local areas_seen, deaths, last_lives, interventions = {[area0] = 0}, 0, g.rd(g.LIVES), 0
local types_seen = {}
for i = 1, FRAMES do
  -- nearest active enemy
  local ax = wxs(0)
  local best, bdx = nil, 1e9
  for s = 1, FIRST - 1 do
    local f, t = g.rd(g.FLAGS + s), g.rd(g.TYPE + s)
    if bit(f, 0x80) then
      types_seen[t] = true
      local dx = wxs(s) - ax
      if math.abs(dx) < math.abs(bdx) then best, bdx = s, dx end
    end
  end
  local d = {}
  if best and math.abs(bdx) < 200 then
    if bdx < 0 and not facing_left then d.left = true
    elseif bdx > 0 and facing_left then d.right = true
    elseif math.abs(bdx) > 72 then
      if bdx > 0 then d.right = true else d.left = true end
    end
  else
    d.right = true
  end
  d.B = (i % 8) < 4
  d.A = (i % 70) < 12
  g.hold(d)
  g.frame(1)
  local a = g.rd(0xAC)
  if areas_seen[a] == nil then
    areas_seen[a] = i
    g.log(string.format("t=%ds area changed -> %d (stage $CF=%d)", math.floor(i / 60), a, g.rd(0xCF)))
    g.shot(string.format("%s_area%02d", g.tag, a))
  end
  local lv = g.rd(g.LIVES)
  if lv < last_lives then deaths = deaths + 1 end
  if lv <= 1 then g.wr(g.LIVES, 3); interventions = interventions + 1; lv = 3 end
  last_lives = lv
  if i % 3600 == 0 then g.wr(0x06F6, 3); interventions = interventions + 1 end
  if i % 1800 == 0 then g.shot(string.format("%s_%05d", g.tag, i)) end
end
g.hold({})
local function dump(t)
  local o = {}
  for k, v in pairs(t) do o[#o + 1] = string.format("%02X:%s", k, tostring(v)) end
  table.sort(o)
  return table.concat(o, " ")
end
local hs = {}
for s = FIRST, 0x13 do hs[#hs + 1] = string.format("%02X:%d", s, hits_by_slot[s]) end
local seen = {}
for k, _ in pairs(types_seen) do seen[#seen + 1] = string.format("%02X", k) end
table.sort(seen)
g.log("final area", g.rd(0xAC), "stage", g.rd(0xCF), "deaths", deaths, "timeouts", timeouts,
      "enemy_damage_routine", damage, "hazard_deaths", hazard.n, "contacts", contact.n, "big_kills", bigkill.n, "final_boss_kills", finalkill.n,
      "arthur_polls", polls, "max_scheduler_gap_frames", max_gap, "harness_interventions", interventions)
g.log("hazard deaths at world X:", table.concat(hazard_x, " "))
g.log("contacts by enemy projectiles (slots $14-$15):", shot_contacts, "types", dump(shot_types))
g.log("weapon-slot hits", table.concat(hs, " "))
g.log("hits by enemy type", dump(hit_types))
g.log("active enemy types seen", table.concat(seen, " "))
g.log("areas reached (frame):", dump(areas_seen))
if AUDIT then g.log("bank-select writes by value:", dump(bank_writes), "bad", bad_banks) end
local hung = max_gap > 600 or emu.framecount() - last_round > 600
local ok = damage == 0 and not hung and bad_banks == 0
local why = nil
if not ok then
  why = damage > 0 and "enemy damage occurred" or (hung and "game stopped scheduling tasks (hang)")
        or "unexpected bank selected"
end
g.finish(ok, why)
