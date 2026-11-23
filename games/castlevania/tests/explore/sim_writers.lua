-- Who writes Simon's RAM: write hooks on ADDRS (hex list), logs each distinct (address, bank, store instruction, JSR chain)
-- with a count, over a scripted run in stage 1 (walk, jump, duck, whip, Up+B dagger, hits, stairs, death). Chain = JSR sites, innermost first.
-- Run: python3 scripts/run_fceux.py games/castlevania/rom/original.nes games/castlevania/tests/explore/sim_writers.lua --game-dir games/castlevania --out <dir> --tag writers [--env ADDRS=038C,0354,003F]
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("maximum")
local rd, wr = t.rd, t.wr
local bank = 0
memory.registerwrite(0x8000, 0x8000, function(a, s, v) bank = v % 8 end)
local STOP = {[0xC0A4] = true, [0xC0AC] = true, [0xC097] = true, [0xC071] = true}   -- NMI's calls: end of chain
local ABS = {[0x8D]=1,[0x9D]=1,[0x99]=1,[0x8E]=1,[0x8C]=1,[0xEE]=1,[0xCE]=1,[0x0E]=1,[0x4E]=1,[0x2E]=1,[0x6E]=1,[0xFE]=1,[0xDE]=1,[0x1E]=1,[0x5E]=1,[0x3E]=1,[0x7E]=1}
local function chain()
  local s, out, i = memory.getregister("s"), {}, memory.getregister("s") + 1
  while i < 0x1FF and #out < 6 do
    local ret = rd(0x100 + i) + 256 * rd(0x101 + i) + 1
    if ret >= 0x8003 and memory.readbyte(ret - 3) == 0x20 then
      if STOP[ret - 3] then break end
      out[#out + 1] = string.format("%04X", ret - 3); i = i + 2
    else i = i + 1 end
  end
  return table.concat(out, "<")
end
local W = {}
local list = t.env("ADDRS", "038C,0354,003F,0040,0041,046C,0434,0450,0488,0568,0044,0045,005B,0047,0070,0071,015B,0064,002A")
for s in string.gmatch(list, "%x+") do
  memory.registerwrite(tonumber(s, 16), 1, function(addr, size, v)
    local pc = memory.getregister("pc")
    local ip = pc - 3
    local opnd = memory.readbyte(pc - 2) + 256 * memory.readbyte(pc - 1)
    if not (ABS[memory.readbyte(pc - 3)] and opnd <= addr and addr - opnd < 0x100) then ip = pc - 2 end
    local k = string.format("$%04X b%d @%04X %-6s %s", addr, ip >= 0xC000 and 7 or bank, ip,
      ip == pc - 3 and (opnd == addr and "abs" or "abs,i") or "zp", chain())
    W[k] = (W[k] or 0) + 1
  end)
end
local function playing() return rd(0x18) == 5 and rd(0x19) == 6 end
local function wait(cond, max) local k = 0; while not cond() and k < (max or 600) do t.frame(1); k = k + 1 end end
local function act(b, n) t.hold(b); t.frame(n) end
emu.poweron(); t.frame(300); t.press({start = true}, 4, 0); t.frame(800); wait(playing)
act({right = true}, 1); wait(function() return rd(0x28) == 1 end, 1500); act({}, 1); wait(playing, 300)
act({right = true}, 30); act({left = true}, 20); act({A = true}, 4); act({}, 50); act({down = true}, 10)
act({down = true, B = true}, 3); act({}, 30); act({B = true}, 3); act({}, 30); act({A = true, B = true}, 3); act({}, 50)
wr(0x15B, 8); wr(0x71, 10); act({up = true, B = true}, 3); act({}, 40)
for i = 1, 600 do act({}, 1) end                                                -- zombies hit Simon
for i = 1, 700 do wr(0x5B, 0x20); act({right = true, up = (i % 40 < 20)}, 1) end  -- stairs, falls
wr(0x5B, 0); wr(0x45, 0); wait(function() return rd(0x18) == 6 end, 600); wait(playing, 600)
local ks = {}
for k in pairs(W) do ks[#ks + 1] = k end
table.sort(ks)
for _, k in ipairs(ks) do t.log(k, "n=" .. W[k]) end
t.finish(true)
