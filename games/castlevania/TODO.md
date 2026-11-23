# Castlevania: investigation TODO

Status 2026-11-17. This is the backlog of questions to answer before building anything, for the USA V1.1 base.

Each investigation ends with a written verdict in `notes/`:
- an effort breakdown per subsystem
- the risks
- a go / no-go recommendation

The sizes below are **guesses made before any investigation**. They come from general NES knowledge and from what the Ghosts'n Goblins hack took. Each investigation replaces its guess with a breakdown.

Sizes, in focused work in this repo's style (trace, patch, automated FCEUX tests):

| Size | Effort |
|---|---|
| S | up to 1 day |
| M | 2-5 days |
| L | 1-3 weeks |
| XL | more than a month |

| # | Item | Guess | Needs | Status |
|---|---|---|---|---|
| 0 | Engine map (groundwork for 1 and 2) | M | — | **done** (2026-11-17): `notes/addresses.md`, `tools/overlay.lua` |
| 1 | Extra player: effort estimate | S-M (cheap variants) to L-XL (full co-op), revised after item 0 | 0 | **parked** (2026-11-17): too many single-player assumptions; see item 0 results |
| 2 | Super C characters and bonuses replacing Simon | estimated: MVP ~15.5 days, full commando ~38 (22-62) | 0, asset decision | **M1-M3 playable** (2026-11-19), estimate in [docs/commando-estimate.md](docs/commando-estimate.md): run-and-gun, 8-way aiming, prone, air control, somersault, Super C's jump, Super C's weapons (M S L F R B) and falcon pickups, no subweapons, no knockback, bullets break blocks, no boss stun-lock, commando art from your own Super C dump. Next: M4 (balance, polish, full play-through) |
| 3 | Other ideas | see the list | mostly 0 | to discuss |

## Item 0 results and what they change (2026-11-17)

The full map is in `notes/addresses.md`. The practice overlay is `tools/overlay.lua` (hitboxes, state, lag counter, infinite mode, stage warp). The facts that move the estimates for items 1 and 2 are below; the sizes are still guesses until those investigations run.

**For item 1 (extra player):**
- **Input is ready:** controller 2 is already read every frame into `$F6/$F8`, and nothing uses it.
- **Simon is hard-wired to one player:**
  - 229 absolute references to slot 0 and Simon's variables inside his update, about 150 more in enemies, collisions, items and the HUD
  - input read only from pad 1
  - the whip in fixed slots 1-2

  Copying the code is out. The realistic route is a **context swap**: save slot 0 and Simon's ~45 state bytes, load player 2's copy with pad 2 mapped onto pad 1, call the update `b6:$934C`, then swap back. The cost is roughly 1,500-2,000 cycles per frame. The median idle time is ~9,000 cycles, but the busiest frames have almost none, so expect some extra lag frames.
- **Collision** (`$E6BA`, the whip box `$E3FF`) checks only slot 0. Damage to player 2 and player 2's whip hits need their own pass, either by running those routines a second time under the swap or with small hooks.
- **Camera:** it pins Simon at screen X `$80`. Floor changes redraw the whole screen, so both players must stay on one floor: player 2 leashed to the screen and teleported to player 1 at floor changes, doors and stage exits.
- **Room:** slots `$17-$1B` are free outside the platform/debris stages and are drawn by the sprite drawer. That's enough for player 2's whip pieces. Sprite flicker is already high (22% of stage-1 frames have a line over 8 sprites), and another hero adds 4-6 sprites.
- **HUD:** there's one health bar. The enemy bar is only needed in boss rooms, so it could show player 2's health outside them.
- **Revised guesses:** alternating 2P S-M; helper player 2 M; full co-op **L** for a prototype by context swap, **XL** polished (bosses, stairs, stage events).

**For item 2 (Super C hero):**
- **Graphics are a data swap:**
  - Simon's frames use 28 tile pairs. Together with the whip's 13, that's 82 8×16 tiles in the **fixed** part of the sprite table (`$0000-$077F`), loaded raw from `b1:$9008` and never changed by stage loads.
  - A commando drawn in those tiles needs no per-stage budget. Later stages have only 2 free pairs, so the commando must fit in those 41 pairs.
  - The metasprite format and tables are known (`b0:$8FBE`).
