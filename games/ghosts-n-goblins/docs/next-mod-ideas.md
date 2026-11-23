# What to change next: ideas for a more interesting NES experience

Brainstorm notes for the next round of mods, starting from what this repo has
already mapped in *Ghosts'n Goblins* (USA). Every idea lists what a player or
viewer would notice, the engine hook we would use, and a rough cost.

Addresses are tagged:
- **verified**: traced and used in this project (see `notes/addresses.md`)
- **lead**: seen in disassembly but not traced yet; confirm before relying on it

## Status (2026-11-15)

Done since this was written:
- **Chat chaos mode** (`tools/chaos/`): see the README.
- **Remix ROM** (`build/ghosts-n-goblins-remix.nes`, separate from the main hack), which includes:
  - the UOROM expansion (256 KiB)
  - a title-screen mode select
  - rainbow burst, weapon cycling on Select, and "4 hits each" armor

  Bank 8 has about 15.8 KiB of space left for the next features.

Still open: the Tier 1 patch menu, homing, reflect, boss rush and everything in Tier 3.

## Where we stand

- **We have a working toolchain.** It includes a preimage-checked patch assembler, a bank-aware disassembler, an FCEUX Lua test harness and pixel/APU regression against the original. Small and medium ROM changes are now cheap to try safely.
- **Big features need room first.** The fixed bank is essentially full: the only padding left is 7 bytes at `$DA6A` and 7 at `$E562`. Anything larger than a few bytes needs one of these first (see [Prerequisite](#prerequisite-make-room-for-real-code)).
- **The engine is friendly to gameplay mods:**
  - weapons and enemies are ordinary objects with type handlers
  - motion goes through one 16-direction table
  - all damage to Arthur passes through one check (`$E014`)
  - enemy damage is a simple hit counter (`$0647,X`)

## Tier 1: byte-sized changes (minutes each, low risk)

| Idea | What the viewer sees | Hook | Status |
|---|---|---|---|
| **Giant weapon hitboxes** | Lances that hit everything near their path; feels like a huge sword | Weapon hitbox half-extents at `$F6EC` (X) / `$F6F1` (Y), 5 bytes each, indexed by weapon type − `$23` | verified |
| **Weapon speed tuning** | Slow-motion "bullet hell" daggers, or instant-hit lances | Speed constants loaded before `JSR $F0A0`: lance `$2C` (`$EB7F`), dagger `$38` (`$EB8E`), torch/axe `$22` (`$EC64`, `$ED02`), cross `$24` (`$ED3E`) | verified |
| **Longer-range cross** | The cross becomes a real projectile instead of a short poke | Cross lifetime `CMP #$0A` at `$ED3A` | verified |
| **Boss HP up/down** | Stage-1 boss takes 30 hits instead of 10 (balances the spread) | `CMP #$0A` at `$FC0C` (type `$05` death threshold); other bosses need their own thresholds found | verified for type `$05` |
| **Different throw sound** | The spread gets its own "shotgun" sound | Sound id `$11` at `$E161` (`LDA #$11 / JMP $ED51`) | verified |
| **Wider/narrower fan** | 7-way or a tight 3-way spread | `ADC #$EF` / slot range in `SpreadFire` (`src/spread.asm`) | verified |
| **Horror / night filter** | Whole game tinted red or greyscale for a "cursed" segment | `$39` looks like the PPUMASK shadow (`$F171`/`$F17A` toggle its render bits). Setting the greyscale/emphasis bits there would tint everything. | lead |
| **More/fewer lives, longer timer** | Classic difficulty dial | `$0715` lives (init at `$C55D`/`$C5E2`/`$C60A`); timer digits `$06F6/$06FA/$06FC` | lives/timer RAM verified, init values lead |

> **Tip:** Tier 1 items make a good "patch menu". Each one is a tiny `.asm` block with its own `.expect`, and the build can produce several variants (for example `spread-hard.nes`, `spread-giant.nes`) from the same sources.

## Tier 2: new code (an evening each, needs code space)

### Rainbow burst (done: remix ROM, SHOT = RAINBOW)
Each of the five projectiles is a different weapon (lance, dagger, torch, axe, cross) in one fan.
- **Hook:** `$E0BE` reads the held weapon from `$053A`. In `SpreadFire`, set `$053A` per slot before each `JSR $E0BE` and restore it after the burst.
- **Why it's fun:** visually loud and instantly readable on stream.
- **Risk:** low.
  - The object handlers are already proven (`tests/t_weapons.lua` runs all five).
  - Unverified: whether all five weapon sprites are loaded in every stage's CHR.

### Weapon cycling on Select (done: remix ROM)
Press Select to rotate through the five weapons without hunting for pickups.
- **Hook:** write `$053A` and `$C5,Y` (what a pickup writes, bank 4 `$BA6B`; `$D1E2` restores it on respawn) on a Select edge. The input byte layout needs tracing: B is `$CC & $40` (verified), Select is unknown.
- **Stream value:** the streamer can respond to chat ("use the torch!").

### Armor as a health bar (done: remix ROM, ARMOR = 4 HITS EACH)
Instead of full invincibility, Arthur survives N hits, then the original armor-loss and death rules apply.
- **Hook:** the existing `$E014` hook. Keep a hit counter in a free RAM byte and let the hit through when it reaches N. A palette flash on each absorbed hit gives feedback.
- **Why:** full invincibility removes tension. An "8-hit armor" mode keeps the game a game while staying generous.
- **Risk:** low, but a free RAM byte has to be found and verified.

### Mode select / live toggles (done: remix title menu; live toggles through the chaos mode)
A title-screen option or a button combo switches between Normal, Invincible, Spread and Both.
- **Hook:** every feature reads one mode byte. The patched branches become conditional: `$E014` checks the mode, and `SpreadFire` falls back to the original single shot.
- **Why:** one ROM covers the whole stream, including "now let's try it for real" segments.

### Homing shots
The fan curves toward the nearest enemy after a few frames.
- **Hook:** weapons already move by `$05F1` (direction index). There seems to be an engine routine that turns a dx/dy into a direction (`$EF99–$EFBE`, lookup table at `$F1A3`), probably what enemies use to aim at Arthur.
- **Plan:** each frame, turn `$05F1` one step toward the target.
- **Status:** lead (the aiming routine is not traced).

### Reflect / parry
Enemy projectiles that touch Arthur turn around and become his weapons.
- **Hook:** at the contact path (`$F5E8`, X = touching slot), if X is `$14–$15`, rewrite that object into a weapon type in a free weapon slot (or reverse its direction and flag it as player-owned).
- **Risk:** medium. Enemy projectile types (`$29`, `$2D`, `$30`, `$31` seen in tests) have their own handlers, and changing ownership touches collision lists.

### Boss rush
Jump straight from boss to boss.
- **Hook:** the built-in stage select (`$A7 == $0F` unlocks it, `$AC` = area, `$D05F`). The rush mode would set `$AC` to the next boss area after each kill.
- **Known boss areas:** 2 (stage 1), 6 (stage 2), 13 (final). The rest need mapping.
- **Caveat:** warping by poking `$AC` directly skipped some graphics loading in tests. Going through the stage-select path loaded cleanly.

## Tier 3: big projects (only with dedicated time)

| Idea | Why it is exciting | Main obstacles |
|---|---|---|
| **Simultaneous 2-player co-op** | Two Arthurs on screen, on stream with a guest | The engine time-shares slot 0 between players (`$8089` swap, `$BA` player index). Needs a second Arthur object and task, input for pad 2, camera rules and death/respawn logic. Weeks, not days. |
| **Enemy remix / randomizer** | Every run has different enemies | Level objects get their type from level data (`LDA ($26),Y` / `STA $0631,X` at `$D6CB–$D6CD`), which is easy to swap. **But** CHR-RAM holds only the current stage's graphics, so an enemy from another stage would draw as garbage unless its tiles are uploaded too. |
| **New moves (double jump, slide, dash)** | Makes Arthur feel modern | Arthur's movement states (`$DAxx–$E4xx`, run every 3rd frame) and jump physics are not traced yet. |
| **New stage segments / mirrored stages** | Fresh content for repeat viewers | Needs a level-format decoder and editor. The `CadEditor` checkout in `~/workspace_cpp` has GnG settings files, which may already describe the level format. |

## Livestream interactivity without touching the ROM

The FCEUX Lua harness already does everything a chat-controlled mode needs:
- read a command file every few frames
- write RAM
- press buttons
- take screenshots

That makes it the **highest value per hour**:

1. A small chat bot (Twitch/YouTube) writes commands into a text file.
2. A Lua script reads them and pokes RAM. Examples:
   - `!torch`: set `$053A=$44`
   - `!armor`: clear bit 5 of `$04F0` **inside Arthur's task**, sampled at `$E014` (because of the `$8089` slot swap)
   - `!time`: `$06F6=0`
   - `!boss`: stage-select warp
3. Viewer votes pick the next "curse" (horror tint, slow weapons, boss HP ×3) or "blessing" (spread, invincibility).

**Advantages:**
- zero ROM risk
- changes can be iterated live during the stream
- the overlay can show what chat triggered (Lua `gui.text`)

**Limitations:**
- only works in FCEUX, not on real hardware
- cheats must respect the engine's quirks (Arthur's code runs every 3rd frame, and slot-0 fields are swapped during rendering)

## Prerequisite: make room for real code

Tier 2 and 3 need more code space than the fixed bank has. There are two options:

**1. Trampoline into a switchable bank**
- A ~20-byte routine in the fixed bank saves `$C7`, selects bank N (writing `$C7` *before* `$C000+N` because the NMI music driver restores from `$C7`), calls the code there and switches back.
- **Problem:** we would still need 20 free fixed-bank bytes. Getting them means freeing a few existing ones, for example by moving a rarely used fixed-bank routine.

**2. Expand to 256 KiB (UOROM)**
- Mapper 2 supports 16 banks. Insert 8 empty banks, keep the original fixed bank as the last bank, and set the header to 16 PRG banks.
- The game's own bank switches (`STA $C000,Y`, banks 0–7) keep working. New banks need their own bus-conflict-safe table.
- Gives 128 KiB of clean space and avoids hunting for caves.
- Emulators and flash carts handle UOROM well. The BPS patch gets bigger, but that's fine.

**Recommendation:** UOROM expansion, once, before any Tier 2 work.

**Done in the remix ROM.** It uses a 21-byte trampoline in the space freed by moving the original fire routine to bank 8.
- **Lesson learned:** with this game's bank-restore code (`STA $C000,Y` with Y = bank), **only bank 8** is safe for code on boards with bus conflicts, because the ROM byte at `$C008` is `$78`.
- Banks 9–14 can hold data that bank-8 code copies or reads, but not code that the NMI might return into.

> **Warning:** Whichever option we pick, keep the rule learned from `$CA76`: a run of `$FF`/`$00` is not free space until pointer-based reads are ruled out. The pixel-exact screen and APU tests must stay in the loop.

## Ideas that carry over to other NES games

The same toolkit (preimage-checked patches, Lua harness, regression against the original) works for most mapper 0/1/2/4 games. The changes that tend to be fun almost anywhere:

- **Physics constants:** gravity, jump height, run speed. Usually a few table bytes.
- **One damage choke point:** most games funnel player damage through one routine, as GnG does with `$E014`. That makes invincibility, health-bar armor and damage multipliers cheap.
- **Projectile behavior:** speed, count, direction tables, piercing.
- **Palette moods:** PPUMASK emphasis or palette-buffer edits for themed segments.
- **Spawn tables:** randomizers. Watch CHR limits on CHR-RAM games; CHR-ROM games swap banks instead.
- **Difficulty curve:** enemy HP thresholds and spawn timers.
- **Chat integration via emulator scripting:** works for any game whose RAM map we know.

## Suggested next three steps

The original three were: chaos mode (done), Tier 1 patch menu (open), and UOROM + mode select (done). From here:

1. **Tier 1 options in the remix menu.** Examples: a third menu line for "giant hitboxes" or "boss HP ×3". The hitbox and threshold reads would have to come from RAM or bank 8 instead of fixed-bank tables.
2. **A human play-through of the remix** in RAINBOW and 4 HITS EACH through stages 3–6. These are the main gaps in the test report.
3. **Boss rush or homing shots**, now that bank 8 has room.
