-- Stage warp for testing (verified on USA V1.1): from stage play, set $29 = N, $18 = $0C, $19 = 7. That is the
-- "start next block" substate of the stage-clear state ($C7E5, bank 7): loads CHR set $C8B0[N], $28 = $29, timer, music, reloads stage N.
-- Run: python3 scripts/run_fceux.py games/castlevania/rom/original.nes games/castlevania/tests/explore/sim_warp.lua --game-dir games/castlevania --out <dir> --tag warp --env STAGES=07,0C
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("maximum")
local function playing() return t.rd(0x18) == 5 and t.rd(0x19) == 6 end
local function wait_play(max) local k = 0; while not playing() and k < (max or 1500) do t.frame(1); k = k + 1 end; return k end

-- Warp to stage n (0..$12, the HUD shows "STAGE nn" = n, 0 shown as 01). Call while the game is in stage play
-- ($18 = 5). Returns the frames it took (~390-620).
local function warp(n)
  t.wr(0x29, n); t.wr(0x18, 0x0C); t.wr(0x19, 7)
  return wait_play()
end

emu.poweron(); t.frame(300); t.press({start = true}, 4, 0); t.frame(800); wait_play()
local fails = 0
for s in string.gmatch(t.env("STAGES", "07"), "%x+") do
  local n = tonumber(s, 16)
  local lives = t.rd(0x2A)
  local k = warp(n)
  t.frame(60)
  local x0 = t.rd(0x40) + 256 * t.rd(0x41)
  t.hold({right = true}); t.frame(30); t.hold({}); t.frame(5)
  local dx = t.rd(0x40) + 256 * t.rd(0x41) - x0
  local ok = playing() and t.rd(0x28) == n and t.rd(0x2A) == lives
  if not ok then fails = fails + 1 end
  t.log(string.format("%s warp to %02X: %d frames, $28=%02X lives=%d timer=%X%02X Simon X=%d Y=%d (walk right moved %d px)",
    ok and "ok  " or "FAIL", n, k, t.rd(0x28), t.rd(0x2A), t.rd(0x43), t.rd(0x42), x0, t.rd(0x3F), dx))
  t.shot(string.format("%s_%02X", t.tag, n))
end
t.finish(fails == 0)
