-- Simon's RAM checked by behaviour in stage 1 (castle hall): scripted input, one "ok"/"FAIL" line per fact.
-- Pokes used: $5B (invincibility) while walking to the stairs, $015B/$71 (subweapon, hearts), $45 (health 0 = death).
-- Run: python3 scripts/run_fceux.py games/castlevania/rom/original.nes games/castlevania/tests/explore/sim_ram.lua --game-dir games/castlevania --out <dir> --tag simram
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("maximum")
local rd, wr = t.rd, t.wr
local fails = 0
local function check(c, what) t.log((c and "ok   " or "FAIL ") .. what); if not c then fails = fails + 1 end end
local function playing() return rd(0x18) == 5 and rd(0x19) == 6 end
local function wait(cond, max) local k = 0; while not cond() and k < (max or 600) do t.frame(1); k = k + 1 end; return cond() end
local function act(b, n) t.hold(b); t.frame(n) end
local function wx() return rd(0x40) + 256 * rd(0x41) end
local function sc() return rd(0x2E) + 256 * rd(0x2F) end

emu.poweron(); t.frame(300); t.press({start = true}, 4, 0); t.frame(800); wait(playing)
check(rd(0x28) == 0 and rd(0x2A) == 4 and rd(0x44) == 0x40 and rd(0x45) == 0x40 and rd(0x71) == 5 and rd(0x43) * 256 + rd(0x42) >= 0x290 and rd(0x43) * 256 + rd(0x42) <= 0x300,
  string.format("new game: $28=0 lives $2A=4 (HUD P-03) health $44/$45=$40 hearts $71=5 timer BCD $43$42=%X%02X (starts at 0300)", rd(0x43), rd(0x42)))
act({right = true}, 1); wait(function() return rd(0x28) == 1 end, 1500); act({}, 1); wait(playing, 300)
check(rd(0x28) == 1, "the castle door leads to $28=1 (HUD still STAGE 01)")
-- walking
local x0 = rd(0x38C)
act({right = true}, 20)
check(rd(0x38C) == x0 + 20 and rd(0x450) == 0 and rd(0x46C) == 0 and rd(0xF7) == 0x01,
  string.format("walk right: $038C +1/frame (%d), facing $0450=0, state $046C=0, $F7=01 (held)", rd(0x38C) - x0))
check(wx() == rd(0x38C) + sc(), string.format("$40/$41 = $038C + scroll $2E/$2F (%d = %d + %d)", wx(), rd(0x38C), sc()))
act({left = true}, 10)
check(rd(0x450) == 1 and rd(0xF7) == 0x02, "walk left: facing $0450=1, $F7=02")
act({}, 5)
-- jump: $0488 counts frames, $0354 = $3F of the previous frame
local y0 = rd(0x3F)
act({A = true}, 1)
local lag_ok, cnt_ok, prev3f, prevj = true, true, rd(0x3F), rd(0x488)
for i = 1, 12 do
  t.frame(1)
  if rd(0x354) ~= prev3f then lag_ok = false end
  if rd(0x488) ~= prevj + 1 then cnt_ok = false end
  prev3f, prevj = rd(0x3F), rd(0x488)
