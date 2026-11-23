# Addresses, banks and RAM — Ghosts'n Goblins (USA)

All findings below were traced on `rom/original.nes` (PRG CRC32 `B4E4879E`) with
`scripts/dis6502.py` (static) and FCEUX 2.6.5 Lua execution/write hooks
(dynamic, `tests/explore/*.lua`, `tests/*.lua`). The exact patched bytes are in
the generated [patch_ranges.md](patch_ranges.md).

**Offsets:** PRG offset = bank × `$4000` + (CPU − bank base). The file offset adds 16 for the iNES header.
For the fixed bank (bank 7, `$C000–$FFFF`): PRG = CPU + `$10000`, file = CPU + `$10010`.

## Mapper, banks, vectors

| Item | Value |
|---|---|
| Mapper | 2 (UNROM), bus conflicts |
| Switchable window | `$8000–$BFFF`, banks 0–6 |
| Fixed bank | bank 7 at `$C000–$FFFF` |
| Bank select | `STA $C000,Y` with Y = bank. `$C000–$C007` holds `00..07` so the stored value matches ROM (bus-conflict safe). |
| Current-bank shadow | `$C7`. The NMI music driver switches to bank 3 and restores from `$C7`, so `$C7` must be written *before* `$C000+n`. |
| Stage bank | `$C8` (restored after object logic, `$F359`) |
| Vectors | NMI `$C0F0`, RESET `$C008`, IRQ `$C008` |
| OAM | Double-buffered at `$0200`/`$0300`, DMA page in `$B1` (alternates 2/3 with reversed sprite order = flicker rotation) |

## Cooperative task kernel (fixed bank)

| Address | Meaning |
|---|---|
| `$00` | current task index (0,2,…,`$0E`; `$10` = idle) |
| `$02,X` / `$03,X` | task state (bit 7 = running) / saved stack pointer |
| `$C3BC,X` | task stack tops (stack page split into 8 × 32 bytes) |
| `$C3CC,X` | task entry − 1 |
| `$C2BC` | start task A |
| `$C2FA` | end current task |
| `$C313` | sleep (`$22/$23` frames) |
| `$C336` | yield |
| `$C37D` | scheduler; `$C395` = end of a round (all tasks ran) |

| Task | Entry | Role |
|---|---|---|
| 8 | `$DA71` | **Arthur's logic** (state routines `$DAxx–$E4xx`, run every 3rd frame) |
| `$A` | `$F367` | bank 4 `$9CC8`: per-frame **object update** |
| `$C` | `$F34F` | bank 4 `$8000`: **renderer** (draw list `$0480`, max 20 objects) |
| 2, 4, 6, `$E` | `$C3DC`, `$C8C4`, `$E68C`, `$E569` | other system tasks |

## Object table (25 slots)

Arrays indexed by slot. Some arrays are shorter than 25 entries, so the high slots only have the first few fields.

| Array | Field | Valid slots |
|---|---|---|
| `$04F0` | flags (bit 7 = active; `$40` = spawned/dormant) | `$00–$18` |
| `$0509` | screen Y | `$00–$18` |
| `$0522` | sprite/metasprite id | `$00–$18` |
| `$053B` | sprite attributes | `$00–$18` |
| `$0554` | screen X | `$00–$18` |
| `$056D` / `$0599` / `$05C5` | world Y: screen page / line / fraction (240-line pages) | `$00–$15` |
| `$0583` / `$05AF` / `$05DB` | world X: high / low / fraction | `$00–$15` |
| `$05F1` | direction index for velocity (`$F2A3` table); for weapons 4 = right, `$0C` = left | `$00–$15` |
| `$0607` | per-object timer/state counter | `$00–$15` |
| `$061D` | misc flags; for weapons: last enemy hit (piercing) | `$00–$13` |
| `$0631` | object type (handler index, jump table bank 4 `$9CED`) | `$00–$15` |
| `$0647` | hit counter (damage taken) | |
| `$065D`, `$066E` | per-type extra state | |

### Slot partition

