-- Spread-shot geometry test: one burst facing right, one facing left.
-- PASS: each burst creates exactly five weapon objects in slots $0F-$13 with
-- directions 2..6 (right) / 10..14 (left, the mirror set); the projectiles
-- separate into a symmetric forward fan; no weapon object appears outside
-- $0F-$13.  Slot s facing right mirrors slot $22-s facing left.
local g = dofile(os.getenv("GAME_DIR") .. "/tests/gng.lua")
local function bit(v, m) return math.floor(v / m) % 2 == 1 end
local FIRST, LAST = 0x0F, 0x13

local function is_weapon(slot)
  local t = g.rd(g.TYPE + slot)
  return g.rd(g.FLAGS + slot) ~= 0 and t >= 0x23 and t <= 0x27
end
local function wx(s) return g.rd(g.XHI + s) * 256 + g.rd(g.XLO + s) end
-- World Y: $056D counts 240-line screens, $0599 is the line within a screen.
local function wy(s) return g.rd(g.YHI + s) * 240 + g.rd(g.YLO + s) end
local stray = 0
local function check_stray()
  for s = 1, 0x18 do
    if (s < FIRST or s > LAST) and s <= 0x15 then
      local t = g.rd(g.TYPE + s)
      if g.rd(g.FLAGS + s) ~= 0 and t >= 0x23 and t <= 0x27 then stray = stray + 1 end
    end
  end
end

local function burst(label)
  -- wait until all weapon slots are free
  for _ = 1, 120 do
    local busy = false
    for s = FIRST, LAST do if g.rd(g.FLAGS + s) ~= 0 then busy = true end end
    if not busy then break end
    g.frame(1)
  end
  local ax, ay = g.arthur_x(), g.arthur_y()
  -- Arthur's state code runs every 3rd frame: hold B >= 3 frames (as a human does)
  g.press({B = true}, 4, 0)
  local res = {count = 0, dirs = {}, d = {}}
  for s = FIRST, LAST do
    if is_weapon(s) then res.count = res.count + 1 end
    res.dirs[#res.dirs + 1] = g.rd(g.DIR + s)
  end
  local start, clean = {}, {}
  for s = FIRST, LAST do start[s] = {wx(s), wy(s)}; clean[s] = true end
  for f = 1, 10 do
    g.frame(1)
    check_stray()
    -- a projectile that struck an enemy/wall (bit 0 = impact) or vanished
    -- stops moving; exclude it from the geometry comparison
    for s = FIRST, LAST do
      if not is_weapon(s) or bit(g.rd(g.FLAGS + s), 1) then clean[s] = false end
    end
    if f == 6 then g.shot(g.tag .. "_" .. label) end
  end
  for s = FIRST, LAST do
    res.d[s] = {wx(s) - start[s][1], wy(s) - start[s][2], alive = is_weapon(s), clean = clean[s]}
  end
  local parts = {}
  for s = FIRST, LAST do
    parts[#parts + 1] = string.format("slot%02X dir=%d dx=%d dy=%d%s", s, g.rd(g.DIR + s),
      res.d[s][1], res.d[s][2], res.d[s].clean and "" or "(hit/gone)")
  end
  g.log(label, "arthur", ax, ay, "weapons_spawned", res.count, "dirs", table.concat(res.dirs, ","))
  g.log(label, table.concat(parts, " | "))
  return res
end

local t0 = g.start_game()
if not t0 then g.finish(false, "gameplay not reached") end
g.frame(30)
local weapon = g.rd(0x053A)
g.log("held weapon sprite id", g.hex(weapon))

local R = burst("right")
-- turn left: tap left, then fire
g.press({left = true}, 6, 4)
local L = burst("left")
-- turn right again and fire a few more bursts to check repeatability
g.press({right = true}, 6, 4)
local counts = {}
for i = 1, 6 do
  local r = burst("repeat" .. i)
  counts[#counts + 1] = r.count
end

local fails = {}
local function expect(c, msg) if not c then fails[#fails + 1] = msg end end
expect(R.count == 5, "right burst spawned " .. R.count)
expect(L.count == 5, "left burst spawned " .. L.count)
expect(table.concat(R.dirs, ",") == "2,3,4,5,6", "right dirs " .. table.concat(R.dirs, ","))
expect(table.concat(L.dirs, ",") == "10,11,12,13,14", "left dirs " .. table.concat(L.dirs, ","))
-- Geometry, using only projectiles that flew freely for the whole window.
-- Sub-pixel fractions are inherited from the slot (as in the original
-- game), so allow +-1 px.
local function near(a, b) return math.abs(a - b) <= 1 end
local EXPECT_DY = {[0x0F] = -1, [0x10] = -1, [0x11] = 0, [0x12] = 1, [0x13] = 1}
local function fan_ok(res, sign)
  local d, used = res.d, 0
  for s = FIRST, LAST do
    if d[s].clean then
      used = used + 1
      if d[s][1] * sign <= 0 then return false, "slot " .. s .. " not forward" end
      local e = EXPECT_DY[sign > 0 and s or (0x22 - s)]
      if (e == 0 and d[s][2] ~= 0) or (e < 0 and d[s][2] >= 0) or (e > 0 and d[s][2] <= 0) then
        return false, "slot " .. s .. " wrong vertical direction"
      end
    end
  end
  local function pair(a, b)
    if d[a].clean and d[b].clean then
      return near(d[a][1], d[b][1]) and near(d[a][2], -d[b][2])
    end
    return true
  end
  if not (pair(0x0F, 0x13) and pair(0x10, 0x12)) then return false, "not symmetric" end
  if used < 3 then return false, "too few unobstructed projectiles (" .. used .. ")" end
  return true
end
local ok, why = fan_ok(R, 1)
expect(ok, "right burst: " .. tostring(why))
ok, why = fan_ok(L, -1)
expect(ok, "left burst: " .. tostring(why))
-- mirror: right slot s <-> left slot $22-s: dx negated, same dy
local mirror, pairs_used = true, 0
for s = FIRST, LAST do
  local m = 0x22 - s
  if R.d[s].clean and L.d[m].clean then
    pairs_used = pairs_used + 1
    if not near(L.d[m][1], -R.d[s][1]) or not near(L.d[m][2], R.d[s][2]) then mirror = false end
  end
end
expect(mirror and pairs_used >= 3, "left burst is not the mirror image of the right burst")
for i, c in ipairs(counts) do expect(c == 5, "repeat burst " .. i .. " spawned " .. c) end
expect(stray == 0, "weapon objects outside $0F-$13: " .. stray)
g.finish(#fails == 0, table.concat(fails, "; "))
