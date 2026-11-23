-- Object-slot survey: logs every change of the object type ($0434,X) of the
-- 28 slots, per-slot type sets/peaks and the code (PC, bank) that writes types,
-- during both attract demos (MODE=demo) or scripted stage-1 play (MODE=game),
-- plus the peak number of simultaneously used slots per slot range. GOD=1 keeps HP full.
-- Run: python3 scripts/run_fceux.py games/castlevania/rom/original.nes games/castlevania/tests/explore/obj_slots.lua --game-dir games/castlevania --out <dir> --tag slots_game --env MODE=game --env FRAMES=3000
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("maximum")
local MODE = t.env("MODE", "game")
local FRAMES = tonumber(t.env("FRAMES", "3000"))
local GOD = t.env("GOD", "0") == "1"

local bank = 0
memory.registerwrite(0x8000, 0x8000, function(a, s, v) bank = AND(v or 0, 7) end)

local writers, wlist = {}, {}
memory.registerwrite(0x0434, 28, function(a, s, v)
  local pc = memory.getregister("pc")
  local key = string.format("%X:%04X slot%02X=%02X", pc >= 0xC000 and 7 or bank, pc, a - 0x0434, v or 0)
  if not writers[key] then writers[key] = 0; wlist[#wlist + 1] = key end
  writers[key] = writers[key] + 1
end)

local prev, types = {}, {}
local ranges = {{0, 0}, {1, 2}, {3, 3}, {4, 0x0D}, {0x0E, 0x13}, {0x14, 0x16}, {0x17, 0x1B}}
local peak = {}
for r = 1, #ranges do peak[r] = 0 end
for i = 0, 27 do prev[i] = 0; types[i] = {} end
local frame = 0
local function survey()
  frame = frame + 1
  for i = 0, 27 do
    local ty = t.rd(0x0434 + i)
    if ty ~= prev[i] then
      t.log(string.format("f%d s%02X %02X->%02X X=%02X Y=%02X st=%02X attr=%02X stg=%02X", frame, i, prev[i], ty,
        t.rd(0x038C + i), t.rd(0x0354 + i), t.rd(0x046C + i), t.rd(0x0300 + i), t.rd(0x0028)))
      prev[i] = ty
    end
    if ty ~= 0 then types[i][ty] = (types[i][ty] or 0) + 1 end
  end
  if frame > 10 then
    for r, rg in ipairs(ranges) do
      local n = 0
      for i = rg[1], rg[2] do local ty = t.rd(0x0434 + i); if ty ~= 0 and ty ~= 0x32 and ty ~= 0xFF then n = n + 1 end end
      if n > peak[r] then peak[r] = n end
    end
  end
end

local function run(n) for _ = 1, n do t.frame(1); survey(); if GOD then t.wr(0x0045, 0x40) end end end

emu.poweron()
if MODE == "demo" then
  run(FRAMES)
else
  run(300)
  t.press({start = true}, 4, 0)
  run(800)
  local k = 0
  while k < FRAMES do
    -- walk right; whip every 48 frames; jump every 120 frames
    local b = {right = true}
    local m = k % 120
    if m % 48 < 4 then b = {B = true} end
    if m >= 100 and m < 104 then b = {right = true, A = true} end
    t.hold(b)
    run(1)
    k = k + 1
    if k % 200 == 0 then
      t.log(string.format("f%d simonX=%02X Y=%02X hp=%02X hearts=%02X scroll=%02X%02X stg=%02X", frame,
        t.rd(0x038C), t.rd(0x0354), t.rd(0x0045), t.rd(0x0071), t.rd(0x002F), t.rd(0x002E), t.rd(0x0028)))
    end
  end
end

local pk = {}
for r, rg in ipairs(ranges) do pk[#pk + 1] = string.format("%02X-%02X:%d", rg[1], rg[2], peak[r]) end
t.log("== peak simultaneous slots in use (type not 00/32) per range: " .. table.concat(pk, " "))
t.log("== per-slot types (type:frames)")
for i = 0, 27 do
  local parts = {}
  for ty, n in pairs(types[i]) do parts[#parts + 1] = string.format("%02X:%d", ty, n) end
  table.sort(parts)
  t.log(string.format("s%02X %s", i, table.concat(parts, " ")))
end
t.log("== type writers (bank:pc slot=value count)")
for _, key in ipairs(wlist) do t.log(key .. " x" .. writers[key]) end
t.finish(true)