| Slots | Original | Patched (`spread.asm`) |
|---|---|---|
| `$00` | Arthur | Arthur |
| `$01–$0E` | enemies / level objects | enemies / level objects |
| `$0F–$10` | enemies / level objects | **player weapons** |
| `$11–$13` | player weapons (2 slots, 3 for the dagger) | player weapons |
| `$14–$15` | enemy projectiles (allocated by about 10 shooters, `LDY #$14`) | unchanged |
| `$16–$18` | sprite-only effects | unchanged |

**Renderer slot swap:** `$8089` (bank 4) swaps the draw fields of slots 0 and 3 around each render pass (sprite priority). Code outside Arthur's task must not read `$04F0` at an arbitrary time and assume it is Arthur's. The tests sample Arthur's flags inside `$E014`, which runs in his task.

### Arthur flags `$04F0` (slot 0)

| Bit | Meaning (evidence) |
|---|---|
| 7 | active / visible (blinks during post-hit invulnerability, `$E3DB`) |
| 6 | post-hit invulnerability (set at `$E182`; skips `$F687` collision) |
| 5 | **no armor** (set at `$E1A6` after a hit; a hit with bit 5 set = death) |
| 4 | standing on a moving platform (bank 4 `$B795`, `$B905`) |
| 3 | set during knockback/intro (`$E1EE`); meaning not fully traced |
| 2 | facing left (copied to thrown weapons at `$E110`) |
| 1 | crouching (smaller hitbox at `$F69B`; lower throw height at `$E126`) |
| 0 | **hit pending** (set by enemy contact `$F5ED` and timer expiry `$D3BD`) |

Bit helpers (all act on `$04F0,X`): test `$F2E3`(b0) `$F2E7`(b1) `$F2EB`(b2) … `$F2FF`(b7); set `$F305`…`$F321`; clear `$F32A`…`$F346`.

## Damage and death (fixed bank)

| Address | Routine |
|---|---|
| `$F687` | Arthur hitbox vs object X (returns no-hit if `$04F0 & $41`) |
| `$F5E3` | generic contact: `JSR $F687`; on hit `$04F0 \|= 1` (`$F5E8–$F5ED`) |
| `$D3AD–$D3C2` | timer reached 0 → `$04F0 \|= 1`, `$BD = $FF` |
| bank 4 `$BAF0` | timer-expiry path in the clock/hourglass code → `$BD = $FF` |
| **`$E014`** | **HitPending**: A = bit 0; carry = hit. Polled by all 8 Arthur state routines as `JSR $E014 / BCC / JMP $E171` (`$DAEE $DC7E $DCD7 $DD1E $DE38 $DE7E $DEC1 $E28E`) |
| `$E171` | damage routine: `$BD ≠ 0` → death `$E1C2`; no armor → death `$E1AC`; else knockback, armor debris, bit 6, bit 5 |
| `$E1BA` | death entry used by the fall/jump states (`$DE7B`, `$DEBE`): pits/water |
| `$0715` | lives (decremented at `$C907`/`$C926`/`$C948`) |
| `$06F6`/`$06FA`/`$06FC` | timer digits; all zero = time up |
| `$BD` | time-up flag |

## Weapons (fixed bank)

