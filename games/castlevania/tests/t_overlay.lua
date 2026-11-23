-- Practice overlay (tools/overlay.lua) loaded as a module on the original ROM.
-- PASS: the text lines show the RAM values; drawing adds Lua-layer pixels
-- (readability on screen is not checked); infinite mode refills health,
-- hearts and an empty timer; the warp reaches stage 4 with its HUD number; outside stage
-- play the warp refuses.
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
local ov = loadfile(t.root .. "/tools/overlay.lua")("module")
emu.speedmode("nothrottle")

local fails = {}
local function check(cond, what)
  t.log((cond and "ok   " or "FAIL ") .. what)
  if not cond then fails[#fails + 1] = what end
end
local function frames(n) for _ = 1, n do ov.tick(); t.frame(1) end end
local function wait_play(max)
  local k = 0
  while not ov.in_play() and k < max do frames(1); k = k + 1 end
  return ov.in_play()
end

emu.poweron()
frames(300)
check(not ov.warp(4), "warp refused on the title screen")
t.press({start = true}, 4, 0)
check(wait_play(1500), "stage play reached")
frames(60)

local lines = ov.lines()
t.log("overlay: " .. table.concat(lines, " | "))
check(lines[1]:find("STAGE 01") ~= nil, "line 1 shows STAGE 01")
check(lines[3]:find("HP 64/64") ~= nil and lines[3]:find("hearts 5") ~= nil, "line 3 shows full health and 5 hearts")

-- drawing: Lua-layer pixels without and with M.draw().  Drawings show up in
-- the readout after the next frame; FCEUX's own on-screen counters may
-- already be in that layer, hence the baseline.
t.hold({right = true}); frames(240); t.hold({})
t.frame(1)
local before = t.lua_pixels()
ov.draw()
t.frame(1)
local after = t.lua_pixels()
check(after > before + 100, string.format("overlay drawn (Lua-layer pixels %d -> %d)", before, after))

ov.infinite = true
t.wr(0x45, 8); t.wr(0x71, 0); t.wr(0x43, 0)
frames(10)
check(t.rd(0x45) == 0x40 and t.rd(0x71) == 99 and t.rd(0x43) == 3,
      string.format("infinite: HP %d hearts %d timer hundreds %d", t.rd(0x45), t.rd(0x71), t.rd(0x43)))
ov.infinite = false

check(ov.warp(4), "warp to stage 4 accepted")
check(wait_play(1500) and t.rd(0x28) == 4 and ov.stage_label() == 4,
      string.format("warp reached stage 4 ($28=%02X, label %d)", t.rd(0x28), ov.stage_label()))
frames(30)
t.log("overlay: " .. table.concat(ov.lines(), " | "))

t.finish(#fails == 0, #fails > 0 and (#fails .. " checks failed: " .. fails[1]) or nil)
