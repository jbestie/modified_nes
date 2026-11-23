# Castlevania (USA, Rev 1): engine map

All addresses are for the USA V1.1 PRG (CRC32 `B668C7FC`), the version this folder builds on.

**Notation:**
- `b6:$934C` means CPU address `$934C` with bank 6 mapped at `$8000`.
- Bank 7 is the fixed bank at `$C000-$FFFF`.
- File offset = 16 + bank × `$4000` + (address − bank base).

**Tags:**
- **verified**: seen at runtime in FCEUX (hook, RAM trace, screenshot) or proven by an overwrite test
- **static**: read from this ROM's disassembly (`scripts/dis6502.py`), not run
- **lead**: plausible, not confirmed

**Sources:**
- Item 0 of `TODO.md` (2026-11-17), using the scripts in `tests/explore/` (listed at the end).
- The [Data Crystal RAM map](https://datacrystal.tcrf.net/wiki/Castlevania_(NES)/RAM_map) was used as leads only. It is mostly right, but some entries are wrong for this ROM (noted below).
- CadEditor's stage-1 config was the lead for the level format (section 13). Only addresses and the format were taken, no data files.

## 1. Cartridge, timing, frame structure

- **verified** Mapper 2 (UNROM), 8 × 16 KiB PRG, 8 KiB CHR-RAM. Banks 0-6 switch in at `$8000`; bank 7 is fixed at `$C000` (`rom_layout.md`).
- **verified** NES 2.0 header with submapper 2 (UxROM with bus conflicts), NTSC. FCEUX runs 29780.5 CPU cycles per frame (`tests/t_boot.lua`). FCEUX emulates bus conflicts for this header.
- **verified** Vectors: RESET `$C008`, NMI `$C052`, IRQ/BRK `$C0BF`.
- **verified** **All game logic runs inside the NMI.**
  - RESET ends in an idle loop at `$C030-$C03C` that only stirs the RNG byte `$6F` (`$6F = $C03F[($6F OR $1A) AND $0F]`, 20 cycles per pass).
  - NMI order:
    1. PPU off, `$2003` = 0, OAM DMA from page `$02` (`$C069`)
    2. PPU buffer flush (`b0:$800A`), PPUMASK from `$FE`
    3. sprite-0 status-bar split (`$F87D`), scroll/PPUCTRL from shadows (`$C11F`)
    4. `INC $1B`, sound (`b0:$838A`), controller read (`$C8CD`)
    5. game-state dispatch (`$C1E4` → `JSR $CA6D` with the word table at `$C1F4`, indexed by `$18`)
    6. object sprite drawer (`b0:$8052`), buffer terminator (`$CCEE`), `$1B` = 0
- **verified** `$1B` is a re-entrancy guard (Data Crystal calls it "graphics enabled", which is wrong). If the next NMI arrives while it is set, the frame lags: only PPUMASK, scroll and the split run, and the bank is restored from `$27` (`$C0D7`).
- **verified** PPU write buffer at `$0700` (write index `$20`), flushed in vblank by `b0:$800A`:
  - a record is `[mode][addr hi][addr lo][data…]$FF`
  - mode 1 = +1, 2 = +32, 0 = end of buffer
  - during scrolling it carries 10-27 nametable bytes per frame

**Game states `$18`** (`$19` = substate):

| `$18` | Handler | Meaning | Tag |
|---|---|---|---|
| 00 | `$B7DC` | boot | static |
| 01 | `$B823` | title; `$1E` counts down every 2nd frame and the attract demo starts at 0 (`b6:$B83E`) | verified |
| 02 | `$B859` | attract demo | verified |
| 04 | `$B911` | intro walk to the castle gate | verified |
| 05 | `$C232` | stage. Substates 0-3 load the stage, 06 = gameplay | verified |
| 06 | `$C2DE` | death/respawn | verified |
| 07 | `$C32C` | game over | static |
| 08 | `$C382` | walking out of a stage exit | verified |
| 09/0A | `$C4E7` | castle gate walk-in | verified |
| 0B | `b?:$8693` | lead: ending | lead |
| 0C | `$C5F5` | stage clear / block map | verified |
| 0D | `$C847` | continue screen | static |
| 0E | | stage 10 intro | verified |

**Gameplay frame** `$CED0` (`$18` = 5, `$19` = 6), in order (**static**, roles **verified** by coverage):
- If Left and Right are both held, only Right is kept in `$F7`.
- `$A2E8`, `$CF53`
- `b6:$A825` whip vs candles/blocks
- `$FA6A` stopwatch timer
- `$CF28` pause (Start toggles `$22`)
- **`b6:$934C` Simon**
- `$F5EA` (bank 4 mapped)
- `b6:$AAE2` background objects (slots `$17-$1B`)
- `b6:$81CA` (stage 6 only)
- **`$E8F0` object loop with collisions** (bank 5 mapped)
- **`$F376` spawners**
- `$A4AA`, `$A63A`

## 2. Banks

- **verified** **One routine does every bank write** (`registerwrite` on `$8000-$FFFF` over a 50,000-frame session):

  ```
  $C1CF  LDY $27 / JMP $C1D8   ; restore the last selected bank
  $C1D4  LDY $24               ; select the home bank
  $C1D6  STY $27               ; select bank Y and remember it
  $C1D8  PHA / LDA $C000,Y / STA $C000,Y / STA $C000,Y / PLA / RTS
  ```

  It writes back the byte it just read from the same address, so it can never hit a bus conflict. The bank table is `$C000-$C007` (`00-07`); `$C008` onward is RESET code.
- **verified** `$24` is the home bank, always 6 (written only by RESET at `$C02B`). `$27` is the last bank selected through `$C1D6`. **New code that switches banks must go through `$C1D6`**, otherwise a lag frame restores the wrong bank.
- **verified** **Where code runs** (exec coverage):

  | Bank | Code | Contents |
  |---|---|---|
  | 0 | `$800A-$8789` | NMI helpers, sound, sprite drawer; title tiles at `$B501-$BB00` |
  | 1, 2, 3 | none | tile graphics |
  | 4 | none | level data |
  | 5 | `$8008-$935D` | enemy/boss handlers; demo input data |
  | 6 | `$805D-$BA16` | main game logic: Simon, spawners, HUD, stages |
  | 7 | most of it | fixed: NMI, states, objects, collisions, items, uploads |

  During stage play there are about 10 bank switches per frame (banks 0, 4, 5, 6; 38 cycles each). Banks 1-3 are selected only by the tile uploader.
- **verified** **256 KiB expansion** (16 banks, bank 7 copied to bank 15): a test ROM ran the whole session identically. With the stock routine only bank 8 can be reached by its number: `$C008` = `$D8` happens to select bank 8. **Fix (tested):** put a table `00-0F` in bank 15's free space and point the operands at `$C1DA/$C1DD/$C1E0` at it. All 16 banks then work, and the `$27` restore keeps working.

## 3. CPU budget

**verified** Idle cycles per frame (the idle loop's count; NTSC frame = 29780.5):

| Phase | Min | 1st percentile | Median |
|---|---|---|---|
| Title | 1,431 | 21,065 | ~21,200 |
| Demo play | 576 | 2,809 | 9,021 |
| Stage play (all 18 stages, 22,027 frames) | 19 | 2,259 | 9,070 |

- **verified** Lag frames: 27 of 22,027 in stage play (0.12%). Each stage load lags 8-13 frames, with NMI off during the tile upload.
- **verified** Every play frame the NMI busy-waits 4,257-5,559 cycles for sprite 0 (`$F8C7-$F8E6`). Work placed before that wait costs no idle time. Hook point: `$F8C4 JSR $A08A`, which runs only when the frame isn't a lag frame (`$1B` = 0) and `$1F` = 0. The commando build runs its bullet pass there (pass + HUD tick: at most 4,288 cycles in the stage-12 profile, leaving at least 1,562 of the wait).
- **verified** **Extra CPU time changes gameplay.** Fewer idle-loop passes change `$6F`, which enemy code reads. Adding ~330 cycles per frame left the demos identical, but stage play diverged after ~1,400 frames. Regression tests for hacks that add per-frame work must check behaviour, not frame-exact traces.

## 4. Controllers

- **verified** One routine, `$C8CD`, called once per frame, reads 8 bits from `$4016` and 8 from `$4017`:

  | Address | Contents |
  |---|---|
  | `$F5` | P1 newly pressed |
  | `$F6` | P2 newly pressed |
  | `$F7` | P1 held |
  | `$F8` | P2 held |

  Bits: A `$80`, B `$40`, Select `$20`, Start `$10`, Up `$08`, Down `$04`, Left `$02`, Right `$01`.
- **verified** **Controller 2 is read but never used:** nothing reads `$F6/$F8`, and P2 Start doesn't pause. The P1|P2 merge path at `$C90D` is unreachable.
- **verified** The demo player overwrites `$F5/$F7` from bank-5 data (`$FEF2/$FEF7`).

## 5. Stages

- **verified** `$28` is the stage number: 0 is the courtyard before the castle, then 1-`$12` are stages 1-18. The HUD shows `19 × $2B + $28`, with 0 shown as 1 (`b6:$A35C`), so the courtyard and stage 1 both read "STAGE 01". `$2B` is the quest loop counter (incremented after stage 18, `$C6C7`).
- **verified** Lives `$2A`; the HUD "P-nn" shows `$2A` − 1. Timer: BCD, `$43` = hundreds, `$42` = tens and units. The start value is `$C9F6[$28]` × 100; timer 0 → death.
- **static** `$29` is a temporary copy of `$28` across the block map screen, not a checkpoint.
- **verified** Stage start position `$CA0C[$28]`, 2 bytes, read by `$C998`:
  - byte 0: Y (AND `$F8`) and the camera page
  - byte 1: X, facing (bit 7) and floor (bit 0)
- **verified** **Death** (`b6:$A1E5` → `$18` = 6):
  - lives −1, subweapon and multiplier cleared, whip level 0
  - timer reset, refill (health `$40`, hearts 5)
  - **no tile reload**
- **verified** **Block clear** (`$18` = `$0C`):
  - `$28` + 1, castle map (tile set 2)
  - then substate 7 (`$C7E5`) loads tile set `$C8B0[$28]`, music and timer, and restarts the stage
- **verified** **Stage warp for tests:** during stage play write `$29 = N`, `$18 = $0C`, `$19 = 7`, then run until `$18 = 5` and `$19 = 6` (about 290-620 frames).
  - Tiles, timer and music load correctly for all stages 0-`$12`; checked with screenshots of stages 4, 9, 15 and 18.
  - Lives, score, whip and subweapon are kept; health is refilled and hearts set to 5.
  - Caveats: `$12` keeps the old timer; `$0A` plays its intro first; `$13` is not a stage.
  - Script: `tests/explore/sim_warp.lua`.
  - **Not usable:** poking `$28` and dying. The death path doesn't reload tiles, so other blocks show the wrong graphics.

## 6. Simon

Slot 0 of the object tables (section 7). The movement code is in bank 6.

| Address | Meaning | Tag |
|---|---|---|
| `$038C` | X on screen (stays `$80` while the camera scrolls) | verified |
| `$0040/$0041` | X in the level (screen X + camera), recomputed at `b6:$98F3` | verified |
| `$003F` | Y, master copy (bottom of the sprite); the player code works on it | verified |
| `$0354` | sprite Y, a copy of `$3F` made at `b6:$9BBA` (one frame behind during jumps); **enemies and collisions use this one** | verified |
| `$0450` | facing: 0 right, 1 left | verified |
| `$046C` | movement state, see below | verified |
| `$0434` | attack: 0 none, 1 standing/stairs whip, 2 crouching, 3 jumping; bit 7 = subweapon throw | verified |
| `$0568` | attack timer, +1 per frame; the whip hits and the subweapon spawns at `$11`, the attack ends near `$16` | verified |
| `$0488` | jump frame counter | verified |
| `$054C` | attack in the air or on stairs = 1 (also knockback/landing counters) | verified |
| `$005F` | contact half-height: `$0C` standing, `$0A` crouching (`$E45A`) | verified |
| `$0044` / `$0045` | health display / real. `$40` = full (16 bars); the display catches up 1 every 2 frames; 0 → death | verified |
| `$005B` | invincibility: `$30` after a knockback lands (`b6:$96AD`), −1 every 2nd frame; `$B4` from the potion | verified |
| `$0047` | stun timer after a hit on stairs (`b6:$96C8`) | static |
| `$0071` | hearts, binary 0-99 | verified |
| `$0070` | whip level: 0 leather, 1 short chain, 2 long chain | verified |
| `$0073/$0074` | whip hitbox half-size: `$10/$06`, `$12/$08`, `$1A/$08` by level | verified |
| `$015B` | subweapon: 0 none, `08` dagger, `09` cross, `0B` holy water, `0D` axe, `0F` stopwatch (the same numbers as the item IDs, section 8) | verified |
| `$015C` | subweapon lock while the stopwatch runs | verified |
| `$0560` | stopwatch freeze flag (`$FF` = active; the object loop skips enemy handlers) | verified |
| `$0064` | shot multiplier: 0, 1 = double, 2 = triple. Usable projectile slots = `$14..$14+$64` | verified |
| `$0046` | floor (vertical sub-level) inside the stage | verified |
| `$0048` | boss-room scroll lock | verified |
| `$0584` | Simon's input/flags byte (copy of `$F7`, stair direction) | static |
| `$0159` | animation index → `$031C` via `b6:$9BF1`; blinks while invincible | static |

`$046C` movement states (dispatch table `b6:$936C`, all **verified**):

| Value | State | Handler |
|---|---|---|
| 0 | stand/walk | `b6:$9380` |
| 1 | jump | `$9482` |
| 2 | attack | `$9511` |
| 3 | crouch | `$9539` |
| 4 | on stairs | `$9586` |
| 5 | knockback | `$965B` |
| 6 | walk to the first stair step | `$9720` |
| 7 | falling | `$9757` |
| 8 | dead | `$97AA` |
| 9 | landing crouch | `$97F2` |

**Simon's code:**
- **verified** The per-frame update is `b6:$934C`, called from `$CED0`. Coverage shows it runs only in bank 6 `$934C-$A46D` and `$AC70-$AD67`, plus bank-7 helpers.
- **static** Key helpers:

  | Address | Role |
  |---|---|
  | `$9809` | horizontal input / camera |
  | `$9A2A` | attack start (B; Up+B → subweapon `$FA26`) |
  | `$9A71` | whip timer and frames |
  | `$9B1E` | vertical motion tables |
  | `$9BBA` | animation and blink |
  | `$9C10` | stairs entry |
  | `$9E70` | floor check |
  | `$9ECE` | wall check |
  | `$9F7A` | stage exit |
  | `$9FF3` | stairs → floor change |
  | `$A38D` | whip sprites in slots 1-2 |

- **verified** Movement details used by the commando build (`src/commando/`):
  - Stand/walk (`$9380`): `$93D9` copies the pad into `$0584`, and `$9809` moves by its Left/Right bits. Up/Down near a staircase goes to `$9C10` first. Then A jumps (`$9401`), the attack start runs (`$943C`), and Down crouches (`$944A`: state 3, `$3F` + 4).
  - Crouch (`$9539`): Left/Right only turn; releasing Down stands up (`$9561` → `$9578`: `$3F` − 4, state 0). The landing crouch (`$97F2`) ORs Down into `$F7` and reuses it.
  - Jump (`$9482`): `$948E JSR $9479` runs every frame, then `$9809` moves by the direction bits latched in `$0584` at take-off. Re-writing those bits mid-air gives air control.
  - Attack start (`$9A2A`): B newly pressed is tested at `$9A2F-$9A33` (`AND #$40`).
  - Frames: `$9BBA` turns the animation index into a frame through `$9BF1`, and `$9BE3 STX $031C` stores it after the blink (frame 0 on even frames while `$5B` ≠ 0). Stand 01, walk 02-04, kneel/jump 05, stairs 02 and `$0D-$0F`.
  - Contact half-height: `$E44F` sets `$5F` = `$0C`, or `$0A` in state 3.
  - Stand frame extent: −16..+14 around `$0354`; crouch frame −12..+11 (drawn 4 px lower).
- **static** Called from elsewhere:
  - hit reaction `b6:$96C1` (knockback facing the enemy; on stairs a stun instead)
  - death start `b6:$A1E5`
  - new game `$C966`; refill/respawn `$C98A`

**Single-player wiring** (the key fact for a 2-player mode; **verified** by coverage with register values):
- **Simon's update:** 140 instructions use slot-0 table entries and 89 use Simon-only variables, all with absolute addresses. Only 13 instructions are indexed with X = 0: the vertical-motion helper `b6:$9B1E` (which still special-cases X = 0) and `$9C13`.
- **Input:** it reads only pad 1 (`$F5/$F7`).
- **Whip:** fixed in slots 1-2.
- **Other code:** about 150 more absolute references to Simon sit in enemy AI, spawners, collisions, items and the HUD. Enemies read Simon from the slot-0 table (`LDA $038C`, `LDA $0354`, `LDA $046C`), never from the `$40/$3F` copies. Example: `$EF84` `LDA $038C / SBC $038C,X` (distance and direction to Simon), used by 17 enemy types.
- **Generic:** only the bank-0 sprite drawer handles all slots by index, Simon included.

## 7. Objects

**28 slots as parallel arrays** (`$0300 + k × $1C`). Addresses **verified**; per-object extras **static**.

| Array | Field | Array | Field |
|---|---|---|---|
| `$0300` | hidden flag (≠ 0: not drawn, no collision) | `$03FC/$0418` | X speed / sub |
| `$031C` | sprite frame (metasprite ID) | `$0434` | object type (for Simon: attack flag) |
| `$0338` | palette override | `$0450` | facing / mirror |
| `$0354` / `$0370` | Y / sub | `$046C` | state |
| `$038C` / `$03A8` | X / sub | `$04C0` | graphic ID (from `$EF04`); not read by the drawer, see below |
| `$03C4/$03E0` | Y speed / sub | `$0568` | timer |
| `$0584` | item ID / subweapon kind | `$04DC`, `$04F8`, `$0514`, `$0530` | per-type scratch (`$0530` = spawner index) |

- **verified** **Graphic IDs** become frames in the animation step `$F1DB`: entry `$F23C + 3 × ID` (IDs from `$56` on: `$F33C`) = [last index, base frame, duration]. `$031C` = base + `$04A4` (the step counter); `$0488` counts the duration down, and bit 7 stops the animation (static frames, such as the dagger: ID `$17` = `00 50 80`, frame `$50`). Setting `$0488` = `$80` keeps a frame written to `$031C` directly.

- **verified** The object loop `$E922` skips slots whose type has bit 7 set (`$E927 BMI`), and the projectile collision `$E5EB` skips kinds 6 and above. The commando's bullets (type `$97`, kind `$10`) use this to stay out of the stock path.
- **verified** **Targets of a shot** (`$E4D9`): types 1-`$2E` except `$17`, `$21`, `$25`; not while state bit 7 is set; not while hidden (`$0300`), except type 4. Box: half-sizes `$E46A + 2 × type` (type `$1D` with `$7A` ≠ 0 uses `$30`) plus the projectile's `$E5DF + 2 × kind`. A hit sets `$0F` = projectile slot, `$0C/$0D` = damage, `$0E` = weapon code (whip `$FF`), then `$E562` (hit SFX, spark, on-hit table `$E579`); the handler's RTS returns to the caller.

**Slot ranges in play:**

| Slots | Use | Tag |
|---|---|---|
| 00 | Simon | verified |
| 01-02 | whip sprite pieces (untyped; Y = `$FC` when hidden) | verified |
| 03 | hit spark (type `$30`), written to fixed `$0437` by `$DF79` | verified |
| 04-0D | enemies (spawner sub-ranges below), enemy projectiles (0C-0D), score popups | verified |
| 0E-13 | candles: slot `$0E + (64-px column mod 6)`; candle → flame → item in the same slot | verified |
| 14-16 | Simon's subweapon projectiles (type `$17`) | verified |
| 17-1B | background objects (moving platforms in stages 4/5/10, block debris), updated by `b6:$AAE2`, **not** by the main loop | static; never used in stages 0-3 or the demos (verified) |

**Peak use** (**verified**):
- stage 1 play: enemies 3, candles 6, projectiles 1
- STAGE 12 demo: enemies 9

Free: 17-1B in stages without platforms or debris (a new object there needs its own update call), and 0C-0D unless an enemy shoots.

**Ending** (**verified**, commando build, `tests/explore/boss_fights.lua` with `ENDING`): after Dracula's second form the magic crystal drops on the coffin; touching it gives `$18` = `$0C` (stage clear), then `$0F` (the ending: the castle falls, the credits loop through substates 5-9), then `$0C`/8 and stage play of stage 0 with `$2B` = 1 (second quest, HUD "STAGE 19"). The contact check (`$E6BA`) and the object loop run with bank 5 mapped throughout play (19,084 calls in 7 stages).

**Moving platforms** (**verified** in FCEUX, stages 4 and 5; code static):
- Type 1 in slots `$17-$1A`, only in stages 4, 5 and `$0A` (`b6:$AAE2`). `$04A4` bit 0 = floor, bits 3-7 = Y; frame `$C9` while on screen. Stage 4 has one on floor 1 (page 0, the gap X 32-95 at Y `$70`); stage 5 two on floor 1 (page 1).
- Standing check `b6:$AC70` (slots `$1A` down to `$17`): box test `$A011` of Simon's Y + `$10` (`$0C` when crouching) against the platform's Y + 4, a 10-px window, and X within ±16. It snaps Simon's Y to the platform top - `$10` and sets `$0142` bit 2. Simon rides along only while not jumping (`$0584` AND 3 = 0); a jump doesn't keep the platform's motion.
- Simon's jump table (`b6:$9B90`): -5, -5, -3 x5, -2 x3, -1 x4, 0, -1, 0 x4; the fall replays it backwards, so he lands at 5 px/frame, then `$80` = 8 px/frame below the take-off height.

**Object loop** `$E8F0` (bank 5 mapped; **static**, return address seen on the stack):
1. Counts `$5B` down every other frame.
2. Builds the whip box (`$E3FF`).
3. For X = `$16` down to `$03`: the type handler from the inline table `$E95C` (types `$00-$35`; addresses below `$C000` are in bank 5), the off-screen despawn check, then collision `$E4D9` (at `$EA77`).

**Type IDs:**
- **verified:**

  | Type | What | Type | What |
  |---|---|---|---|
  | 01 | zombie | 30 | flame, no drop |
  | 02 | bat | 31 | flame with drop |
  | 11 | black panther | 32 | erase |
  | 17 | Simon's subweapon | 33 | score popup |
  | 19 | Phantom Bat boss | 28 | candle (graphic `$27`) / brazier (`$28`) |
  | 2F | item on the ground | | |

- **lead:**
  - enemies: 03 fishman, 06 Medusa head, 08 axe knight, 0C fleaman (rides 12), 0F raven, 12 eagle, 14-16 bone dragon
  - bosses: 18 Death, 1A mummy, 1B Medusa, 1C Frankenstein, 1D Dracula, 1F Igor
  - 20-24 enemy projectiles
- **unknown:** 07, 0A, 0E, 10, 13, 1E, 34.

Handlers come from the inline table at `$E95C` (2 bytes per type; addresses below `$C000` are in bank 5).

**Spawning** (bank 7, **static**):
- `$F41F` finds a free slot: X = first slot, `$4B` = end (exclusive); returns X = `$FF` if none.
- `$F42C` creates type A in slot X; `$F447` does the same from spawner data.
- `$F48D`, bosses: runs once, clears 04-0D, always uses **slot 07**.
- `$EC88`: a shot aimed at Simon, in slot 0D or 0C.
- **Spawners:** 6 entries (`$0160` flags, `$0166` type, `$016C` state, `$0172` X, `$017E` Y, `$0184` timer).
  - `$F376` runs those whose X is in `$08..$F8`.
  - It dispatches through the 32-entry table `$F3DD` to mostly bank-6 routines, each with a fixed slot sub-range: zombies 04-06, fishmen 07-08, panthers 07-09, bats, Medusa heads and ravens 09-0B.
- **Spawn data:**
  1. `$D290 + 2 × stage` → area pointers (by floor `$46`).
  2. Each area has 2 bytes per 64-px column: a spawner index and a candle index.
  3. Both point through `$D6C6` (candles with bit 7 through `$D7C6`).
  4. Spawner entries are `[type, X, Y]`; candle entries are `[FF drop]? [FE]? X Y`.

  The loader is `$D1BE`.

## 8. Subweapons and items

**Subweapon throw** (**verified**):
- Up+B → `$FA26`, which needs hearts > 0, `$015B` ≠ 0 and `$015C` = 0.
- `$DA44` needs a free slot in `$14..$14+$64` and takes 1 heart (5 for the stopwatch).
- On attack frame `$11`, `$DA5F` (jump table on `$015B` − 8) creates type `$17` with kind `$0584`:

  | `$015B` | Subweapon | Kind | Behaviour |
  |---|---|---|---|
  | 08 | dagger | 0 | 4 px/frame; destroyed on hit |
  | 09 | cross | 1 | boomerang; pierces |
  | 0B | holy water | 3 | arc, then fire |
  | 0D | axe | 5 | arc |
  | 0F | stopwatch | 7 | sets `$0560` = `$FF` |

  **verified** The stopwatch object (`$DB21`) follows Simon's X and lasts `$B4` frames (8 in boss rooms), then unfreezes slots 4-`$0D` and erases itself; it keeps slot `$14` busy meanwhile. `$FA26` spawns it at once and returns C=0, so the original game swings the whip after using it.

**Item IDs** (`$0584` low nibble; each forced on a candle and picked up; **verified**). Pickup code `$E762`; graphic table `$EC0A`.

- **verified** Pickup dispatch (`$E762`, on ID AND `$0F`): 0 heart, `$0C` multiplier `$E801`, `$0A` rosary `$E7EB`, `$0E` potion `$E7D6`, 1 money `$E8A5`, 3 whip `$E88E`, 4 big heart `$E85E`, 5 pork chop `$E874`, 6 crystal `$E83A`; every other ID takes the subweapon branch `$E7AF` (`$79`, `$64` = 0, `$0141` = `$80`, `$015B` = ID, `$72` = 0, SFX `$18`). The branches end in `JMP $EC60`.
- **verified** Item frames (graphic → animation → frame, 2 sprites at y −8, x −8/0): dagger `$50` (BD/BB, flipped, palette 2), cross `$28` (52/54), holy water `$2B` (A1/A3), axe `$4C` (B7/B9, palette 1), potion `$2C` (42/44, palette 0), stopwatch `$2D` (89/8B), rosary `$72` (AD/AF), multiplier `$51` (A5/A7), whip upgrade `$6F` (C1/C3, palette 3). Table-1 item tiles come from tile set 3 (`b1:$A008 + 16 × pair`); the cross and potion tiles are table-0 raw tiles (`b1:$9008 + 16 × pair`).
- **verified** HUD subweapon icon: `b6:$A113` draws OAM 15-16 from `b6:$A151 + 3 × ($015B − 8)` = [attribute for both][left tile][right tile]; hidden while `$015B` = 0.
- **verified** Sprite palettes in play (all stages): 0 = `27 37 07`, 1 = `23 34 0F`, 2 = `37 11 0F`, 3 = `16 25 0F`.
- **static** Wall-block hidden items `b6:$AA4F` = `00 04 05 11 0C 07 0E 0E` (index from the block entry's bits 0-2).

| ID | Item | Effect |
|---|---|---|
| 00 | small heart | hearts +1 (max 99) |
| 01 | money bag | score popup; high nibble = colour/value |
| 03 | whip upgrade | `$70` + 1 |
| 04 | big heart | hearts +5 |
| 05 | pork chop | health + `$18` |
| 06 | magic crystal | full health, stage clear |
| 08 / 09 / 0B / 0D / 0F | dagger / cross / holy water / axe / stopwatch | `$015B` = ID; `$64` = 0, `$79` = 0 |
| 0A | rosary | screen flash (`$015D` = `$0F`) |
| 0C | double/triple shot | `$64` = 1 or 2 (only with 08/09/0B/0D; otherwise a money bag) |
| 0E | invisibility potion | `$5B` = `$B4` |

IDs 02 and 07 are unused junk items.

**Candle drops** (`$EB65`, **verified**):
- **Fixed drop:** given in the candle data (`FF dd`). A subweapon or whip drop is rerolled when the drop guard `$72` is set or when it equals the held subweapon.
- **Random drop** (`dd` = 0), in order:
  1. A multiplier, if `$79` (subweapon hits) ≥ 10.
  2. Otherwise a whip upgrade, if the hearts/whip rule allows it.
  3. Otherwise `$6F AND 1`: small heart or money bag.

**Enemy drops** (`$E097`, **static**):
- 1 in 8 (by frame counter) becomes a dropping flame; a big heart for types 03, 08, 0C, 0E, 12.
- When `($1A AND $0F) = 2`: a special drop from `$E138` (6 groups of 3 stages × 4 entries, indexed by `$7B AND 3`).

**Hooks for replacing power-ups:**
- the candle data bytes
- `$EC0A` (graphics)
- `$EBBD-$EBE9` (random branch)
- `$E0B7-$E0F3` / `$E138` (enemy drops)
- `$E762-$E7AF` (pickup dispatch)

## 9. Collision

All in bank 7, once per object from the object loop (`$EA77` → `$E4D9`).
- **Hitbox half-sizes** per type: `$E46A + 2 × type`. Examples: zombie `06,0E`, bat `06,06`, Phantom Bat `14,0A`, candle `06,06`.
- **Whip** (**verified**):
  - `$E3FF` builds the box on attack frame `$11` from slot 0, whip level `$70`, and the tables `$E45D/$E460/$E464`.
  - Damage `$E5D9`: 6/8/8 by whip level. On-hit handlers: table `$E579` (default `$E097` kill; candles `$E3D7`).
  - Boss HP: `$01A8/$01A9` −= damage at `$E3C0` (lead: `$01A9` = boss HP).
  - **verified** (commando bullets, `tests/explore/boss_fights.lua`) Every boss starts at `$01A9` = 64, and bosses scale the damage they take: damage units per 64 HP are 64 for the Phantom Bat, 127 for Medusa, Frankenstein, Death and Dracula's first form, 250 for the mummies, 253 for Dracula's second form. It is linear: a 6-damage rifle needs 11 hits on the bat and 22 on Medusa. The mummies' `$01A9` is the sum of their own HP in `$0584` (`$E3A8`). Dracula takes damage only through type `$04` (his head in form 1, also in form 2), not his body `$1D`. No invulnerability between bullet hits: 5 S bullets landing on consecutive frames all count.
  - Reaching the bosses for tests: warp to the stage (`$29`, `$18` = `$0C`, `$19` = 7), set `$46`/`$2F`/`$41` to the page before the boss lock `$FC5E[$28]` (high nibble = floor), `$18` = 5, `$19` = 0, then walk right: the boss is in slot 7 when `$48` = 1.
- **Subweapons** (`$E5EB`): box `$E5DF + 2 × kind`; damage `$E6A8 + 3 × kind`: dagger 6, cross 8, holy water `$40` sub-units per frame, axe 8. Each hit increments `$79`.
- **Enemy vs Simon** (`$E6BA`, **verified**):
  - Skipped while Simon is in state 5 or 8, or `$5B` ≠ 0, or type ≥ `$28`.
  - Box: |X difference| < type half-width + 4, and |Y difference| < type half-height + `$5F`.
  - **Damage depends on the stage, not the enemy:** 8 in stages < 7, `$0C` in 7-`$0B`, `$10` from `$0C` on or in the second quest.
  - **verified** Order: first the hit reaction `b6:$96C1` (through `$FC97`), then `$45` −= damage (`$E754`, skipped if `$45` is already negative). Health can underflow; zero or negative counts as dead in the stand handler `b6:$9380` and the knockback landing `$96A6`. Crouch, stairs and attack states don't check it.
- **Items:** a type `$2F` object goes to the pickup `$E762`, skipping the invincibility check.
- Contact kills: bats (`$02`), Medusa heads (`$07`) and `$0F` die on contact (`$E09A`); Medusa (`$1B`) calls `$EAA9`.
- Commando build hooks: `$E6D2` (the invincibility skip) and `$E718` (the contact damage) jump to bank 5 for B's barrier; the potion's `LDA #$B4 / STA $5B` at `$E7E4` runs with bank 5 mapped (`$E7DF` selects it).
- Stairs entry from stand/walk: `$93E9` tests Up/Down of `$F7`, then `$9C10` finds a staircase (`$9CBD`) and starts state 6 (walk to the first step) or 4.

## 10. Enemy targeting

All of it reads slot 0 (**verified** for bat and Medusa head, **static** for the rest):
- **Bat, Medusa head:** aim once, at spawn. They appear at the screen edge Simon faces, at Simon's Y (with an offset), then fly a sine wave without reading Simon again.
- **Fishman:** spawns at least `$28` px from Simon, then keeps turning to face him (`$EF7C`).
- **Phantom Bat:** waypoints relative to Simon (X ± `$48`, Y − `$28`), a dive at (X, Y + `$18`), and aimed shots through `$EC88`.
- Distance/facing helpers `$EF84`/`$EF7C` are used by types 03, 07-0A, 0C, 0E, 0F, 11, 13, 16, 18, 1A-1E.

## 11. Graphics

- **verified** PPUCTRL in play is `$B0`/`$B1`: **8×16 sprites**, background from table `$1000`. An even sprite tile comes from table `$0000` (sprites only); an odd one from `$1000`, shared with the background (flames, items, HUD box).
- **verified** **OAM layout** (page `$02`):

  | Entries | Use |
  |---|---|
  | 0 | sprite-0 marker for the status-bar split |
  | 1-6 | hidden (door leaves in the gate scene) |
  | 7-14 | HUD subweapon frame (4 sprites on lines `$17-$3A`, always) |
  | 15-16 | HUD subweapon icon |
  | 17-63 | 47 sprites for objects |

  **Flicker** comes from rotating OAM order: start offset `$78` += `$44` per frame, `$C4` per sprite.
- **verified** **Sprite drawer** `b0:$8052`:
  - For each slot not hidden, it reads `$0338`, `$0354`, `$038C`, `$0450` and `$031C`.
  - Frame pointer tables: `b0:$8FBE` (frames `$00-$7F`) and `b0:$90BE` (`$80-$FF`); data at `b0:$919C-$9B7F`.
  - Format: `N`, then N entries `[Ybyte][tile][attr, omitted if Ybyte bit 0 is set][Xoff]`. Y offset = Ybyte >> 1, signed. `$80 lo hi` = shared sub-list, `$81` = return.
- **verified** **Simon's frames:**

  | Frames | Pose |
  |---|---|
  | 01 | stand |
  | 02-04 | walk |
  | 05 | crouch/jump |
  | 06-08 | whip |
  | 09-0B | crouching whip |
  | 0D-0F | stairs |
  | 97 | hurt |
  | 98 | dead |
  | 99 | kneel |
  | A4-AC | whip on stairs |

  - Each frame is 3-4 sprites (16×32).
  - **All of Simon's frames use 28 tile pairs = 56 8×8 tiles** (table 0 pairs `02-1C, 22, 28, 2A, 32-3E, 4C, 4E, 5E, 6E`).
  - The whip (slots 1-2, frames `0C, 10-18`) uses 13 more pairs that Simon doesn't share.
  - Simon's tiles are stored **raw** at `b1:$9008` + 16 × tile.
- **verified** **Tile uploads to CHR-RAM:** `$FD23` (A = set) uses the 12-set table `$FDBB`. Records are bank / source / PPU destination / length, raw copies with the screen off.

  | When | Set |
  |---|---|
  | power-on | 0 |
  | after Start | 1 |
  | new game, demo start | 3 (base) |
  | each block | `$C8B0[$28]`: 0-3 → 3, 4-6 → 4, 7-9 → 5, `$0A-$0C` → 6, `$0D-$0F` → 7, `$10-$11` → 8, `$12` → 9 |

  **No uploads during play**: not at doors, at floor changes or at deaths.
  - Table 0 `$0000-$077F` (pairs `00-76`: Simon, whip, items) is fixed.
  - Table 0 `$0780-$0FFF` is per block (enemies, bosses).
  - Table 1 `$1900-$1FFF` is fixed (HUD, font, odd sprite tiles).
  - Records of the 12 sets are `[bank][source][PPU destination][length]`, ending with `$FF` (`$FDBB` → pointers). Set 1 (the intro) loads `b6:$B117` to `$11C0-$16DF`; no other set uses that data.
- **verified** **Intro back view:** frame `$19` (Simon from behind at the gate) uses the odd tiles 1D 1F 21 2F, i.e. table-1 pairs `$1C $1E $20 $2E` from set 1 (`b6:$B117`, `$B137`, `$B157`, `$B237`). No other set has those tiles there.
  - **verified** The rest of set 1 is the intro's background: the intro BG uses table 1, and its nametables reference every tile `$30-$6D`. Sprite tiles in the intro: 1D-2F odd (back view, bats), table-0 tiles of the walk frames, 9D, FB-FF. Only `$1C-$2F` of set 1 is free of BG use.
  - **verified** Set 1 is uploaded by `JSR $FD23` at `b6:$B928` (A = 1) in the intro setup (bank 6 mapped). `$FD23` turns NMI and rendering off (`$C132`), copies each record with `$FD7E` (`$00/$01` source, `$02/$03` PPU address, `$04` length high, `$05` low), restores the bank and sets PPUCTRL `$B0` (`$C102`). The commando build calls its own upload first, to table-0 pairs `$E0-$EA` (no set writes `$0E00-$0FDF` before block 4).
- **verified** **Free sprite tiles:**
  - Stages 0-3: 21 pairs (`00`, X-placeholder pairs `78 7A 7C 7E B6`, and `E0-FC`, which are never written).
  - Later blocks: only 2 pairs.

  New sprite graphics therefore have to reuse existing tiles: Simon's 28 pairs, and the whip's 13 if the whip goes.
- **verified** (static, frame table) **Item and subweapon tiles that only their own frames use:**
  - table 1: A3 (holy water 2B), B9 (axe 4C-4F), C3 (whip upgrade 6E, 6F; 6E is a copy of 6F), AF (rosary 72), BB (dagger 50), A5/A7 (multiplier 51); table 0: 44 (potion 2C), 54 (cross 28/29), 4A (thrown cross 27). Frames 94/96 also use 44/4A/54, but they are title-screen frames drawn from set 0's tiles.
  - Thrown subweapon frames: dagger 50, cross 27-29, holy water 25 (bottle) and 5A-5E (flames: tiles 91-99, shared with the burn flames 2E-30, 55, 56, 7F-81, 8C-8E), axe 4C-4F.
  - Sprite palettes are the same in every stage ($3F10: `0F 27 37 07  0F 23 34 0F  0F 37 11 0F  0F 16 25 0F`).
- **verified** **Sprites per scanline:**

  | Where | Max on one line | Frames with more than 8 |
  |---|---|---|
  | stage 1 | 18 | 22% |
  | STAGE 12 demo | 17 | 12% |
  | other demos | 11-12 | 2-5% |

## 12. Camera

- **verified**
  - **Scroll registers:** `$2E` = scroll pixel, `$2F` = page, `$2D` = subpixel.
  - **No dead zone:** Simon is pinned at screen X `$80` while the camera scrolls at his speed (`b6:$9809-$9964`); `$3C` bit 2 = camera locked.
  - **Page limits** per stage and floor: `$FBB0` (right) and `$FBC3` (left), high nibble = floor 0; read by `$D015/$D025`.
- **verified** **Boss lock:** `b6:$9967` sets `$48` = 1 when the camera reaches `$FC5E[$28]` (stages 3, 6, 9, `$0C`, `$0F`, `$12`).
- **verified** **Stairs between floors:** `b6:$9FF3` changes `$46` when Y reaches `$30`/`$D0`. The screen blanks and both nametables are redrawn (~18 frames); the horizontal scroll is kept. **No vertical scrolling in play.**
- **verified** **Stage exits:** `$FC12[$28]` → `$18` = 8; auto-scroll, walk through the door, `INC $28`. The courtyard gate uses `$18` = `$0A`.

## 13. Level data and terrain

The lead came from CadEditor (github.com/spiiin/CadEditor, MIT): its `settings_nes/castlevania` config describes stage 1 only and targets the European ROM. Bank 4 is identical in both versions. The tables below extend it to every stage. Decoder: `tools/level_data.py` (`map` prints a stage's terrain, `check` compares with the explore logs).

- **verified** **Layout:**
  - `$FB23 + 2 × stage` → floor table; `+ 2 × floor` → pointer L (`$CFF9` copies it to `$33/$34`).
  - Screen data is in bank 4, column-major: 6 metatile numbers per 32-px column.
  - Camera page p shows columns 8p to 8p+7, counted from L + 24. Columns 0-3 behind L are never shown: the courtyard's L is `$7FF2`, below the ROM.
  - Floors can share columns with the next floor's data (stage 1 ends 24 bytes into stage 2 floor 1).
- **verified** **Metatiles:**
  - `$F9FA + 2 × stage` → blockset B. Stages share sets: 0-3, 4-6, 7-9, 10-12, 13-15, 16-17, 18.
  - Metatile m is 17 bytes at B + 17m: an attribute byte, then 4×4 tile ids, row-major.
  - Metatile row 0 starts at nametable row 4, and its top two tile rows stay under the HUD (the column writer skips them, `$F788`).
  - Writer: `$F69E`, which computes the offset as 6 × column `$35/$36` + row − 1.
- **verified** **Terrain comes from the tiles:**
  - `$F9D4` turns each tile id the writer draws into a 2-bit code: `$60-$6B` → 1, `$66` → 2 (part of the brick floor), anything else → 0.
  - Simon's wall check (`b6:$9ECE`, lookup `$F9A0`) stops on any non-zero code.
  - RAM buffer: `$05A0 + $B0 × ((page + $FBD6[stage]) & 1)`. Each 8-px row from screen Y `$30` to `$DF` takes 8 bytes, 2 bits per 8×8 cell, with the leftmost cell in the top bits.
  - **Editing the metatile numbers or a blockset changes the graphics and the terrain together.** No separate collision table needs patching.
  - Tested: a scratch ROM with metatile `$37` written into courtyard column 3, rows 2-4. The game built a wall at x 96-127 in its terrain buffer, and `lvl_starts.lua` on that ROM matched the decoder 14,080 of 14,080.
- **verified** **Page limits** `$FBB0` (right) / `$FBC3` (left): left nibble `$F` means page 0, otherwise nibble + 1.
- **Checks:**
  - The decoder matched every terrain cell of the full fly-through (`tests/explore/lvl_flythrough.lua`): 78,144 of 78,144 cells over all 35 recorded stage/floor maps. Floors 1 of stages 3, 9 and `$0C` don't exist.
  - It also matched the nametable tiles and terrain at ten stage starts (`lvl_starts.lua`): 14,080 of 14,080.
- **static** The European fixed bank is shifted (section 16), so the table addresses above are for the USA version only.
- Not decoded yet: stairs (separate tables), breakable blocks (spawner/candle data, section 7), palettes per stage.

## 14. Free space

**verified** by three methods:
- no executed instruction references these regions
- a read watcher on all 294 ROM-reading instructions
- overwrite tests: everything below overwritten at once with `$00`, then `$EA`, left a 50,000-frame session and a 9,000-frame attract run identical

| Bank | Usable | Must stay as is |
|---|---|---|
| 0 | `$BB01-$BFFF` (1279) | |
| 1 | `$BD08-$BFFF` (760) | lead: `b1:$9E08-$9FE7` (480 bytes of placeholder tiles) is never uploaded |
| 2 | `$BD08-$BFFF` (760) | `$BCE8-$BD07` (tiles for stages 13-15) |
| 3 | `$BF08-$BFFF` (248) | |
| 4 | `$B408-$B8C5`, `$B8D7-$BAC3`, `$BAD5-$BFFF` (3030) | `$B8C6-$B8D6`, `$BAC4-$BAD4` (read at every map screen) |
| 5 | `$9E49-$BFFF` (8631) | `$9E47-$9E48` (read by the third demo) |
| 6 | `$BA3C-$BFFF` (1476) | `$BA3B` (table terminator) |
| 7 | `$FF2A-$FFF9` (208, contiguous: `$FF` and leftover filler) | vectors `$FFFA-$FFFF` |

- Bank 7's `$00` runs at `$D46E`, `$D59A`, `$D5F4` and `$FBC8` are inside data tables and are not free.
- Bank 0 `$B501-$BB00` is the title screen's sprite tiles.
- Caveat: rare events not covered by the session (ending, second quest) could still read a "free" byte.
- **verified** **RAM:** `$0100-$012F` and `$01B2-$01E1` were never written in the 50,000-frame session (write watch on page 1). The stack reached down to `$01E2`, so keep new variables near `$01B2`. The commando build uses `$01B4-$01B5`.

## 15. Testing notes

- `emu.speedmode("maximum")` gave false differences when several FCEUX instances ran at once; `"nothrottle"` is deterministic and as fast. The Castlevania tests use `"nothrottle"`.
- Added CPU time changes the RNG (section 3), so compare behaviour, not frame-exact traces, for hacks that add per-frame work.
- **Explore scripts** (`tests/explore/`, run with `scripts/run_fceux.py`; each has a header comment):

  | Script | What it covers |
  |---|---|
  | `bank_session.lua` | the shared 50,000-frame scripted session |
  | `bank_writes.lua` | bank writes, state changes, idle cycles |
  | `bank_exec_cov.lua` | where code runs |
  | `bank_budget.lua` | idle cycles and lag |
  | `bank_poison.lua` | per-frame trace for overwrite tests |
  | `bank_readwatch.lua` | reads into free-space candidates |
  | `bank_input.lua` | controller bits |
  | `sim_ram.lua` | Simon's RAM checked by behaviour (25 checks) |
  | `sim_warp.lua` | stage warp |
  | `sim_coverage.lua` | coverage of the gameplay frame |
  | `sim_writers.lua` | writers of Simon's RAM |
  | `obj_slots.lua` | slot survey |
  | `obj_items.lua` | every item ID forced and picked up |
  | `obj_collide.lua` | collision hooks |
  | `obj_subweapons.lua` | every subweapon thrown |
  | `obj_warp.lua` | types per stage |
  | `gfx_ppu_writes.lua` | PPU writes and uploads |
  | `gfx_oam_survey.lua` | tile use, sprites per line, dumps |
  | `gfx_frame_viewer.lua` | forces a frame on slot 0 |
  | `gfx_camera_trace.lua` | camera, doors, boss lock |
  | `lvl_flythrough.lua` | terrain map of every stage and floor (check with `tools/level_data.py`) |
  | `lvl_starts.lua` | nametables and terrain at ten stage starts (same check) |
  | `cmd_soak.lua` | commando build: a bot fires through every stage 1-18 (shots, hits, blocks, lag, hangs) |
  | `boss_fights.lua` | commando build: warps to each boss, a bot fights it with every weapon, logs hits and HP (balance; `boss_replay.py` replays the logs under any damage table) |

## 16. European version (PAL, PRG CRC32 `A93527E2`): port notes

Not supported by the build. Compared with the USA V1.1 PRG on 2026-11-17:
- Banks 0-4 are byte-identical.
- Bank 5 matches 54% at the same offsets (the largest matching part sits 40 bytes earlier in the USA version).
- Bank 6 matches 85%. Example: the code that writes `$0028` is 18 bytes later in the USA version (`$B911/$B97E/$B864` in the European one).
- Bank 7 matches 32% at the same offsets; most of the rest is the same code shifted by −7 to −12 bytes (`$E44E` European = `$E442` USA).
- The RAM addresses checked so far behaved the same.
- `tests/t_boot.lua` passes on the European ROM with PAL timing.

## 17. Open questions

- Boss AI was not covered by coverage runs; bosses may read Simon in other ways.
- Not reached: the ending, the second quest, and the late parts of most stages.
- The names of several object types (section 7); money-bag score values; `$5C`; `$04C0` for slot 0.
- When tile sets 2, 10 and 11 run in a real game (static callers only).
- Free tiles in table 1 usable by odd sprite tiles (needs per-stage nametable use).
