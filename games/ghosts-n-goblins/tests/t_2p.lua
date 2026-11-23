-- 2-player mode: player 1 loses a life to a forced timeout, then player 2
-- plays.  PASS: player 2 gets five-way bursts and enemy contact never enters
-- the damage routine.
local g = dofile(os.getenv("GAME_DIR") .. "/tests/gng.lua")
local damage, contact = 0, g.counter(0xF5E8)
-- count projectiles at spawn time: $E062 follows each WeaponInit call in the
-- spread loop, $E071 (DEC $85) ends a burst.  The remix ROM runs the same
-- loop in bank 8 (GNG_REMIX=1: Fire@spawned / Fire@fired from build/*.sym).
local spawned, burst_sizes = 0, {}
local function on_spawn() spawned = spawned + 1 end
local function on_burst() burst_sizes[#burst_sizes + 1] = spawned; spawned = 0 end
if g.env("GNG_REMIX", "0") == "1" then
  g.exec_in(g.sym("Fire@spawned"), 8, on_spawn)
  g.exec_in(g.sym("Fire@fired"), 8, on_burst)
else
  memory.registerexec(0xE062, 1, on_spawn)
  memory.registerexec(0xE071, 1, on_burst)
end
memory.registerexec(0xE171, 1, function()
  if memory.readbyte(g.TIMEUP) == 0 then damage = damage + 1 end
end)
emu.speedmode("maximum")
g.frame(120)
g.press({select = true}, 4, 8)          -- cursor to "2 PLAYERS"
g.press({start = true}, 4, 4)
for _ = 1, 1500 do g.frame(1) if emu.framecount() > 900 and g.rd(g.FLAGS) == 0x80 then break end end
g.log("P1 in play, player index $BA =", g.rd(0xBA))
g.wr(0x06F6, 0); g.wr(0x06FA, 0); g.wr(0x06FC, 1)   -- P1 times out
local p2 = false
for _ = 1, 2400 do
  g.frame(1)
  if g.rd(0xBA) == 1 and g.rd(g.FLAGS) == 0x80 then p2 = true break end
end
if not p2 then g.finish(false, "player 2 turn not reached") end
g.log("P2 in play at frame", emu.framecount())
g.pad = 2   -- player 2 plays with controller 2
g.shot(g.tag .. "_p2")
local c0 = contact.n
local nb0 = #burst_sizes
local function slots_free()
  for s = 0x0F, 0x13 do if g.rd(g.FLAGS + s) ~= 0 then return false end end
  return true
end
local presses = 0
for i = 1, 20 do
  for _ = 1, 200 do if slots_free() then break end g.frame(1) end
  g.press({B = true}, 4, 0)
  presses = presses + 1
  g.frame(116)
end
local bursts, good = #burst_sizes - nb0, 0
for k = nb0 + 1, #burst_sizes do if burst_sizes[k] == 5 then good = good + 1 end end
g.shot(g.tag .. "_p2_end")
g.log("P2: presses", presses, "bursts fired", bursts, "with 5 projectiles", good, "contacts", contact.n - c0, "damage", damage,
      "player", g.rd(0xBA), "lives P2", g.rd(g.LIVES))
local ok = bursts == presses and good == bursts and damage == 0 and contact.n - c0 > 0
local why = nil
if not ok then why = "bursts " .. good .. "/" .. bursts .. " damage " .. damage .. " contacts " .. (contact.n - c0) end
g.finish(ok, why)
