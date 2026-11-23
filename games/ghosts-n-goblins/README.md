# Ghosts'n Goblins (NES, USA): Invincible Arthur + five-way spread shot

ROM patches for *Ghosts'n Goblins* (NES, USA, mapper 2 / UNROM, 128 KiB PRG,
CHR-RAM). This folder has only source, tools and documentation. **No ROM
is included.** Bring your own dump.

This is one game of a multi-game repository (see the [top-level README](../../README.md)).
Paths below are relative to this folder; shell commands run from the repository root.

| Build | What it is |
|---|---|
| `ghosts-n-goblins-spread.nes` | The main hack: invincible Arthur + five-way spread, same size as the original |
| `ghosts-n-goblins-remix.nes` | A **separate** ROM: title-screen menu for shot and armor modes, rainbow burst, weapon cycling ([below](#remix-rom-separate)) |
| `tools/chaos/` | Chat chaos mode for streams: viewers trigger effects through FCEUX Lua, no ROM change ([below](#chat-chaos-mode-fceux-lua)) |

## What it does

**Invincible Arthur**
- Enemy bodies and enemy projectiles never knock Arthur back, strip his armor or cost a life.
- No blinking, no lost control. Whatever he was doing (walking, jumping, climbing, crouching, throwing) just continues.
- Pickups, ladders, platforms, bosses and stage transitions work as before.
- **Still lethal:** falling into pits or water, and the stage timer running out. Stage progression is not changed.

**Five-way spread shot**
- Every attack throws five copies of Arthur's current weapon (lance, dagger, torch, axe or cross) in a forward fan.
- The angles are up 45°, up 22.5°, level, down 22.5° and down 45°, mirrored exactly when Arthur faces left.
- Each projectile is a real game object with its own movement, wall and off-screen removal, enemy collision and damage. Bosses take hits from all five.
- At most 5 player projectiles exist at once (one burst). A new burst fires only when the previous one is completely gone, so the projectile table can't overflow.

Controls are unchanged (B = attack, A = jump).

## Remix ROM (separate)

A second, independent ROM built from the same original. The main hack above is not changed by it.

**Title-screen menu.** Two lines under "2 PLAYERS" show the settings. Press **A** to change the shot, **B** to change the armor, then Start as usual.

| Setting | Options (first = default) |
|---|---|
| A: SHOT | **5 WAY SPREAD** (as in the main hack) · **RAINBOW** (each burst throws lance, dagger, torch, axe and cross at once) · **NORMAL** (the original single shot) |
| B: ARMOR | **INVINCIBLE** (as in the main hack) · **4 HITS EACH** (see below) · **NORMAL** (original damage) |

- **4 HITS EACH:** each armor piece takes 4 hits. Hits 1 to 3 only make Arthur blink (the game's own 1.5 s post-hit invulnerability, with an armor clank) without knockback or armor loss. The 4th hit applies the original rule: armor off, then in boxers another 4 hits until death. That's 8 hits per life. Pits, water and the timer stay lethal.
- **Select cycles the weapon** during play (lance → dagger → torch → axe → cross), with the pickup sound. The weapon is kept after a death, like a pickup. Off when SHOT is NORMAL.
- **NORMAL + NORMAL is the original game.** The tests check it pixel-for-pixel and per APU frame against the unmodified ROM (only the menu text differs).
- **Settings survive a console reset** and return to the defaults at power-on.

Notes:
- The remix is a **256 KiB** image (mapper 2 "UOROM": 16 × 16 KiB banks); the new code lives in bank 8. FCEUX, Mesen and current flash carts support this; a real cartridge would need a 256 KiB UxROM board.
- Mode changes take effect from the title screen. With 5 WAY SPREAD or RAINBOW, enemies get 14 object slots (as in the main hack); with NORMAL shot they get the original 16.
- Pressing A or B on the title restarts its idle timer, so the attract demo waits while you choose. The hidden stage-select code uses A/B, so entering it also changes the menu.

## Chat chaos mode (FCEUX Lua)

Viewers type commands in chat and the game reacts. Nothing in the ROM changes: a Lua script in FCEUX writes the same RAM a pickup or the game itself writes. It works with the original ROM and all builds here; the mode commands need the remix ROM.

1. In FCEUX: *File > Load Lua Script* > `tools/chaos/chaos.lua`. Recent commands and active effects appear at the bottom of the game screen.
2. Start the bridge, which turns chat into lines in `tools/chaos/commands.txt`:
   ```sh
   cd games/ghosts-n-goblins
   python3 tools/chaos/chat_bridge.py --twitch yourchannel                  # anyone can trigger, with cooldowns
   python3 tools/chaos/chat_bridge.py --twitch yourchannel --vote 30        # one winning command every 30 s
   python3 tools/chaos/chat_bridge.py --stdin                               # type commands yourself (offline)
   ```
   Twitch chat is read anonymously; no account or token is needed. Defaults: 20 s cooldown per command, 10 s per viewer. Use `--allow` / `--deny` to choose the command set (for example `--deny naked,hurry,mortal` for a gentle chat).

| Command | Effect |
|---|---|
| `!lance` `!dagger` `!torch` `!axe` `!cross` | Change Arthur's weapon |
| `!life` | +1 life (max 9) |
| `!time` / `!hurry` | +1 minute on the clock / clock set to 0:20 |
| `!armor` / `!naked` | Armor back on / armor off |
| `!blood` `!toxic` `!grey` | 20 s red, green or greyscale picture |
| `!spread` `!rainbow` | Remix ROM: switch between the two five-way shots |
| `!god` `!tough` `!mortal` | Remix ROM: armor INVINCIBLE / 4 HITS EACH / NORMAL |

## Patching your ROM

Required input: *Ghosts'n Goblins (USA)* with PRG CRC32 `B4E4879E`. Two header variants are common, and there is a patch for each:

| Your file's CRC32 | Patch |
|---|---|
| `87ED54AA` (iNES 1.0 header, GoodNES "[!]") | `dist/ghosts-n-goblins-invincible-spread.bps` |
| `102A8B76` (NES 2.0 header, No-Intro) | `dist/ghosts-n-goblins-invincible-spread.nes2-header.bps` |

Apply the patch with Floating IPS (flips), beat, an online BPS patcher, or the included tool:

```sh
python3 scripts/bps.py apply games/ghosts-n-goblins/dist/ghosts-n-goblins-invincible-spread.bps original.nes patched.nes
# or: make patch IN=original.nes OUT=patched.nes
```

The patcher checks the input CRC32 and refuses a wrong or already-patched ROM.
Expected output CRC32 is `F5A34725` from the iNES-header input, or `626498F9` from the NES 2.0-header input.

The remix ROM has its own patches, made from the same original:

| Your file's CRC32 | Patch | Output CRC32 |
|---|---|---|
| `87ED54AA` | `dist/ghosts-n-goblins-remix.bps` | `4AEB08B4` |
| `102A8B76` | `dist/ghosts-n-goblins-remix.nes2-header.bps` | `3F8569F2` |

```sh
make patch PATCH=games/ghosts-n-goblins/dist/ghosts-n-goblins-remix.bps IN=original.nes OUT=remix.nes
```

The remix patches contain only the new code (under 1 KB). The relocated fixed bank is encoded as copies from your ROM, so no original game data is in the patch.

## Building from source

Requirements: Python 3 (standard library only for the build). FCEUX 2.6.x is needed for the tests (and Pillow for screenshot comparison).
cc65 is **not** required: the hooks are written in 6502 assembly and assembled by the shared `scripts/asm6502.py`, a small two-pass assembler.

```sh
cp /path/to/your/dump.nes games/ghosts-n-goblins/rom/original.nes
make            # -> build/{invincible,ghosts-n-goblins-spread,ghosts-n-goblins-remix}.nes, dist/*.bps
make test       # full emulator test suite (~3 min, opens FCEUX windows)
```

`ghosts-n-goblins` is the Makefile's default game, so `GAME=ghosts-n-goblins` can be left out.

The build refuses to patch anything except the expected ROM. Every patch block in `src/*.asm` declares the original bytes it replaces (`.expect`). The build fails if they don't match, and it checks that the final diff contains exactly the assembled bytes.

## Folder layout

```text
game.py                 game definition: expected ROM, header variants, build targets, patches
game.mk                 Makefile defaults for this game (default PATCH)
run_tests.py            whole test suite -> tests/out/summary.txt
GHOSTS_N_GOBLINS_CLAUDE_TASK.md  the original task specification
src/invincible.asm      Feature A hooks (annotated)
src/spread.asm          Feature B hooks (annotated)
src/remix/bank8.asm     remix ROM: new code in bank 8 (modes, rainbow, cycling, menu)
src/remix/hooks.asm     remix ROM: fixed-bank hooks and the bank-8 trampoline
tools/chaos/            chat chaos mode: chaos.lua (FCEUX) + chat_bridge.py
tests/gng.lua           shared helpers for the Lua tests (input, logging, RAM map)
tests/*.lua             FCEUX Lua tests; tests/explore/ = investigation probes
tests/test_chat_bridge.py  offline tests for the chat bridge
notes/rom_layout.md     header, checksums, bank map (generated by make layout)
notes/addresses.md      traced routines, RAM map, hooks, rejected caves
notes/patch_ranges.md   exact patched bytes (generated by the build)
notes/test_report.md    what was tested, results, limitations
docs/next-mod-ideas.md  brainstorm: what to change next
rom/original.nes        your dump (not committed)
build/, dist/           generated ROMs (not committed) and the distributable patches
```

The build, assembler, disassembler, BPS tool, ROM report and FCEUX runner are shared by all games and live in the repository's `scripts/`.

## Design notes and tradeoffs

- **Invincibility hook:** the damage routine (`$E171`) is reached only through the HitPending check (`$E014`) that every Arthur state polls. The patch swallows the pending hit there unless the timer has expired, so it doesn't fight the engine's own post-hit invulnerability and no RAM flag is forced every frame. See `src/invincible.asm`.
- **Five real slots:** the engine has 25 object slots, of which only 3 were for player weapons. Slots `$0F–$10` move from the enemy range to the weapon range, so enemies and level objects now have 14 slots instead of 16.
  - Peak active enemies observed in testing: 8.
  - When the range is full, the level-object placer retries the same object until a slot frees (objects are delayed, never lost). Random and periodic spawners spawn a little less often under load.
- **Angles:** the engine's 16-direction table gives 22.5° steps, so the fan is ±22.5°/±45° rather than the ±15°/±30° originally suggested. This reuses the game's own fixed-point motion and collision code, and is more exaggerated.
- **Graphics:** projectiles keep their normal horizontal sprites, even on diagonals. No CHR changes.
- **Sound:** the throw effect is triggered five times in the same frame, so it sounds like a single throw.
- **Sprite limits:** the NES shows 8 sprites per scanline. A burst next to Arthur and enemies exceeds that briefly, and the game's own OAM rotation turns it into flicker. Hits still register, since collision is independent of drawing.
- **Remix code space:** the fixed bank is full, so the remix doubles the ROM and puts its code in bank 8. A 21-byte trampoline (in the space freed by moving the original fire routine) maps bank 8, calls the function and restores the previous bank. Bank 8 is chosen on purpose: the game restores banks with `STA $C000,Y`, and only for bank 8 is that write safe on boards with bus conflicts (the ROM byte at `$C008` is `$78`, and `$08 AND $78 = $08`). Details in `notes/addresses.md`.

## Legal

Ghosts'n Goblins © Capcom. This project distributes only original patch
code, tools and documentation. Do not commit or share ROM images; the
repository's `.gitignore` excludes `*.nes`, `rom/` and `build/`.
