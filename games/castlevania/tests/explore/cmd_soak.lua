-- Soak run for the commando build: warp into every stage 1-18 and let a bot walk, jump, climb and fire for
-- FRAMES frames each (invincible except pits). Logs per stage: shots, hits, kills, blocks broken, deaths,
-- lag frames, unexpected game states, and whether the frame counter kept running (no hang).
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("nothrottle")
local rd, wr = t.rd, t.wr
local FRAMES = tonumber(t.env("FRAMES", "1200"))
local function playing() return rd(0x18) == 5 and rd(0x19) == 6 end
local function wait(cond, max) local k = 0; while not cond() and k < (max or 600) do t.frame(1); k = k + 1 end; return cond() end
local shots, hits, kills, breaks = 0, 0, 0, 0
local INIT = t.sym("InitBullet")
if INIT then memory.registerexec(INIT, function() if t.rd(0x27) == 5 and t.rd(0x012D) ~= 0x16 then shots = shots + 1 end end) end
memory.registerexec(0xE562, function() if t.rd(0x0E) ~= 0xFF then hits = hits + 1 end end)   -- shot hits (bullets and subweapons)
memory.registerexec(0xE097, function() kills = kills + 1 end)
memory.registerexec(0xA8F8, function() breaks = breaks + 1 end)
-- 6 death, 7 game over, $0D continue: the bot walks into pits (invincibility doesn't cover them), and the
-- commando keeps walking where the original's whip would stop him
local known = {[5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [0x0A] = true, [0x0C] = true, [0x0D] = true, [0x0E] = true}
emu.poweron(); t.frame(300); t.press({start = true}, 4, 0); t.frame(800); wait(playing, 1500)
local total_bad = 0
for s = 1, 18 do
  wr(0x29, s); wr(0x18, 0x0C); wr(0x19, 7); t.frame(2)
  local ok = wait(playing, 1500)
  shots, hits, kills, breaks = 0, 0, 0, 0
  local deaths, lag, odd, f0, stuck = 0, 0, 0, rd(0x1A), 0
  local lastx, same = -1, 0
  for i = 1, FRAMES do
    wr(0x5B, 0x30); wr(0x45, 0x40)
    local m = i % 160
    local b = {right = (m < 120), left = (m >= 140), B = (i % 9 == 0)}
    if m >= 60 and m < 64 then b.A = true end
    if (i % 400) >= 300 then b.up = (i % 40 < 20) end
    if (i % 500) >= 450 then b.down = true; b.right = false end
    t.hold(b); t.frame(1)
    if emu.lagged() then lag = lag + 1 end
    if rd(0x46C) == 8 and rd(0x18) == 5 then deaths = deaths + 1; wait(playing, 600) end
    if not known[rd(0x18)] then odd = odd + 1 end
  end
  t.hold({})
  local f1 = rd(0x1A)
  local bad = (not ok) or odd > 0 or f1 == f0
  if bad then total_bad = total_bad + 1 end
  t.log(string.format("stage %02d: reached=%s shots %d hits %d kills %d blocks %d death-frames %d lag %d/%d odd-states %d now $28=%02X $18=%02X lives %d %s",
    s, tostring(ok), shots, hits, kills, breaks, deaths, lag, FRAMES, odd, rd(0x28), rd(0x18), rd(0x2A), bad and "BAD" or ""))
  if rd(0x18) == 0x0D or rd(0x18) == 7 then wr(0x2A, 3); wr(0x18, 5); wr(0x19, 0); wait(playing, 1500) end
  t.shot(string.format("%s_s%02d", t.tag, s))
end
t.finish(total_bad == 0, total_bad > 0 and (total_bad .. " stages misbehaved") or nil)
