-- Boss fights with each commando weapon: warp to a boss stage (3, 6, 9, 12, 15, 18), reload the area at the page
-- before the boss lock, walk right until the boss is in slot 7, then for each weapon mode a bot (invincible, health
-- kept full) aims at the boss and fires: forward when it is level, straight up when it is overhead, else walks
-- towards it; rifle/S/F pressed every 6 frames, M and L held, FC charged 34 frames and released. Dracula's head
-- (type 04) is aimed at first: his first form only takes head hits.
-- Logs per run "RUN stage S mode M frames F hits N first F0 deaths D endhp H", then "hp <frame> <HP>" changes and
-- "hit <frame> <damage /bin/bashD> <target type> <slot>" for every bullet hit ( calls, whip excluded).
-- Kill times for other damage tables: run it on the measurement ROM of boss_replay.py and replay the logs there.
-- ENDING=<frames> (with STAGES=18 MODES=rifle): after Dracula, walk to the crystal, play the ending and credits, and
-- in the second quest check the commando's moves: logs "ending f<n> $18=.. $19=.. $28=.. quest $2B=.." state
-- changes, "second quest <move>: frames ..." and "ENDING PASS/FAIL" (stand 01, walk 02-04, jump 05 or a
-- somersault frame, fire 08, prone F7 or 05).
-- Run: python3 scripts/run_fceux.py <rom> games/castlevania/tests/explore/boss_fights.lua --game-dir games/castlevania
--        --out <dir> --tag b3 --env STAGES=3 [--env MODES=rifle,M,S,L,F,FC --env MAXF=7200 --env ENDING=7000]
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("nothrottle")
local rd, wr = t.rd, t.wr
local function playing() return rd(0x18) == 5 and rd(0x19) == 6 end
local function wait(cond, max) local k = 0; while not cond() and k < (max or 600) do t.frame(1); k = k + 1 end; return cond() end
local function inv() wr(0x5B, 0x30); wr(0x45, 0x40) end
local MAXF = tonumber(os.getenv("MAXF") or "4800")
local function list(s) local r = {} for x in s:gmatch("[^,]+") do r[#r + 1] = x end return r end
local STAGES, MODES = list(os.getenv("STAGES") or "3"), list(os.getenv("MODES") or "rifle,M,S,L,F,FC")
local LOCK = {[3] = 0x02, [6] = 0x10, [9] = 0x05, [12] = 0x03, [15] = 0x10, [18] = 0x10}
local BOSS = {[3] = {[0x19] = 1}, [6] = {[0x1B] = 1}, [9] = {[0x1A] = 1}, [12] = {[0x1C] = 1}, [15] = {[0x18] = 1}, [18] = {[0x1D] = 1, [0x04] = 1}}
local WEAPON = {rifle = 0, M = 8, S = 9, L = 0x0B, F = 0x0D, FC = 0x0D}
local cur_set, fnum, hits = nil, 0, nil
memory.registerexec(0xE562, function()
  if not hits or rd(0x0E) == 0xFF then return end
  local x = memory.getregister("x")
  local ty = rd(0x434 + x)
  hits[#hits + 1] = string.format("hit %d %d %02X %02X", fnum, rd(0x0D), ty, x)
end)
emu.poweron(); t.frame(300); t.press({start = true}, 4, 0); t.frame(800); wait(playing)
for _, sts in ipairs(STAGES) do
  local st = tonumber(sts)
  wr(0x29, st); wr(0x18, 0x0C); wr(0x19, 7); t.frame(2); wait(playing, 1500)
  local lk = LOCK[st]
  local fl, pg = math.floor(lk / 16), lk % 16
  local tp = pg > 0 and pg - 1 or 0
  wr(0x46, fl); wr(0x2F, tp); wr(0x2E, 0); wr(0x2D, 0)
  wr(0x38C, 0x30); wr(0x40, 0x30); wr(0x41, tp); wr(0x450, 0)
  wr(0x18, 5); wr(0x19, 0); wr(0x4A, 5); wr(0x1F, 5)
  wait(playing, 600)
  local k = 0
  while k < 2500 do
    inv(); t.hold({right = (k % 200) < 170, A = (k % 50 == 10)}); t.frame(1); k = k + 1
    if rd(0x48) == 1 and BOSS[st][rd(0x434 + 7)] then break end
  end
  t.hold({}); inv(); t.frame(1)
  local bs = savestate.create(); savestate.save(bs)
  for _, mode in ipairs(MODES) do
    savestate.load(bs)
    hits = {}
    local hplog, lasthp, zero, deaths, first = {}, -1, 0, 0, nil
    for f = 1, MAXF do
      fnum = f
      inv(); wr(0x15B, WEAPON[mode]); wr(0x70, 0)
      -- target: nearest boss-type slot
      local sx, sy = rd(0x38C), rd(0x354) - 8
      local best, tx, ty = 9999, nil, nil
      for sl = 4, 0x0D do
        local ty0 = rd(0x434 + sl)
        if BOSS[st][ty0] and rd(0x46C + sl) < 0x80 and (rd(0x300 + sl) == 0 or ty0 == 4) then
          local d = math.abs(rd(0x38C + sl) - sx) + math.abs(rd(0x354 + sl) - sy)
          if ty0 == 4 then d = d - 1000 end   -- Dracula's head first (form 1 only takes head hits)
          if d < best then best, tx, ty = d, rd(0x38C + sl), rd(0x354 + sl) end
        end
      end
      local h = {}
      if tx then
        local dx, dy = tx - sx, ty - sy
        local face = dx < 0 and "left" or "right"
        local facing_left = rd(0x450) == 1
        if math.abs(dy) <= 14 then
          if (dx < 0) ~= facing_left then h[face] = true end
        elseif dy < 0 and math.abs(dx) <= 10 then
          h.up = true
        else
          h[face] = true
        end
      end
      local state = rd(0x46C)
      if state == 4 or state == 5 then h = {down = true} end
      if mode == "M" or mode == "L" then h.B = true
      elseif mode == "FC" then h.B = (f % 36) < 34
      else h.B = (f % 6 == 0) end
      t.hold(h); t.frame(1)
      if rd(0x46C) == 8 then deaths = deaths + 1 end
      local hp = rd(0x1A9)
      if hp ~= lasthp then hplog[#hplog + 1] = string.format("hp %d %d", f, hp); lasthp = hp end
      if #hits > 0 and not first then first = f end
      if hp == 0 and first then zero = zero + 1 else zero = 0 end
      if zero >= 240 or rd(0x18) ~= 5 then break end
    end
    t.hold({})
    if os.getenv("ENDING") and st == 18 then
      local last, verdict = "", "FAIL (the second quest never started)"
      for f = 1, tonumber(os.getenv("ENDING")) do
        if rd(0x18) == 5 and rd(0x2B) == 0 then
          local tx                             -- walk to the crystal (an item, type $2F), jumping now and then
          for sl = 4, 0x13 do if rd(0x434 + sl) == 0x2F then tx = rd(0x38C + sl) end end
          local h = {A = (f % 90 == 45)}
          if tx then h[tx < rd(0x38C) and "left" or "right"] = true end
          inv(); t.hold(h)
        else
          t.hold({start = (f % 600 == 300) and rd(0x18) ~= 5})
        end
        t.frame(1)
        local sname = string.format("$18=%02X $19=%02X $28=%02X quest $2B=%02X", rd(0x18), rd(0x19), rd(0x28), rd(0x2B))
        if sname ~= last then t.log(string.format("ending f%d %s", f, sname)); last = sname end
        if rd(0x2B) == 1 and rd(0x18) == 5 and rd(0x19) == 6 then
          t.hold({}); for _ = 1, 150 do t.frame(1) end          -- the respawn blink runs out
          local q = savestate.create(); savestate.save(q)
          local want = {idle = {[1] = 1}, right = {[2] = 1, [3] = 1, [4] = 1}, jump = {[5] = 1, [0xF9] = 1, [0xFA] = 1, [0xFB] = 1, [0xFC] = 1},
                        fire = {[8] = 1}, down = {[0xF7] = 1, [5] = 1}}
          local ok = true
          for _, ex in ipairs({{"idle", {}}, {"right", {right = true}}, {"jump", {A = true}}, {"fire", {B = true}}, {"down", {down = true}}}) do
            savestate.load(q)
            local seen, hit = {}, false
            for i = 1, 90 do t.hold(i < 30 and ex[2] or {}); t.frame(1); local fr = rd(0x31C); seen[#seen + 1] = fr; if want[ex[1]][fr] then hit = true end end
            if not hit then ok = false end
            local u, ks = {}, {}
            for _, v in ipairs(seen) do if not u[v] then u[v] = true; ks[#ks + 1] = string.format("%02X", v) end end
            t.log(string.format("second quest %s: frames %s%s", ex[1], table.concat(ks, " "), hit and "" or "  <- missing"))
          end
          t.hold({}); t.shot(t.tag .. "_second_quest"); t.frame(1)
          verdict = ok and "PASS" or "FAIL (a move doesn't draw its frame)"
          break
        end
      end
      t.log("ENDING " .. verdict)
    end
    t.log(string.format("RUN stage %d mode %s frames %d hits %d first %s deaths %d endhp %d $18=%02X", st, mode, fnum, #hits, tostring(first), deaths, rd(0x1A9), rd(0x18)))
    for _, l in ipairs(hplog) do t.log(l) end
    for _, l in ipairs(hits) do t.log(l) end
    hits = nil
  end
end
t.finish(true)
