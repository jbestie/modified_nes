-- Super C's jump (src/commando/jump_superc.asm, part of the commando build), checked by behaviour.
--   A. a flat jump in stage 1: 55-57 frames in the air, 57-59 px high, 55-58 px long with Right held
--   B. the low-ceiling jump of stage 5, floor 1 (take-off at level X 191, feet $C0, to the ledge at feet $B0):
--      lands alive. With head probes in the jump's wall check the head would stop the motion over the pit.
-- On a build without jump_superc.asm (Simon's arc) A fails and B passes (Simon's jump stays under that ceiling).
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("nothrottle")
local rd, wr = t.rd, t.wr
local fails = {}
local function check(c, what)
  t.log((c and "ok   " or "FAIL ") .. what)
  if not c then fails[#fails + 1] = what end
end
local function playing() return rd(0x18) == 5 and rd(0x19) == 6 end
local function wait(cond, max) local k = 0; while not cond() and k < (max or 600) do t.frame(1); k = k + 1 end; return cond() end
local function wx() return rd(0x40) + 256 * rd(0x41) end
local function calm() for sl = 4, 0x13 do wr(0x434 + sl, 0) end; wr(0x5B, 0x30); wr(0x45, 0x40) end
local function step(n) for _ = 1, n do calm(); t.frame(1) end end

emu.poweron(); t.frame(300); t.press({start = true}, 4, 0); t.frame(800); wait(playing)
t.hold({right = true}); t.frame(1); wait(function() return rd(0x28) == 1 end, 1500); t.hold({}); t.frame(1); wait(playing, 300)
step(20)

-- A. flat jump
t.hold({right = true}); step(30); t.hold({}); step(10)
local x0, y0, top, air = wx(), rd(0x3F), rd(0x3F), 0
t.hold({right = true, A = true}); step(1); t.hold({right = true})
for _ = 1, 90 do
  step(1)
  top = math.min(top, rd(0x3F))
  if rd(0x46C) == 1 then air = air + 1 else break end
end
t.hold({}); step(10)
local rise, dx = y0 - top, wx() - x0
check(air >= 54 and air <= 57 and rise >= 57 and rise <= 59 and dx >= 55 and dx <= 59 and rd(0x3F) == y0,
  string.format("A: flat jump: %d frames in the air, %d px high, %d px long (Super C: 55-56 frames, 58-59 px, 56-57 px)", air, rise, dx))

-- B. stage 5, floor 1: reload the area on floor 1 with the camera at page 0, Simon at the take-off point
wr(0x29, 5); wr(0x18, 0x0C); wr(0x19, 7); t.frame(2); wait(playing, 1500); step(5)
local TX, FEET = 191, 0xC0
wr(0x46, 1); wr(0x2F, 0); wr(0x2E, 0); wr(0x2D, 0)
wr(0x38C, TX); wr(0x40, TX); wr(0x41, 0); wr(0x3F, FEET - 16); wr(0x450, 0)
wr(0x18, 5); wr(0x19, 0); wr(0x4A, 5); wr(0x1F, 5)
wait(playing, 600); step(20)
local sx, sy, st = wx(), rd(0x3F), rd(0x46C)
t.log(string.format("B: before the jump: level X %d, Y $%02X, state %d, floor %d", sx, sy, st, rd(0x46)))
t.shot(t.tag .. "_s5_before")
if sx ~= TX then   -- walk to the take-off pixel
  for _ = 1, 120 do
    if wx() == TX then break end
    t.hold({[wx() < TX and "right" or "left"] = true}); step(1)
  end
  t.hold({}); if rd(0x450) ~= 0 then t.hold({right = true}); step(1); t.hold({}) end
  step(5)
end
local tx = wx()
t.hold({right = true, A = true}); step(1); t.hold({right = true})
local died = false
for _ = 1, 100 do
  step(1)
  if rd(0x46C) == 8 or rd(0x18) ~= 5 then died = true; break end
  if rd(0x46C) ~= 1 then break end
end
t.hold({}); step(10)
t.shot(t.tag .. "_s5_after")
check(not died and rd(0x3F) == FEET - 32 and wx() >= 215,
  string.format("B: stage 5 floor 1 low-ceiling jump from X %d: %s, now X %d Y $%02X (the ledge: Y $%02X)",
    tx, died and "DIED" or "alive", wx(), rd(0x3F), FEET - 32))

t.finish(#fails == 0, #fails > 0 and (#fails .. " checks failed: " .. fails[1]) or nil)
