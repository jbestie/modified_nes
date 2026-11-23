-- Frame viewer: starts stage 1, then forces object slot 0's sprite frame ($031C) to each id in FRAMES just before the
-- bank-0 sprite drawer ($8052) runs (restored at its RTS $80C1), and saves one screenshot per id (<tag>_fr<id>.png).
-- Run: python3 scripts/run_fceux.py games/castlevania/rom/original.nes games/castlevania/tests/explore/gfx_frame_viewer.lua
--      --game-dir games/castlevania --out <dir> --tag fv [--env FRAMES=01,02,97] [--env MIRROR=1]
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("maximum")
local list = {}
for h in string.gmatch(t.env("FRAMES", "01,02,03,04,05,06,07,08,09,0A,0B,0D,0E,0F,97,98,99,A4,A5,A6,A7,A8,A9,AA,AB,AC"), "%x+") do
  list[#list + 1] = tonumber(h, 16)
end
local force, saved = nil, nil
memory.registerexec(0x8052, 1, function()
  if force and memory.readbyte(0x27) == 0 then
    saved = memory.readbyte(0x31C)
    memory.writebyte(0x31C, force)
    if t.env("MIRROR", "0") == "1" then memory.writebyte(0x450, 1) end
  end
end)
memory.registerexec(0x80C1, 1, function()
  if saved and memory.readbyte(0x27) == 0 then memory.writebyte(0x31C, saved); saved = nil end
end)
emu.poweron()
t.frame(300); t.press({start = true}, 4, 0)
t.frame(900)                                   -- courtyard, Simon standing at X=$46
t.log(string.format("Simon X=%02X Y=%02X frame=%02X", t.rd(0x38C), t.rd(0x354), t.rd(0x31C)))
for _, f in ipairs(list) do
  force = f
  t.frame(2)
  t.shot(string.format("%s_fr%02X", t.tag, f))
end
force = nil
t.finish(true)
