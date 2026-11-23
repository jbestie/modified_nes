# Castlevania (NES, USA)

Mods for *Castlevania* (NES, USA revision 1 / "V1.1", mapper 2 / UNROM,
128 KiB PRG, CHR-RAM). This folder has only source, tools and
documentation. **No ROM is included.** Bring your own dump.

This is one game of a multi-game repository (see the [top-level README](../../README.md)).
Paths below are relative to this folder; shell commands run from the repository root.

## Status

- **Commando** (item 2 of [TODO.md](TODO.md)): milestones M1-M3 of [docs/commando-estimate.md](docs/commando-estimate.md) are playable, with the commando's look and the falcon letters from your own Super C dump (below).
- The engine map: `notes/addresses.md` (item 0).
- A practice overlay for FCEUX (below).
- A level decoder for every stage (below).
- Item 1 (co-op) is parked.

## Commando

Milestones M1-M3 of [docs/commando-estimate.md](docs/commando-estimate.md) are in: run-and-gun, aiming, prone, steering in the air, the somersault, Super C's jump, Super C's weapons and pickups. Of M4: a faster bullet routine, Super C's bullet sprites for every weapon, and the intro's back view.

Two ROMs come out of it:

| ROM | What it is | Share it? |
|---|---|---|
| `build/private/castlevania-commando-superc.nes` | **The one to play.** The commando's graphics and the falcon letters are imported from your own Super C (USA) dump | **No.** It contains Super C graphics and stays on your machine (`build/` is ignored by git) |
| `build/castlevania-commando.nes`, patch `dist/castlevania-commando-mechanics.bps` | The same rules with Castlevania's graphics: Simon's frames, bullets show the dagger, pickups show the old items (dagger = M, cross = S, holy water = L, axe = F, whip = R, potion = B) | The BPS patch, yes: it holds only this repository's code |

```sh
make GAME=castlevania                 # both ROMs (the private one if your Super C dump is in rom/) + the BPS patch
make GAME=castlevania art             # only the private ROM; SUPERC="path/to/Super C (U).nes" if it isn't in rom/
make GAME=castlevania art ART_FLAGS="--colours p1"   # Super C's player-1 colours instead of the blue commando
make GAME=castlevania checkpoint NAME=<name>         # keep a copy in build/private/checkpoints/
```

**Checkpoints** (ready-to-run ROMs in `build/private/checkpoints/`):

| File | State |
|---|---|
| `castlevania-commando-m2a-aiming.nes` | 8-way aiming, Select for the subweapon, air control, somersault, firing poses |
| `castlevania-commando-m2b-prone-stairs.nes` | Adds prone, the diagonal-down run, and shots along the stairs |
| `castlevania-commando-m2c-superc-jump.nes` | 2b with Super C's jump (test variant) |
| `castlevania-commando-m3a-fast-bullets.nes` | 2b with the new bullet routine: 4 bullets, almost no lag |
| `castlevania-commando-m3b-fast-bullets-back-view.nes` | Adds the commando's back view in the intro (top-down frame) |
| `castlevania-commando-m3b-superc-jump.nes` | 3b with Super C's jump (test variant) |
| `castlevania-commando-m4a-weapons.nes` | Super C's weapons and falcon pickups, Super C's jump, no subweapons, a drawn back view |
| `castlevania-commando-m4b-bullet-sprites.nes` | Super C's bullet sprite for each weapon (the laser along its direction), the back view redrawn at the commando's height |
| `castlevania-commando-m4c-damage.nes` | Super C's damage ratios with S and L capped: rifle, M, F and fragments 6, S 3, L 4, charged F 30 |
| `castlevania-commando-m4d-barrier-stairs.nes` | B is Super C's barrier (8.5 s, enemies that touch you die); Up/Down climbs stairs only after 16 frames without B (**latest**) |

**Controls:**

| Input | On the ground | In the air | On stairs |
|---|---|---|---|
| B | shoot forward | shoot forward | shoot forward |
| Up+B | shoot straight up; while walking, diagonally up | straight up; with Left/Right, diagonally up | up along the steps |
| Down | prone (Down alone); Down + Left/Right walks aiming diagonally down | Down+B shoots straight down; with Left/Right, diagonally down | down along the steps |
| Left/Right | walk | steer: turn or start moving (Super C air control) | climb |
| Up/Down at a staircase | steps onto it after 16 frames held with no B (while you tap or hold B you stay on the floor and shoot) | | |
| Select | nothing (no subweapons) | | |

