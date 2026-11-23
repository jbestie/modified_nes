-- Camera fly-through: records the terrain map ($05A0, 2 bits per 8x8 cell) of every stage and floor.
-- Check it against the ROM decoder: tools/level_data.py ROM check <log>.  STAGES=00,01,.. limits the run.
-- Simon stands still (pinned by pokes); a hook at the streamer $F5EA fakes camera motion 1 px/frame.
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("nothrottle")
local rd, wr = t.rd, t.wr
local function playing() return rd(0x18) == 5 and rd(0x19) == 6 end
local function wait(cond, max) local k = 0; while not cond() and k < (max or 600) do t.frame(1); k = k + 1 end; return cond() end
local function rom7(a) return memory.readbyte(a) end

local fly, pinY = false, nil
memory.registerexec(0xF5EA, function()
  if not fly then return end
  local s = rd(0x2E) + 1
  local p = rd(0x2F)
  if s > 255 then s = 0; p = p + 1 end
  wr(0x2E, s); wr(0x2F, p); wr(0x3C, 1)
end)
memory.registerexec(0x934C, function()
  if pinY then wr(0x3F, pinY); wr(0x46C, 0); wr(0x5B, 0x30); wr(0x45, 0x40); wr(0x43, 3); wr(0x47, 0) end
end)

local cells = {}
local function cam() return rd(0x2E) + 256 * rd(0x2F) end
local function record(x0, x1)
  local par = rom7(0xFBD6 + rd(0x28))
  for x = x0, x1 - 1, 8 do
    local nt = (par + math.floor(x / 256)) % 2
    local lx = x % 256
    local col = math.floor(x / 8)
    local shift = (3 - (col % 4)) * 2
    for row = 0, 21 do
      local b = rd(0x05A0 + nt * 0xB0 + row * 8 + math.floor(lx / 32))
      cells[col * 32 + row] = math.floor(b / (2 ^ shift)) % 4
    end
  end
end
local function dump(tag, c0, c1)
  for row = 0, 21 do
    local s = {}
    for col = c0, c1 - 1 do s[#s + 1] = tostring(cells[col * 32 + row] or "?") end
    t.log(tag .. string.format(" ROW %02d ", row) .. table.concat(s, ""))
  end
end

emu.poweron(); t.frame(300); t.press({start = true}, 4, 0); t.frame(800); wait(playing)
local stages = {}
for s in string.gmatch(t.env("STAGES", "00,01,02,03,04,05,06,07,08,09,0A,0B,0C,0D,0E,0F,10,11,12"), "%x+") do stages[#stages + 1] = tonumber(s, 16) end
for _, n in ipairs(stages) do
  wr(0x29, n); wr(0x18, 0x0C); wr(0x19, 7); pinY = nil; fly = false
  wait(playing, 1500); t.frame(5)
  local f0 = rd(0x46)
  for _, f in ipairs({f0, 1 - f0}) do
    local rl, ll = rom7(0xFBB0 + n), rom7(0xFBC3 + n)
    local R = (f == 0) and math.floor(rl / 16) or (rl % 16)
    local L = (f == 0) and math.floor(ll / 16) or (ll % 16)
    local left = (L == 15) and 0 or (L + 1)
    -- reload the stage on floor f with the camera at the left limit
    pinY = nil; fly = false
    wr(0x46, f); wr(0x2F, left); wr(0x2E, 0); wr(0x2D, 0)
    wr(0x38C, 0x80); wr(0x40, 0x80); wr(0x41, left)
    wr(0x18, 5); wr(0x19, 0); wr(0x4A, 5); wr(0x1F, 5)
    local ok = wait(playing, 600)
    t.frame(3)
    pinY = rd(0x3F)
    cells = {}
    record(cam(), cam() + 256)
    t.log(string.format("stage %02X floor %d: reload=%s cam=%d L=%d R=%d Y=%02X", n, f, tostring(ok), cam(), left, R, pinY))
    fly = true
    local k = 0
    while cam() < R * 256 and k < 4000 do
      t.frame(1); k = k + 1
      if k % 4 == 0 then record(cam(), cam() + 160) end
    end
    fly = false
    t.frame(30)
    record(cam(), cam() + 256)
    t.log(string.format("stage %02X floor %d: end cam=%d frames=%d", n, f, cam(), k))
    t.shot(string.format("fly_%02X_%d", n, f))
    dump(string.format("S%02X F%d", n, f), math.floor(left * 256 / 8), math.floor((cam() + 256) / 8))
    pinY = nil
  end
  -- back to a sane state on the start floor before the next warp
  wr(0x46, f0); wr(0x2F, 0); wr(0x2E, 0); wr(0x18, 5); wr(0x19, 0); wait(playing, 600)
end
t.finish(true)
