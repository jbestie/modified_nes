-- Capture the between-lives screen after a death in a warped area.
-- Used to compare original vs patched ROMs (same inputs, same warp).
local g = dofile(os.getenv("GAME_DIR") .. "/tests/gng.lua")
local AREA = tonumber(g.env("GNG_AREA", "1"))
local warped, select_seen = false, 0
memory.registerexec(0xD058, 1, function()
  if not warped then memory.writebyte(0xA7, 0x0F); memory.writebyte(0xAC, AREA); warped = true end
end)
memory.registerexec(0xD089, 1, function() select_seen = emu.framecount() end)
emu.speedmode("maximum")
g.frame(120)
g.press({start = true}, 4, 4)
local pressed = false
for _ = 1, 3000 do
  g.frame(1)
  if select_seen > 0 and not pressed and emu.framecount() - select_seen < 3 then
    g.frame(30); g.press({start = true}, 4, 4); pressed = true; g.wr(0xA7, 0)
  end
  if pressed and g.rd(g.FLAGS) == 0x80 then break end
end
local lives = g.rd(g.LIVES)
local shots = 0
for i = 1, 5400 do
  g.hold({right = true, A = (i % 70) < 12})
  g.frame(1)
  if g.rd(g.LIVES) < lives then
    lives = g.rd(g.LIVES)
    for k = 1, 8 do g.frame(30); g.shot(string.format("%s_death%d_%d", g.tag, shots, k)) end
    shots = shots + 1
    if shots >= 1 then break end
  end
end
if shots > 0 then g.finish(true) else g.finish(false, "no death happened") end
