-- Logs PPU register traffic: distinct PPUCTRL ($2000) values + PCs, OAM DMA ($4014) writes, every call of the
-- CHR upload routine $FD23 (A = upload set) and every run of $2007 writes into the pattern tables ($0000-$1FFF).
-- MODE=game: Start at f300, then a random bot (walk right/whip/jump/climb); MODE=demo: no input (attract demos).
-- Run: python3 scripts/run_fceux.py games/castlevania/rom/original.nes games/castlevania/tests/explore/gfx_ppu_writes.lua --game-dir games/castlevania --out <dir> --tag ppuw [--env MODE=demo|game] [--env FRAMES=n]
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("maximum")
local MODE = t.env("MODE", "game")
local FRAMES = tonumber(t.env("FRAMES", "3000"))

local frame = 0
local ctrl = 0
local latch, vaddr = 0, 0
local ctrlvals = {}
local dma = {}
local runs = {}          -- pattern-table write runs
local cur = nil
local ntw = 0            -- nametable/palette byte count per frame window

memory.registerwrite(0x2000, 1, function(a, s, v)
  ctrl = v
  local pc = memory.getregister("pc")
  local k = string.format("%02X@%04X", v, pc)
  ctrlvals[k] = (ctrlvals[k] or 0) + 1
end)
memory.registerwrite(0x2005, 1, function() latch = 1 - latch end)
memory.registerwrite(0x2006, 1, function(a, s, v)
  if latch == 0 then vaddr = AND(v, 0x3F) * 256 + AND(vaddr, 0xFF)
  else vaddr = AND(vaddr, 0xFF00) + v end
  latch = 1 - latch
  cur = nil
end)
memory.registerwrite(0x2007, 1, function(a, s, v)
  local pc = memory.getregister("pc")
  if vaddr < 0x2000 then
    if cur and cur.pc == pc and cur.next == vaddr and cur.frame == frame then
      cur.n = cur.n + 1
    else
      cur = {frame = frame, pc = pc, start = vaddr, n = 1, bank = memory.readbyte(0x27)}
      runs[#runs + 1] = cur
    end
    cur.next = vaddr + ((AND(ctrl, 4) ~= 0) and 32 or 1)
  else
    ntw = ntw + 1
  end
  vaddr = AND(vaddr + ((AND(ctrl, 4) ~= 0) and 32 or 1), 0x3FFF)
end)
memory.registerwrite(0x4014, 1, function(a, s, v)
  local pc = memory.getregister("pc")
  local k = string.format("%02X@%04X", v, pc)
  dma[k] = (dma[k] or 0) + 1
end)

memory.registerexec(0xFD23, 1, function()
  local sp = memory.getregister("s")
  local ret = memory.readbyte(0x101 + sp) + 256 * memory.readbyte(0x102 + sp) - 2
  t.log(string.format("UPLOAD set=%d f%d caller=%04X $18=%02X $28=%02X $29=%02X", memory.getregister("a"), frame, ret,
    memory.readbyte(0x18), memory.readbyte(0x28), memory.readbyte(0x29)))
end)
local seed = 4242
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return math.floor(seed / 65536) % n end
local cur = {}
local function bot()
  if frame % 6 == 0 then
    cur = {}
    local r = rnd(100)
    if r < 70 then cur.right = true elseif r < 78 then cur.left = true end
    if rnd(100) < 35 then cur.B = true end
    if rnd(100) < 10 then cur.A = true end
    if rnd(100) < 20 then cur.up = true end
    if frame % 600 < 6 then cur = {start = true} end  -- gets through game over / continue screens (pauses briefly in play)
  end
  t.hold(cur)
end
emu.poweron()
local function step(n)
  for _ = 1, n do t.frame(1); frame = frame + 1 end
end
if MODE == "game" then
  step(300)
  t.press({start = true}, 4, 0); frame = frame + 4
  step(800)
  local last18 = -1
  while frame < FRAMES do
    bot(); step(1)
    if memory.readbyte(0x18) ~= last18 then
      last18 = memory.readbyte(0x18)
      t.log(string.format("STATE f%d $18=%02X $19=%02X $28=%02X $29=%02X", frame, last18, memory.readbyte(0x19), memory.readbyte(0x28), memory.readbyte(0x29)))
    end
  end
else
  step(FRAMES)
end

for k, n in pairs(ctrlvals) do t.log("CTRL " .. k .. " x" .. n) end
for k, n in pairs(dma) do t.log("DMA  " .. k .. " x" .. n) end
-- merge consecutive runs (same frame, contiguous address) for compact output
local merged = {}
for _, r in ipairs(runs) do
  local m = merged[#merged]
  if m and m.frame == r.frame and m.stop == r.start and m.pc == r.pc then
    m.stop = r.start + r.n; m.n = m.n + r.n
  else
    merged[#merged + 1] = {frame = r.frame, pc = r.pc, start = r.start, stop = r.start + r.n, n = r.n, bank = r.bank}
  end
end
for _, m in ipairs(merged) do
  t.log(string.format("CHR f%d pc=%04X bank=%d %04X-%04X (%d bytes)", m.frame, m.pc, m.bank, m.start, m.stop - 1, m.n))
end
t.log("nametable/palette bytes total " .. ntw)
t.finish(true)
