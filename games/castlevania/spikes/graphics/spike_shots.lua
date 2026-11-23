-- Screenshots for the commando graphics spike (works on any Castlevania USA V1.1 image, original or imported).
-- 1. intro walk; 2. courtyard: stand, walk cycle, crouch, jump, whip; 3. every frame id in FRAMES forced on slot 0
--    (as tests/explore/gfx_frame_viewer.lua does), facing right and left; 4. warp to each stage in WARP, stand and walk.
-- Output: <tag>_<name>.png in the --out dir, plus a log with Simon's frame id per shot.
-- Run: python3 scripts/run_fceux.py <rom> games/castlevania/spikes/graphics/spike_shots.lua --game-dir games/castlevania
--      --out <dir> --tag <tag> [--env FRAMES=01,02,EF] [--env WARP=01,09]
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("nothrottle")

local force, saved, mirror = nil, nil, 0
memory.registerexec(0x8052, 1, function()
  if force and memory.readbyte(0x27) == 0 then
    saved = { memory.readbyte(0x31C), memory.readbyte(0x450) }
    memory.writebyte(0x31C, force)
    memory.writebyte(0x450, mirror)
  end
end)
memory.registerexec(0x80C1, 1, function()
  if saved and memory.readbyte(0x27) == 0 then
    memory.writebyte(0x31C, saved[1]); memory.writebyte(0x450, saved[2]); saved = nil
  end
end)

local function shot(name)
  t.log(string.format("%s: $18=%02X $28=%02X frame=%02X state=%02X X=%02X Y=%02X", name, t.rd(0x18), t.rd(0x28),
    force or t.rd(0x31C), t.rd(0x46C), t.rd(0x38C), t.rd(0x354)))
  t.shot(t.tag .. "_" .. name)
end
local function playing() return t.rd(0x18) == 5 and t.rd(0x19) == 6 end
local function wait_play() local k = 0; while not playing() and k < 2000 do t.frame(1); k = k + 1 end end

emu.poweron()
t.frame(300); t.press({start = true}, 4, 0)
local k = 0
while t.rd(0x18) ~= 4 and k < 600 do t.frame(1); k = k + 1 end
t.frame(90); shot("intro_walk")
t.frame(200); shot("intro_late")
wait_play(); t.frame(60)
shot("c_stand")
t.hold({right = true})
for i = 1, 4 do t.frame(4); shot("c_walk" .. i) end
t.hold({}); t.frame(20)
t.hold({down = true}); t.frame(10); shot("c_crouch")
t.hold({down = true, B = true}); t.frame(14); shot("c_crouch_whip"); t.hold({}); t.frame(30)
t.hold({A = true}); t.frame(14); shot("c_jump"); t.hold({}); t.frame(40)
t.hold({B = true}); t.frame(4); shot("c_whip_a"); t.frame(8); shot("c_whip_b"); t.frame(6); shot("c_whip_c")
t.hold({}); t.frame(40)
t.hold({left = true}); t.frame(12); shot("c_walk_left"); t.hold({}); t.frame(10); shot("c_stand_left")

for h in string.gmatch(t.env("FRAMES", ""), "%x+") do
  force = tonumber(h, 16)
  mirror = 0; t.frame(2); shot("fr" .. h)
  mirror = 1; t.frame(2); shot("fr" .. h .. "_L")
end
force = nil
t.frame(4)

for s in string.gmatch(t.env("WARP", ""), "%x+") do
  local n = tonumber(s, 16)
  t.wr(0x29, n); t.wr(0x18, 0x0C); t.wr(0x19, 7)
  wait_play(); t.frame(60)
  shot(string.format("st%02X_stand", n))
  t.hold({right = true}); t.frame(30); shot(string.format("st%02X_walk", n)); t.hold({})
  t.frame(10)
end
t.finish(true)