- **Shooting:** the subweapon system already handles up to 3 projectiles with the double/triple multiplier, plus collision. A Super C spread of 5 needs 2 more slots (`$17-$1B`) and a wider projectile collision loop (`$E5EB`).
- **Bonuses:** drops, pickups and their graphics are fully mapped. Item IDs 02 and 07 are unused. The subweapon IDs could become Super C weapon letters, with hearts as ammo or removed.
- **Unchanged:** the asset question (below) still needs a decision before any graphics work.
- **Revised guesses:** looks only M; shooting M-L; weapons and bonuses M on top; full moveset XL.

## 0. Engine map (groundwork)

Items 1 and 2 need the same facts, so trace them once. Each fact goes into `notes/addresses.md`, tagged verified or lead.

- **Player:** RAM for Simon's state:
  - position, speed, facing, animation and state (walk, jump, stairs, hurt, death)
  - health, hearts, whip level, subweapon, double/triple shot, invulnerability timer

  Also: which routine updates Simon every frame, and in which bank.
- **Objects:** the object table layout and slot count. Which slots hold enemies, subweapon projectiles, items and effects, and how spawning works.
- **Input:** does the game read controller 2 at all?
- **Collision:**
  - player vs enemies and projectiles
  - whip vs enemies
  - subweapons vs enemies
  - item pickups
- **Graphics:**
  - sprite size (8×8 or 8×16)
  - how Simon's metasprites (multi-tile sprite layouts) are stored
  - which tiles are uploaded to CHR-RAM, and when
  - how many sprite tiles are free in each stage
