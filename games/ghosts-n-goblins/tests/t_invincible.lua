-- Invincibility test.
--   GNG_MODE=vanilla : control run on the original ROM; PASS means damage
--                      *was* observed (proves the probes detect damage).
--   GNG_MODE=patched : PASS means enemies touched Arthur repeatedly but the
--                      damage routine never ran, armor and lives were kept,
--                      Arthur could still walk and jump, and timer expiry
--                      still killed him.
local g = dofile(os.getenv("GAME_DIR") .. "/tests/gng.lua")
local mode = g.env("GNG_MODE", "patched")
local function bit(v, m) return math.floor(v / m) % 2 == 1 end

local contact = g.counter(0xF5E8)      -- generic enemy/projectile contact sets hit bit
local damage = g.counter(0xE171)       -- damage routine (knockback/armor loss/death)
local death_hit = g.counter(0xE1AC)    -- death: hit without armor
local death_time = g.counter(0xE1C2)   -- death: timer expired
-- Arthur's flags must be sampled inside his own task: the renderer (bank 4
-- $8089) temporarily swaps slot 0/3 draw fields, so a frame-boundary read of
-- $04F0 can return an enemy's flags.  $E014 (HitPending) runs every frame in
-- Arthur's state code with X = 0.
local polls, naked_polls = 0, 0
memory.registerexec(0xE014, 1, function()
  polls = polls + 1
  if bit(memory.readbyte(g.FLAGS), 0x20) then naked_polls = naked_polls + 1 end
end)
local hitbit_sets = 0
local last = 0
memory.registerwrite(g.FLAGS, 1, function()
  local v = memory.readbyte(g.FLAGS)
  local pc = memory.getregister("pc")
  if pc ~= 0x8090 and pc ~= 0x8093 then          -- ignore the P1/P2 slot swap
    if bit(v, 1) and not bit(last, 1) then hitbit_sets = hitbit_sets + 1 end
    last = v
  end
end)

local t0 = g.start_game()
if not t0 then g.finish(false, "gameplay not reached") end
local lives0 = g.rd(g.LIVES)
g.log("mode", mode, "gameplay at frame", t0, "lives", lives0, "flags", g.hex(g.rd(g.FLAGS)))
g.shot(g.tag .. "_start")

-- Phase 1: stand still at the stage start for 40 s; zombies walk into Arthur.
local min_lives = lives0
for i = 1, 2400 do
  g.frame(1)
  if g.rd(g.LIVES) < min_lives then min_lives = g.rd(g.LIVES) end
  if i == 1300 then g.shot(g.tag .. "_standing") end
end
g.log("phase1 contact_events", contact.n, "hitbit_sets", hitbit_sets, "damage_routine", damage.n,
      "death_hit", death_hit.n, "polls", polls, "naked_polls", naked_polls, "lives", lives0, "->", g.rd(g.LIVES),
      "min", min_lives)
local p1 = {contact = contact.n, damage = damage.n, naked = naked_polls, lives = g.rd(g.LIVES)}

-- Phase 2: walk right and jump repeatedly for 20 s.
local x0 = g.arthur_x()
local ymin, ymax = 1e9, -1e9
for i = 1, 1200 do
  local jump = (i % 50) < 12
  g.hold({right = true, A = jump})
  g.frame(1)
  local y = g.arthur_y()
  if y < ymin then ymin = y end
  if y > ymax then ymax = y end
  if i == 600 then g.shot(g.tag .. "_walking") end
end
g.hold({})
local x1 = g.arthur_x()
g.log("phase2 x", x0, "->", x1, "travel", x1 - x0, "y range", ymin, ymax, "contact_events", contact.n,
      "damage_routine", damage.n, "polls", polls, "naked_polls", naked_polls, "lives", g.rd(g.LIVES))
local p2 = {travel = x1 - x0, yrange = ymax - ymin, damage = damage.n, naked = naked_polls,
            lives = g.rd(g.LIVES), contact = contact.n}

-- Phase 3: force the stage timer to ~0 and wait: expiry must stay lethal.
local lives_before = g.rd(g.LIVES)
g.wr(0x06F6, 0); g.wr(0x06FA, 0); g.wr(0x06FC, 1)
local died_frame = nil
for i = 1, 900 do
  g.frame(1)
  if not died_frame and (death_time.n > 0 or g.rd(g.LIVES) < lives_before) then died_frame = i end
end
g.shot(g.tag .. "_timeup")
g.log("phase3 timeup", g.hex(g.rd(g.TIMEUP)), "death_time", death_time.n, "lives", lives_before,
      "->", g.rd(g.LIVES), "died_after_frames", died_frame)

if mode == "vanilla" then
  local ok = p1.contact > 0 and p1.damage > 0 and p1.naked > 0
  g.finish(ok, ok and "baseline takes damage as expected" or "baseline damage NOT observed")
else
  local fails = {}
  if polls < 1000 then fails[#fails + 1] = "Arthur state code not polled (probe broken)" end
  if p1.contact < 3 then fails[#fails + 1] = "too few enemy contacts to prove anything" end
  if p2.damage ~= 0 then fails[#fails + 1] = "damage routine ran" end
  if p2.naked ~= 0 then fails[#fails + 1] = "armor lost" end
  if p2.lives ~= lives0 then fails[#fails + 1] = "life lost to enemies" end
  if p2.travel < 64 then fails[#fails + 1] = "Arthur did not walk" end
  if p2.yrange < 8 then fails[#fails + 1] = "Arthur did not jump" end
  if death_time.n == 0 then fails[#fails + 1] = "timer expiry no longer lethal" end
  g.finish(#fails == 0, table.concat(fails, "; "))
end
