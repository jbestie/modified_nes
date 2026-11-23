-- Collision probe: a simple bot plays stage 1 (walk right, face+whip nearby
-- enemies, throw the subweapon SUBW every 150 frames) and logs collision events
-- from exec hooks in bank 7 (whip hit, subweapon hit, contact hit, kills, candle
-- breaks, pickups) and the stores to HP $45, hearts $71, $5B and slots $14-$16.
-- Run: python3 scripts/run_fceux.py games/castlevania/rom/original.nes games/castlevania/tests/explore/obj_collide.lua --game-dir games/castlevania --out <dir> --tag collide [--env SUBW=08 --env FRAMES=5000]
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("maximum")
local FRAMES = tonumber(t.env("FRAMES", "5000"))
local SUBW = tonumber(t.env("SUBW", "08"), 16)
local frame = 0
local counts = {}
local function ev(key, line)
  counts[key] = (counts[key] or 0) + 1
  if counts[key] <= tonumber(t.env("MAXEV", "12")) then t.log(string.format("f%d ", frame) .. line) end
end
local function stack(n)
  local sp = memory.getregister("s")
  local p = {}
  for i = 1, n do p[#p + 1] = string.format("%02X", memory.readbyte(0x100 + AND(sp + i, 0xFF))) end
  return table.concat(p, " ")
end
local function reg(r) return memory.getregister(r) end
local function obj(x) return string.format("slot%02X type%02X X=%02X Y=%02X", x, t.rd(0x434 + x), t.rd(0x38C + x), t.rd(0x354 + x)) end

memory.registerexec(0xE550, 1, function() ev("whiphit", "WHIP-HIT " .. obj(reg("x")) .. string.format(" whipbox X=%02X Y=%02X w=%02X h=%02X lvl=%d", t.rd(0x68), t.rd(0x69), t.rd(0x73), t.rd(0x74), t.rd(0x70))) end)
memory.registerexec(0xE65D, 1, function() local y = reg("y"); ev("subhit", "SUBW-HIT " .. obj(reg("x")) .. " by " .. obj(y) .. string.format(" kind=%02X", t.rd(0x584 + y))) end)
memory.registerexec(0xE714, 1, function() ev("contact" .. t.rd(0x08), "CONTACT " .. obj(reg("x")) .. string.format(" item=%d simon X=%02X Y=%02X inv=%02X", t.rd(0x08), t.rd(0x38C), t.rd(0x354), t.rd(0x5B))) end)
memory.registerexec(0xE097, 1, function() ev("kill", "KILL " .. obj(reg("x")) .. string.format(" atk$0E=%02X dmg$0D=%02X $0C=%02X frame$1A=%02X", t.rd(0x0E), t.rd(0x0D), t.rd(0x0C), t.rd(0x1A))) end)
memory.registerexec(0xE3D7, 1, function() ev("candle", "CANDLE-BREAK " .. obj(reg("x")) .. string.format(" atk$0E=%02X drop=%02X", t.rd(0x0E), t.rd(0x584 + reg("x")))) end)
memory.registerexec(0xE762, 1, function() local x = reg("x"); ev("pickup", "PICKUP " .. obj(x) .. string.format(" item=%02X", t.rd(0x584 + x))) end)
memory.registerwrite(0x0045, 1, function(a, s, v) ev("hp", string.format("HP<-%02X (was %02X) pc=%04X stack=%s stage=%02X $2B=%02X", v or 0, t.rd(0x45), reg("pc"), stack(8), t.rd(0x28), t.rd(0x2B))) end)
memory.registerwrite(0x0071, 1, function(a, s, v) ev("hearts" .. reg("pc"), string.format("HEARTS<-%02X pc=%04X stack=%s", v or 0, reg("pc"), stack(6))) end)
memory.registerwrite(0x005B, 1, function(a, s, v) if (v or 0) > t.rd(0x5B) + 1 then ev("inv", string.format("INV<-%02X pc=%04X stack=%s", v or 0, reg("pc"), stack(6))) end end)
memory.registerwrite(0x0448, 3, function(a, s, v) ev("proj" .. (v or 0), string.format("PROJ slot%02X<-%02X pc=%04X stack=%s kind=%02X subw=%02X", a - 0x434, v or 0, reg("pc"), stack(6), t.rd(0x584 + a - 0x434), t.rd(0x15B))) end)

emu.poweron()
t.frame(300)
t.press({start = true}, 4, 0)
t.frame(800)
local nextthrow, cool = 150, 0
for k = 1, FRAMES do
  frame = k
  if k == 2 then t.wr(0x015B, SUBW); t.wr(0x0071, 0x40) end
  if t.rd(0x45) < 0x10 and t.rd(0x45) < 0x80 then t.wr(0x45, 0x40) end
  local sx, sy = t.rd(0x38C), t.rd(0x354)
  local best, bdx = nil, 999
  for i = 4, 0x0D do
    local ty = t.rd(0x434 + i)
    if ty > 0 and ty < 0x28 and t.rd(0x300 + i) == 0 then
      local dx = t.rd(0x38C + i) - sx
      if math.abs(dx) < math.abs(bdx) and math.abs(t.rd(0x354 + i) - sy) < 0x28 then best, bdx = i, dx end
    end
  end
  local b = {right = true}
  if cool > 0 then cool = cool - 1; b = {}
  elseif best and math.abs(bdx) < 0x34 then
    local facing_left = t.rd(0x450) ~= 0
    if (bdx < 0) ~= facing_left then b = {left = bdx < 0, right = bdx >= 0} else b = {B = true}; cool = 24 end
  elseif k >= nextthrow then b = {up = true, B = true}; cool = 24; nextthrow = k + 150 end
  t.hold(b)
  t.frame(1)
  if k % 500 == 0 then
    t.log(string.format("f%d status simonX=%02X Y=%02X hp=%02X hearts=%02X scroll=%02X%02X stg=%02X sys=%02X", k, t.rd(0x38C), t.rd(0x354), t.rd(0x45), t.rd(0x71), t.rd(0x2F), t.rd(0x2E), t.rd(0x28), t.rd(0x18)))
  end
end
local keys = {}
for k, n in pairs(counts) do keys[#keys + 1] = k .. "=" .. n end
table.sort(keys)
t.log("counts " .. table.concat(keys, " "))
t.finish(true)
