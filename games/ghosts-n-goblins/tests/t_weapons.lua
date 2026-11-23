-- Five-way burst with every weapon.  For each weapon sprite id
-- (lance $40, dagger $42, torch $44, axe $36, cross $46) the held weapon is
-- forced in $053A/$C5 (what a pickup writes), one burst is checked (five
-- objects, expected engine type, directions 2..6), then the bot plays for
-- 40 s and damage events are counted per weapon slot.  Harness (as in
-- t_area.lua): lives topped up at 1 and the timer reset every 20 s, so all
-- five phases are gameplay (no game over / title screen).
local g = dofile(os.getenv("GAME_DIR") .. "/tests/gng.lua")
local FIRST, LAST = 0x0F, 0x13
local WEAPONS = {{0x40, 0x23, "lance"}, {0x42, 0x24, "dagger"}, {0x44, 0x25, "torch"},
                 {0x36, 0x26, "axe"}, {0x46, 0x27, "cross"}}
local hits = {}
local cur = nil
memory.registerexec(0xF5D0, 1, function()
  if cur then
    local y = memory.getregister("y")
    hits[cur][y] = (hits[cur][y] or 0) + 1
  end
end)
local t0 = g.start_game()
if not t0 then g.finish(false, "gameplay not reached") end
local fails = {}
for _, w in ipairs(WEAPONS) do
  local id, typ, name = w[1], w[2], w[3]
  hits[name] = {}
  cur = name
  g.wr(0x053A, id); g.wr(0x00C5, id)
  -- wait for free weapon slots, face right, fire one burst
  g.press({right = true}, 4, 2)
  for _ = 1, 200 do
    local busy = false
    for s = FIRST, LAST do if g.rd(g.FLAGS + s) ~= 0 then busy = true end end
    if not busy then break end
    g.frame(1)
  end
  g.press({B = true}, 4, 0)
  local count, types, dirs = 0, {}, {}
  for s = FIRST, LAST do
    local t = g.rd(g.TYPE + s)
    if g.rd(g.FLAGS + s) ~= 0 and t == typ then count = count + 1 end
    types[#types + 1] = string.format("%02X", t)
    dirs[#dirs + 1] = g.rd(g.DIR + s)
  end
  g.frame(6)
  g.shot(g.tag .. "_" .. name)
  -- 40 s of play with this weapon held
  for i = 1, 2400 do
    g.wr(0x053A, id); g.wr(0x00C5, id)
    -- harness: stay in gameplay (no game over), as in t_area.lua
    if g.rd(g.LIVES) <= 1 then g.wr(g.LIVES, 3) end
    if i % 1200 == 0 then g.wr(0x06F6, 3) end
    local d = ((i % 240) < 200) and {right = true} or {left = true}
    d.B = (i % 8) < 4
    d.A = (i % 90) < 10
    g.hold(d)
    g.frame(1)
  end
  g.hold({})
  local hs, slots_hit = {}, 0
  for s = FIRST, LAST do
    hs[#hs + 1] = string.format("%02X:%d", s, hits[name][s] or 0)
    if (hits[name][s] or 0) > 0 then slots_hit = slots_hit + 1 end
  end
  g.log(string.format("%-6s id=$%02X burst=%d types=%s dirs=%s hits[%s]", name, id, count,
        table.concat(types, ","), table.concat(dirs, ","), table.concat(hs, " ")))
  if count ~= 5 then fails[#fails + 1] = name .. " burst " .. count end
  if table.concat(dirs, ",") ~= "2,3,4,5,6" then fails[#fails + 1] = name .. " dirs" end
  if slots_hit < 3 then fails[#fails + 1] = name .. " damaged enemies from only " .. slots_hit .. " slots" end
end
g.finish(#fails == 0, table.concat(fails, "; "))
