-- Exec coverage of the gameplay frame, labelled by which top-level call of the gameplay handler ($CED0, bank 7)
-- is running ("934C" = Simon's update in bank 6). Optional STAGES="01,07,0C" warps there first (warp: $29=N, $18=$0C, $19=7).
-- Run: python3 scripts/run_fceux.py games/castlevania/rom/original.nes games/castlevania/tests/explore/sim_coverage.lua --game-dir games/castlevania --out <dir> --tag cov --timeout 400 [--env STAGES=01,07] ; writes <out>/<tag>_cov.txt "seg bank pc count x0 xn y0 yn"
local t = dofile(os.getenv("GAME_DIR") .. "/tests/cv.lua")
emu.speedmode("maximum")
local bank = 0
memory.registerwrite(0x8000, 0x8000, function(a, s, v) bank = v % 8 end)
local SEG = {[0xCEE7]="A2E8",[0xCEEA]="CF53",[0xCEED]="A825",[0xCEF0]="FA6A",[0xCEF3]="CF28",[0xCEFA]="934C",[0xCEFD]="F5EA",
  [0xCF08]="AAE2",[0xCF0B]="post",[0xCF14]="E8F0",[0xCF1F]="F376",[0xCF22]="A4AA",[0xCF25]="A63A",[0xC0A7]="nmi2",[0xC052]="nmi",[0xCED0]="CED0"}
local seg, cov, fz, fn, yz, yn = "?", {}, {}, {}, {}, {}
local function hook()
  local pc = memory.getregister("pc")
  local s = SEG[pc]
  if s then seg = s end
  local k = seg .. " " .. (pc >= 0xC000 and 7 or bank) .. " " .. pc
  cov[k] = (cov[k] or 0) + 1
  local x, y = memory.getregister("x"), memory.getregister("y")
  if x == 0 then fz[k] = true else fn[k] = true end
  if y == 0 then yz[k] = true else yn[k] = true end
end
local function playing() return t.rd(0x18) == 5 and t.rd(0x19) == 6 end
local function wait_play() local k = 0; while not playing() and k < 1500 do t.frame(1); k = k + 1 end end
emu.poweron(); t.frame(300); t.press({start = true}, 4, 0); t.frame(800); wait_play()
local stages = {}
for s in string.gmatch(t.env("STAGES", "00"), "%x+") do stages[#stages + 1] = tonumber(s, 16) end
local frames = tonumber(t.env("FRAMES", "900"))
for _, n in ipairs(stages) do
  t.wr(0x2A, 5); t.wr(0x29, n); t.wr(0x18, 0x0C); t.wr(0x19, 7); wait_play()
  memory.registerexec(0x8000, 0x8000, hook)
  for i = 1, frames do
    t.wr(0x45, 0x40); t.wr(0x43, 0x03); t.wr(0x2A, 5)          -- keep Simon alive (health, timer, lives)
    local ph = i % 240
    local b = {right = ph < 150, left = ph >= 180, A = (i % 97) < 3, B = (i % 53) < 3, up = (i % 300) < 4}
    if ph >= 150 and ph < 180 then b.down = true end
    t.hold(b); t.frame(1)
  end
  memory.registerexec(0x8000, 0x8000, nil)
  t.hold({}); t.log(string.format("stage %02X done, 28=%02X 18=%02X 19=%02X", n, t.rd(0x28), t.rd(0x18), t.rd(0x19)))
end
local f = io.open(t.out .. "/" .. t.tag .. "_cov.txt", "w")
for k, n in pairs(cov) do f:write(k, " ", n, " ", fz[k] and 1 or 0, " ", fn[k] and 1 or 0, " ", yz[k] and 1 or 0, " ", yn[k] and 1 or 0, "\n") end
f:close()
t.finish(true)
