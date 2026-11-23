-- Bank-switch, frame-budget and input survey (explore script, not a test). Session: power-on attract
-- (3590 frames), then a game from the title with PLAY_FRAMES (15000) of scripted play (gate -> stage 1, deaths, game over).
-- Logs every UNROM bank-register write (PC after store, target, value, ROM byte there), $18 transitions,
-- idle CPU cycles per frame (end of full NMI $C0B5 -> next NMI $C052), lag frames, P2 -> $F6/$F8 check.
-- Run: python3 scripts/run_fceux.py games/castlevania/rom/original.nes \
--        games/castlevania/tests/explore/bank_writes.lua --game-dir games/castlevania --out <dir> --timeout 300
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode(os.getenv("SPEED") or "maximum")   -- SPEED=nothrottle: no frame skipping

local phase = "boot"
local writes = {}          -- key "phase pc addr val" -> count
local order = {}
local cur_bank = -1
local banks_by_phase = {}  -- phase -> {bank -> count}
local bus_bad = 0
local mism24, mism27, checks = 0, 0, 0

memory.registerwrite(0x8000, 0x8000, function(addr, size, value)
  local pc = memory.getregister("pc")
  value = value or 0
  local rombyte = memory.readbyte(addr)   -- $C000+ = fixed bank, so this is the ROM byte
  if addr >= 0xC000 and rombyte ~= value then bus_bad = bus_bad + 1 end
  local k = string.format("%-8s pc=%04X addr=%04X val=%02X rom=%02X y=%02X $24=%02X $27=%02X",
                          phase, pc, addr, value, rombyte, memory.getregister("y"), t.rd(0x24), t.rd(0x27))
  if not writes[k] then writes[k] = 0; order[#order + 1] = k end
  writes[k] = writes[k] + 1
  cur_bank = AND(value, 7)
  local bp = banks_by_phase[phase] or {}
  bp[cur_bank] = (bp[cur_bank] or 0) + 1
  banks_by_phase[phase] = bp
end)

-- Frame budget
local last_end = nil
local stats = {}           -- phase -> {n, sum, min, max, nested, busy_sum, busy_max}
local function st() local s = stats[phase]; if not s then s = {n=0,sum=0,min=1e9,max=0,nested=0,bmax=0,bsum=0,bn=0,lag=0,frames=0,nonmi=0}; stats[phase]=s end; return s end
local nmi_entry, nmi_this_frame = nil, 0
memory.registerexec(0xC052, 1, function()
  nmi_this_frame = nmi_this_frame + 1
  local c = debugger.getcyclescount()
  local s = st()
  if t.rd(0x1B) ~= 0 then
    s.nested = s.nested + 1            -- previous NMI still running: no idle time
  else
    if last_end then
      local idle = c - last_end
      s.n = s.n + 1; s.sum = s.sum + idle
      if idle < s.min then s.min = idle end
      if idle > s.max then s.max = idle end
      s.lastidle = idle
    end
    nmi_entry = c
  end
end)
memory.registerexec(0xC0B5, 1, function()
  local c = debugger.getcyclescount()
  last_end = c
  if nmi_entry then
    local s = st(); local b = c - nmi_entry
    s.bsum = s.bsum + b; s.bn = s.bn + 1
    if b > s.bmax then s.bmax = b end
  end
end)

-- Input routine probe: which pads are read, where results go
local ctl_reads = {}
memory.registerwrite(0x4016, 1, function(a, s, v)
  local k = phase .. string.format(" $4016 write pc=%04X val=%02X", memory.getregister("pc"), v or 0)
  ctl_reads[k] = (ctl_reads[k] or 0) + 1
end)

local function frames(n, f)
  for i = 1, n do
    if f then f(i) end
    t.frame(1)
    local s = st()
    s.frames = s.frames + 1
    if emu.lagged() then s.lag = s.lag + 1 end
    if nmi_this_frame == 0 then s.nonmi = s.nonmi + 1 end
    nmi_this_frame = 0
    -- at the frame boundary the main loop should have bank $24 selected
    if cur_bank >= 0 and t.rd(0x1B) == 0 then
      checks = checks + 1
      if cur_bank ~= t.rd(0x24) then mism24 = mism24 + 1 end
      if cur_bank ~= t.rd(0x27) then mism27 = mism27 + 1 end
    end
  end
end

-- Session A: no input. title (0-300), demo/title cycle to frame 3600
emu.poweron()
phase = "titleA"; frames(690)
phase = "demo"; frames(2900)
-- Session B: game from title
emu.poweron(); last_end = nil
phase = "titleB"; frames(300)
t.hold({start = true}); phase = "intro"; frames(4); t.hold({}); frames(796)
local trans = {}
local last_sig = ""
local loops = 0
memory.registerexec(0xC030, 1, function() loops = loops + 1 end)
local enemy_idle = {}      -- active enemy count (slots 3-13 with type ~= 0) -> {n, sum, min}
local last_idle_seen = 0
local p2press = 0
local F = tonumber(t.env("PLAY_FRAMES", "15000"))
frames(F, function(i)
  local m = i % 120
  local b = {right = true}
  if m >= 30 and m < 33 then b.B = true end
  if m >= 70 and m < 76 then b.A = true end
  if m >= 100 and m < 103 then b.B = true end
  -- press Start on game-over / continue screens now and then
  if m == 110 and t.rd(0x18) ~= 5 then b = {start = true} end
  t.hold(b)
  phase = string.format("B18=%02X", t.rd(0x18))
  local sig = string.format("$18=%02X $28=%02X $29=%02X $2A=%02X", t.rd(0x18), t.rd(0x28), t.rd(0x29), t.rd(0x2A))
  if sig ~= last_sig then trans[#trans + 1] = string.format("f%05d %s", i, sig); last_sig = sig end
  -- controller 2 test: hold P2 Left+A and watch $F6/$F8
  if i >= 2000 and i < 2010 then joypad.set(2, {left = true, A = true}) end
  if i >= 2001 and i < 2012 and (t.rd(0xF8) ~= 0 or t.rd(0xF6) ~= 0) then p2press = p2press + 1 end
  if t.rd(0x18) == 5 then
    local n = 0
    for sl = 3, 13 do if t.rd(0x434 + sl) ~= 0 then n = n + 1 end end
    local s = stats[phase]
    if s and s.n > 0 then
      local e = enemy_idle[n] or {n = 0, sum = 0, min = 1e9, lsum = 0}
      local idle = s.lastidle or 0
      e.n = e.n + 1; e.sum = e.sum + idle; if idle < e.min then e.min = idle end
      e.lsum = e.lsum + loops
      enemy_idle[n] = e
    end
  end
  loops = 0
end)
t.log("== state transitions in session B (frame, $18 $28 $29 $2A)")
for _, l in ipairs(trans) do t.log(l) end
t.log("P2 frames with $F6/$F8 nonzero while P2 held:", p2press)
t.log("== $18=05 idle cycles by active enemy-slot count (slots 3-13 type~=0): n avg min | main-loop iterations avg x20")
for k = 0, 11 do local e = enemy_idle[k]; if e then
  t.log(string.format("enemies=%d frames=%d idle avg=%d min=%d | loop iters avg=%d (x20=%d)", k, e.n, math.floor(e.sum / e.n), e.min,
        math.floor(e.lsum / e.n), math.floor(20 * e.lsum / e.n))) end end

t.log("== bank writes (phase pc-after-store target value romByte Y $24 $27) count")
for _, k in ipairs(order) do t.log(k, writes[k]) end
t.log("bus-conflict mismatches:", bus_bad)
t.log("== banks selected per phase")
for ph, bp in pairs(banks_by_phase) do
  local p = {}
  for b = 0, 7 do if bp[b] then p[#p + 1] = b .. ":" .. bp[b] end end
  t.log(ph, table.concat(p, " "))
end
t.log(string.format("frame-boundary checks %d, bank~=$24 %d, bank~=$27 %d", checks, mism24, mism27))
t.log("== frame budget per phase: frames lagged(emu) noNMI nestedNMI | idle n min avg max | NMI busy avg max")
for ph, s in pairs(stats) do
  t.log(string.format("%-8s frames=%d lagged=%d noNMI=%d nested=%d | idle n=%d min=%d avg=%d max=%d | busy avg=%d max=%d",
    ph, s.frames, s.lag, s.nonmi, s.nested, s.n, s.n > 0 and s.min or 0, s.n > 0 and math.floor(s.sum / s.n) or 0, s.max,
    s.bn > 0 and math.floor(s.bsum / s.bn) or 0, s.bmax))
end
t.log("== $4016 writes")
for k, v in pairs(ctl_reads) do t.log(k, v) end
t.finish(true)