| Address | Routine |
|---|---|
| `$E01E` | attack: needs `$061D & $12 == 0`, B pressed (`$CC & $40`) or autofire (`$94`), latch `$85 == 0` |
| `$E045–$E073` | original: find a free slot in `$11–$12` (`$13` if `$053A == $42`), set Arthur attack flags, `JSR $E0BE`, `$85 = $FF` |
| `$E074` | no shot: `$85 = 0` |
| `$E0BE` | weapon init for slot Y: copy Arthur's world position, clear timers, sprite = `$053A`, type from `$053A` (`$40`→`$23` lance, `$42`→`$24` dagger, `$44`→`$25` torch, `$36`→`$26` axe, else `$27` cross), flags `$40` \| facing, `$05F1` = 4/`$0C`, throw height, left sprite +1, sound `$11` via `$ED51` (preserves X, may clobber Y) |
| `$053A`, `$C5,Y` | held weapon (sprite id), per player |
| `$EB75 $EB84 $EC10 $ECAF $ED27` | handlers for types `$23–$27` |
| `$EBC1` | impact animation and removal |
| `$EBE9` | impact spark choice (originally `$05F1 == 4`) |
| `$F03E` / `$EFDA` | add velocity = direction table[`$05F1`] × speed(A) to the world position (24-bit) |
| `$F2A3` | 16-direction table, 4 bytes/entry = (Y, X) signed, magnitude 64; 0 = up, 4 = right, 8 = down, 12 = left, 22.5°/step |
| `$F0A3` | off-camera test (carry = remove) |
| `$F5A0` / `$F585` | enemy-vs-weapon wrapper used by enemy handlers. `$F5D0` = `INC $0647,X` (damage applied). Bosses read the hitting weapon's type via Y (e.g. type `$05` at `$FBF5` deflects the cross). |
| `$F5F2`/`$F5F9` | loop over weapon slots (`LDY #$11 … CPY #$14`) |
| `$F611` | weapon-vs-enemy box test (hitbox tables `$F6EC`/`$F6F1` indexed by type − `$23`) |

## Enemy allocation and level objects

| Address | Routine |
|---|---|
| `$DA18` | FindFreeEnemySlot `$01–$10` (`CPY #$11` at `$DA20`); carry set = none (`$DA24`) |
| `$DA28` | recycle a free/dormant slot, round-robin from `$CE` (bounds `$DA4E`, `$DA60`) |
| `$D744` | census of free/dormant regular slots (bound `$D763`); spawns a random enemy only if ≥ 9 |
| `$D374` | sweep: clear non-active slots `$01–$10` (bound `$D381`) |
| `$D529` | wipe slots `$01–$10` on stage (re)start (bound `$D531`) |
| `$D5xx` | level-object placer: dispatch table `$D5FB`; spawners `$D692–$D72B` return on failure **without** advancing `$C1`, so the object is retried, never lost; success ends in `INC $C1` (`$D6EE`) |
| bank 2 `$8435–$8907` | stage-specific spawners (zombie generator `$8907` skips one spawn on failure) |

## Stages

| Address | Meaning |
|---|---|
| `$AC,X` | area of player X (0–13), `$BA` = current player |
| `$CF` | stage = `$CC86[area]`: areas 0–2 → stage 1, 3–6 → 2, 7–8 → 3, 9–10 → 4, 11 → 5, 12 → 6, 13 → final |
| `$D05F` | built-in stage select when `$A7 == $0F` (Up/Down change `$AC`, Start exits, `$EF20`) |
| `$FBC4` | type `$05` big enemy (stage-1 boss): dies at `$0647 ≥ $0A` |
| type `$1F` | final boss (`$F70B`: on death `$BF = $FF`) |

## Hooks used by the patch

| Feature | Bank:CPU | File off | Change |
|---|---|---|---|
| A | 7:`$E014` | `$1E024` | `JSR $F2E3` → `JMP $FFE8` |
| A | 7:`$FFE8–$FFF7` | `$1FFF8` | InvHitPending (16 bytes, cave) |
| B | 7:`$DA20`, `$DA4E`, `$DA60`, `$D763`, `$D381`, `$D531` | see patch_ranges.md | enemy-range bound `$11` → `$0F` |
| B | 7:`$F5F9` | `$1F609` | weapon collision loop start `$11` → `$0F` |
| B | 7:`$E045–$E073` | `$1E055` | SpreadFire (same 47 bytes as the original routine) |
| B | 7:`$EBE9` | `$1EBF9` | impact spark: test facing bit instead of `dir == 4` |

## Code caves

