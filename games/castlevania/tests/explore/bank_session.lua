-- Shared scripted session for the bank_* explore scripts (not runnable on its own).
-- Load with: local session = loadfile(os.getenv("GAME_DIR") .. "/tests/explore/bank_session.lua")()
-- session(t, step, setlabel) runs: power-on attract (title + demos 1-2, 3600 frames; demo 3 = stage 08 needs ~9000),
-- power-on game start,
-- 6000 frames of scripted play (stage 0 -> 1 via the gate, deaths), pause, game over + continue, then a
-- stage-clear warp into every stage 1-18 ($28 = S-1, $18 = 0C, $19 = 0) with 900 frames of play each.
-- step(n) must advance n frames (applying t's held buttons); returns the list of stages reached.
return function(t, step, setlabel)
  local function play(n)
    for i = 1, n do
      local m = i % 120
      local b = {right = true}
      if m >= 30 and m < 33 then b.B = true end
      if m >= 70 and m < 76 then b.A = true end
      if m >= 100 and m < 103 then b.B = true end
      if m >= 110 and m < 113 then b = {up = true, B = true} end
      t.hold(b)
      step(1)
    end
    t.hold({})
  end
  emu.poweron()
  setlabel("attract"); step(3600)
  emu.poweron()
  setlabel("title"); step(300)
  t.hold({start = true}); step(4); t.hold({}); step(796)
  setlabel("play"); play(6000)
  setlabel("pause"); t.hold({start = true}); step(3); t.hold({}); step(60); t.hold({start = true}); step(3); t.hold({}); step(30)
  setlabel("gameover")
  t.wr(0x2A, 1); t.wr(0x45, 0)
  for i = 1, 600 do step(1); if t.rd(0x18) == 0x0D then break end end
  step(30); t.hold({start = true}); step(4); t.hold({}); step(300)
  local reached = {}
  for s = 1, 18 do
    setlabel(string.format("warp%02d", s))
    t.wr(0x28, s - 1); t.wr(0x18, 0x0C); t.wr(0x19, 0)
    local ok = false
    for i = 1, 2000 do step(1); if t.rd(0x18) == 5 and t.rd(0x28) == s then ok = true; break end end
    reached[#reached + 1] = s .. (ok and "+" or "-")
    for k = 1, 6 do t.wr(0x5B, 0xFF); t.wr(0x45, 0x40); play(150) end   -- keep Simon alive ($5B lead, $45 health)
  end
  return reached
end