- **Camera:** horizontal scrolling, stairs between floors, doors, boss-room locks.
- **Frame budget:** lag frames per stage today (how much CPU time is left).
- **Banks:**
  - where code and data live
  - how the game switches banks, and which banks are safe to switch to on boards with bus conflicts (the Ghosts'n Goblins lesson: only one extra bank was usable)
  - real free space (the candidates are in `notes/rom_layout.md`)
- **Prior art:** public RAM maps and disassemblies of the USA version. Use them as leads, and verify every fact we rely on.
  - Found: the [Data Crystal RAM map](https://datacrystal.tcrf.net/wiki/Castlevania_(NES)/RAM_map) (detailed; revision not stated).
  - No public disassembly of Castlevania 1 was found.
  - A [Super C disassembly](https://github.com/cyneprepou4uk/NES-Games-Disassembly) exists, which is useful for item 2.

Method: FCEUX Lua execution and write hooks, `scripts/dis6502.py`, and RAM diffs between runs. Small Lua tools go in `tests/explore/`. A hitbox/RAM overlay would also be useful later for streams.

## 1. Extra player: effort estimate

NES Castlevania is single-player. Three variants need separate estimates:

| Variant | What it is | Guess |
|---|---|---|
| a. Alternating 2P | Players take turns, switching at each death, as in many NES games. Mostly menu work plus a saved state per player. | S-M |
| b. Helper P2 | Controller 2 drives a light companion, for example a floating spirit that throws the current subweapon. No platforming, so no camera or stairs problems. | M-L |
| c. Full co-op | A second hero (Simon, or Bill/Lance from item 2) with full movement, whip, stairs, damage and death. | XL |

For variant c, the investigation must answer:
- **Player code:** is it written for one fixed RAM block, or indexed by object slot? A fixed block means duplicating or rewriting the code.
- **Room:** are there free object slots and RAM for a second player state?
- **Camera:**
  - who drives the scroll
  - how far apart the players may be
  - what happens at stairs and doors that move to another floor or room
- **Sprites:**
  - the NES draws 8 sprites per scanline and 64 in total; how much flicker is there already with enemies?
  - is CPU time already short (lag frames)?
- **Targeting:** enemies and bosses that aim at "the player" (Medusa heads, bats, boss attacks): which player do they aim at?
- **HUD and rules:** a second health bar, hearts, lives, game-over rules.
- **Stage events:** boss doors, the stage-clear sequence, cutscenes.
- **ROM space:** room for hooks in the fixed bank 7 (no free run over 39 bytes), and code in a switchable bank or a 256 KiB expansion like the Ghosts'n Goblins remix.

Deliverable:
- days per subsystem for each variant
- the risks
- a recommendation
- a first proof-of-concept milestone, for example "P2 visible and walking in stage 1"

## 2. Super C characters and bonuses replacing Simon

Goal: a Super C commando replaces Simon. That means the commando's looks, run-and-gun shooting, and Super C weapon pickups instead of Castlevania's items. Each layer gets its own estimate:

| Layer | What it is | Guess |
|---|---|---|
| a. Looks only | Commando sprites replace Simon's in all his animations (walk, jump, crouch, stairs, hurt, death); the whip becomes a muzzle flash. Depends on the tile budget and the metasprite format. | M-L |
| b. Shooting instead of the whip | B fires bullets as projectile objects, possibly reusing the subweapon slots. Aiming up or diagonally is new to this engine and must coexist with stairs. | L |
| c. Weapons and bonuses | Falcon capsules drop from candles and map onto bullet types: spread (like our Ghosts'n Goblins spread), laser, fire, rapid fire, and the barrier as timed invulnerability. Hearts and subweapons are removed or repurposed. | M-L on top of b |
| d. Full Super C moveset | Somersault jump, lying prone, run speed. Castlevania's levels are built for Simon's movement, so this adds little. | XL |

Also to check: balance. The stages assume a slow melee hero with knockback, so a ranged hero makes some fights trivial (enemy HP, boss HP).

**Asset question (decide before any graphics work):**
- **The constraint:** this repo distributes patches only, never game data. Super C's graphics are Konami data inside a different ROM, so a Castlevania BPS patch can't carry them. Super C uses mapper 4 (MMC3) with CHR-ROM; check this on the actual dump.
- **Option 1, import step:** a script copies the tiles from your own Super C dump at build/install time. That needs two input ROMs, a patch plus a script, and a Super C dump in `games/castlevania/rom/`.
- **Option 2, new art:** original pixel art in a commando style. No third-party data, but real art work.
- **Option 3, placeholder:** a recoloured Simon, so the mechanics can be tested first.

Deliverable:
- the tile and metasprite budget
- days per layer
- the recommended asset path

## 3. Other ideas to discuss

These aren't scheduled. Pick the ones worth an investigation.

| Idea | What a player or viewer gets | Guess | Notes |
|---|---|---|---|
| Practice tools (Lua) | Hitbox overlay, stage select, infinite hearts, lag counter | S | Speeds up items 0-2 too |
| Chat chaos mode | Viewers grant subweapons, hearts or whip upgrades, freeze time, apply colour curses | S-M | Reuses the Ghosts'n Goblins chat bridge; Lua only; needs the RAM map |
| Remix title menu | Start stage, difficulty, starting whip and subweapon | M | Like the Ghosts'n Goblins remix; needs a hook in bank 7. For the commando: the current damage table plays as an easy mode (user, 2026-11-23); a normal mode would lower it (`tests/explore/boss_replay.py` gives the boss kill times for any table) |
| No knockback, air control | Hits no longer throw Simon back into pits; jumps can be steered | M | The classic quality-of-life request; physics routine |
| Subweapon cycling on Select | Keep every collected subweapon and switch between them | M | Like the Ghosts'n Goblins weapon cycling |
| Spread subweapons | Daggers and axes fan out | M | Contra flavour with no asset issue; same approach as the Ghosts'n Goblins spread |
| Boss rush | Bosses back to back | M-L | Needs the stage loader |
| Randomizer | Candle drops and subweapons shuffled per seed | M-L | Data tables in banks 0-6 |
| Level remix | New or harder layouts built from each stage's existing tiles | S-M per stage | Format decoded for every stage, and the terrain follows the tiles (`notes/addresses.md` section 13). CadEditor could edit them visually if we generate its configs |
| Hard mode from the start | The second quest without beating the game first | S | Find the loop flag |
| European port | Every patch also for the PAL version | S-M per patch | Banks 0-4 are identical (`notes/addresses.md`) |

## Proposed order

1. **Item 0, engine map,** together with the practice-tools overlay. Both later estimates depend on it, and the overlay pays for itself immediately.
2. **Items 1 and 2:** written estimates, each with a small proof of concept where the risk is highest:
   - item 1: a second player object that is visible and moving
   - item 2: one commando frame drawn in place of Simon
3. **Review here:** pick what to build, and the asset path for item 2.
