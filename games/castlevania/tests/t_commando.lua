-- Commando prototype 1 (src/commando/commando.asm), checked by behaviour.
--   A. walking right while pressing B: X keeps rising 1 px/frame, bullets spawn, no attack state, no whip
--   B. jumping while pressing B: the jump keeps its arc, bullets spawn in the air
--   C. crouching (prone) + B: stays down; the bullet starts 14 px lower than a standing shot
--   D. no subweapons: Select does nothing (no attack, hearts kept); Up+B with a subweapon id set shoots up
--   L. aiming (bullet tracks): ground Up = straight up, walking + Up/Down = diagonal, in the air Up/Down/diagonals,
--      on stairs Up/Down = along the steps
--   M. air control: Left/Right in a jump starts the motion or turns around
--   N. poses: aim up, somersault, prone (commando frames when ART=1, else Simon's); prone contact half-height $04;
--      Down + Right walks instead of crouching
--   P. at most 4 bullets on screen under rapid fire; all bullet slots empty again after the shots leave
--   W. weapons (set directly): M auto-fires every 7 frames (6 on screen); S fires a 5-way fan; L a 5-segment
--      train 8 px apart, restarted by a new press; F flies 5.5 px/frame, a charged release makes a charged ball,
--      a hit bursts it into fragments; R makes the rifle 5.5 px/frame
--   X. pickups from a courtyard candle: the dagger gives M and ends R; the stopwatch acts as the potion
--   E. standing and shooting: a bullet kills an enemy
--   F. on stairs + B (Up held): keeps climbing, and every press fires a bullet, subweapon or not
--   S. next to a staircase: Up while tapping B stays on the floor and shoots up; Up alone steps on after 16 frames
--   G. an enemy hit: health drops, no knockback state, no push, invincibility $30
--   H. a hit at zero health: dead (state 8) at once, without knockback first
--   I. stage 3: a bullet breaks the wall block (its bit in $0146, SFX $15 path)
--   J. bullets (kind 0) don't freeze a boss (mummy, type $1A): its HP drops, $0568 and $0488 bit 7 stay clear
--   K. the title never starts the attract demo
--   Y. B is Super C's barrier: the pickup gives 510 frames of invincibility with BarrierOn; a zombie touching the
--      commando dies and his health stays; a mummy (boss) touching him is spared
--   V. intro: the back view at the gate is the drawn commando (ART: tiles E0-EA, uploaded by IntroTiles), else
--      Simon's (tiles 1D 1F 21 2F, and the upload is empty)
--   W (frames): each bullet kind has its own metasprite with ART=1 (rifle 10, M 11, S and fragments 12, laser 13 /
--      up 14, fire ball 17, charged ball 18), else the dagger's $50
-- The whip is "visible" when slot 1 or 2 has a frame and a Y other than $FC (b6:$9AF8 parks them at $FC).
-- Frames frozen by an item pickup ($7E) don't count as walking frames.
-- Run on the original ROM as a negative control: most checks fail there.
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

-- shots: calls of InitBullet in bank 5 (a slot can be emptied and refilled within one frame, so slot contents
-- at frame end would miss shots); fragments ($012D = K_FRAG) not counted. Muzzle height from the slots.
local spawns, whip, attacked, frozen, knocked, invuln = 0, 0, 0, 0, 0, false
local calm = false                             -- clear enemy and candle slots every frame (aim and pose checks)
local spawn_dy = {}
local last_slot = nil
local kinds = {}                               -- ShotKind of each spawn (all, fragments included)
local INIT = t.sym("InitBullet")
if INIT then
  memory.registerexec(INIT, function()
    if rd(0x27) ~= 5 then return end
    local k = rd(0x012D)
    kinds[#kinds + 1] = k
    if k ~= 0x16 then spawns = spawns + 1; last_slot = memory.getregister("x") end
  end)
end
local ART = os.getenv("ART") == "1"
-- per-frame watch: whip, attack state, knockback state, new bullets' height relative to Simon
local prev = {0, 0, 0}
local function watch()
  for i = 0, 2 do
    local ty = rd(0x434 + 0x14 + i)
    if ty == 0x97 and prev[i + 1] ~= 0x97 and spawn_dy then spawn_dy[#spawn_dy + 1] = rd(0x354 + 0x14 + i) - rd(0x354) end
    prev[i + 1] = ty
  end
  if (rd(0x31D) ~= 0 and rd(0x355) ~= 0xFC) or (rd(0x31E) ~= 0 and rd(0x356) ~= 0xFC) then whip = whip + 1 end
  if rd(0x7E) ~= 0 then frozen = frozen + 1 end
  if rd(0x46C) == 2 then attacked = attacked + 1 end
  if rd(0x46C) == 5 then knocked = knocked + 1 end
  if invuln then wr(0x5B, 0x30) end
  if calm then for sl = 4, 0x13 do wr(0x434 + sl, 0); wr(0x46C + sl, 0) end end
end
local function step(n) for _ = 1, (n or 1) do t.frame(1); watch() end end
local function reset_counts() spawns, whip, attacked, frozen, knocked = 0, 0, 0, 0, 0; spawn_dy = {} end

-- shot hits (the hit chain $E562 with a weapon code other than the whip's $FF; X = target slot) and kills
-- ($E097, X = victim slot). Bullets reach $E562 from BulletPass, thrown subweapons from $E5EB.
local hits, kills = {}, {}
memory.registerexec(0xE562, function()
  if rd(0x0E) == 0xFF then return end
  local x = memory.getregister("x")
  hits[#hits + 1] = string.format("slot %02X type %02X", x, rd(0x434 + x))
end)
memory.registerexec(0xE097, function()
  local x = memory.getregister("x")
  if x >= 4 and x <= 0x0D then kills[#kills + 1] = string.format("slot %02X type %02X", x, rd(0x434 + x)) end
end)

-- K. title: no attract demo (the original starts it at about frame 1500)
emu.poweron()
local demo = false
for _ = 1, 2400 do t.frame(1); if rd(0x18) == 2 then demo = true; break end end
check(not demo and rd(0x18) == 1, string.format("K: no attract demo after 2400 title frames ($18=%02X)", rd(0x18)))

-- boot, start; V. the intro's back view (frame $19 in slot 0 while $18 = 4)
local back_tiles, back_seen, back_nz = {}, 0, 0
emu.poweron(); t.frame(300); t.press({start = true}, 4, 0)
for _ = 1, 800 do
  t.frame(1)
  if rd(0x18) == 4 and rd(0x31C) == 0x19 then
    back_seen = back_seen + 1
    if back_seen == 10 then
      for sp = 0, 63 do if rd(0x200 + 4 * sp) < 0xEF then back_tiles[rd(0x201 + 4 * sp)] = true end end
      for a = 0x0E00, 0x0EBF do if ppu.readbyte(a) ~= 0 then back_nz = back_nz + 1 end end
    end
  end
end
wait(playing)
local function has_all(list) for _, tl in ipairs(list) do if not back_tiles[tl] then return false end end return true end
if ART then
  check(back_seen > 10 and has_all({0xE0, 0xE2, 0xE4, 0xE6, 0xE8, 0xEA}) and back_nz > 100,
    string.format("V: intro back view: %d frames, the drawn commando's tiles E0-EA %s, %d non-zero bytes at PPU $0E00", back_seen,
      has_all({0xE0, 0xE2, 0xE4, 0xE6, 0xE8, 0xEA}) and "shown" or "missing", back_nz))
else
  check(back_seen > 10 and has_all({0x1D, 0x1F, 0x21, 0x2F}) and back_nz == 0,
    string.format("V: intro back view: %d frames, Simon's tiles %s, the empty upload: %d non-zero bytes at PPU $0E00", back_seen,
      has_all({0x1D, 0x1F, 0x21, 0x2F}) and "shown" or "missing", back_nz))
end

-- X. pickups from the first courtyard candle (slot $10): shoot it, walk onto the item
local court = savestate.create(); savestate.save(court)
local function pickup(id, pre)
  savestate.load(court)
  wr(0x584 + 0x10, id); wr(0x72, 0)
  if pre then pre() end
  t.hold({right = true})
  for _ = 1, 300 do t.frame(1); if rd(0x38C) >= 0x40 then break end end
  t.hold({})
  for _ = 1, 400 do
    wr(0x5B, 0x30)
    if rd(0x434 + 0x10) ~= 0x28 then break end
    local b = (emu.framecount() % 8 == 0)
    t.hold({B = b, [rd(0x38C + 0x10) < rd(0x38C) and "left" or "right"] = (emu.framecount() % 30 == 0)})
    t.frame(1)
  end
  t.hold({})
  for _ = 1, 300 do t.frame(1); if rd(0x434 + 0x10) == 0x2F then break end end
  t.frame(40)
  local got = false
  for _ = 1, 400 do
    if rd(0x434 + 0x10) ~= 0x2F then got = true; break end
    t.hold({[rd(0x38C + 0x10) < rd(0x38C) and "left" or "right"] = true}); t.frame(1)
  end
  t.hold({})
  return got
end
local got = pickup(0x08, function() wr(0x70, 1); wr(0x15B, 0) end)
check(got and rd(0x15B) == 0x08 and rd(0x70) == 0,
  string.format("X: the dagger pickup gives M ($015B=%02X) and ends R ($70=%d)", rd(0x15B), rd(0x70)))
local BON = t.sym("BarrierOn")
got = pickup(0x0F, function() wr(0x15B, 0); wr(0x5B, 0) end)
local inv, bon = rd(0x5B), BON and rd(BON) or 0
check(got and rd(0x15B) == 0 and inv >= 0xD0 and bon ~= 0,
  string.format("X: the stopwatch pickup gives B: invincibility $%02X (the barrier starts at $FF), barrier %d, weapon %02X", inv, bon, rd(0x15B)))
savestate.load(court)

-- walk through the courtyard gate into stage 1
t.hold({right = true}); t.frame(1); wait(function() return rd(0x28) == 1 end, 1500); t.hold({}); t.frame(1); wait(playing, 300)
t.frame(20)
local stage1 = savestate.create(); savestate.save(stage1)
invuln = true

-- A. walk right for 150 frames, B tapped every 10 frames
reset_counts()
local x0 = wx()
for i = 1, 150 do t.hold({right = true, B = (i % 10 == 1)}); step(1) end
local dx = wx() - x0
local stand_dy = spawn_dy[1]
check(dx >= 145 - frozen, string.format("A: walking continues while firing: X +%d in 150 frames, %d frozen by a pickup", dx, frozen))
check(spawns >= 3, string.format("A: bullets spawned while walking: %d", spawns))
check(attacked == 0 and whip == 0, string.format("A: no attack state (%d frames) and no whip (%d frames)", attacked, whip))
t.hold({}); step(60)

-- B. jump right, B tapped during the jump
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
check(air >= 54 and air <= 57 and dx >= 55 and dx <= 59 and rd(0x3F) == y0,
  string.format("B: the jump keeps its arc while firing: %d frames in the air, X +%d (Super C arc: 55 frames, 57 px)", air, dx))
check(spawns >= 1 and attacked == 0 and whip == 0, string.format("B: bullets in the air: %d, attack frames %d, whip frames %d", spawns, attacked, whip))
t.hold({}); step(20)

-- C. crouch, then B while crouched
reset_counts()
t.hold({down = true}); step(8)
local crouched = 0
for i = 1, 30 do
  t.hold({down = true, B = (i == 2 or i == 14)}); step(1)
  if rd(0x46C) == 3 then crouched = crouched + 1 end
end
local crouch_dy = spawn_dy[1]
check(crouched == 30 and spawns >= 1 and whip == 0,
  string.format("C: crouch + B stays crouched (%d/30 frames in state 3), bullets %d, whip frames %d", crouched, spawns, whip))
check(stand_dy ~= nil and crouch_dy ~= nil and crouch_dy - stand_dy == 14,
  string.format("C: muzzle height: bullet Y - Simon Y standing %s, prone %s (prone 14 px lower)", tostring(stand_dy), tostring(crouch_dy)))
t.hold({}); step(30)

-- D. no subweapons: Select does nothing; Up+B shoots (the rifle)
wait(function() return rd(0x46C) == 0 and rd(0x434) == 0 end, 120)
step(70)                                       -- let earlier shots leave the screen
wr(0x15B, 0); wr(0x71, 10); step(2)
reset_counts()
t.hold({select = true}); step(2); t.hold({}); step(20)
check(rd(0x434) == 0 and rd(0x71) == 10 and attacked == 0 and spawns == 0,
  string.format("D: Select does nothing ($0434=%02X, hearts %d, attack frames %d, shots %d)", rd(0x434), rd(0x71), attacked, spawns))
reset_counts()
t.hold({up = true, B = true}); step(2); t.hold({}); step(4)
check(spawns == 1 and rd(0x71) == 10 and attacked == 0 and whip == 0,
  string.format("D: Up+B fires a bullet (%d), hearts kept (%d), no attack or whip", spawns, rd(0x71)))
step(30)

-- L. aiming: fire, then measure the bullet's motion over 4 frames (from the frame after the spawn)
local function track(held, pre)
  for sl = 0x14, 0x16 do wr(0x434 + sl, 0) end
  last_slot = nil
  if pre then pre() end
  local b = {}; for k, v in pairs(held) do b[k] = v end; b.B = true
  t.hold(b); step(1); t.hold(held); step(1)
  local sl = last_slot
  if not sl or rd(0x434 + sl) ~= 0x97 then return nil end
  local function lx() return rd(0x38C + sl) + rd(0x2E) + 256 * rd(0x2F) end   -- level X: the camera may scroll
  local x0, y0 = lx(), rd(0x354 + sl)
  step(4)
  if rd(0x434 + sl) ~= 0x97 then return nil end
  local face = rd(0x450 + sl) == 0 and 1 or -1
  return (lx() - x0) * face, rd(0x354 + sl) - y0
end
local function aim_ok(name, dx, dy, ex, ey)
  local good = dx ~= nil and math.abs(dx - ex) <= 2 and math.abs(dy - ey) <= 2
  check(good, string.format("L: %s: bullet moved %s in 4 frames (expected %+d, %+d)", name,
    dx and string.format("%+d, %+d", dx, dy) or "nothing (gone or not spawned)", ex, ey))
end
local function jump_then(held)
  return function() t.hold({A = true}); step(1); t.hold({}); step(8) end
end
invuln, calm = false, true
wr(0x5B, 0); wr(0x70, 0); wr(0x15B, 0)         -- rifle without R (whip-upgrade drops picked up earlier give R)
wait(function() return rd(0x46C) == 0 end, 120)
local dx, dy = track({up = true})
aim_ok("standing + Up = straight up", dx, dy, 0, -16)
step(20)
dx, dy = track({up = true, right = true}, function() t.hold({right = true, up = true}); step(6) end)
aim_ok("walking + Up = diagonal up", dx, dy, 11, -11)
t.hold({}); step(30)
dx, dy = track({down = true, right = true}, function() t.hold({right = true, down = true}); step(6) end)
aim_ok("walking + Down = diagonal down", dx, dy, 11, 11)
t.hold({}); step(30)
dx, dy = track({}, jump_then())
aim_ok("jump, no direction = forward", dx, dy, 16, 0)
step(50)
dx, dy = track({down = true}, jump_then())
aim_ok("jump + Down = straight down", dx, dy, 0, 16)
step(50)
dx, dy = track({up = true, right = true}, jump_then())
aim_ok("jump + Up+Right = diagonal up", dx, dy, 11, -11)
t.hold({}); step(50)

-- M. air control
wait(function() return rd(0x46C) == 0 end, 120)
local mx0 = wx()
t.hold({A = true}); step(1); t.hold({}); step(5); t.hold({right = true}); step(20); t.hold({}); step(30)
local neutral = wx() - mx0
mx0 = wx()
t.hold({A = true, right = true}); step(1); t.hold({right = true}); step(8); t.hold({left = true}); step(4)
local face_mid = rd(0x450)
step(20); t.hold({}); step(30)
local back = wx() - mx0
check(neutral >= 15 and face_mid == 1 and back < 0,
  string.format("M: air control: a neutral jump + Right moves %+d px; Left mid-jump turns (facing %d) and moves back (%+d px)", neutral, face_mid, back))

-- N. poses, prone, Down + Right
wait(function() return rd(0x46C) == 0 end, 120)
t.hold({up = true}); step(4)
local up_frame = rd(0x31C)
t.hold({}); step(4)
t.hold({A = true}); step(1); t.hold({}); step(12)
local spin_frame = rd(0x31C)
step(40)
t.hold({down = true}); step(8)
local prone_frame, prone_h, prone_state = rd(0x31C), rd(0x5F), rd(0x46C)
t.hold({}); step(10)
local wx0 = wx()
t.hold({down = true, right = true}); step(20)
local dr_state, dr_dx = rd(0x46C), wx() - wx0
t.hold({}); step(10)
if ART then
  check(up_frame == 0xEF and spin_frame >= 0xF9 and spin_frame <= 0xFC and prone_frame == 0xF7,
    string.format("N: commando poses: aim up %02X ($EF), jump %02X (somersault $F9-$FC), prone %02X ($F7)", up_frame, spin_frame, prone_frame))
else
  check(up_frame == 0x01 and (spin_frame == 0x01 or spin_frame == 0x05) and prone_frame == 0x05,
    string.format("N: mechanics build keeps Simon's frames: aim up %02X, jump %02X, prone %02X", up_frame, spin_frame, prone_frame))
end
check(prone_state == 3 and prone_h == 4, string.format("N: Down alone = prone (state %d), contact half-height $%02X (crouch was $0A)", prone_state, prone_h))
check(dr_state == 0 and dr_dx >= 15, string.format("N: Down + Right walks (state %d, X %+d in 20 frames)", dr_state, dr_dx))

-- P. rapid fire: never more than 4 bullets; the slots empty again
calm = true
local maxb, over = 0, 0
local function live() local n = 0; for sl = 0x14, 0x1B do if rd(0x434 + sl) == 0x97 then n = n + 1 end end; return n end
for i = 1, 90 do
  t.hold({B = (i % 4 == 1)}); step(1)
  local n = live(); maxb = math.max(maxb, n); if n > 4 then over = over + 1 end
end
t.hold({}); step(80)
check(maxb == 4 and over == 0 and live() == 0,
  string.format("P: rapid fire: at most %d bullets on screen (frames over 4: %d); %d left 80 frames later", maxb, over, live()))

-- W. weapons
local function slots97(kind)
  local r = {}
  for sl = 0x14, 0x1B do
    if rd(0x434 + sl) == 0x97 and (not kind or rd(0x584 + sl) == kind) then r[#r + 1] = sl end
  end
  return r
end
local function clear_bullets() for sl = 0x14, 0x1B do if rd(0x434 + sl) == 0x97 then wr(0x434 + sl, 0); wr(0x46C + sl, 0) end end end
local function face_right() if rd(0x450) ~= 0 then t.hold({right = true}); step(1); t.hold({}) end; step(4) end
local wf = {}                                  -- metasprite of each kind's first bullet
local function fr(kind) local sl = slots97(kind)[1]; return sl and rd(0x31C + sl) or nil end
wait(function() return rd(0x46C) == 0 end, 120)
face_right()
-- M
wr(0x15B, 8); wr(0x70, 0); clear_bullets(); step(2)
reset_counts(); kinds = {}
local mmax = 0
t.hold({B = true})
for _ = 1, 63 do step(1); mmax = math.max(mmax, #slots97()); wf.M = wf.M or fr(0x11) end
t.hold({}); step(60)
check(spawns >= 8 and spawns <= 10 and mmax <= 6 and kinds[1] == 0x11,
  string.format("W: M held 63 frames: %d shots (every 7 frames: 9-10), at most %d on screen (6), kind %s", spawns, mmax, kinds[1] and string.format("$%02X", kinds[1]) or "-"))
-- S
wr(0x15B, 9); clear_bullets(); step(2)
reset_counts(); kinds = {}
t.hold({B = true}); step(1); t.hold({}); step(1)
wf.S = fr(0x12)
local ys, want = {}, {["+0000"] = 1, ["+00C8"] = 1, ["+0188"] = 1, ["-00C8"] = 1, ["-0188"] = 1}
for _, sl in ipairs(slots97(0x12)) do
  local k = string.format("%s%02X%02X", (rd(0x4DC + sl) == 1 and rd(0x3C4 + sl) + rd(0x3E0 + sl) > 0) and "-" or "+", rd(0x3C4 + sl), rd(0x3E0 + sl))
  ys[#ys + 1] = k; want[k] = nil
end
check(spawns == 5 and #ys == 5 and next(want) == nil,
  string.format("W: S fires %d bullets, Y speeds %s (0, +-0.78, +-1.53 px/frame)", spawns, table.concat(ys, " ")))
step(60)
-- L
wr(0x15B, 0x0B); clear_bullets(); step(2)
reset_counts()
t.hold({B = true}); step(1); t.hold({}); step(12)
wf.L = fr(0x13)
local xs = {}
for _, sl in ipairs(slots97(0x13)) do if rd(0x300 + sl) == 0 then xs[#xs + 1] = rd(0x38C + sl) end end
table.sort(xs)
local spaced = #xs == 5
for i = 2, #xs do if xs[i] - xs[i - 1] ~= 8 then spaced = false end end
local first = spawns
t.hold({B = true}); step(1); t.hold({}); step(1)
local again = #slots97(0x13)
check(first == 5 and spaced and again == 5 and spawns == 10,
  string.format("W: L: %d segments, X %s after 12 frames (8 px apart); a new press: %d live, %d shots in all (10)", first, table.concat(xs, ","), again, spawns))
step(60)
clear_bullets(); step(2)
t.hold({up = true, B = true}); step(1); t.hold({}); step(12)
wf.Lup = fr(0x13)
step(60)
-- F: speed, charged shot
wr(0x15B, 0x0D); clear_bullets(); step(2)
reset_counts(); kinds = {}
t.hold({B = true}); step(1)
local f1 = slots97(0x14)[1]
local fspeed = f1 and string.format("%02X%02X", rd(0x3FC + f1), rd(0x418 + f1)) or "-"
wf.F = f1 and rd(0x31C + f1)
for _ = 1, 40 do step(1) end
t.hold({}); step(2)
wf.FC = fr(0x15)
check(fspeed == "0580" and kinds[1] == 0x14 and kinds[2] == 0x15,
  string.format("W: F: ball at $%s (5.5 px/frame), held 40 frames then released: kinds %s", fspeed,
    table.concat((function() local r = {} for _, k in ipairs(kinds) do r[#r + 1] = string.format("%02X", k) end return r end)(), ",")))
step(60)
-- F burst on a mummy pinned in front
calm = false
wr(0x434 + 7, 0x1A); wr(0x46C + 7, 0); wr(0x300 + 7, 0); wr(0x584 + 7, 0x20); wr(0x530 + 7, 0)
wr(0x450 + 7, 1); wr(0x38C + 7, rd(0x38C) + 0x30); wr(0x354 + 7, rd(0x354) - 8); wr(0x488 + 7, 0); wr(0x31C + 7, 1)
clear_bullets(); kinds = {}
local frags = 0
t.hold({B = true}); step(1); t.hold({})
for _ = 1, 30 do
  if rd(0x434 + 7) == 0x1A then wr(0x38C + 7, rd(0x38C) + 0x30); wr(0x354 + 7, rd(0x354) - 8) end
  step(1)
  wf.frag = wf.frag or fr(0x16)
end
for _, k in ipairs(kinds) do if k == 0x16 then frags = frags + 1 end end
check(frags >= 3, string.format("W: F hitting a mummy bursts into %d fragments (4)", frags))
wr(0x434 + 7, 0); calm = true; step(30)
-- R
wr(0x15B, 0); wr(0x70, 1); clear_bullets(); step(2)
t.hold({B = true}); step(1); t.hold({})
local r1 = slots97(0x10)[1]
local rspeed = r1 and string.format("%02X%02X", rd(0x3FC + r1), rd(0x418 + r1)) or "-"
wf.rifle = r1 and rd(0x31C + r1)
wr(0x70, 0); step(40)
check(rspeed == "0580", string.format("W: R: the rifle flies at $%s (5.5 px/frame)", rspeed))
local names = {"rifle", "M", "S", "L", "Lup", "F", "FC", "frag"}
local want_f = ART and {rifle = 0x10, M = 0x11, S = 0x12, L = 0x13, Lup = 0x14, F = 0x17, FC = 0x18, frag = 0x12} or {}
local fok, fs = true, {}
for _, n in ipairs(names) do
  local w = want_f[n] or 0x50
  if wf[n] ~= w then fok = false end
  fs[#fs + 1] = string.format("%s %s", n, wf[n] and string.format("%02X", wf[n]) or "-")
end
check(fok, string.format("W: metasprites per kind: %s (%s)", table.concat(fs, ", "),
  ART and "rifle 10, M 11, S and fragments 12, laser 13 / up 14, ball 17, charged 18" or "all the dagger's $50"))
invuln, calm = true, false

-- E. stand and shoot (turn around every 90 frames) until a bullet kills an enemy
hits, kills = {}, {}
local k = 0
while #kills == 0 and k < 2400 do
  local face = (math.floor(k / 90) % 2 == 0) and "left" or "right"
  local b = {B = (k % 12 == 0)}
  if k % 90 < 2 then b[face] = true end
  t.hold(b); step(1); k = k + 1
end
check(#kills > 0 and #hits > 0, string.format("E: a bullet killed an enemy after %d frames (%s); projectile hits: %d", k, kills[1] or "none", #hits))
t.hold({}); step(30)

-- F. walk right with Up pulses until on the stairs, then climb and press B every 20 frames
local seen = 0
for i = 1, 1500 do
  t.hold({right = true, up = (i % 40 < 20)}); step(1)
  if rd(0x46C) == 4 then seen = i; break end
end
step(1)
for s = 0x14, 0x16 do wr(0x434 + s, 0) end     -- start with free slots
reset_counts()
local ys = rd(0x3F)
local onstairs, presses = 0, 0
for i = 1, 60 do
  local b = (i % 20 == 1)
  if b then presses = presses + 1 end
  t.hold({up = true, B = b}); step(1)
  if rd(0x46C) == 4 then onstairs = onstairs + 1 end
end
check(seen > 0 and onstairs == 60 and ys - rd(0x3F) >= 28 and whip == 0,
  string.format("F: on stairs + B keeps climbing (state 4 for %d/60 frames, Y %02X -> %02X), whip frames %d", onstairs, ys, rd(0x3F), whip))
check(spawns == presses, string.format("F: every press on the stairs fired: %d bullets for %d presses", spawns, presses))
calm = true
local sdx, sdy = track({up = true})
aim_ok("on stairs + Up = up along the steps", sdx, sdy, 11, -11)
calm = false
t.hold({}); step(2)

-- S. stairs and aiming: find where Up starts the stairs walking right in stage 1, stop there, then Up+B and Up
savestate.load(stage1)
invuln, calm = true, true
local xe = nil
for i = 1, 1500 do
  t.hold({right = true, up = true}); step(1)
  local st = rd(0x46C)
  if st == 6 or st == 4 then xe = wx(); break end
end
savestate.load(stage1)
if xe then
  for i = 1, 1500 do
    if wx() >= xe then break end
    t.hold({right = true}); step(1)
  end
end
t.hold({}); step(4)
local sp = savestate.create(); savestate.save(sp)
reset_counts()
local climbed_b = 0
for i = 1, 60 do t.hold({up = true, B = (i % 10 == 1)}); step(1); local st = rd(0x46C); if st == 4 or st == 6 then climbed_b = climbed_b + 1 end end
local shots_b = spawns
t.hold({}); step(2)
savestate.load(sp)
local climb_at = nil
for i = 1, 60 do t.hold({up = true}); step(1); local st = rd(0x46C); if (st == 4 or st == 6) and not climb_at then climb_at = i end end
t.hold({}); step(2)
check(xe ~= nil and climbed_b == 0 and shots_b >= 5 and climb_at ~= nil and climb_at >= 16 and climb_at <= 20,
  string.format("S: at the stair base (X %s): Up, B tapped every 10 frames for 60 frames: %d frames on the stairs, %d shots; Up alone steps on after %s frames (16-20)",
    tostring(xe), climbed_b, shots_b, tostring(climb_at)))
invuln, calm = true, false

-- G. an enemy hit without knockback (stage 1, standing still facing the zombies)
savestate.load(stage1)
invuln = false
wr(0x5B, 0)
reset_counts()
local hp0, hit_at, xhit, inv_after = rd(0x45), nil, nil, nil
for i = 1, 1500 do
  t.hold({}); step(1)
  if rd(0x45) < hp0 then hit_at = i; xhit = wx(); step(1); inv_after = rd(0x5B); break end
end
local xmax = 0
if hit_at then for _ = 1, 30 do step(1); xmax = math.max(xmax, math.abs(wx() - xhit)) end end
check(hit_at ~= nil and knocked == 0 and xmax == 0 and inv_after ~= nil and inv_after >= 0x2E,
  string.format("G: hit after %s frames: health %d -> %d, knockback frames %d, pushed %d px, invincibility %s",
    tostring(hit_at), hp0, rd(0x45), knocked, xmax, inv_after and string.format("$%02X", inv_after) or "?"))

-- H. a hit at zero health: dead at once
savestate.load(stage1)
wr(0x5B, 0)
reset_counts()
local died_at, state_seq = nil, {}
wr(0x45, 1); wr(0x44, 1)
for i = 1, 1500 do
  t.hold({}); step(1)
  local st = rd(0x46C)
  if state_seq[#state_seq] ~= st then state_seq[#state_seq + 1] = st end
  if st == 8 then died_at = i; break end
end
check(died_at ~= nil and knocked == 0,
  string.format("H: at zero health a hit kills at once: dead after %s frames, states %s, knockback frames %d",
    tostring(died_at), table.concat(state_seq, ","), knocked))

-- Y. B's barrier: standing still in stage 1 as in G, a zombie walks into the commando and dies; the barrier lasts
-- 510 frames; then a mummy pinned on him: spared, and he isn't hurt
savestate.load(stage1)
invuln = false
reset_counts()
local nk, hpy = #kills, rd(0x45)
wr(0x5B, 0xFF); if BON then wr(BON, 1) end
local bar_end, touch_kills = nil, 0
for i = 1, 700 do
  t.hold({}); step(1)
  if not bar_end and BON and rd(BON) == 0 then bar_end = i end
  if bar_end then break end
end
touch_kills = #kills - nk
check(touch_kills >= 1 and rd(0x45) == hpy and spawns == 0 and bar_end and bar_end >= 505 and bar_end <= 515,
  string.format("Y: barrier: %d enemies died touching the commando (no shots: %d), health %d -> %d, the barrier lasted %s frames (510)",
    touch_kills, spawns, hpy, rd(0x45), tostring(bar_end)))
savestate.load(stage1)
calm = true
step(2)
calm = false
wr(0x434 + 7, 0x1A); wr(0x46C + 7, 0); wr(0x300 + 7, 0); wr(0x370 + 7, 0); wr(0x3A8 + 7, 0)
wr(0x514 + 7, 0); wr(0x568 + 7, 0); wr(0x584 + 7, 0x20); wr(0x530 + 7, 0)
wr(0x450 + 7, 1); wr(0x488 + 7, 0); wr(0x31C + 7, 0x01)
wr(0x5B, 0xFF); if BON then wr(BON, 1) end
local mhp, hpm = rd(0x584 + 7), rd(0x45)
for _ = 1, 60 do
  if rd(0x434 + 7) == 0x1A then wr(0x38C + 7, rd(0x38C)); wr(0x354 + 7, rd(0x354)) end
  t.hold({}); t.frame(1)
end
check(rd(0x434 + 7) == 0x1A and rd(0x584 + 7) == mhp and rd(0x45) == hpm,
  string.format("Y: barrier: a mummy pinned on the commando for 60 frames is spared (type %02X, HP $%02X -> $%02X), health %d -> %d",
    rd(0x434 + 7), mhp, rd(0x584 + 7), hpm, rd(0x45)))
wr(0x434 + 7, 0)

-- I. stage 3 boss room: a bullet breaks the wall block (level X $02B8, the whip breaks it from Y $C0)
local breaks = 0
memory.registerexec(0xA8F8, function() breaks = breaks + 1 end)
savestate.load(stage1)
invuln = true
wr(0x29, 3); wr(0x18, 0x0C); wr(0x19, 7); t.frame(2); wait(playing, 1500); t.frame(30)
local BX = 0x2B8
for _ = 1, 1500 do
  wr(0x5B, 0x30)
  local d = wx() - BX
  if math.abs(d) >= 0x38 and math.abs(d) <= 0x40 and rd(0x46C) == 0 then break end
  if d > 0x40 then t.hold({left = true}) elseif d < -0x40 then t.hold({right = true})
  elseif d > 0 then t.hold({right = true}) else t.hold({left = true}) end
  t.frame(1)
end
t.hold({})
if (wx() > BX) ~= (rd(0x450) == 1) then t.press({[wx() > BX and "left" or "right"] = true}, 1, 2) end
step(10)
local before = rd(0x146)
for _ = 1, 4 do t.hold({B = true}); step(1); t.hold({}); step(25); if rd(0x146) ~= before then break end end
if rd(0x146) == before then
  for _ = 1, 4 do t.hold({down = true}); step(6); t.hold({down = true, B = true}); step(1); t.hold({down = true}); step(25); if rd(0x146) ~= before then break end end
end
t.hold({}); step(20)
check(rd(0x146) ~= before and breaks >= 1,
  string.format("I: stage 3: a bullet broke the wall block from %d px ($0146 %02X -> %02X, break sequence %d)", math.abs(wx() - BX), before, rd(0x146), breaks))
t.shot(t.tag .. "_block")

-- J. bullets don't freeze a boss: a mummy (type $1A) pinned in front of Simon, a bullet every 12 frames
-- (bullet objects as FireTick makes them: type $97, 4 px/frame to the right)
savestate.load(stage1)
invuln = true
local S = 7
local function spawn_bullet(slot, x)
  wr(0x434 + slot, 0x97); wr(0x584 + slot, 0x10); wr(0x46C + slot, 0); wr(0x300 + slot, 0); wr(0x370 + slot, 0); wr(0x3A8 + slot, 0)
  wr(0x3FC + slot, 4); wr(0x418 + slot, 0); wr(0x3C4 + slot, 0); wr(0x3E0 + slot, 0); wr(0x4DC + slot, 0)
  wr(0x450 + slot, 0); wr(0x38C + slot, x); wr(0x354 + slot, 0xA8); wr(0x488 + slot, 0x80)
end
wr(0x434 + S, 0x1A); wr(0x46C + S, 0); wr(0x300 + S, 0); wr(0x370 + S, 0); wr(0x3A8 + S, 0)
wr(0x514 + S, 0); wr(0x568 + S, 0); wr(0x584 + S, 0x20); wr(0x530 + S, 0)
wr(0x450 + S, 1); wr(0x38C + S, 0x90); wr(0x354 + S, 0xA8); wr(0x488 + S, 0); wr(0x31C + S, 0x01)
local hp_start, frozen_seen, boss_hits = rd(0x584 + S), 0, 0
local nhits = #hits
for f = 1, 200 do
  if rd(0x434 + S) == 0x1A then wr(0x38C + S, 0x90); wr(0x354 + S, 0xA8); wr(0x300 + S, 0) end
  if f % 12 == 1 and rd(0x434 + 0x16) == 0 then spawn_bullet(0x16, 0x70) end
  t.frame(1)
  if rd(0x434 + S) == 0x1A and (rd(0x568 + S) ~= 0 or AND(rd(0x488 + S), 0x80) ~= 0) then frozen_seen = frozen_seen + 1 end
end
boss_hits = #hits - nhits
check(boss_hits >= 5 and rd(0x584 + S) < hp_start and frozen_seen == 0,
  string.format("J: mummy hit %d times by bullets, HP $%02X -> $%02X, frames frozen %d", boss_hits, hp_start, rd(0x584 + S), frozen_seen))

t.finish(#fails == 0, #fails > 0 and (#fails .. " checks failed: " .. fails[1]) or nil)
