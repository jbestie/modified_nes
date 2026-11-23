-- Read watcher (FCEUX has no read hooks): exec-hooks the ROM-reading instructions listed in WATCH_ADDRS
-- (a Lua file "return {addr, ...}" made from bank_exec_cov output), computes each effective address and logs
-- reads that land in the free-space candidate windows below, during the bank_session.lua session.
-- Run: python3 scripts/run_fceux.py games/castlevania/rom/original.nes games/castlevania/tests/explore/bank_readwatch.lua \
--        --game-dir games/castlevania --out <dir> --timeout 900 --env WATCH_ADDRS=<abs path> [--env SPEED=nothrottle] [--env BY_LABEL=1]
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode(os.getenv("SPEED") or "maximum")

-- candidate windows: {bank, lo, hi}
local W = {
  {0, 0xBB01, 0xBFFF}, {1, 0xBD08, 0xBFFF}, {2, 0xBCE8, 0xBFFF}, {3, 0xBF08, 0xBFFF}, {4, 0xB408, 0xBFFF},
  {5, 0x9E47, 0xBFFF}, {6, 0xBA3B, 0xBFFF}, {7, 0xFF2A, 0xFFF9},
}
local cur_bank = 0
memory.registerwrite(0xC000, 0x4000, function(a, s, v) cur_bank = AND(v or 0, 7) end)

local function mode_of(o)
  local lo, cc = AND(o, 0x1F), AND(o, 3)
  if cc == 1 then
    if lo == 0x01 then return "izx" elseif lo == 0x11 then return "izy"
    elseif lo == 0x0D then return "abs" elseif lo == 0x1D then return "abx" elseif lo == 0x19 then return "aby" end
  end
  local m = {[0xAE]="abs",[0xBE]="aby",[0xAC]="abs",[0xBC]="abx",[0x2C]="abs",[0xCC]="abs",[0xEC]="abs",
    [0x0E]="abs",[0x1E]="abx",[0x2E]="abs",[0x3E]="abx",[0x4E]="abs",[0x5E]="abx",[0x6E]="abs",[0x7E]="abx",
    [0xCE]="abs",[0xDE]="abx",[0xEE]="abs",[0xFE]="abx",[0x6C]="ind"}
  return m[o]
end

local label = "boot"
local hits, order = {}, {}
local function hook(pc)
  local o = memory.readbyte(pc)
  local m = mode_of(o)
  if not m then return end
  local ea
  local b1 = memory.readbyte(pc + 1)
  if m == "izy" then
    ea = memory.readbyte(b1) + 256 * memory.readbyte(AND(b1 + 1, 0xFF)) + memory.getregister("y")
  elseif m == "izx" then
    local z = AND(b1 + memory.getregister("x"), 0xFF)
    ea = memory.readbyte(z) + 256 * memory.readbyte(AND(z + 1, 0xFF))
  else
    ea = b1 + 256 * memory.readbyte(pc + 2)
    if m == "abx" then ea = ea + memory.getregister("x") elseif m == "aby" then ea = ea + memory.getregister("y") end
  end
  ea = AND(ea, 0xFFFF)
  if ea < 0x8000 then return end
  local bank = ea >= 0xC000 and 7 or cur_bank
  for wi, w in ipairs(W) do
    if bank == w[1] and ea >= w[2] and ea <= w[3] then
      local codebank = pc >= 0xC000 and 7 or cur_bank
      local k = string.format("window %d:%04X  pc=%d:%04X %s", w[1], w[2], codebank, pc, m)
      if os.getenv("BY_LABEL") then k = k .. " " .. label end
      local h = hits[k]
      if not h then h = {n = 0, lo = ea, hi = ea, first = label}; hits[k] = h; order[#order + 1] = k end
      h.n = h.n + 1
      if ea < h.lo then h.lo = ea end
      if ea > h.hi then h.hi = ea end
    end
  end
end
local list = dofile(os.getenv("WATCH_ADDRS"))
for _, a in ipairs(list) do memory.registerexec(a, 1, function() hook(a) end) end
t.log("hooked", #list, "instructions")

local session = loadfile(os.getenv("GAME_DIR") .. "/tests/explore/bank_session.lua")()
local reached = session(t, function(n) t.frame(n) end, function(l) label = l end)
t.log("stages reached", table.concat(reached, " "))
for _, k in ipairs(order) do
  local h = hits[k]
  t.log(string.format("%s reads=%d ea=%04X-%04X first in %s", k, h.n, h.lo, h.hi, h.first))
end
t.log("windows with no reads: see list above (only windows with hits are printed)")
t.finish(true)
