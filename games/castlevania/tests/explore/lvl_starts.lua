-- Nametables and terrain buffer at the start of ten stages (tile ids and terrain codes in one log).
-- Check it against the ROM decoder: tools/level_data.py ROM check <log>.
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
local ov = loadfile(t.root .. "/tools/overlay.lua")("module")
emu.speedmode("nothrottle")
local function frames(n) for _ = 1, n do ov.tick(); t.frame(1) end end
local function wait_play(max)
  local k = 0
  while not ov.in_play() and k < max do frames(1); k = k + 1 end
  return ov.in_play()
end
local function dump(tag)
  local nt, buf = {}, {}
  for a = 0x2000, 0x27FF do nt[#nt + 1] = string.format("%02X", ppu.readbyte(a)) end
  for a = 0x05A0, 0x06FF do buf[#buf + 1] = string.format("%02X", t.rd(a)) end
  t.log(string.format("%s stage=%d floor=%d scroll=%d page=%d", tag, t.rd(0x28), t.rd(0x46), t.rd(0x2E), t.rd(0x2F)))
  t.log(table.concat(nt))
  t.log(table.concat(buf))
end
emu.poweron()
frames(300)
t.press({start = true}, 4, 0)
wait_play(1500); frames(60)
dump("start")
for _, s in ipairs({2, 4, 5, 7, 9, 10, 13, 16, 18}) do
  ov.warp(s)
  wait_play(1500); frames(60)
  dump("warp" .. s)
end
t.finish(true)
