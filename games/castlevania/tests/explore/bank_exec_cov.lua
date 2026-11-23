-- Where code actually executes in each switchable bank ($8000-$BFFF exec hook + current bank).
-- Session: bank_session.lua (attract, game start + play, deaths, game over, stage-clear warp into
-- every stage 1-18). Also logs bank-switch callers (C1D6/C1D8 entries) and CHR-loader ($FD23) calls.
-- Run: python3 scripts/run_fceux.py games/castlevania/rom/original.nes \
--   games/castlevania/tests/explore/bank_exec_cov.lua --game-dir games/castlevania --out <dir> --timeout 900
--   writes <out>/<tag>_cov.txt (executed instruction ranges per bank)
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode(os.getenv("SPEED") or "maximum")   -- SPEED=nothrottle: no frame skipping

local cur_bank = 0
local exec = {}            -- bank -> {addr -> true}
for b = 0, 7 do exec[b] = {} end
memory.registerwrite(0xC000, 0x4000, function(addr, size, value) cur_bank = AND(value or 0, 7) end)
memory.registerexec(0x8000, 0x4000, function(addr)
  addr = addr or memory.getregister("pc")
  exec[cur_bank][addr] = true
end)
local fixed = {}

-- who switches banks with which Y (caller = JSR return address - 2 from the stack)
local callers = {}
local function caller()
  local s = memory.getregister("s")
  local lo, hi = memory.readbyte(0x101 + s), memory.readbyte(0x102 + s)
  return hi * 256 + lo - 2
end
local chr = {}
local chr_order = {}
-- one exec hook covers the fixed bank (only one callback per address is allowed)
memory.registerexec(0xC000, 0x4000, function(addr)
  addr = addr or memory.getregister("pc")
  fixed[addr] = true
  if addr == 0xC1D6 or addr == 0xC1D8 then
    local k = string.format("%04X entry, caller %04X, Y=%02X", addr, caller(), memory.getregister("y"))
    callers[k] = (callers[k] or 0) + 1
  elseif addr == 0xFD23 then
    local k = string.format("FD23 list A=%02X caller %04X $28=%02X $29=%02X $18=%02X", memory.getregister("a"), caller(),
                            t.rd(0x28), t.rd(0x29), t.rd(0x18))
    if not chr[k] then chr[k] = 0; chr_order[#chr_order + 1] = k end
    chr[k] = chr[k] + 1
  end
end)

local session = loadfile(os.getenv("GAME_DIR") .. "/tests/explore/bank_session.lua")()
local reached = session(t, function(n) t.frame(n) end, function(l) end)
local stages_seen = {"stages reached: " .. table.concat(reached, " ")}

-- merge executed instruction starts into ranges (gap <= 3 bytes joins)
local f = io.open(t.out .. "/" .. t.tag .. "_cov.txt", "w")
local function ranges(set, lo, hi)
  local out, rs, last, n = {}, nil, nil, 0
  for a = lo, hi do
    if set[a] then
      n = n + 1
      if rs and a - last <= 3 then last = a else
        if rs then out[#out + 1] = string.format("%04X-%04X", rs, last) end
        rs, last = a, a
      end
    end
  end
  if rs then out[#out + 1] = string.format("%04X-%04X", rs, last) end
  return out, n
end
for b = 0, 6 do
  local r, n = ranges(exec[b], 0x8000, 0xBFFF)
  t.log(string.format("bank %d: %d instruction addresses, %d ranges, lowest %s highest %s", b, n, #r, r[1] or "-", r[#r] or "-"))
  f:write(string.format("bank %d (%d instr addrs)\n  %s\n", b, n, table.concat(r, " ")))
end
local r, n = ranges(fixed, 0xC000, 0xFFFF)
t.log(string.format("bank 7: %d instruction addresses, highest range %s", n, r[#r] or "-"))
f:write(string.format("bank 7 (%d instr addrs)\n  %s\n", n, table.concat(r, " ")))
f:close()
t.log("== bank-switch entries")
local keys = {}
for k in pairs(callers) do keys[#keys + 1] = k end
table.sort(keys)
for _, k in ipairs(keys) do t.log(k, callers[k]) end
t.log("== CHR loader calls")
for _, k in ipairs(chr_order) do t.log(k, chr[k]) end
t.log("== stage sweep")
for _, l in ipairs(stages_seen) do t.log(l) end
t.finish(true)
