# Test report

Builds under test, all made from `rom/original.nes` (CRC32 `87ED54AA`, PRG `B4E4879E`):
- `build/ghosts-n-goblins-spread.nes` (CRC32 `F5A34725`, 68 bytes changed): the main hack
- `build/invincible.nes` (CRC32 `6C9EA864`, 19 bytes changed): intermediate
- `build/ghosts-n-goblins-remix.nes` (CRC32 `4AEB08B4`, 256 KiB): the separate remix ROM, see [Remix ROM](#remix-rom)
- `tools/chaos/` (Lua + Python, no ROM change): see [Chat chaos mode](#chat-chaos-mode)

## Environment and method

- Ubuntu, Python 3.14, **FCEUX 2.6.5** (Qt/SDL) driven by Lua scripts through `scripts/run_fceux.py`.
- MesenCE and cc65 are not installed. Mesen's debugger was replaced by FCEUX Lua execution/write hooks and a custom disassembler; ca65 was replaced by `scripts/asm6502.py`.
- Results come from **the game's own code paths**: execution counters on routine addresses such as the damage routine `$E171`, damage applied `$F5D0`, contact `$F5E8`, pit death `$E1BA`, boss deaths `$F7A5`/`$F70F` and scheduler round `$C395`, plus RAM audits of the object table.
- Screenshots are evidence only, except the pixel-exact regression test.
- Run everything with `make test`, which takes about 3 minutes. The summary goes to `tests/out/summary.txt`; logs and screenshots go to `tests/out/` (not committed).

**Last full run: 59/59 automated checks passed** (clean rebuild, `make clean && make test`): 26 for the main hack, 30 for the remix ROM, 3 for the chaos mode.

### Harness interventions (disclosed)

- **Stage warps** (`t_area.lua`) use the game's own stage select: `$A7=$0F` unlocks it and `$AC=area` is set at `$D058`, then the bot presses Start and the lock is restored.
- **Long area runs:** to keep a 3-minute run going, the harness resets the stage timer every 60 s and tops up lives when they reach 1. Deaths are still counted.
- **Weapon test:** forces the held weapon by writing `$053A`/`$C5`, which is what a pickup writes.
- **Bot timing:** Arthur's state code runs every 3rd frame, so the bots hold B for 4 frames. A human press is longer; the original game behaves the same.
- **5-minute session and weapon test** (`t_play.lua`, `t_weapons.lua`): like the area runs, lives are topped up at 1 and the timer is reset, so the whole run is gameplay. Before this, the bots reached game over and kept pressing A/B on the title. That was harmless on the main hack (the attract demo started), but on the remix A/B are menu keys that restart the idle timer.
- **Remix regressions:** for the NORMAL/NORMAL comparison with the original, `t_screens.lua`/`t_sound.lua` write the two menu bytes at frame 30 (`GNG_MODES=2,2`), because pressing A/B plays the menu sound (see Remix limitations). One screen run presses Start at frame 220 instead of 120 so the title with the menu is captured; the original gets the same inputs.
- **Ladder hit** (`t_ladder.lua`, `GNG_LADDER_HIT=1`): Arthur walks to the ladder in the invincible mode, then the armor byte is switched to 4 HITS EACH and one hit is forced (bit 0 set inside his task) as he climbs.

## Results

| # | Test (script) | Result | Evidence |
|---|---|---|---|
| 1 | Build, preimage checks, BPS round-trip (`build.py`) | PASS | Every patched byte matched its `.expect` preimage. Diff = assembled bytes only. Header untouched. Both `.bps` files re-create the build output; the NES 2.0-header patch was also applied to the real No-Intro dump on disk (PRG identical). |
| 2 | Pixel-exact screens vs original (`t_screens.lua`) | PASS | 76 frames (title, intro, gameplay start, timer death, PLAYER READY, map, respawn): 0 differ for both builds. **Negative control:** junk written to `$CA76` → 20 frames differ, so the test detects screen-data damage. |
| 3 | Sound vs original (`t_sound.lua`) | PASS | Per-frame APU state (5 channels: volume/period/duty) identical for 1900 frames; 2286 channel-frames with sound playing (music, effects, death jingle). |
| 4 | Control: original ROM takes damage (`t_invincible.lua`, vanilla) | PASS | 4 contacts → damage routine 4×, armor lost, lives 3→1 in 40 s, then game over. Proves the probes detect damage. |
| 5 | Invincibility, `invincible.nes` | PASS | 40 s standing among zombies: **220 contacts, damage routine 0×, armor kept (0 of 803 polls without armor), lives 3→3**. Then 20 s walking and jumping: 1077 px travelled, jump height 50 px, still no damage. Forced timeout: **died 56 frames later, lives 3→2**. |
| 6 | Invincibility, final ROM | PASS | Same numbers as #5 (234 contacts in phase 2, damage 0, timeout still lethal). |
| 6b | Ladder among enemies (`t_ladder.lua`) | PASS | Stage-1 hill ladder at world X 920: climbed 80 px (Y 184 → 104) and stepped off onto the upper level. 175 enemy contacts during the run, damage 0. |
| 7 | Spread geometry (`t_spread.lua`) | PASS | Right burst: 5 objects in `$0F–$13`, dirs 2,3,4,5,6; after 10 frames dx/dy = (31,−31) (40,−16) (44,0) (40,16) (31,31). Left burst: dirs 10..14, dx/dy exactly mirrored (±1 px sub-pixel). Six repeated bursts: 5/5 each. No weapon object ever outside `$0F–$13`. |
| 8 | All five weapons (`t_weapons.lua`) | PASS | Lance `$23`, dagger `$24`, torch `$25`, axe `$26`, cross `$27`: each burst = 5 objects of the right type and direction. 40 s of play each, damage events by slot `$0F/$10/$11/$12/$13`: lance 6/4/8/3/3, dagger 4/2/7/1/0, torch 4/5/5/2/1, axe 4/7/8/2/2, cross 1/2/6/3/0. |
| 9 | 2-player mode (`t_2p.lua`) | PASS | Player 2 (controller 2): 20 presses → 20 bursts, all exactly 5 projectiles (counted at spawn time). 56 contacts, damage 0. |
| 10 | 5-minute stage-1 session, constant fire (`t_play.lua`) | PASS | Damage events by slot `$0F`:20 `$10`:23 `$11`:69 `$12`:21 `$13`:6. Object-table audit every frame: 0 non-weapons in weapon slots, 0 stray weapons, weapon cap 5 never exceeded. Enemy damage 0. 5 deaths, all pits (7 harness interventions). |
| 11 | 14-area sweep, aiming bot, 3 min each (`t_area.lua`) | PASS (14/14) | No enemy damage in any area. Scheduler never paused > 80 frames (no hangs). Details below. |

### Area sweep details

| Area (stage) | Notable result |
|---|---|
| 0 (1) | 101 zombie hits, 0 deaths |
| 1 (1) | 11 deaths, **all pit/water** (`$E1BA`) at world X ≈ 1960–2040. The invincibility-only ROM dies at the same pit (3× in the same time: the bot reaches it less often when enemies survive longer). |
| 2 (1, boss) | **Stage-1 boss (type `$05`) killed** with 10 hits from slots `$0F–$13`. Game advanced to area 3 (stage 2) at 35 s, stage 2 loaded and played normally for 5 more minutes (separate 6-min run). |
| 3–5 (2) | enemies of types `$06`, `$07`, `$08`, `$14` hit; 0 deaths |
| 6 (2, boss) | **both type-`$05` bosses killed** (20 hits, 2 death routines); the key dropped. The bot does not pick up the key, so the stage 2→3 transition was not exercised. |
| 7–8 (3) | 101 zombie hits, types `$0A`, `$0B`, `$2A`, …; 0 deaths |
| 9 (4) | 11 pit deaths (same result on the invincibility-only ROM: terrain + bot) |
| 10 (4) | bot stuck on terrain; no events |
| 11–12 (5–6) | types `$04`, `$06`, `$32` hit; 0 deaths |
| 13 (final) | **Final boss (type `$1F`) killed** (29 hits, `$F70F` death routine ran), then the game restarted at stage 1: the original first-loop "trap" behavior |

Enemy-projectile contacts (slots `$14–$15`, damage 0 in every case): area 2: 10, area 11: 11, area 12: 1, area 13: 5.

### Performance and sprite limits (5-min session, same inputs on both ROMs)

| Metric | Invincible only (3 weapon slots) | Final (5-way) |
|---|---|---|
| Scheduler rounds / frames (logic rate) | 36.5 % | 36.5 % (no measurable slowdown) |
| Frames with > 8 sprites on a scanline | 39.0 % | 32.6 % |
| Max sprites on one scanline | 24 | 24 |
| Peak active enemies | 8 | 8 |
| Enemy spawn refusals (no free slot) | 35 | 155 |

> **Note:** The scanline-overflow figure is a relative indicator (it scans OAM page `$0200`). Stage 1 already exceeds 8 sprites per line constantly (rows of zombies, HUD sprites), and the game's OAM rotation turns that into flicker. The figure depends heavily on which enemies are alive: an earlier run of the same session measured 37.5 % vs 38.4 %, this one 39.0 % vs 32.6 %. Read it as "no large change", not as an exact difference. The remix ROM in its default modes gives the same numbers as the main hack (every game counter identical; 32.7 % overflow).

## Remix ROM

`build/ghosts-n-goblins-remix.nes`, tests in `tests/t_remix_menu.lua`, `tests/t_remix.lua` and the shared tests with remix options.

| # | Test | Result | Evidence |
|---|---|---|---|
| R1 | Build: 256 KiB expansion, preimages, BPS | PASS | Banks 0–7 identical to the input, only header byte 4 changed besides the assembled bytes. Both remix patches round-trip; the NES 2.0-header patch applied to the No-Intro dump on disk gives CRC32 `3F8569F2` and the same PRG. The patch has 653 literal bytes (new code + header byte); the relocated fixed bank is encoded as copies from the input. |
| R2 | Screens, default modes vs main hack | PASS | 76 frames, 0 differ (outside the menu text) |
| R3 | Screens, NORMAL/NORMAL vs original | PASS | 80 frames: 0 differ outside the menu text, 4 title frames differ only inside it (menu drawn) |
| R4 | Sound, default vs main hack; NORMAL/NORMAL vs original | PASS | APU traces identical, 1900 frames each |
| R5 | Title menu (`t_remix_menu.lua`) | PASS | 49 checks: lines drawn on the first title frame (nametable rows 23–24 read back tile by tile), A/B cycle and wrap (3 values each), EnemyEnd `$0F/$0F/$11`, idle timer restarted, Select still moves the 1P/2P cursor, settings kept after a console reset, defaults after power-on, lines redrawn after the attract demo |
| R6 | RAINBOW | PASS | Right burst types `23,24,25,26,27` dirs 2–6; left dirs 10–14; six repeated bursts of 5; held weapon unchanged |
| R7 | Select weapon cycling | PASS | `$42 → $44 → $36 → $46 → $40 → $42` with `$C5` and HUD palette (0, 2, 1, 0, 0); each burst used the selected weapon; kept after a death |
| R8 | NORMAL/NORMAL in play | PASS | EnemyEnd `$11`; 55 shots, all single, weapons only in `$11–$13`, at most 2 lances; Select ignored; enemies damaged Arthur (4×, lives 3 → 1) |
| R9 | 4 HITS EACH, stage-1 crowd, 60 s | PASS | 12 absorbed hits, 4 damage events, each after exactly 3 absorbs; first life lost after 8 hits; every absorb gave 90 frames of invulnerability, Arthur visible at the end; timer expiry still kills |
| R10 | Absorbed hit on a ladder | PASS | Hit at Y 166 absorbed, Arthur kept climbing to Y 104 and stepped off; invulnerability ended after 96 frames, visible |
| R11 | Default modes: invincibility, ladder, spread geometry, five weapons, 2-player, 5-minute session | PASS | Same results as tests 5–10 for the main hack (the 5-minute session and weapon test give identical counters) |
| R12 | 14-area sweep with bank audit | PASS (14/14) | No enemy damage, no hangs; every mapper write selected bank 0–6 or 8 (e.g. area 2: banks 0–6 and 8, 0 others); stage-1 boss killed and stage 2 reached (area 2) |

## Chat chaos mode

| # | Test | Result | Evidence |
|---|---|---|---|
| C1 | Bridge, offline (`tests/test_chat_bridge.py`) | PASS | Parsing (case, trailing text, unknown), command list identical to `chaos.lua`, per-command and per-user cooldowns, vote rounds (one vote per user, tie → earliest), `--stdin` end to end with `--deny` |
| C2 | Commands on the remix ROM (`t_chaos.lua`) | PASS | Through the command file: weapon (+ `$C5`, palette), life, time, hurry, armor off/on (bit 5 inside Arthur's task), red tint on and removed after 20 s with the rendering bits intact, unknown command refused, incomplete line held until its newline, rainbow (real burst `23..27`), spread, tough, mortal, god |
| C3 | Commands on the original ROM | PASS | Same effects; `!rainbow` refused as remix-only |

`chaos.lua` was also run standalone in FCEUX for 9 s, with commands appended while it ran, and reported no Lua errors. The overlay text itself was not checked automatically.

## Acceptance checklist

| Item | Status |
|---|---|
| Original ROM hash/layout inspected and documented | **PASS** (`notes/rom_layout.md`) |
| Original game boots before modification | **PASS** (automated: title → intro → gameplay, #2/#4) |
| Invincibility build boots with normal graphics, controls, sound and progression | **PASS**. Graphics and sound identical to the original over the deterministic sequence (#2, #3); controls #5; progression: stage-1 boss → stage 2 (#11, final ROM). |
| Repeated contact with enemy bodies does not damage Arthur | **PASS** (#5, #6, #9, #10, #11) |
| Enemy shots do not strip armor or kill Arthur | **PASS**. The area sweep records contacts by the touching object's slot. **27 contacts from enemy-projectile slots `$14–$15`** (types `$29`×15, `$30`×5, `$31`×5, `$2D`×2: stage-1 boss area, stages 5–6, final room), all with damage routine 0×. |
| Normal movement, ladders, jumping and pickups still work | **PASS** for walking/jumping (#5) and ladder climbing among enemies (#6b). Weapon pickups: the bots collect items in play (score changes), but a pickup changing the weapon was not checked in isolation: **UNVERIFIED**. |
| Exactly five projectiles in a forward fan when firing right | **PASS** (#7, #8) |
| Exactly five in a mirrored fan when firing left | **PASS** (#7) |
| Every individual projectile can damage an enemy | **PASS**. Each slot `$0F–$13` recorded damage events (#8, #10, area runs). |
| Repeated presses / crowded scenes do not overflow tables or crash | **PASS**: per-frame audits (#10), 14-area sweep with hang detection (#11), 5-minute constant fire |
| Bosses can be damaged and defeated; stage transitions continue | **PASS for stage 1 boss → stage 2, stage 2 boss pair (killed), final boss (killed → first-loop restart).** Bosses of stages 3–6 were not reached by the bot: **UNVERIFIED**. Stage transitions other than 1→2 and final→1: **UNVERIFIED**. |
| Known flicker/slowdown noted | **PASS** (table above) |
| Both features coexist without regressions | **PASS** for everything above. Pixel/APU identity holds until gameplay diverges. |
| Patch reapplies deterministically, reproducing the final binary | **PASS** (#1; two clean builds gave identical CRC32/SHA-1) |
| Only patch/source/docs intended for sharing | **PASS**: `.gitignore` excludes `*.nes`, `rom/`, `build/`; `dist/` holds only `.bps`. |

## Not verified / known limitations

1. **Emulator coverage:** only FCEUX 2.6.5 was used. Not tested on MesenCE, other emulators or real hardware (flash cart).
2. **No human play-through.** The bots can't do precise platforming, so bosses of stages 3–6, most stage transitions, the second loop and the ending are **UNVERIFIED**.
3. **The magician's frog spell** was not exercised (**UNVERIFIED**). It isn't a damage hit; whether it's still applied to the invincible Arthur is unknown. A weapon pickup changing the thrown weapon was not checked in isolation.
4. **14 enemy slots instead of 16:** spawn refusals rose from 35 to 144 in the stage-1 session.
   - Level objects are retried until a slot frees (traced at `$D6EE`, never skipped), and periodic/random spawners spawn somewhat less often under load.
   - No test showed a missing platform or boss, but a stage where a required object waits a long time for a slot can't be ruled out without full play-throughs.
5. **Gameplay quirks of the fan:**
   - The down-45° shot hits the ground at once when Arthur stands on flat ground. It still hits low enemies and is useful when jumping.
   - Diagonal shots use the normal horizontal sprites.
   - Bursts vary by ±1 px because sub-pixel fractions are inherited from the slot (the original game has the same quirk).
6. **Weapon-specific boss reactions are original behavior.** For example, the type-`$05` boss deflects the cross, so five crosses = five deflections.
7. **Projectile contacts** are measured on the generic contact path (`$F5E8`). An enemy that sets Arthur's hit bit through its own code would still go through `$E014`, and no test saw `$E171` run for a non-timer cause, but such paths weren't enumerated one by one.

### Remix ROM limitations / not verified

8. **Hardware:** a 256 KiB mapper-2 image needs a UOROM-capable board or flash cart. Only FCEUX was used. The bank-8 bus-conflict argument (`$C008` = `$78`) is reasoned from the code, not measured on hardware: **UNVERIFIED**.
9. **Menu sound and music:** each A/B press plays the throw sound. On the title this briefly changes the music channels; in the regression run with presses, the APU trace differed from frame 152 to 519 (into the intro music) and was identical afterwards.
10. **Not separately tested:** weapon cycling by player 2 in 2-player mode; RAINBOW and 4 HITS EACH beyond stage 1 (the area sweep ran in the default modes); NORMAL/NORMAL beyond the deterministic sequence and the stage-1 session; the hidden stage-select code (it uses A/B, so it also changes the menu).
11. **Mode changes in play** (chaos commands): only SPREAD ↔ RAINBOW and the armor modes, which don't change the slot partition. NORMAL shot is title-only by design.
