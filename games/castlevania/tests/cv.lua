-- Shared helpers for the Castlevania FCEUX Lua tests (loaded with dofile
-- from each test).  scripts/run_fceux.py exports GAME_DIR, TEST_OUT,
-- TEST_ROM, TEST_LOG and TEST_TAG.
local M = {}

M.root = os.getenv("GAME_DIR")
M.out = os.getenv("TEST_OUT")
M.tag = os.getenv("TEST_TAG") or "test"
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

function M.env(k, default) return os.getenv(k) or default end
function M.hex(v, n) return string.format("%0" .. (n or 2) .. "X", v) end
function M.rd(a) return memory.readbyte(a) end
function M.wr(a, v) memory.writebyte(a, v) end
function M.word(a) return M.rd(a) + 256 * M.rd(a + 1) end

-- The ROM file's 16-byte header as a table of byte values (1-based)
-- Address of a symbol of the commando build (build/castlevania-commando.sym), or nil.
-- Code in a switchable bank: check $27 (the last bank selected) in exec hooks.
local syms = nil
function M.sym(name)
  if not syms then
    syms = {}
    local f = io.open(M.root .. "/build/castlevania-commando.sym")
    if f then
      for line in f:lines() do
        local k, v = line:match("^(%S+) = %$(%x+)$")
        if k then syms[k] = tonumber(v, 16) end
      end
      f:close()
    end
  end
  return syms[name]
end

function M.header()
  local f = io.open(os.getenv("TEST_ROM"), "rb")
  local h = {f:read(16):byte(1, 16)}
  f:close()
  return h
end

local held = {}
M.pad = 1
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

-- FCEUX writes the screenshot at the end of the next frame, so advance one
-- (otherwise a following emu.poweron() would be captured instead).
function M.shot(name)
  gui.savescreenshotas(M.out .. "/" .. name .. ".png")
  M.frame(1)
end

-- Screen sample: one colour per 8x8 cell (32 x 28 points), for coarse checks.
function M.screen_sample()
  local s = {}
  for y = 8, 232, 8 do
    for x = 0, 255, 8 do
      local r, g, b = emu.getscreenpixel(x, y, true)
      s[#s + 1] = r * 65536 + g * 256 + b
    end
  end
  return s
end

function M.distinct(sample)
  local seen, n = {}, 0
  for _, v in ipairs(sample) do
    if not seen[v] then seen[v] = true; n = n + 1 end
  end
  return n
end

-- Pixels where the screen with Lua drawings differs from the emulator's own
-- picture (screenshots and screen_sample() never include Lua drawings)
function M.lua_pixels()
  local n = 0
  for y = 0, 239 do
    for x = 0, 255 do
      local r1, g1, b1 = emu.getscreenpixel(x, y, false)
      local r2, g2, b2 = emu.getscreenpixel(x, y, true)
      if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 then n = n + 1 end
    end
  end
  return n
end

-- Percentage of sample points that differ between two samples
function M.diff_pct(a, b)
  local d = 0
  for i = 1, #a do if a[i] ~= b[i] then d = d + 1 end end
  return math.floor(100 * d / #a)
end

-- RAM map (see notes/addresses.md): nothing traced yet.

return M
