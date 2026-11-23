-- Remix ROM: title-screen menu.
-- PASS: the two menu lines are drawn in the nametable when the title appears,
-- A cycles the shot mode and B the armor mode (3 values each, wrapping), the
-- slot partition byte EnemyEnd ($BE) follows the shot mode, a change restarts
-- the title idle timer, Select still moves the 1P/2P cursor, the settings
-- survive a console reset, power-on restores the defaults, and the lines are
-- redrawn after the attract demo.
local g = dofile(os.getenv("GAME_DIR") .. "/tests/gng.lua")
local SHOT, ARMOR, ENEMY_END = 0x071A, 0x071B, 0xBE
local SHOT_LINES = {[0] = "A SHOT   5 WAY SPREAD ", "A SHOT   RAINBOW      ", "A SHOT   NORMAL       "}
local ARMOR_LINES = {[0] = "B ARMOR  INVINCIBLE   ", "B ARMOR  4 HITS EACH  ", "B ARMOR  NORMAL       "}
local ENEMY_ENDS = {[0] = 0x0F, 0x0F, 0x11}

local function tile(c)
  local b = c:byte()
  if c == " " then return 0xFF end
  if b >= 48 and b <= 57 then return b - 48 end
  return b - 65 + 10
end
local function row_is(row, str)
  for i = 1, #str do
    if ppu.readbyte(0x2000 + row * 32 + 4 + i) ~= tile(str:sub(i, i)) then return false end
  end
  return true
end

local title_frames, sessions, demo_seen = 0, 0, false
memory.registerexec(g.sym("TitleStub"), 1, function() title_frames = title_frames + 1 end)
memory.registerexec(0xC424, 1, function() sessions = sessions + 1 end)   -- title loop setup
local function wait_title(max)
  local s0 = sessions
  for _ = 1, max or 1200 do
    g.frame(1)
    if g.rd(0x94) ~= 0 then demo_seen = true end
    if sessions > s0 then g.frame(4) return true end
  end
  return false
end

local fails = {}
local function check(cond, what)
  g.log((cond and "ok   " or "FAIL ") .. what)
  if not cond then fails[#fails + 1] = what end
end
local function check_state(shot, armor, what)
  g.frame(2)   -- the NMI copies the queued lines in the next vblank
  check(g.rd(SHOT) == shot and g.rd(ARMOR) == armor,
        string.format("%s: modes %d/%d (want %d/%d)", what, g.rd(SHOT), g.rd(ARMOR), shot, armor))
  check(g.rd(ENEMY_END) == ENEMY_ENDS[shot], string.format("%s: EnemyEnd $%02X", what, g.rd(ENEMY_END)))
  check(row_is(23, SHOT_LINES[shot]), what .. ": shot line '" .. SHOT_LINES[shot] .. "'")
  check(row_is(24, ARMOR_LINES[armor]), what .. ": armor line '" .. ARMOR_LINES[armor] .. "'")
end

emu.speedmode("maximum")
check(wait_title(600), "title loop reached")
check_state(0, 0, "power-on defaults")
g.shot(g.tag .. "_defaults")

for k = 1, 3 do
  g.frame(30)
  g.press({A = true}, 3, 1)
  local timer = g.rd(0x87) * 256 + g.rd(0x86)
  check(timer >= 0x01C2 - 3, string.format("A press %d restarts idle timer ($%04X)", k, timer))
  check_state(k % 3, 0, "after A x" .. k)
  if k == 2 then g.shot(g.tag .. "_normal_shot") end
end
for k = 1, 3 do
  g.press({B = true}, 3, 1)
  check_state(0, k % 3, "after B x" .. k)
  if k == 1 then g.shot(g.tag .. "_4hits") end
end

local cursor = g.rd(0xA3)
g.press({select = true}, 3, 3)
check(g.rd(0xA3) ~= cursor and g.rd(SHOT) == 0 and g.rd(ARMOR) == 0,
      string.format("Select moves the 1P/2P cursor ($A3 %d -> %d), modes unchanged", cursor, g.rd(0xA3)))
g.press({select = true}, 3, 3)

-- rainbow + 4 hits, then console reset
g.press({A = true}, 3, 3)
g.press({B = true}, 3, 3)
emu.softreset()
check(wait_title(900), "title after reset")
check_state(1, 1, "after console reset (settings kept)")
g.shot(g.tag .. "_after_reset")

emu.poweron()
check(wait_title(900), "title after power cycle")
check_state(0, 0, "after power cycle (defaults)")

-- leave the title idle: attract demo, then the title again
g.press({B = true}, 3, 3)
check(wait_title(4000), "title again after the attract demo")
check(demo_seen, "attract demo ran ($94 set)")
check_state(0, 1, "redrawn after the demo")

g.log("title frames hooked:", title_frames, "sessions:", sessions)
g.finish(#fails == 0, #fails > 0 and (#fails .. " checks failed: " .. fails[1]) or nil)