**Weapons** (Super C's rules; the letters replace Castlevania's items in every candle and drop):

| Pickup | Was | What it does |
|---|---|---|
| (none) | | Rifle: one shot per press, 4 on screen, 4 px/frame |
| **M** | dagger | Machine gun: holding B fires every 7 frames, 6 on screen |
| **S** | cross | Spread: 5 bullets per press in a 45-degree fan |
| **L** | holy water | Laser: 5 segments 8 px apart; a new press restarts it, holding B refires when it's gone |
| **F** | axe | Fire: 5.5 px/frame, 2 on screen; bursts into 4 fragments on a hit. Hold B 32 frames and release for a charged ball (8 fragments, more damage) |
| **R** | whip upgrade | Faster bullets: 5.5 px/frame (F: 7.0); not for L. A new weapon ends R |
| **B** | potion, stopwatch | Super C's barrier: 510 frames (8.5 s; Super C 512) of invincibility, and enemies that touch you die. Bosses are spared, as in Super C |
| falcon | rosary | Clears the screen (the rosary's effect) |

The weapon and R end when you die. Hearts are only a counter now. The HUD box shows the weapon's letter.

**Bullet sprites** (private ROM; Super C's own, from your dump, in Castlevania's orange sprite palette): rifle dot, M ring, S ball, the laser as a line along its direction (horizontal, vertical or either diagonal), F a 16 x 16 fire ball, the charged shot a 24 x 32 one. F's fragments use the S ball: Super C's 16 x 16 ball for every fragment cost about 20 more lag frames per 1,200 under constant fire in stage 12.

**Rules:**
- Bullets have their own routine. It runs in time the game used to waste waiting for the status-bar split, so shooting adds almost no lag.
- **Damage:** Super C's ratios (every bullet the same, the charged ball 5 times that) at the dagger's 6, with the outliers capped: rifle, M, F and fragments 6, S 3 per bullet, L 4 per segment, charged F 30 (Castlevania units: the whip does 6-8). Uncapped, S's 5 bullets and L's 5 segments all hit a big boss and killed bosses 2.6-8.2 (S) and 1.1-2.8 (L) times faster than the rifle; capped they are 1.1-2.1 and 0.9-1.9 times as fast. Measured with a boss bot in all 6 boss fights (`tests/explore/boss_fights.lua`, `boss_replay.py`). Bullets break the hidden wall blocks and don't freeze bosses or tough enemies.
- **Super C's jump:** 58 px high and 56 frames (Simon: 36 px, 40). The wall check doesn't probe at head height during jumps, so low ceilings don't stop a jump (stage 5, floor 1). On every stage's map no jump is lost; 14 shortcuts open. Stage 6's spike crushers (instant kill) are harder to time with it; kept on purpose.
- **No knockback.** A hit costs health and gives the usual blinking invincibility. At zero health you die where you stand.
- **Prone** shrinks your contact box (half-height `$04` instead of crouching's `$0A`), so shots at chest height pass over you. Enemies walking on the floor still hit.
- The title screen no longer starts attract demos (their recorded input would desync).

**Intro:** at the castle gate the commando is seen from behind: an original 16 x 48 drawing (Super C has no such pose), in `tools/commando_art.py`. He is 33 px tall like his side view (the first drawing was 29 px), feet on the walk frames' line. Its 6 tiles don't fit the intro's own tile set (the castle and the gate use the rest), so the intro uploads them to table-0 tiles that nothing uses before block 4.

**Not in yet** (milestone M4):
- a full human play-through of all 18 stages (the bot has run the ending, the credits and the start of the second quest: `tests/explore/boss_fights.lua` with `ENDING`)

**Easy mode, as is:** bosses go down quickly with these weapons (your playtest of 4c). That suits an easy mode; a normal mode would lower the damage table (see the remix title menu in [TODO.md](TODO.md)).

**Testing:**
- A bot soak (`tests/explore/cmd_soak.lua`) fires through every stage without hangs; lag on the private ROM is 0-3 of 1,200 frames, 18 in stage 12 (the busiest stage). Under constant fire in stage 12 (a walking, jumping bot): rifle 0, M 7, S 54, L 58, F 31 of 1,200.
- `tests/t_commando.lua` makes 42 behaviour checks on both ROMs, including every weapon, its sprite, two pickups, the barrier, the stairs rule and the intro's back view. The original ROM fails 39 of them (negative control).
- `tests/explore/boss_fights.lua` with `ENDING`: Dracula, the crystal, the ending and credits, then the commando's moves in the second quest. `tests/t_jump_superc.lua` checks the jump's arc and the stage 5 jump.

## Practice overlay

In FCEUX, load the ROM, then *File > Load Lua Script* > `games/castlevania/tools/overlay.lua`.
- **Display:** stage, Simon's position and state, health, hearts, whip, subweapon, invincibility and lag frames. In stage play it also draws the collision boxes the game uses: Simon green, enemies red with their type number, candles white, the whip yellow on its hit frame, subweapons cyan.
- **Keys:** H boxes on/off, I infinite health/hearts/time (pits still kill), N next stage, V previous stage.
- **Warp:** it uses the game's own stage-start code, so every stage's graphics load correctly.

## Level data

`tools/level_data.py` reads the level layout, the tiles and the terrain of any stage and floor from your ROM. The terrain is built from the tiles, so a layout edit changes both. Format and checks: `notes/addresses.md` section 13.

```sh
python3 games/castlevania/tools/level_data.py games/castlevania/rom/original.nes map 05 1   # stage 5, floor 1
```

## Input ROM

| Item | Value |
|---|---|
| Version | USA, revision 1 ("V1.1"). Revision 0 and the European (PAL) version have a different PRG and are **not** accepted |
| PRG CRC32 | `B668C7FC` |
| Known file | `12A6CB14`: NES 2.0 header, NTSC ("Castlevania (U) (V1.1) [!]") |

```sh
cp "/path/to/Castlevania (U) (V1.1) [!].nes" games/castlevania/rom/original.nes   # or a symlink
make GAME=castlevania           # checks the input, builds the commando prototype
make GAME=castlevania test      # build + all FCEUX tests (about 15 s)
make GAME=castlevania layout    # regenerate notes/rom_layout.md
```

The European version differs only in banks 5-7. `notes/addresses.md` has the comparison, which is useful for a later port.

## Folder layout

```text
TODO.md                 investigation backlog: extra player, Super C hero, other ideas
game.py                 game definition: expected ROM, header variants, build targets, patches
game.mk                 make defaults: PATCH, the art and checkpoint targets (SUPERC, ART_OUT, ART_FLAGS, NAME)
run_tests.py            test suite -> tests/out/summary.txt
src/commando/           commando mechanics (commando.asm) and Super C's jump (jump_superc.asm)
tests/cv.lua            helpers for the Lua tests (input, logging, screen samples, ROM header)
tests/t_boot.lua        boot smoke test (timing follows the ROM header's region)
tests/t_overlay.lua     practice overlay test
tests/t_commando.lua    commando: 37 behaviour checks
tests/t_jump_superc.lua Super C jump: arc, stage 5 low-ceiling jump
tests/explore/          investigation scripts behind notes/addresses.md (listed there)
tools/overlay.lua       practice overlay for FCEUX
tools/level_data.py     level layout, tile and terrain decoder
tools/commando_art.py   installer: the commando's graphics from your own Super C dump (output stays private)
docs/commando-estimate.md  deep estimate: Super C commando replacing Simon
spikes/run-and-gun/     proof of concept: B fires while walking/jumping/climbing (patch + test; not a build target)
spikes/graphics/        proof of concept: importer for the commando graphics from your own Super C dump (no Super C data here)
notes/rom_layout.md     header, checksums, bank map, raw free-space scan (generated)
notes/addresses.md      engine map: states, banks, CPU budget, Simon, objects, items, collision, graphics, camera, free space
rom/original.nes        your dump (not committed)
build/, dist/           generated ROMs (not committed) and the distributable patches
```

## Adding a patch

1. Write `src/<name>.asm`. Use `.bank`/`.org`, and give every block an `.expect` with the original bytes it replaces. See `src/commando/` for an example.
2. Add the target to `TARGETS` in `game.py`, and a BPS patch to `PATCHES` if it should be distributed.
3. Run `make GAME=castlevania`. The build fails if any preimage doesn't match.
4. Add a Lua test under `tests/` and a `record(...)` line in `run_tests.py`.

## Legal

Castlevania © Konami. This project distributes only original patch code,
tools and documentation. Do not commit or share ROM images; the repository's
`.gitignore` excludes `*.nes`, `rom/` and `build/`.
