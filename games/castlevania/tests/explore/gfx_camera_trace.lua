-- Camera trace: starts a game (optionally at stage STAGE by poking $28/$29 at bank 6 $B990, and with the camera moved
-- to page PAGE at stage init, bank 7 $C24B), walks right (INPUT=right|rightup, whip every 20 frames) and logs every
-- change of $18/$19/$28/$46/$48 (with PC), CHR uploads ($FD23 calls), plus scroll/Simon vars every EVERY frames; screenshots at boss lock / stage change.
-- Run: python3 scripts/run_fceux.py games/castlevania/rom/original.nes games/castlevania/tests/explore/gfx_camera_trace.lua
--      --game-dir games/castlevania --out <dir> --tag cam [--env STAGE=3] [--env PAGE=4] [--env INPUT=rightup] [--env FRAMES=6000]
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("maximum")
local STAGE = tonumber(t.env("STAGE", "-1"))
local PAGE = tonumber(t.env("PAGE", "-1"))
local UP = t.env("INPUT", "right") == "rightup"
local EVERY = tonumber(t.env("EVERY", "16"))
local FRAMES = tonumber(t.env("FRAMES", "6000"))
local frame = 0

if STAGE >= 0 then
  memory.registerexec(0xB990, 1, function()          -- right after STX $28 in the new-game path
    if memory.readbyte(0x27) == 6 then memory.writebyte(0x28, STAGE); memory.writebyte(0x29, STAGE) end
  end)
end
if PAGE >= 0 then
  memory.registerexec(0xC24B, 1, function()          -- stage init, after $2E/$2F were saved to $03FC/$0418
    local want = STAGE >= 0 and STAGE or 1
    if memory.readbyte(0x28) == want then
      memory.writebyte(0x2F, PAGE); memory.writebyte(0x418, PAGE)
      t.log(string.format("f%d camera moved to page %d", frame, PAGE))
    end
  end)
end
memory.registerexec(0xFD23, 1, function()
  t.log(string.format("f%d CHR upload set %d ($28=%02X)", frame, memory.getregister("a"), memory.readbyte(0x28)))
end)
local last = {}
for _, a in ipairs({0x18, 0x19, 0x28, 0x46, 0x48}) do
  memory.registerwrite(a, 1, function(addr, s, v)
    if last[addr] ~= v then
      last[addr] = v
      t.log(string.format("f%d $%02X=%02X pc=%04X bank=%d", frame, addr, v, memory.getregister("pc"), memory.readbyte(0x27)))
    end
  end)
end

emu.poweron()
local function step(n) for _ = 1, n do t.frame(1); frame = frame + 1 end end
step(300); t.press({start = true}, 4, 0); frame = frame + 4
step(800)
local stage0, locked = t.rd(0x28), false
while frame < FRAMES do
  local b = {right = true, up = UP or nil}
  if frame % 20 < 2 then b.B = true end
  t.hold(b)
  step(1)
  if frame % EVERY == 0 then
    t.log(string.format("  f%d $18=%02X $19=%02X $28=%02X scroll $2F:$2E=%02X:%02X $3C=%02X $46=%02X $48=%02X Simon X=%02X Y=%02X frame=%02X",
      frame, t.rd(0x18), t.rd(0x19), t.rd(0x28), t.rd(0x2F), t.rd(0x2E), t.rd(0x3C), t.rd(0x46), t.rd(0x48), t.rd(0x38C), t.rd(0x354), t.rd(0x31C)))
  end
  if t.rd(0x48) ~= 0 and not locked then locked = true; t.shot(t.tag .. "_bosslock"); frame = frame + 1 end
  if t.rd(0x28) ~= stage0 and t.rd(0x18) == 5 and t.rd(0x19) == 6 then
    step(120); t.shot(string.format("%s_stage%02X", t.tag, t.rd(0x28))); frame = frame + 1
    stage0 = t.rd(0x28)
  end
end
t.finish(true)
