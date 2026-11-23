-- Ladder test on the first hill of stage 1 (ladder at world X ~920).
-- Jump-walk to the hill, step right in small increments trying Up, climb to
-- the top, step off.  PASS: climbed >= 32 px, ended on the upper level (>= 24
-- px above the ground), the damage routine never ran for an enemy hit, and
-- enemies touched Arthur during the run (zombies emerge around the hill).
-- GNG_LADDER_HIT=1 (remix ROM): walk to the ladder in the default
-- (invincible) mode, then switch the armor setting ($071B) to "4 HITS EACH"
-- and force one hit as soon as Arthur is on the ladder.  PASS: the hit is
-- absorbed, he keeps climbing to the top, the post-hit invulnerability
-- (bit 6) ends and he is visible.
local g = dofile(os.getenv("GAME_DIR") .. "/tests/gng.lua")
local LADDER_HIT = g.env("GNG_LADDER_HIT", "0") == "1"
local ladder_ok = nil
local damage = 0
memory.registerexec(0xE171, 1, function()
  if memory.readbyte(g.TIMEUP) == 0 then damage = damage + 1 end
end)
local contact = g.counter(0xF5E8)
local force_hit, aflags, polls, absorbs = false, 0, 0, 0
local hit_frame, hit_polls, hit_absorbs, hit_y = nil, 0, 0, 0
local function watch_inv()   -- after the forced hit: wait for bit 6 to clear
  if LADDER_HIT and hit_frame and ladder_ok == nil and polls > hit_polls + 1
      and math.floor(aflags / 0x40) % 2 == 0 then
    local visible = math.floor(aflags / 0x80) % 2 == 1
    g.log("ladder hit at y", hit_y, ": absorbed", absorbs - hit_absorbs, "; invulnerability ended after",
          emu.framecount() - hit_frame, "frames at y", g.arthur_y(), "; visible", tostring(visible))
    ladder_ok = absorbs - hit_absorbs >= 1 and visible
  end
end
memory.registerexec(0xE014, 1, function()
  if force_hit then
    memory.writebyte(g.FLAGS, OR(memory.readbyte(g.FLAGS), 1))
    force_hit = false
  end
  aflags = memory.readbyte(g.FLAGS)
  polls = polls + 1
end)
if LADDER_HIT then
  g.exec_in(g.sym("ArthurTick@absorb"), 8, function() absorbs = absorbs + 1 end)
end
local t0 = g.start_game()
if not t0 then g.finish(false, "gameplay not reached") end
local function settle()
  local last, same = -1, 0
  for _ = 1, 240 do
    g.hold({}); g.frame(1)
    local y = g.arthur_y()
    if y == last then same = same + 1 else same = 0 end
    last = y
    if same >= 20 then break end
  end
  return last
end
for i = 1, 2400 do
  g.hold({right = true, A = (i % 50) < 12}); g.frame(1)
  if g.arthur_x() >= 800 then break end
end
local base_y = settle()
g.log("at hill: x", g.arthur_x(), "ground y", base_y)
local climb_x, y_top = nil, nil
for target = 880, 960, 2 do
  for i = 1, 200 do
    if g.arthur_x() >= target then break end
    g.hold({right = (i % 3 == 0)}); g.frame(1)
  end
  local y0 = g.arthur_y()
  for _ = 1, 20 do g.hold({up = true}); g.frame(1) end
  if g.arthur_y() < y0 - 6 then
    climb_x = g.arthur_x()
    g.shot(g.tag .. "_climbing")
    if LADDER_HIT then
      g.wr(0x071B, 1)                          -- harness: armor mode 4 HITS EACH
      force_hit = true
      hit_frame, hit_polls, hit_absorbs, hit_y = emu.framecount(), polls, absorbs, g.arthur_y()
    end
    local last, same = g.arthur_y(), 0
    for _ = 1, 600 do
      g.hold({up = true}); g.frame(1)
      watch_inv()
      local y = g.arthur_y()
      if y == last then same = same + 1 else same = 0 end
      last = y
      if same >= 30 then break end
    end
    y_top = last
    break
  end
  g.hold({}); g.frame(6)
end
if not climb_x then g.finish(false, "could not grab the ladder") end
for _ = 1, 30 do g.hold({right = true}); g.frame(1); watch_inv() end
local end_y = settle()
for _ = 1, 600 do
  if not LADDER_HIT or ladder_ok ~= nil then break end
  g.hold({}); g.frame(1); watch_inv()
end
g.shot(g.tag .. "_top")
g.log("climbed at x", climb_x, "from y", base_y, "to", y_top, "(" .. (base_y - y_top) .. " px)",
      "after stepping off y", end_y, "contacts", contact.n, "damage", damage)
local ok = base_y - y_top >= 32 and end_y <= base_y - 24 and damage == 0 and contact.n > 0
if LADDER_HIT then   -- natural contacts after the switch may also be absorbed or hurt
  ok = base_y - y_top >= 32 and end_y <= base_y - 24 and ladder_ok == true
end
if ok then g.finish(true) else g.finish(false, "climb/upper-level/damage check failed") end