| Range | Status |
|---|---|
| 7:`$FFE8–$FFF9` (18 × `$FF`) | **used** (invincibility, 16 bytes). Padding between the last routine (`JMP $EA55` at `$FFE5`) and the vectors. No absolute, indexed or pointer references (the `#$FF`/`#$F0` hits at bank 4 `$BBE0`/`$BC4A` and 7:`$FF9A` are velocity constants). |
| 7:`$CA76–$CA95` (32 × `$FF`) | **REJECTED, live data.** `$CA63` points `$26/$27` at it and copies 32 bytes to the PPU (a blank nametable row used to clear screens). Using it corrupted the "PLAYER READY" and map screens; the pixel-exact screen test (`tests/t_screens.lua`) catches this. |
| 7:`$DA6A–$DA70`, 7:`$E562–$E568` (7 × `$FF` each) | padding before task entries; unused |
| banks 0–2 large `$FF` runs | not used; bank 0 is graphics data, so not trusted without CHR-load tracing |

## Engine facts traced for the remix ROM and the chaos mode

| Address | Meaning |
|---|---|
| `$C278` | controller read (from the NMI). `$42`/`$44` = pad 1/2 held (A `$80`, B `$40`, Select `$20`, Start `$10`, Up `$08`, Down `$04`, Left `$02`, Right `$01`); `$43`/`$45` = same with A only on a new press |
| `$CC` | current player's buttons in play (`$89`/`$8A` by `$BA`, set at `$D2CD`; demo input when `$94 ≠ 0`) |
| `$C008` reset | cold boot (magic `$8B/$8C ≠ $14/$22`) clears `$0300–$07FF` and zero page; warm reset clears only `$00–$8A`. Zero page `≥ $8B` and `$0300–$07FF` survive a console reset |
| `$C424` | title loop setup: idle timer `$86/$87 = $01C2` (450 frames, then the attract demo), cursor = slot 0 (`$0509` Y, `$A3` index) |
| `$C44B–$C4F6` | title loop: Start `$EF20`; cheat check `$C45B` (Right + A/B, then Up BBB Left BBB Down BBB, table `$C61C`) → `$A7`; Select moves the cursor (`$C4A5`); `JSR $C336` at `$C4CE` = once per frame |
| `$D882` | pause (Start in play): `$80 = $FF`, sound `$21`, wait for Start |
| `$EECF` | queue PPU data: `$22` rows × `$23` bytes from `($26)` to PPU `$25:$24`, into the NMI buffer `$0720` (index `$31`, lock `$4F`) |
| title font | BG tiles `$00–$09` = 0–9, `$0A–$23` = A–Z, `$24` ©, `$25` !, `$26` ., `$FF` blank. In play the BG pattern table holds stage graphics only; the HUD is sprites (digits and a few letters) |
| `$0715,X` | lives of player X (`$BA`); extra life = `INC $0715,X` (`$D9BF`) |
| `$053A` / `$0553` | held weapon = slot `$18` sprite (the HUD icon), its palette; pickup writes `$C5,Y`, `$053A`, `$0553` (bank 4 `$BA63–$BA71`); respawn restores from `$C5,Y` and sets the palette for torch (2) and axe (1) (`$D1DD–$D200`); lance, dagger, cross use 0 |
| `$0647,X` (Arthur) | post-hit invulnerability counter: +1 per Arthur tick while bit 6 is set, bit 7 (visible) = counter bit 0, bit 6 cleared at `$1E` (`$E3B9–$E3C8`) = 90 frames; it also runs while climbing |
| `$39` | PPUMASK shadow, copied to `$2001` every NMI (`$C21B`); game uses bits 1–4. Bit 0 = greyscale, bits 5–7 = colour emphasis |
| sounds (`$ED51`, A = id) | `$0A` death, `$11` throw, `$14` armor pickup, `$1D` armor knocked off, `$21` pause. `$ED51` switches to bank 3 and back to `$C7` |

## Remix ROM (`build/ghosts-n-goblins-remix.nes`)

**Image:** 256 KiB, mapper 2 with 16 banks (UOROM). Banks 0–7 are the original (bank 7 is an unpatched copy of the fixed bank that the game never selects: the area sweep audits every mapper write, only values 0–6 and 8 occur), bank 8 holds the new code, banks 9–14 are `$FF`, bank 15 is the fixed bank. Header byte 4 = `$10`. File offset in bank 15 = CPU + `$30010`; in bank 8 = CPU + `$18010`.

