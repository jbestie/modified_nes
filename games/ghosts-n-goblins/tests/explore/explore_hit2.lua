local g = dofile(os.getenv("GAME_DIR") .. "/tests/gng.lua")
local function callers(depth)
  local s = memory.getregister("s")
  local out = {}
  for i = 0, depth - 1 do
    local lo = memory.readbyte(0x101 + s + i * 2)
    local hi = memory.readbyte(0x102 + s + i * 2)
    out[#out + 1] = g.hex(hi * 256 + lo - 2, 4)
  end
  return table.concat(out, "<")
end
local last = 0
local hitframe = nil
memory.registerwrite(0x04F0, 1, function()
  local pc = memory.getregister("pc")
  local val = memory.readbyte(0x04F0)
  if pc == 0x8093 or pc == 0x8090 then return end
  if val ~= last and emu.framecount() > 1200 then
    g.log("f" .. emu.framecount(), "W04F0", g.hex(last), "->", g.hex(val), "pc", g.hex(pc, 4), "A", g.hex(memory.getregister("a")), "X", memory.getregister("x"), "call", callers(3), "bank", memory.readbyte(0xC7))
  end
  if val % 2 == 1 and last % 2 == 0 and emu.framecount() > 1200 and not hitframe then hitframe = emu.framecount() end
  last = val
end)
emu.speedmode("maximum")
g.frame(120)
g.press({start = true}, 4, 4)
g.frame(1100)
local snaps = {}
while emu.framecount() < 1720 do
  local snap = memory.readbyterange(0, 0x800)
  snaps[emu.framecount()] = snap
  g.frame(1)
end
-- RAM diff: before first hit vs 10 frames after; ignore stack, OAM pages
local h = hitframe
g.log("hitframe", h)
local a, b, c = snaps[h - 2], snaps[h + 10], snaps[h + 40]
local line = {}
for i = 0, 0x7FF do
  if not (i >= 0x100 and i < 0x400) then
    local x, y, z = a:byte(i + 1), b:byte(i + 1), c:byte(i + 1)
    if x ~= y then
      -- count how often this byte changed over the 300 frames before the hit (stability)
      local ch = 0
      for f = h - 80, h - 3 do
        if snaps[f] and snaps[f+1] and snaps[f]:byte(i+1) ~= snaps[f+1]:byte(i+1) then ch = ch + 1 end
      end
      if ch == 0 then line[#line + 1] = g.hex(i, 4) .. ":" .. g.hex(x) .. ">" .. g.hex(y) .. ">" .. g.hex(z) end
    end
  end
end
g.log("stable-before & changed-at-hit:", table.concat(line, " "))
g.finish(true)
