-- Controller-input probe: the read routine $C8CD (called once per full NMI from $C0A1) strobes $4016, reads
-- 8 bits from $4016 -> $04 and $4017 -> $05, then stores P1 pressed/held in $F5/$F7 and P2 in $F6/$F8.
-- Holds buttons on pad 1 / pad 2 in stage play and logs $04 $05 $F5 $F6 $F7 $F8; counts the P1|P2 merge path $C90D.
-- Run: python3 scripts/run_fceux.py games/castlevania/rom/original.nes games/castlevania/tests/explore/bank_input.lua --game-dir games/castlevania --out <dir> --timeout 120
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode(os.getenv("SPEED") or "maximum")
local merge, reads, s4017 = 0, 0, 0
memory.registerexec(0xC90D, 1, function() merge = merge + 1 end)
memory.registerexec(0xC8CD, 1, function() reads = reads + 1 end)
memory.registerexec(0xC8E5, 1, function() s4017 = s4017 + 1 end)   -- LDA $4017
local function st() return string.format("$04=%02X $05=%02X $F5=%02X $F6=%02X $F7=%02X $F8=%02X", t.rd(4), t.rd(5), t.rd(0xF5), t.rd(0xF6), t.rd(0xF7), t.rd(0xF8)) end
emu.poweron()
t.frame(300); t.press({start = true}, 4, 0); t.frame(900)
local f0 = 0
local fails = 0
local tests = {
  {1, {A = true}, 0x80}, {1, {B = true}, 0x40}, {1, {select = true}, 0x20}, {1, {up = true}, 0x08},
  {1, {down = true}, 0x04}, {1, {left = true}, 0x02}, {1, {right = true}, 0x01},
  {2, {A = true}, 0x80}, {2, {B = true}, 0x40}, {2, {start = true}, 0x10}, {2, {select = true}, 0x20},
  {2, {up = true}, 0x08}, {2, {down = true}, 0x04}, {2, {left = true}, 0x02}, {2, {right = true}, 0x01},
}
for _, tc in ipairs(tests) do
  local pad, btn, bit = tc[1], tc[2], tc[3]
  local logs = {}
  for i = 1, 3 do
    joypad.set(pad, btn)
    emu.frameadvance()
    logs[#logs + 1] = st()
  end
  for i = 1, 3 do emu.frameadvance() end
  local pressed = pad == 1 and 0xF5 or 0xF6
  local held = pad == 1 and 0xF7 or 0xF8
  t.log(string.format("pad%d bit %02X: f1 %s | f2 %s", pad, bit, logs[1], logs[2]))
end
-- P2 Start during play: does it pause? ($22 lead: pause flag)
local p0 = t.rd(0x22)
joypad.set(2, {start = true}); emu.frameadvance(); emu.frameadvance()
for i = 1, 30 do emu.frameadvance() end
t.log(string.format("P2 Start in play: $22 before %02X after %02X", p0, t.rd(0x22)))
joypad.set(1, {start = true}); emu.frameadvance(); emu.frameadvance()
for i = 1, 30 do emu.frameadvance() end
t.log(string.format("P1 Start in play: $22 after %02X", t.rd(0x22)))
t.log(string.format("controller reads %d, $4017 reads (exec $C8E5) %d, merge path $C90D executed %d times", reads, s4017, merge))
t.finish(true)
