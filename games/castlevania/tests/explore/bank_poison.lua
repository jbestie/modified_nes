-- Free-space "poison" test: runs the fixed session of bank_session.lua (attract, game start, play, deaths,
-- game over + continue, stage-clear warp into every stage 1-18 with play) and writes a per-frame
-- trace (RAM hash every frame, screen-sample hash every 2 frames, CHR-RAM + nametable hash every 30 frames)
-- to <out>/<tag>_trace.txt (use SPEED=nothrottle for parallel runs).  Run it on the original and on a copy with a candidate region overwritten, then
-- diff the traces (any difference = the region is used).  Run:
--   python3 scripts/run_fceux.py <rom> games/castlevania/tests/explore/bank_poison.lua --game-dir games/castlevania --out <dir> --tag <name> --timeout 600
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode(os.getenv("SPEED") or "maximum")   -- SPEED=nothrottle: no frame skipping

local tr = io.open(t.out .. "/" .. t.tag .. "_trace.txt", "w")
local fno = 0
local M = 2147483629
local function hash_ram()
  local h = 7
  for a = 0, 0x7FF do h = (h * 31 + memory.readbyte(a)) % M end
  return h
end
local function hash_screen()
  local h = 7
  for y = 8, 232, 8 do
    for x = 0, 255, 8 do
      local r, g, b = emu.getscreenpixel(x, y, true)
      h = (h * 31 + r * 65536 + g * 256 + b) % M
    end
  end
  return h
end
local function hash_ppu()
  local h = 7
  for a = 0, 0x27FF do h = (h * 31 + ppu.readbyte(a)) % M end
  return h
end
local label = "boot"
local function step(n)
  for _ = 1, (n or 1) do
    t.frame(1)
    fno = fno + 1
    local line = string.format("%d %s r=%d", fno, label, hash_ram())
    if fno % 2 == 0 then line = line .. " s=" .. hash_screen() end
    if fno % 30 == 0 then line = line .. " p=" .. hash_ppu() end
    tr:write(line, "\n")
  end
end
local session = loadfile(os.getenv("GAME_DIR") .. "/tests/explore/bank_session.lua")()
local reached = session(t, step, function(l) label = l end)
tr:close()
t.log("frames", fno, "stages reached", table.concat(reached, " "))
t.finish(true)
