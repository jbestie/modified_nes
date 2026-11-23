-- Chat chaos mode for Ghosts'n Goblins (USA) in FCEUX 2.6.
--
-- Run it from FCEUX (File > Load Lua Script) with any of: the original ROM,
-- build/invincible.nes, build/ghosts-n-goblins-spread.nes or
-- build/ghosts-n-goblins-remix.nes.  It never patches the ROM; it only does
-- what a pickup or the game itself does (RAM writes), between frames.
--
-- Commands arrive as lines appended to a text file, one per line:
--     <user> !<command>
-- (tools/chaos/chat_bridge.py writes them from Twitch chat or the keyboard).
-- Default file: commands.txt next to this script; set CHAOS_CMDS to change it.
--
-- Commands (see COMMANDS below): weapons, extra life, more/less time, armor
-- on/off, colour curses, and on the remix ROM the shot/armor modes.
-- Unknown commands are shown as ignored.  Cooldowns and votes are the
-- bridge's job; this script applies whatever reaches the file.
--
-- Loaded by the tests as a module: loadfile(path)("module") returns the
-- table M without starting the main loop.

local M = {}
local AS_MODULE = (... == "module")

-- ---- engine RAM (notes/addresses.md) ----
local FLAGS, LIVES, PLAYER = 0x04F0, 0x0715, 0xBA
local HELD, P_WEAPON, HUD_ATTR = 0x053A, 0x00C5, 0x0553
local T_MIN, T_TENS, T_SECS = 0x06F6, 0x06FA, 0x06FC
local PPUMASK_SHADOW = 0x39
local SHOT, ARMOR = 0x071A, 0x071B              -- remix ROM only

local function rd(a) return memory.readbyte(a) end
local function wr(a, v) memory.writebyte(a, v) end

-- The remix ROM's HitPending stub starts with LDY #0 ($A0); the original has
-- JSR ($20), the invincible builds JMP ($4C).
function M.is_remix() return rd(0xE014) == 0xA0 end
-- Arthur is in play (his task polls $E014; see the hook below)
local last_poll_frame = -1000
function M.in_play() return emu.framecount() - last_poll_frame < 10 end

-- Changes to Arthur's own flags must happen inside his task: the renderer
-- swaps the slot 0/3 draw fields around each pass ($8089), so a write at an
-- arbitrary moment can hit an enemy.  $E014 runs in his task with X = 0.
-- (FCEUX keeps one exec callback per address: a script that loads this
-- module must not hook $E014 itself; it can read M.arthur_flags instead.)
local pending_flags = nil      -- {set = mask, clear = mask}
M.arthur_flags = 0
memory.registerexec(0xE014, 1, function()
  last_poll_frame = emu.framecount()
  M.arthur_flags = rd(FLAGS)
  if pending_flags then
    local f = rd(FLAGS)
    f = AND(f, 0xFF - pending_flags.clear)
    f = OR(f, pending_flags.set)
    wr(FLAGS, f)
    pending_flags = nil
  end
end)

-- ---- timed colour effects (PPUMASK shadow: bit 0 greyscale, 5-7 emphasis) ----
local TINT_BITS = 0xE1
local tint = {bits = 0, until_frame = 0, name = nil}
local function tint_tick()
  local v = rd(PPUMASK_SHADOW)
  if tint.bits ~= 0 and emu.framecount() < tint.until_frame then
    wr(PPUMASK_SHADOW, OR(AND(v, 0xFF - TINT_BITS), tint.bits))
  elseif tint.bits ~= 0 then
    wr(PPUMASK_SHADOW, AND(v, 0xFF - TINT_BITS))
    tint.bits, tint.name = 0, nil
  end
end
local function start_tint(bits, seconds, name)
  tint.bits, tint.until_frame, tint.name = bits, emu.framecount() + seconds * 60, name
end

local function set_weapon(id, attr)
  wr(HELD, id)
  wr(HUD_ATTR, attr)
  wr(P_WEAPON + rd(PLAYER), id)       -- what a pickup writes (bank 4 $BA63)
end

local function add_time(minutes)
  local m = rd(T_MIN) + minutes
  if m > 9 then m = 9 end
  wr(T_MIN, m)
end

