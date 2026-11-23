-- Subweapon probe: in stage 1 (courtyard) sets $015B to each subweapon item ID
-- (and $64 multiplier = MULT), throws it with Up+B and logs slots $14-$16
-- (type, kind $0584, graphic $04C0, X/Y) every 4 frames, hearts before/after,
-- and slot $00-$03 fields during the throw (whip/spark slots).
-- Run: python3 scripts/run_fceux.py games/castlevania/rom/original.nes games/castlevania/tests/explore/obj_subweapons.lua --game-dir games/castlevania --out <dir> --tag subw [--env MULT=2]
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("maximum")
local MULT = tonumber(t.env("MULT", "0"))
emu.poweron()
t.frame(300)
t.press({start = true}, 4, 0)
t.frame(800)
local st = savestate.create()
savestate.save(st)
local function slots(a, b)
  local p = {}
  for i = a, b do
    p[#p + 1] = string.format("s%02X:t%02X k%02X g%02X %02X,%02X st%02X", i, t.rd(0x434 + i), t.rd(0x584 + i),
      t.rd(0x4C0 + i), t.rd(0x38C + i), t.rd(0x354 + i), t.rd(0x46C + i))
  end
  return table.concat(p, " ")
end
for _, w in ipairs({0x08, 0x09, 0x0B, 0x0D, 0x0F}) do
  savestate.load(st)
  t.wr(0x015B, w); t.wr(0x0071, 0x20); t.wr(0x0064, MULT)
  t.frame(2)
  local h0 = t.rd(0x71)
  t.log(string.format("== subweapon %02X (mult %d) hearts %d", w, MULT, h0))
  for n = 1, 3 do
    t.hold({up = true, B = true}); t.frame(3); t.hold({}); t.frame(3)
  end
  for f = 1, 60 do
    t.frame(1)
    if f % 4 == 1 then t.log(string.format(" f%02d %s | %s", f, slots(0x14, 0x16), slots(0x00, 0x03))) end
  end
  t.log(string.format("  hearts %d -> %d, $015C=%02X $015D=%02X $0560=%02X", h0, t.rd(0x71), t.rd(0x15C), t.rd(0x15D), t.rd(0x560)))
end
t.finish(true)
