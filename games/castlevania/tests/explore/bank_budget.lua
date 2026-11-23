-- CPU frame budget: idle cycles per frame = cycles from the end of the full NMI ($C0B5, STA $1B=0) to the next
-- NMI entry ($C052), i.e. time spent in the RESET main loop $C030-$C03C. Per session phase (bank_session.lua
-- label / $18): frames, emu.lagged() frames, nested NMIs ($1B~=0 at entry), idle min/p1/p5/median/avg/max.
-- Run: python3 scripts/run_fceux.py games/castlevania/rom/original.nes games/castlevania/tests/explore/bank_budget.lua \
--        --game-dir games/castlevania --out <dir> --timeout 900 [--env SPEED=nothrottle]
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode(os.getenv("SPEED") or "maximum")

local label, phase = "boot", "boot"
local P, porder = {}, {}
local function ph()
  local s = P[phase]
  if not s then s = {idle = {}, frames = 0, lag = 0, nested = 0, nonmi = 0, bmax = 0}; P[phase] = s; porder[#porder + 1] = phase end
  return s
end
local last_end, entry, nmis = nil, nil, 0
memory.registerexec(0xC052, 1, function()
  nmis = nmis + 1
  local c = debugger.getcyclescount()
  local s = ph()
  if t.rd(0x1B) ~= 0 then s.nested = s.nested + 1
  else
    if last_end then s.idle[#s.idle + 1] = c - last_end end
    entry = c
  end
end)
memory.registerexec(0xC0B5, 1, function()
  local c = debugger.getcyclescount()
  last_end = c
  if entry then local s = ph(); if c - entry > s.bmax then s.bmax = c - entry end end
end)

local function step(n)
  for _ = 1, n do
    t.frame(1)
    local s = ph()
    s.frames = s.frames + 1
    if emu.lagged() then s.lag = s.lag + 1 end
    if nmis == 0 then s.nonmi = s.nonmi + 1 end
    nmis = 0
    local st = t.rd(0x18)
    phase = label .. (st == 5 and "" or string.format("/18=%02X", st))
  end
end
local session = loadfile(os.getenv("GAME_DIR") .. "/tests/explore/bank_session.lua")()
local reached = session(t, step, function(l) label = l; last_end = nil; entry = nil end)
t.log("stages reached", table.concat(reached, " "))
t.log("phase              frames lagged noNMI nested | idle(cycles) n min p1 p5 median avg max | NMI busy max")
local all = {}
for _, k in ipairs(porder) do
  local s = P[k]
  local v = s.idle
  table.sort(v)
  local n = #v
  local function pct(p) if n == 0 then return 0 end return v[math.max(1, math.floor(p * n / 100 + 0.5))] end
  local sum = 0
  for _, x in ipairs(v) do sum = sum + x end
  if string.find(k, "^warp") and not string.find(k, "/") or k == "play" then for _, x in ipairs(v) do all[#all + 1] = x end end
  t.log(string.format("%-18s %6d %6d %5d %6d | n=%d %d %d %d %d %d %d | %d", k, s.frames, s.lag, s.nonmi, s.nested,
    n, v[1] or 0, pct(1), pct(5), pct(50), n > 0 and math.floor(sum / n) or 0, v[n] or 0, s.bmax))
end
table.sort(all)
local n = #all
t.log(string.format("ALL stage play ($18=05, play + warp01-18): frames=%d min=%d p0.1=%d p1=%d p5=%d median=%d max=%d; <2000: %d, <5000: %d",
  n, all[1], all[math.max(1, math.floor(n / 1000))], all[math.floor(n / 100)], all[math.floor(n / 20)], all[math.floor(n / 2)], all[n],
  (function() local c = 0; for _, x in ipairs(all) do if x < 2000 then c = c + 1 end end; return c end)(),
  (function() local c = 0; for _, x in ipairs(all) do if x < 5000 then c = c + 1 end end; return c end)()))
t.finish(true)
