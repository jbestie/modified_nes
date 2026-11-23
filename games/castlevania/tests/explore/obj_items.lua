-- Item-ID probe: forces the drop byte $0584 of the first stage-1 candle
-- (slot $10) to each value in ITEMS, whips the candle, screenshots the item,
-- walks Simon onto it and logs what the pickup changed (RAM diff + store PCs).
-- Run: python3 scripts/run_fceux.py games/castlevania/rom/original.nes games/castlevania/tests/explore/obj_items.lua --game-dir games/castlevania --out <dir> --tag items [--env ITEMS=00,01,02]
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("maximum")
local list = {}
for v in string.gmatch(t.env("ITEMS", "00,01,02,03,04,05,06,07,08,09,0A,0B,0C,0D,0E,0F,11,21,31"), "[^,]+") do
  list[#list + 1] = tonumber(v, 16)
end
local SLOT = 0x10

local bank = 0
memory.registerwrite(0x8000, 0x8000, function(a, s, v) bank = AND(v or 0, 7) end)
local function stack(n)
  local sp = memory.getregister("s")
  local p = {}
  for i = 1, n do p[#p + 1] = string.format("%02X", memory.readbyte(0x100 + AND(sp + i, 0xFF))) end
  return table.concat(p, " ")
end
local stores = {}
local function watch(addr, name)
  memory.registerwrite(addr, 1, function(a, s, v)
    local pc = memory.getregister("pc")
    stores[#stores + 1] = string.format("%s=%02X@%X:%04X[%s]", name, v or 0, pc >= 0xC000 and 7 or bank, pc, stack(6))
  end)
end
watch(0x0434 + SLOT, "type")
for _, w in ipairs({{0x71, "hearts"}, {0x15B, "subw"}, {0x70, "whip"}, {0x64, "mult"}, {0x45, "hp"},
                    {0x5B, "inv"}}) do watch(w[1], w[2]) end

local function snap() local m = {} for a = 0, 0x7FF do m[a] = memory.readbyte(a) end return m end
local function skip(a) return (a >= 0x300 and a < 0x4F0) or (a >= 0x100 and a < 0x160) or a >= 0x5A0 end

emu.poweron()
t.frame(300)
t.press({start = true}, 4, 0)
t.frame(800)
local st = savestate.create()
savestate.save(st)

for _, item in ipairs(list) do
  savestate.load(st)
  t.wr(0x0584 + SLOT, item)
  t.wr(0x0072, 0)
  stores = {}
  local f = 0
  t.hold({right = true})
  while t.rd(0x038C) < 0x40 do t.frame(1) end
  t.hold({})
  -- whip until the candle breaks (type 28 -> 31), then wait for the item (2F)
  while t.rd(0x0434 + SLOT) == 0x28 and f < 300 do t.press({B = true}, 4, 26); f = f + 30 end
  while t.rd(0x0434 + SLOT) ~= 0x2F and f < 600 do t.frame(1); f = f + 1 end
  t.frame(40)
  local spr, pal, drop = t.rd(0x031C + SLOT), t.rd(0x0338 + SLOT), t.rd(0x0584 + SLOT)
  t.shot(string.format("item_%02X", item))
  local before = snap()
  local base = snap()
  stores = {}
  t.hold({right = true})
  local n = 0
  while t.rd(0x0434 + SLOT) == 0x2F and n < 200 do
    base = before; before = snap()
    t.frame(1); n = n + 1
  end
  t.hold({})
  t.frame(30)
  local after = snap()
  local d = {}
  for a = 0, 0x7FF do
    if not skip(a) and after[a] ~= before[a] and base[a] == before[a] then
      d[#d + 1] = string.format("%03X:%02X>%02X", a, before[a], after[a])
    end
  end
  t.log(string.format("item %02X: drop=%02X sprite=%02X pal=%02X pickup_after=%d", item, drop, spr, pal, n))
  t.log("  diff " .. table.concat(d, " "))
  t.log("  stores " .. table.concat(stores, " "))
end
t.finish(true)
