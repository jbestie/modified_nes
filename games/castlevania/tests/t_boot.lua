-- Boot smoke test for the original ROM: no RAM map needed yet.
-- Two runs from power-on with the same timing: one without input (the title
-- times out into the attract demo), one with Start on the title.
-- PASS: RESET runs once per power-on; frames take the time the header's
-- region asks for (NTSC 29780.5 / PAL 33247.5 CPU cycles); the title screen
-- is drawn; with Start the screen at frame 1500 differs from the demo's (a
-- game started, not the demo); NMI runs every frame in the stage.
-- Screenshots: <tag>_title.png, <tag>_demo.png, <tag>_intro.png, <tag>_stage1.png.
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("nothrottle")

local fails = {}
local function check(cond, what)
  t.log((cond and "ok   " or "FAIL ") .. what)
  if not cond then fails[#fails + 1] = what end
end

local reset_vec, nmi_vec = t.word(0xFFFC), t.word(0xFFFA)
local pal = t.header()[13] % 4 == 1           -- NES 2.0 byte 12: 0 NTSC, 1 PAL
local resets, nmis = 0, 0
memory.registerexec(reset_vec, 1, function() resets = resets + 1 end)
memory.registerexec(nmi_vec, 1, function() nmis = nmis + 1 end)

-- Run 1: no input.  Frame 300 = title screen, frame 1500 = attract demo.
emu.poweron()
t.frame(60)
local c0 = debugger.getcyclescount()
t.frame(240)
local cycles = debugger.getcyclescount() - c0
check(resets == 1, string.format("RESET $%04X ran once after power-on (%d)", reset_vec, resets))
-- CPU cycles per frame: NTSC 341 x 262 / 3 = 29780.67, one dot shorter on
-- odd frames, 29780.5 on average; PAL 341 x 312 / 3.2 = 33247.5
local per_frame = pal and 33247.5 or 29780.5
check(math.abs(cycles - 240 * per_frame) <= 240,
      string.format("%s timing: %d cycles in 240 frames", pal and "PAL" or "NTSC", cycles))
local title = t.screen_sample()
t.shot(t.tag .. "_title")
check(t.distinct(title) >= 6, string.format("title screen drawn (%d colours sampled)", t.distinct(title)))
t.frame(1200)
local demo = t.screen_sample()
t.shot(t.tag .. "_demo")

-- Run 2: Start on the title.  Frame 700 = walk to the castle gate.
emu.poweron()
t.frame(300)
check(resets == 2, string.format("RESET ran again after the second power-on (%d)", resets))
t.press({start = true}, 4, 0)
t.frame(396)
t.shot(t.tag .. "_intro")
t.frame(400)
local n0 = nmis
t.frame(400)                                   -- frame ~1500
local stage_nmis = nmis - n0
local game = t.screen_sample()
t.shot(t.tag .. "_stage1")
check(t.diff_pct(demo, game) >= 25, string.format("Start began a game, not the demo (%d%% differs from the demo)",
                                                  t.diff_pct(demo, game)))
check(t.diff_pct(title, game) >= 25, string.format("the title is gone (%d%% differs)", t.diff_pct(title, game)))
check(stage_nmis == 400, string.format("NMI $%04X every frame in the stage (%d in 400 frames)", nmi_vec, stage_nmis))

t.finish(#fails == 0, #fails > 0 and (#fails .. " checks failed: " .. fails[1]) or nil)
