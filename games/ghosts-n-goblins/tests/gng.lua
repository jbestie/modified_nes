-- Shared helpers for FCEUX Lua tests (loaded with dofile from each test).
local M = {}

M.root = os.getenv("GAME_DIR")
M.out = os.getenv("TEST_OUT")
local logf = io.open(os.getenv("TEST_LOG"), "w")

function M.log(...)
  local parts = {}
  local args = {...}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring(args[i]) end
  logf:write(table.concat(parts, " "), "\n")
  logf:flush()
end

function M.finish(pass, msg)
  M.log("RESULT " .. (pass and "PASS" or "FAIL") .. (msg and (" " .. msg) or ""))
  logf:close()
  emu.exit()
end

function M.hex(v, n) return string.format("%0" .. (n or 2) .. "X", v) end

local held = {}
M.pad = 1   -- controller driven by hold/press (player 2 uses controller 2)
-- Buttons persist until changed; joypad.set must be re-applied every frame.
function M.hold(buttons) held = buttons or {} end

function M.frame(n)
  for _ = 1, (n or 1) do
    joypad.set(M.pad, held)
    emu.frameadvance()
  end
end

function M.press(buttons, frames, release)
  M.hold(buttons)
  M.frame(frames or 2)
  M.hold({})
  M.frame(release or 2)
end

function M.shot(name)
  gui.savescreenshotas(M.out .. "/" .. name .. ".png")
  emu.frameadvance()
end

function M.rd(a) return memory.readbyte(a) end
function M.wr(a, v) memory.writebyte(a, v) end

M.tag = os.getenv("TEST_TAG") or "test"
function M.env(k, default) return os.getenv(k) or default end

-- Deterministic input script for the regression tests (t_screens, t_sound).
-- GNG_START = frame of the Start press (default 120); GNG_KEYS = extra
-- presses "BUTTON@frame,..." (each held 2 frames), e.g. "A@130,B@140".
function M.script_pad()
  local start = tonumber(M.env("GNG_START", "120"))
  local keys = {}
  for btn, f in string.gmatch(M.env("GNG_KEYS", ""), "(%a+)@(%d+)") do
    f = tonumber(f)
    keys[f], keys[f + 1] = btn, btn
  end
  return function(f)
    if f >= start and f <= start + 3 then return {start = true} end
    if keys[f] then return {[keys[f]] = true} end
    return {}
  end
end

-- Symbol lookup for build outputs: build/<rom>.sym is written by build.py.
local syms = nil
function M.sym(name)
  if not syms then
    syms = {}
    local f = io.open((os.getenv("TEST_ROM") or ""):gsub("%.nes$", ".sym"), "r")
    if f then
      for line in f:lines() do
        local k, v = line:match("^(%S+) = %$(%x+)$")
        if k then syms[k] = tonumber(v, 16) end
      end
      f:close()
    end
  end
  return syms[name] or error("symbol not found: " .. name)
end

-- Execution hook that only counts when `bank` is mapped at $8000 ($C7).
function M.exec_in(addr, bank, fn)
  memory.registerexec(addr, 1, function()
    if memory.readbyte(0xC7) == bank then fn() end
  end)
end

-- RAM map (see notes/addresses.md)
M.FLAGS, M.TYPE, M.DIR, M.HITS = 0x04F0, 0x0631, 0x05F1, 0x0647
M.XLO, M.XHI, M.YLO, M.YHI = 0x05AF, 0x0583, 0x0599, 0x056D
M.LIVES, M.TIMEUP = 0x0715, 0xBD

function M.arthur_x() return M.rd(M.XHI) * 256 + M.rd(M.XLO) end
function M.arthur_y() return M.rd(M.YHI) * 256 + M.rd(M.YLO) end

-- Title screen -> gameplay.  Returns the frame where Arthur becomes
-- controllable (flags == $80: active, armored, no intro bits), or nil.
function M.start_game()
  emu.speedmode("maximum")
  M.frame(120)
  M.press({start = true}, 4, 4)
  for _ = 1, 1500 do
    M.frame(1)
    if emu.framecount() > 900 and M.rd(M.FLAGS) == 0x80 then return emu.framecount() end
  end
  return nil
end

-- Count executions of a CPU address (fixed bank, or bank-checked via $C7).
function M.counter(addr, bank)
  local c = {n = 0, log = {}}
  memory.registerexec(addr, 1, function()
    if bank == nil or memory.readbyte(0xC7) == bank then
      c.n = c.n + 1
      if c.on_hit then c.on_hit(c) end
    end
  end)
  return c
end

return M
