-- Stage-warp enemy survey: overrides every write of $0028 during the 800
-- frames after Start with STAGE (hex), then a bot walks right/whips (HP kept full) for FRAMES frames; on
-- the first sighting of each object type in slots 03-0D it saves a screenshot
-- (<tag>_tNN.png) and logs slot/X/Y, so type IDs can be matched to enemies.
-- Run: python3 scripts/run_fceux.py games/castlevania/rom/original.nes games/castlevania/tests/explore/obj_warp.lua --game-dir games/castlevania --out <dir> --tag warp02 --env STAGE=02 [--env FRAMES=4000 --env DIR=right]
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("maximum")
local STAGE = tonumber(t.env("STAGE", "02"), 16)
local FRAMES = tonumber(t.env("FRAMES", "4000"))
local DIR = t.env("DIR", "right")
local armed, done = false, false
memory.registerwrite(0x0028, 1, function(a, s, v)
  if armed then memory.writebyte(0x28, STAGE); done = true end
end)
emu.poweron()
t.frame(300)
armed = true
t.press({start = true}, 4, 0)
t.frame(800)
armed = false
t.log(string.format("after warp: $28=%02X done=%s", t.rd(0x28), tostring(done)))
t.shot(t.tag .. "_start")
local seen, pending = {}, {}
local cool = 0
for k = 1, FRAMES do
  t.wr(0x45, 0x40)
  t.wr(0x05B, 0x10) -- keep Simon invulnerable so the bot survives
  for i = 3, 0x0D do
    local ty = t.rd(0x434 + i)
    if ty > 0 and ty < 0x28 and not seen[ty] then
      seen[ty] = true
      pending[#pending + 1] = {ty = ty, slot = i, at = k + 6}
      t.log(string.format("f%d new type %02X slot%02X X=%02X Y=%02X st=%02X stage=%02X scroll=%02X%02X", k, ty, i,
        t.rd(0x38C + i), t.rd(0x354 + i), t.rd(0x46C + i), t.rd(0x28), t.rd(0x2F), t.rd(0x2E)))
    end
  end
  for j = #pending, 1, -1 do
    local p = pending[j]
    if k >= p.at then
      t.log(string.format("  shot type %02X slot%02X now type=%02X X=%02X Y=%02X", p.ty, p.slot, t.rd(0x434 + p.slot), t.rd(0x38C + p.slot), t.rd(0x354 + p.slot)))
      gui.savescreenshotas(string.format("%s/%s_t%02X.png", t.out, t.tag, p.ty))
      table.remove(pending, j)
    end
  end
  local b = {[DIR] = true}
  if cool > 0 then cool = cool - 1; b = {} elseif k % 40 == 0 then b = {B = true}; cool = 24 end
  if k % 300 > 280 then b = {[DIR] = true, A = true} end
  t.hold(b)
  t.frame(1)
  if k % 500 == 0 then
    t.log(string.format("f%d simonX=%02X Y=%02X scroll=%02X%02X stage=%02X sys=%02X", k, t.rd(0x38C), t.rd(0x354), t.rd(0x2F), t.rd(0x2E), t.rd(0x28), t.rd(0x18)))
  end
end
t.finish(true)
