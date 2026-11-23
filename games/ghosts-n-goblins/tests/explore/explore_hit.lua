local g = dofile(os.getenv("GAME_DIR") .. "/tests/gng.lua")
local last = -1
memory.registerwrite(0x04F0, 1, function(a, sz, v)
  local val = memory.readbyte(0x04F0)
  if v ~= nil then val = v end
  local pc = memory.getregister("pc")
  if val ~= last and pc ~= 0x8093 and pc ~= 0x8090 then
    g.log("f" .. emu.framecount(), "W04F0", g.hex(last < 0 and 0 or last), "->", g.hex(val), "pc", g.hex(memory.getregister("pc"), 4), "bank", memory.readbyte(0xC7))
    last = val
  end
end)
memory.registerwrite(0x0715, 1, function()
  g.log("f" .. emu.framecount(), "W0715 pc", g.hex(memory.getregister("pc"), 4), "old", memory.readbyte(0x0715))
end)
emu.speedmode("maximum")
g.frame(120)
g.press({start = true}, 4, 4)
for i = 1, 30 do
  g.frame(60)
  g.shot(string.format("explore_%02d", i))
  g.log("f" .. emu.framecount(), "t=" .. i .. "s", "04F0=" .. g.hex(g.rd(0x04F0)), "0715=" .. g.rd(0x0715), "C7=" .. g.rd(0xC7))
end
g.finish(true)