end
check(rd(0x46C) == 1 and rd(0x3F) < y0, string.format("jump: $046C=1, Y $3F rises (%02X -> %02X)", y0, rd(0x3F)))
check(cnt_ok, "jump: $0488 +1 per frame")
check(lag_ok, "jump: $0354 (sprite Y) = $3F of the previous frame")
act({}, 50)
check(rd(0x46C) == 0 and rd(0x3F) == y0, "landed: $046C=0, $3F back")
-- duck
act({down = true}, 6)
check(rd(0x46C) == 3 and rd(0x5F) == 0x0A, string.format("duck: $046C=3, height $5F=%02X (standing 0C)", rd(0x5F)))
act({}, 6)
check(rd(0x5F) == 0x0C, "standing: $5F=0C")
-- whip
act({B = true}, 2); act({}, 3)
local w = rd(0x568)
t.frame(1)
check(rd(0x46C) == 2 and rd(0x434) == 1 and rd(0x568) == w + 1, string.format("whip: $046C=2, $0434=1, $0568 +1/frame (%02X)", rd(0x568)))
act({}, 30)
check(rd(0x46C) == 0 and rd(0x434) == 0, "whip over: $046C=0, $0434=0")
act({down = true}, 4); act({down = true, B = true}, 2); act({down = true}, 2)
check(rd(0x434) == 2 and rd(0x46C) == 2, string.format("duck + B: $0434=2 (crouching whip), $046C=2 ($0434=%02X)", rd(0x434)))
act({}, 30)
act({A = true}, 6); act({B = true}, 2); act({}, 1)
check(rd(0x434) == 3 and rd(0x46C) == 1 and rd(0x54C) ~= 0, string.format("jump + B: $0434=3 (jumping whip), $046C stays 1, $054C=%02X (attack-in-air flag)", rd(0x54C)))
act({}, 60)
-- subweapon (poked): dagger = 08
wait(function() return rd(0x46C) == 0 and rd(0x434) == 0 end, 120)
wr(0x15B, 8); wr(0x71, 10); act({}, 2)
act({up = true, B = true}, 2); act({}, 2)
check(rd(0x434) == 0x81 and rd(0x71) == 9, string.format("Up+B with $015B=08: $0434=81 (bit 7 = subweapon), hearts $71 10 -> %d", rd(0x71)))
act({}, 40)
-- pad 2 does not move Simon
t.pad = 2; local xs = wx(); act({right = true}, 10); t.pad = 1
check(rd(0xF8) == 0x01 and rd(0xF7) == 0 and wx() == xs, "pad 2 right: $F8=01, $F7=00, Simon does not move")
act({}, 2)
-- hit by a zombie (stand still)
local hit = wait(function() return rd(0x46C) == 5 end, 900)
local h = rd(0x45)
check(hit and rd(0x44) > h, string.format("hit: $046C=5 (knockback), real health $45=%02X drops at once, display $44=%02X follows", h, rd(0x44)))
wait(function() return rd(0x46C) == 9 end, 120)
check(rd(0x5B) == 0x30, string.format("knockback landing: $046C=9, invincibility $5B=30 (%02X)", rd(0x5B)))
local i0 = rd(0x5B); t.frame(8)
check(i0 - rd(0x5B) == 4 and rd(0x44) == h, string.format("$5B -1 every 2 frames (%02X -> %02X); $44 reached $45", i0, rd(0x5B)))
wait(function() return rd(0x46C) == 0 end, 120)
-- stairs (invincible while walking right with Up pulses)
local seen = {}
for i = 1, 700 do
  wr(0x5B, 0x20)
  act({right = true, up = (i % 40 < 20)}, 1)
  seen[rd(0x46C)] = true
  if rd(0x46C) == 4 then break end
end
check(seen[6] and seen[4], "stairs: Up near a staircase -> $046C=6 (walk to the step) then 4 (on stairs)")
local ys = rd(0x3F); act({up = true}, 16)
check(rd(0x3F) < ys and rd(0x46C) == 4, string.format("climbing: $3F %02X -> %02X", ys, rd(0x3F)))
act({}, 2)
-- death and respawn
local lives = rd(0x2A)
wr(0x5B, 0); wr(0x45, 0)
check(wait(function() return rd(0x46C) == 8 end, 30), "health $45=0 -> death, $046C=8")
check(wait(function() return rd(0x18) == 6 end, 600), "death animation ends in $18=6")
wait(playing, 600)
check(rd(0x2A) == lives - 1 and rd(0x45) == 0x40 and rd(0x71) == 5 and rd(0x15B) == 0 and rd(0x70) == 0,
  string.format("respawn: lives $2A %d -> %d, health refilled, hearts 5, subweapon and whip level cleared", lives, rd(0x2A)))
t.finish(fails == 0, fails > 0 and (fails .. " checks failed") or nil)
