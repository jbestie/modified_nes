-- Run-and-gun spike test (games/castlevania/spikes/run-and-gun/run_and_gun.asm).
-- In stage 1 it checks, by behaviour:
--   A. walking right while pressing B: X keeps increasing 1 px/frame, daggers spawn, no attack state, no whip
--   B. jumping while pressing B: the jump keeps its arc (state 1 for 40 frames, 41 px), a dagger spawns
--   C. crouching + B: stays crouched (state 3), a dagger spawns
--   D. Up+B with the dagger subweapon: the original subweapon throw (attack flag $81, one heart)
--   E. standing and shooting: a dagger kills an enemy (kill handler $E097 on an enemy slot)
--   F. on stairs + B: keeps climbing (state 4, Y changes), a dagger spawns
-- The whip is "visible" when slot 1 or 2 has a sprite frame (0 before the first whip) and a Y other than $FC
-- (b6:$9AF8 parks them at $FC when a whip ends).
-- Frames frozen by an item pickup ($7E, e.g. the whip-upgrade pause after a dagger broke a candle) are not
-- counted as walking frames: the original game stops everything then.
-- Test aid: invincibility $5B is held at $30 so knockback can't disturb the movement checks
-- (it only skips enemy-vs-Simon contact; projectile hits are unaffected).
-- Run on the original ROM as a negative control: checks A, B, C, F fail there.
-- Run: python3 scripts/run_fceux.py <rom> games/castlevania/spikes/run-and-gun/t_run_and_gun.lua
--        --game-dir games/castlevania --out <dir> --tag rng --timeout 300
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("nothrottle")
local rd, wr = t.rd, t.wr
local fails = 0
local function check(c, what) t.log((c and "ok   " or "FAIL ") .. what); if not c then fails = fails + 1 end end
local function playing() return rd(0x18) == 5 and rd(0x19) == 6 end
local function wait(cond, max) local k = 0; while not cond() and k < (max or 600) do t.frame(1); k = k + 1 end; return cond() end
local function wx() return rd(0x40) + 256 * rd(0x41) end

-- per-frame watch: projectile spawns (slot $14-$16 type becomes $17), whip, attack state
local spawns, whip, attacked, frozen, invuln = 0, 0, 0, 0, false
local prev = {0, 0, 0}
local function watch()
  for i = 0, 2 do
    local ty = rd(0x434 + 0x14 + i)
    if ty == 0x17 and prev[i + 1] ~= 0x17 then spawns = spawns + 1 end
    prev[i + 1] = ty
  end
  if (rd(0x31D) ~= 0 and rd(0x355) ~= 0xFC) or (rd(0x31E) ~= 0 and rd(0x356) ~= 0xFC) then whip = whip + 1 end
  if rd(0x7E) ~= 0 then frozen = frozen + 1 end
  if rd(0x46C) == 2 then attacked = attacked + 1 end
  if invuln then wr(0x5B, 0x30) end
end
local function step(n) for _ = 1, (n or 1) do t.frame(1); watch() end end
local function reset_counts() spawns, whip, attacked, frozen = 0, 0, 0, 0 end