-- name -> {help, needs_remix, needs_play, fn() -> message or nil}
local COMMANDS = {
  lance  = {"weapon: lance",  false, true, function() set_weapon(0x40, 0) end},
  dagger = {"weapon: dagger", false, true, function() set_weapon(0x42, 0) end},
  torch  = {"weapon: torch",  false, true, function() set_weapon(0x44, 2) end},
  axe    = {"weapon: axe",    false, true, function() set_weapon(0x36, 1) end},
  cross  = {"weapon: cross",  false, true, function() set_weapon(0x46, 0) end},
  life   = {"+1 life (max 9)", false, true, function()
             local a = LIVES + rd(PLAYER)
             if rd(a) < 9 then wr(a, rd(a) + 1) end
           end},
  time   = {"+1 minute on the clock", false, true, function() add_time(1) end},
  hurry  = {"clock set to 0:20", false, true, function()
             wr(T_MIN, 0); wr(T_TENS, 2); wr(T_SECS, 0)
           end},
  armor  = {"armor back on", false, true, function() pending_flags = {set = 0, clear = 0x20} end},
  naked  = {"armor off (boxers)", false, true, function() pending_flags = {set = 0x20, clear = 0} end},
  blood  = {"20 s red moon",  false, false, function() start_tint(0x20, 20, "blood") end},
  toxic  = {"20 s green fog", false, false, function() start_tint(0x40, 20, "toxic") end},
  grey   = {"20 s greyscale", false, false, function() start_tint(0x01, 20, "grey") end},
  -- remix ROM: live mode changes.  NORMAL shot is title-only (it changes the
  -- object-slot partition), so only spread <-> rainbow switch in play.
  spread  = {"5-way spread", true, false, function()
              if rd(SHOT) > 1 then return "only from RAINBOW" end
              wr(SHOT, 0)
            end},
  rainbow = {"rainbow burst", true, false, function()
              if rd(SHOT) > 1 then return "only from 5-WAY SPREAD" end
              wr(SHOT, 1)
            end},
  god     = {"armor: invincible", true, false, function() wr(ARMOR, 0) end},
  tough   = {"armor: 4 hits each", true, false, function() wr(ARMOR, 1) end},
  mortal  = {"armor: normal", true, false, function() wr(ARMOR, 2) end},
}
M.COMMANDS = COMMANDS

-- ---- command log for the overlay ----
local history = {}
local function note(text)
  table.insert(history, 1, text)
  while #history > 5 do table.remove(history) end
end
M.history = history

-- Apply one command line ("user !cmd" or "!cmd").  Returns true if applied.
function M.apply(line)
  local user, cmd = line:match("^%s*(%S+)%s+!(%w+)")
  if not user then
    cmd = line:match("^%s*!(%w+)")
    user = "?"
  end
  if not cmd then return false end
  cmd = cmd:lower()
  local c = COMMANDS[cmd]
  if not c then note(user .. ": !" .. cmd .. " (unknown)") return false end
  if c[2] and not M.is_remix() then note(user .. ": !" .. cmd .. " (remix ROM only)") return false end
  if c[3] and not M.in_play() then note(user .. ": !" .. cmd .. " (not in play)") return false end
  local err = c[4]()
  if err then note(user .. ": !" .. cmd .. " (" .. err .. ")") return false end
  note(user .. ": " .. c[1])
  return true
end

-- ---- command file polling ----
local ok_dir, script_dir = pcall(function() return debug.getinfo(1, "S").source:match("^@(.*[/\\])") end)
if not ok_dir or not script_dir then script_dir = "" end
M.path = os.getenv("CHAOS_CMDS") or (script_dir .. "commands.txt")
local offset = nil
function M.poll()
  local f = io.open(M.path, "r")
  if not f then return 0 end
  local size = f:seek("end")
  if offset == nil or size < offset then offset = size end   -- start at the end; file truncated
  local n = 0
  if size > offset then
    f:seek("set", offset)
    local data = f:read(size - offset)
    local last_nl = data:match(".*()\n")
    if last_nl then                                          -- only complete lines
      for line in data:sub(1, last_nl):gmatch("([^\n]*)\n") do
        if M.apply(line) then n = n + 1 end
      end
      offset = offset + last_nl
    end
  end
  f:close()
  return n
end
function M.reset_offset() offset = nil end

function M.overlay()
  local y = 8
  if tint.name then
    gui.text(4, y, string.format("%s %ds", tint.name, math.ceil((tint.until_frame - emu.framecount()) / 60)))
    y = y + 9
  end
  for i = #history, 1, -1 do
    gui.text(4, 230 - i * 9, history[i])
  end
end

-- per-frame work; poll the file every 15 frames
function M.tick()
  if emu.framecount() % 15 == 0 then M.poll() end
  tint_tick()
end

if AS_MODULE then return M end

note("chaos mode: " .. M.path)
while true do
  M.tick()
  M.overlay()
  emu.frameadvance()
end
