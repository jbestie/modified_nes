-- APU trace over the same deterministic sequence as t_screens.lua (title,
-- intro music, gameplay, timer death jingle, map, respawn).  Each frame logs
-- volume / period register / duty of the five APU channels; the traces of the
-- original and patched ROMs must be identical.
local g = dofile(os.getenv("GAME_DIR") .. "/tests/gng.lua")
emu.speedmode("maximum")
local active = 0
local function sig()
  local s = sound.get().rp2a03
  local parts = {}
  for _, ch in ipairs({"square1", "square2", "triangle", "noise", "dpcm"}) do
    local c = s[ch]
    local v = c.volume or 0
    if v > 0 then active = active + 1 end
    parts[#parts + 1] = string.format("%s:%.3f/%d/%s", ch:sub(1, 2), v, c.regs.frequency or 0,
                                      tostring(c.duty or c.short or ""))
  end
  return table.concat(parts, " ")
end
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
  g.log("APU f" .. f, sig())
end
g.log("channel-frames with nonzero volume:", active)
if active > 100 then g.finish(true) else g.finish(false, "no audio activity recorded") end
