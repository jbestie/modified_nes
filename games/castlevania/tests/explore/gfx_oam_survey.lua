-- OAM survey: snapshots the $0200 page at each OAM DMA ($4014) while a stage is playing ($18 = 2 demo / 5 game)
-- and records, per stage ($28): OAM tile bytes used (8x16 mode: bit 0 = pattern table), max sprites per scanline,
-- >8-per-line frequency, object frame ids ($031C) per slot; dumps CHR-RAM + palettes (.chr/.pal) + a screenshot per stage.
-- Run: python3 scripts/run_fceux.py games/castlevania/rom/original.nes games/castlevania/tests/explore/gfx_oam_survey.lua
--      --game-dir games/castlevania --out <dir> --tag oam_game --env MODE=game|demo [--env FRAMES=n] [--env STAGE=n (game: poke $28 at load)]
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("maximum")
local MODE = t.env("MODE", "game")
local FRAMES = tonumber(t.env("FRAMES", "8000"))
local STAGE = tonumber(t.env("STAGE", "-1"))

local frame = 0
local S = {}              -- per-stage stats
local function st(k)
  if not S[k] then
    S[k] = {use = {}, hist = {}, frames = 0, over = 0, lines_over = 0, max = 0, maxf = 0, slotf = {}, dumped = false, first = frame}
  end
  return S[k]
end
-- playing = demo (2) or game (5) state; skip the few frames after a demo starts where slot 0 still holds
-- title-screen object frames ($E6-$EE) drawn with stage CHR
local function playing()
  local s = memory.readbyte(0x18)
  return (s == 2 or s == 5) and memory.readbyte(0x31C) < 0xE6
end

memory.registerwrite(0x4014, 1, function()
  if not playing() or AND(memory.readbyte(0xFE), 0x10) == 0 then return end
  local s = st(memory.readbyte(0x28))
  s.frames = s.frames + 1
  local per = {}
  for i = 0, 63 do
    local y = memory.readbyte(0x200 + 4 * i)
    if y > 0 and y < 0xEF then    -- Y=0: entries cleared by the load code ($C185), not drawn by the game
      local tile = memory.readbyte(0x201 + 4 * i)
      s.use[tile] = (s.use[tile] or 0) + 1
      for l = y + 1, math.min(y + 16, 239) do per[l] = (per[l] or 0) + 1 end
    end
  end
  local m, over, ml = 0, 0, 0
  for l, n in pairs(per) do
    if n > m then m = n; ml = l end
    if n > 8 then over = over + 1 end
  end
  s.hist[m] = (s.hist[m] or 0) + 1
  if m > s.max then
    s.max = m; s.maxf = frame
    local d = {}
    for i = 0, 63 do
      local y = memory.readbyte(0x200 + 4 * i)
      if y > 0 and y < 0xEF and y + 1 <= ml and ml <= y + 16 then
        d[#d + 1] = string.format("%02X@%02X,%02X", memory.readbyte(0x201 + 4 * i), memory.readbyte(0x203 + 4 * i), y)
      end
    end
    s.maxdesc = string.format("line %d: %s", ml, table.concat(d, " "))
  end
  if over > 0 then s.over = s.over + 1; s.lines_over = s.lines_over + over end
end)

if STAGE >= 0 then
  memory.registerexec(0xB990, 1, function()
    if memory.readbyte(0x27) == 6 then memory.writebyte(0x28, STAGE); memory.writebyte(0x29, STAGE) end
  end)
end

local function dump(name)
  local f = io.open(t.out .. "/" .. name .. ".chr", "wb")
  for a = 0, 0x1FFF do f:write(string.char(ppu.readbyte(a))) end
  f:close()
  f = io.open(t.out .. "/" .. name .. ".pal", "wb")
  for a = 0x3F00, 0x3F1F do f:write(string.char(ppu.readbyte(a))) end
  f:close()
  t.log(string.format("DUMP %s f%d $18=%02X $28=%02X $2E=%02X $2F=%02X $46=%02X", name, frame, t.rd(0x18), t.rd(0x28), t.rd(0x2E), t.rd(0x2F), t.rd(0x46)))
  gui.savescreenshotas(t.out .. "/" .. name .. ".png")
end

local function track()
  if not playing() then return end
  local s = st(memory.readbyte(0x28))
  for k = 0, 0x1B do
    if memory.readbyte(0x300 + k) == 0 then
      local fr = memory.readbyte(0x31C + k)
      if fr ~= 0 then
        s.slotf[k] = s.slotf[k] or {}
        s.slotf[k][fr] = (s.slotf[k][fr] or 0) + 1
      end
    end
  end
end

-- deterministic bot for game mode: mostly walk right and whip, sometimes jump/crouch/climb
local seed = tonumber(t.env("SEED", "12345"))
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return math.floor(seed / 65536) % n end
local cur = {}
local function bot()
  if frame % 6 == 0 then
    cur = {}
    local r = rnd(100)
    if r < 70 then cur.right = true elseif r < 78 then cur.left = true end
    if rnd(100) < 35 then cur.B = true end
    if rnd(100) < 10 then cur.A = true end
    if rnd(100) < 8 then cur.down = true end
    if rnd(100) < 20 then cur.up = true end
  end
  t.hold(cur)
end

emu.poweron()
local pending = {}
while frame < FRAMES do
  if MODE == "game" then
    if frame == 300 then t.hold({start = true}) elseif frame == 304 then t.hold({}) end
    if frame >= 1150 then bot() end
  end
  t.frame(1); frame = frame + 1
  track()
  if playing() then
    local k = memory.readbyte(0x28)
    local s = st(k)
    if not s.dumped and frame - s.first > 120 then
      s.dumped = true
      dump(string.format("%s_st%02d", t.tag, k)); t.frame(1); frame = frame + 1
    end
  end
end

local ks = {}
for k in pairs(S) do ks[#ks + 1] = k end
table.sort(ks)
for _, k in ipairs(ks) do
  local s = S[k]
  t.log(string.format("STAGE $28=%02X sampled %d frames; max sprites/line %d (f%d); frames with >8 on a line: %d (%d%%); line-frames >8: %d",
    k, s.frames, s.max, s.maxf, s.over, s.frames > 0 and math.floor(100 * s.over / s.frames) or 0, s.lines_over))
  local hs = {}
  for m = 0, 64 do if s.hist[m] then hs[#hs + 1] = m .. ":" .. s.hist[m] end end
  t.log("  HIST maxPerLine:frames " .. table.concat(hs, " "))
  t.log("  MAX " .. (s.maxdesc or "-") .. "  (tile@X,Y)")
  local tk = {}
  for tb in pairs(s.use) do tk[#tk + 1] = tb end
  table.sort(tk)
  local parts = {}
  for _, tb in ipairs(tk) do parts[#parts + 1] = string.format("%02X", tb) end
  t.log("  TILES " .. #tk .. ": " .. table.concat(parts, " "))
  for slot = 0, 0x1B do
    if s.slotf[slot] then
      local p, fk = {}, {}
      for fr in pairs(s.slotf[slot]) do fk[#fk + 1] = fr end
      table.sort(fk)
      for _, fr in ipairs(fk) do p[#p + 1] = string.format("%02X:%d", fr, s.slotf[slot][fr]) end
      t.log(string.format("  SLOT %02X %s", slot, table.concat(p, " ")))
    end
  end
end
t.finish(true)