-- subweapon hits ($E65D INC $79, X = target slot) and kills ($E097, X = victim slot)
local hits, kills = {}, {}
memory.registerexec(0xE65D, function()
  local x = memory.getregister("x")
  hits[#hits + 1] = string.format("slot %02X type %02X", x, rd(0x434 + x))
end)
memory.registerexec(0xE097, function()
  local x = memory.getregister("x")
  if x >= 4 and x <= 0x0D then kills[#kills + 1] = string.format("slot %02X type %02X", x, rd(0x434 + x)) end
end)

-- boot, start, walk through the courtyard gate into stage 1
emu.poweron(); t.frame(300); t.press({start = true}, 4, 0); t.frame(800); wait(playing)
t.hold({right = true}); t.frame(1); wait(function() return rd(0x28) == 1 end, 1500); t.hold({}); t.frame(1); wait(playing, 300)
t.frame(20)
invuln = true

-- A. walk right for 150 frames, B tapped every 10 frames
reset_counts()
local x0 = wx()
for i = 1, 150 do
  t.hold({right = true, B = (i % 10 == 1)}); step(1)
  if i == 40 then gui.savescreenshotas(t.out .. "/" .. t.tag .. "_walk_fire.png") end
end
local dx = wx() - x0
check(dx >= 145 - frozen, string.format("A: walking continues while firing: X +%d in 150 frames, %d frozen by a pickup (1 px/frame)", dx, frozen))
check(spawns >= 3, string.format("A: daggers spawned while walking: %d", spawns))
check(attacked == 0, string.format("A: no attack state ($046C=2) while walking: %d frames", attacked))
check(whip == 0, string.format("A: whip never shown (slots 1-2 without a frame or parked at Y=$FC): %d frames with a whip", whip))
t.hold({}); step(60)

-- B. jump right, B tapped 8 frames after take-off
wait(function() return rd(0x46C) == 0 end, 120)
reset_counts()
x0 = wx()
local y0 = rd(0x3F)
t.hold({right = true, A = true}); step(1)
local air = 0
for i = 1, 80 do
  t.hold({right = true, B = (i == 8 or i == 20)}); step(1)
  if rd(0x46C) == 1 then air = air + 1 else break end
end
dx = wx() - x0
check(air >= 38 and dx >= 39 and dx <= 43 and rd(0x3F) == y0,
  string.format("B: the jump keeps its arc while firing: %d frames in the air, X +%d (original 40 frames, 41 px)", air, dx))
check(spawns >= 1 and attacked == 0 and whip == 0, string.format("B: daggers in the air: %d, attack frames %d, whip frames %d", spawns, attacked, whip))
t.hold({}); step(20)

-- C. crouch, then B while crouched
reset_counts()
t.hold({down = true}); step(8)
local crouched = 0
for i = 1, 30 do
  t.hold({down = true, B = (i == 2 or i == 14)}); step(1)
  if rd(0x46C) == 3 then crouched = crouched + 1 end
end
check(crouched == 30 and spawns >= 1 and whip == 0,
  string.format("C: crouch + B stays crouched (%d/30 frames in state 3), daggers %d, whip frames %d", crouched, spawns, whip))
t.hold({}); step(30)

-- D. Up+B with the dagger subweapon: the original throw still works
wait(function() return rd(0x46C) == 0 and rd(0x434) == 0 end, 120)
wr(0x15B, 8); wr(0x71, 10); step(2)
t.hold({up = true, B = true}); step(2); t.hold({}); step(2)
check(rd(0x434) == 0x81 and rd(0x71) == 9, string.format("D: Up+B throws the subweapon the original way ($0434=%02X, hearts 10 -> %d)", rd(0x434), rd(0x71)))
step(40)
wr(0x15B, 0); step(2)

-- E. stand and shoot (turn around every 90 frames) until a dagger kills an enemy
hits, kills = {}, {}
local k = 0
while #kills == 0 and k < 2400 do
  local face = (math.floor(k / 90) % 2 == 0) and "left" or "right"
  local b = {B = (k % 12 == 0)}
  if k % 90 < 2 then b[face] = true end
  t.hold(b); step(1); k = k + 1
end
check(#kills > 0 and #hits > 0, string.format("E: a dagger killed an enemy after %d frames (%s); subweapon hits: %d (%s)",
  k, kills[1] or "none", #hits, table.concat(hits, ", ", 1, math.min(#hits, 4))))
if #kills > 0 then step(1); t.shot(t.tag .. "_kill") end
t.hold({}); step(30)

-- F. walk right with Up pulses until on the stairs, then climb and shoot
local seen = 0
for i = 1, 1500 do
  t.hold({right = true, up = (i % 40 < 20)}); step(1)
  if rd(0x46C) == 4 then seen = i; break end
end
reset_counts()
local ys = rd(0x3F)
local onstairs = 0
for i = 1, 48 do
  t.hold({up = true, B = (i % 12 == 1)}); step(1)
  if rd(0x46C) == 4 then onstairs = onstairs + 1 end
end
check(seen > 0 and onstairs == 48 and ys - rd(0x3F) >= 22 and spawns >= 1 and whip == 0,
  string.format("F: on stairs + B keeps climbing (state 4 for %d/48 frames, Y %02X -> %02X, 0.5 px/frame = 24), daggers %d, whip frames %d",
    onstairs, ys, rd(0x3F), spawns, whip))
t.hold({}); step(2)

t.finish(fails == 0, fails > 0 and (fails .. " checks failed") or nil)