**Why bank 8:** the NMI (`$C231`) and the sound routine (`$ED69`) restore the bank with `LDA $C7 / TAY / STA $C000,Y`, i.e. they write N to `$C000+N`. `$C000–$C007` hold 0–7, so the original banks are bus-conflict safe. `$C008` holds `$78`, and `$08 AND $78 = $08`, so bank 8 is safe too. `$C009` = `$A2` (9 AND `$A2` = 0) and beyond are not, so banks 9–14 must not hold code.

**Trampoline `Far8` (`$E047`, 21 bytes):** push `$C7`; `$C7 = 8` (shadow first, the NMI restores from it); write 8 to the ROM byte `$E04B` (the `LDA #$08` operand, so the bus sees the same value); `JSR $8000` (Dispatch8, Y = function); pull; `$C7 =` old bank; `STA $C000,Y`. Preserves X and the callee's carry. Bank-8 code must not yield (`$C336`/`$C313`): other tasks switch banks.

| Hook (bank 15) | Was | Now |
|---|---|---|
| `$E014` HitPending | `JSR $F2E3 / BEQ …` | `LDY #0 / JMP Far8` → ArthurTick (damage modes + weapon cycling); returns carry like the original |
| `$E045` | single-shot slot search (47 bytes) | `$E045` `LDY #2` falls into Far8 → Fire; `$E047` Far8; `$E05C` TitleStub (`LDY #4 / JSR Far8 / JMP $C336`). `$E064–$E073`: old bytes, unreachable |
| `$C4CE` | `JSR $C336` | `JSR TitleStub` (TitleTick, then the original yield) |
| `$DA20 $DA4E $DA60 $D763 $D381 $D531` | `CPY/CMP/CPX #$11` | same opcodes on zero page `$BE` (EnemyEnd) |
| `$F5F9` | `LDY #$11` | `LDY $BE` (weapon loop starts at EnemyEnd) |
| `$EBE9` | spark: `dir == 4` | spark: facing bit (same as the main hack) |

| Bank 8 | Function |
|---|---|
| `$8000` Dispatch8 | `RTS` jump through `FarTable` by Y (0 ArthurTick, 2 Fire, 4 TitleTick) |
| ArthurTick | Select edge → next weapon (writes `$053A`, `$0553`, `$C5,Y`; sound `$14`); hit pending: timer expired or armor NORMAL → carry (original damage); INVINCIBLE → clear bit 0; 4 HITS EACH → count per armor piece, absorb hits 1–3 (clear bit 0, set bit 6, `$0647 = 0`, sound `$1D`), let the 4th through |
| Fire | NORMAL: the original `$E045` logic; SPREAD/RAINBOW: the main hack's five-slot fan, with RAINBOW setting `$053A` per slot (lance, dagger, torch, axe, cross) and restoring it |
| TitleTick | A/B new presses cycle `$071A`/`$071B` (wrap at 3, also repairs stray values), set `$BE` from the shot mode, restart the idle timer + sound `$11` on a change, queue the two 22-character lines to nametable rows 23–24 via `$EECF` on the first title frame (timer = `$01C2`) and on changes |

| New RAM | Use |
|---|---|
| `$BE` | EnemyEnd = first weapon slot: `$0F` (spread/rainbow) or `$11` (normal) |
| `$071A` | shot mode: 0 spread, 1 rainbow, 2 normal |
| `$071B` | armor mode: 0 invincible, 1 four hits per armor piece, 2 normal |
| `$071C` | title: previous pad-1 state |
| `$071D` | play: previous Select state |
| `$071E` / `$071F` | 4-hit armor: hits absorbed / armor bit (`$20`) the count belongs to |

All seven bytes were never written by the original game after the boot-time clear (write hooks over all 14 areas, title, demo, game over). They sit in the ranges a warm reset keeps, so the menu settings persist until power-off.
