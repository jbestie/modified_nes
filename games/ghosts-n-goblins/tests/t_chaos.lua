-- Chat chaos mode (tools/chaos/chaos.lua) driven through its command file.
-- PASS: every command has its effect in RAM (weapon + per-player copy + HUD
-- palette, lives, clock, armor bit inside Arthur's task, colour bits in the
-- PPUMASK shadow and their removal after 20 s, remix shot/armor modes with a
-- real rainbow burst); unknown commands and remix-only commands on another
-- ROM are refused; a line is applied only once it is complete.
local g = dofile(os.getenv("GAME_DIR") .. "/tests/gng.lua")
local function bit(v, m) return math.floor(v / m) % 2 == 1 end
local CMDS = g.out .. "/" .. g.tag .. "_commands.txt"
io.open(CMDS, "w"):close()
-- chaos.lua reads CHAOS_CMDS; FCEUX's Lua has no setenv, so set the module's
-- path before its first poll.  The module hooks $E014 (one callback per
-- address in FCEUX), so Arthur's flags come from chaos.arthur_flags.
local chaos = loadfile(g.root .. "/tools/chaos/chaos.lua")("module")
chaos.path = CMDS

local fails = {}
local function check(cond, what)
  g.log((cond and "ok   " or "FAIL ") .. what)
  if not cond then fails[#fails + 1] = what end
end
local function frames(n) for _ = 1, n do chaos.tick(); g.frame(1) end end
local function send(text, raw)
  local f = io.open(CMDS, "a")
  f:write(text .. (raw and "" or "\n"))
  f:close()
  frames(20)          -- polled every 15 frames
end

if not g.start_game() then g.finish(false, "gameplay not reached") end
frames(30)
chaos.poll()          -- start reading at the current end of the file
local remix = chaos.is_remix()
g.log("ROM", remix and "remix" or "other", "in play", tostring(chaos.in_play()))

send("viewer1 !torch")
check(g.rd(0x053A) == 0x44 and g.rd(0x00C5) == 0x44 and g.rd(0x0553) == 2, "!torch: held $44, $C5 $44, HUD palette 2")
send("viewer2 !Axe now please")
check(g.rd(0x053A) == 0x36 and g.rd(0x0553) == 1, "!Axe (case, trailing text): held $36, palette 1")
local lives = g.rd(g.LIVES)
send("viewer3 !life")
check(g.rd(g.LIVES) == math.min(lives + 1, 9), string.format("!life: lives %d -> %d", lives, g.rd(g.LIVES)))
local m = g.rd(0x06F6)
send("!time")
check(g.rd(0x06F6) == math.min(m + 1, 9), string.format("!time (no user): minutes %d -> %d", m, g.rd(0x06F6)))
send("viewer4 !hurry")
check(g.rd(0x06F6) == 0 and g.rd(0x06FA) <= 2, string.format("!hurry: clock %d:%d%d", g.rd(0x06F6), g.rd(0x06FA), g.rd(0x06FC)))
g.wr(0x06F6, 3)       -- harness: don't let the hurried clock run out
send("viewer5 !naked")
check(bit(chaos.arthur_flags, 0x20), "!naked: armor bit set inside Arthur's task")
g.shot(g.tag .. "_naked")
send("viewer6 !armor")
check(not bit(chaos.arthur_flags, 0x20), "!armor: armor bit cleared")
send("viewer7 !blood")
check(bit(g.rd(0x39), 0x20), string.format("!blood: red emphasis on ($39=$%02X)", g.rd(0x39)))
g.shot(g.tag .. "_blood")
frames(20 * 60)
check(not bit(g.rd(0x39), 0x20) and AND(g.rd(0x39), 0x1E) == 0x1E,
      string.format("tint removed after 20 s, rendering bits intact ($39=$%02X)", g.rd(0x39)))
send("viewer8 !bogus")
check(chaos.history[1]:find("unknown") ~= nil, "unknown command refused: " .. chaos.history[1])
send("viewer9 !lance", true)                 -- no newline yet
check(g.rd(0x053A) == 0x36, "incomplete line not applied yet")
send("")                                     -- newline completes it
check(g.rd(0x053A) == 0x40, "line applied once complete")

if remix then
  send("viewer10 !rainbow")
  check(g.rd(0x071A) == 1, "!rainbow: shot mode 1")
  for _ = 1, 150 do
    local busy = false
    for s = 0x0F, 0x13 do if g.rd(g.FLAGS + s) ~= 0 then busy = true end end
    if not busy then break end
    frames(1)
  end
  g.press({B = true}, 4, 0)
  local t = {}
  for s = 0x0F, 0x13 do t[#t + 1] = string.format("%02X", g.rd(g.TYPE + s)) end
  check(table.concat(t, ",") == "23,24,25,26,27", "rainbow burst after the command: " .. table.concat(t, ","))
  send("viewer11 !spread")
  check(g.rd(0x071A) == 0, "!spread: shot mode 0")
  send("viewer12 !tough")
  check(g.rd(0x071B) == 1, "!tough: armor mode 1")
  send("viewer13 !mortal")
  check(g.rd(0x071B) == 2, "!mortal: armor mode 2")
  send("viewer14 !god")
  check(g.rd(0x071B) == 0, "!god: armor mode 0")
else
  local before = g.rd(0x071A)
  send("viewer10 !rainbow")
  check(g.rd(0x071A) == before and chaos.history[1]:find("remix ROM only") ~= nil,
        "remix-only command refused: " .. chaos.history[1])
end
g.log("overlay history:", table.concat(chaos.history, " | "))
g.finish(#fails == 0, #fails > 0 and (#fails .. " checks failed: " .. fails[1]) or nil)
