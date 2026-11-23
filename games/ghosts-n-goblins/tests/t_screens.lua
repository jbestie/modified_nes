-- Deterministic screen capture for pixel-exact regression against the
-- original ROM.  Inputs are identical and no enemy touches Arthur before the
-- forced timer death, so every captured frame must match the original.
-- Covers: title, intro cutscene, gameplay start, timer death animation,
-- "PLAYER 1 READY" screen, map screen, respawn.
local g = dofile(os.getenv("GAME_DIR") .. "/tests/gng.lua")
emu.speedmode("maximum")
local n = 0
local function shot() n = n + 1; gui.savescreenshotas(string.format("%s/%s_%03d.png", g.out, g.tag, n)) end
local pad = g.script_pad()
-- remix ROM: GNG_MODES="shot,armor" sets the title-menu settings in RAM
-- (after the cold-boot RAM clear, before the title appears), e.g. "2,2"
local modes = nil
local ms, ma = string.match(g.env("GNG_MODES", ""), "(%d),(%d)")
if ms then modes = {tonumber(ms), tonumber(ma)} end
local shift = tonumber(g.env("GNG_START", "120")) - 120   -- later start: same sequence, shifted
for f = 1, 1900 + shift do
  joypad.set(1, pad(f))
  if f == 30 and modes then g.wr(0x071A, modes[1]); g.wr(0x071B, modes[2]) end
  if f == 1100 + shift then g.wr(0x06F6, 0); g.wr(0x06FA, 0); g.wr(0x06FC, 1) end
  emu.frameadvance()
  if f % 25 == 0 then shot() end
end
g.log("captured", n, "frames; lives", g.rd(g.LIVES))
g.finish(true)
