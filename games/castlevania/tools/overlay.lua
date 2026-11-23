-- Practice overlay for Castlevania (USA, Rev 1) in FCEUX 2.6.
--
-- Run it from FCEUX (File > Load Lua Script) with games/castlevania's ROM.
-- It shows Simon's state, the collision boxes the game uses, and a lag-frame
-- counter.  Keys (change them in KEYS below):
--   H  hitboxes on/off
--   I  infinite health, hearts and time on/off (pits still kill)
--   N  warp to the next stage, V  warp to the previous stage
-- Only the practice keys write RAM, and they write it the way the game does
-- (warp: the game's own "start block" code; see notes/addresses.md, section 5).
--
-- Loaded by the tests as a module: loadfile(path)("module") returns the
-- table M without starting the main loop.

local M = {}
local AS_MODULE = (... == "module")
local KEYS = {boxes = "H", infinite = "I", next = "N", prev = "V"}

local function rd(a) return memory.readbyte(a) end
local function wr(a, v) memory.writebyte(a, v) end

local STATES = {[0] = "stand", "jump", "attack", "crouch", "stairs", "knockback",
                "to stairs", "fall", "dead", "land"}
local SUBWEAPONS = {[0] = "-", [0x08] = "dagger", [0x09] = "cross", [0x0B] = "holy water",
                    [0x0D] = "axe", [0x0F] = "stopwatch"}
local WHIPS = {[0] = "leather", "short chain", "long chain"}
local LAST_STAGE = 0x12

M.show_boxes = true
M.infinite = false
M.lag = 0
M.keyboard = not AS_MODULE   -- the tests drive M directly

-- Stage gameplay ($18 = 5, substate 6)
function M.in_play() return rd(0x18) == 5 and rd(0x19) == 6 end

-- The number the HUD shows: 19 x loop + stage, 0 (courtyard) shown as 1
function M.stage_label()
  local n = 19 * rd(0x2B) + rd(0x28)
  if n == 0 then n = 1 end
  return n
end

function M.lines()
  local state = rd(0x046C)
  return {
    string.format("STAGE %02d ($28=%02X)  game %02X/%02X  lag %d", M.stage_label(), rd(0x28),
                  rd(0x18), rd(0x19), M.lag),
    string.format("X %d Y %d %s %s", rd(0x40) + 256 * rd(0x41), rd(0x3F),
                  STATES[state] or string.format("%02X", state), rd(0x0450) == 0 and ">" or "<"),
    string.format("HP %d/64  hearts %d  whip %s", rd(0x45), rd(0x71), WHIPS[rd(0x70)] or "?"),
    string.format("sub %s x%d  inv %d%s", SUBWEAPONS[rd(0x015B)] or string.format("%02X", rd(0x015B)),
                  rd(0x64) + 1, rd(0x5B), M.infinite and "  INFINITE" or ""),
  }
end

local function box(cx, cy, hw, hh, color)
  gui.box(cx - hw, cy - hh, cx + hw, cy + hh, "clear", color)
end

-- The boxes the collision code compares (notes/addresses.md, section 9): an
-- enemy touches Simon when his box and the enemy's box overlap.
function M.draw_boxes()
  if rd(0x0300) == 0 then
    box(rd(0x038C), rd(0x0354), 4, rd(0x5F), "green")                  -- Simon ($E6BA)
  end
  if rd(0x5C) == 0 then
    box(rd(0x68), rd(0x69), rd(0x73), rd(0x74), "yellow")              -- whip, attack frame $11
  end
  for x = 3, 0x16 do
    local t = rd(0x0434 + x)
    if t ~= 0 and rd(0x0300 + x) == 0 then
      local cx, cy = rd(0x038C + x), rd(0x0354 + x)
      if x >= 0x14 then                                                 -- Simon's projectiles ($E5DF)
        local k = rd(0x0584 + x)
        box(cx, cy, rd(0xE5DF + 2 * k), rd(0xE5E0 + 2 * k), "cyan")
      elseif t <= 0x35 then                                             -- per-type box ($E46A)
        local hh = rd(0xE46B + 2 * t)
        box(cx, cy, rd(0xE46A + 2 * t), hh, t >= 0x28 and "white" or "red")
        gui.text(cx - 6, cy - hh - 9, string.format("%02X", t))
      end
    end
  end
end

function M.draw()
  if M.show_boxes and M.in_play() then M.draw_boxes() end
  -- just under the game's HUD (FCEUX draws its own frame counter bottom left)
  for i, l in ipairs(M.lines()) do gui.text(2, 40 + 9 * i, l) end
end

-- Stage warp (stages 0-$12, wrapping).  Only from stage gameplay; the game
-- loads the stage's tiles, timer and music itself (~300-600 frames).
function M.warp(n)
  if not M.in_play() then return false end
  if n < 0 then n = LAST_STAGE elseif n > LAST_STAGE then n = 0 end
  wr(0x29, n); wr(0x18, 0x0C); wr(0x19, 7)
  return true
end

function M.apply_infinite()
  if not M.infinite or not M.in_play() then return end
  wr(0x45, 0x40)                       -- health (the display catches up)
  wr(0x71, 99)                         -- hearts
  if rd(0x43) == 0 then wr(0x43, 3) end  -- timer hundreds (BCD)
end

local prev = {}
local function pressed(name, keys)
  local k = KEYS[name]
  local now = keys[k] and true or false
  local edge = now and not prev[k]
  prev[k] = now
  return edge
end

-- Per-frame work between frames: keys, practice writes, lag count.
function M.tick()
  if emu.lagged() then M.lag = M.lag + 1 end
  -- input.get() crashes FCEUX 2.6.5 when called in the frame of an
  -- emu.poweron() (frame counter 0)
  if not M.keyboard or emu.framecount() == 0 then return M.apply_infinite() end
  local keys = input.get()
  if pressed("boxes", keys) then M.show_boxes = not M.show_boxes end
  if pressed("infinite", keys) then M.infinite = not M.infinite end
  if pressed("next", keys) then M.warp(rd(0x28) + 1) end
  if pressed("prev", keys) then M.warp(rd(0x28) - 1) end
  M.apply_infinite()
end

if AS_MODULE then return M end

gui.register(M.draw)
while true do
  M.tick()
  emu.frameadvance()
end
