# NES ROM hacks

Patches and mods for NES games: one folder per game under `games/`, plus
shared tools in `scripts/`. This repository has only source, tools and
documentation. **No ROM is included.** Bring your own dumps.

| Game | Folder | What's there |
|---|---|---|
| Ghosts'n Goblins (USA) | [games/ghosts-n-goblins](games/ghosts-n-goblins/README.md) | Invincible Arthur + five-way spread shot; a separate remix ROM with title-menu modes; a chat chaos mode for streams |
| Castlevania (USA) | [games/castlevania](games/castlevania/README.md) | Commando (milestones M1-M3, most of M4): run-and-gun, aiming, prone, air control, Super C's jump, weapons and barrier; mechanics patch plus a private art install from your own Super C dump |

## Quick start

```sh
cp /path/to/your/dump.nes games/<game>/rom/original.nes
make GAME=<game>            # build the ROMs and patches (default GAME=ghosts-n-goblins)
make GAME=<game> test       # the game's emulator test suite
make games                  # list the games
```

Each game's README lists its patches, the input CRC32 they expect, and how to apply them.

## Layout

```text
Makefile                shared entry point: make [build|test|quicktest|layout|patch|clean] GAME=<game>
scripts/build.py        deterministic build of a game: assemble, check preimages, diff, write BPS patches
scripts/asm6502.py      6502 patch assembler with preimage checks (.expect)
scripts/dis6502.py      bank-aware disassembler
scripts/bps.py          BPS create/apply (patches never carry original ROM data)
scripts/rom_info.py     header/checksum/bank/free-space report of any iNES image
scripts/run_fceux.py    run FCEUX with a Lua test script (hard timeout, PASS/FAIL from its log)
scripts/compare_shots.py  pixel-compare two screenshot series
scripts/gamedef.py      loads games/<game>/game.py
games/<game>/           everything for one game (see below)
```

A game folder contains:

```text
game.py        expected input ROM, header variants, build targets, patches
game.mk        optional Makefile defaults (e.g. the default PATCH)
run_tests.py   the game's test suite (make test)
src/           assembly sources
tests/         FCEUX Lua tests (output in tests/out/)
notes/         reverse-engineering notes, layout and test reports
rom/           your dump, rom/original.nes (never committed)
build/, dist/  generated ROMs (never committed) and the distributable patches
```

## Adding a game

1. Copy your dump to `games/<name>/rom/original.nes`.
2. Get a first look at it:
   ```sh
   python3 scripts/rom_info.py games/<name>/rom/original.nes
   ```
   The report shows the mapper, the PRG/CHR sizes, the checksums, the bank map and runs of `$00`/`$FF`.
3. Write `games/<name>/game.py`. Copy the one in `games/ghosts-n-goblins/` and set:
   - `TITLE`, `MAPPER`, `PRG_BANKS`, `CHR_BANKS`, `PRG_CRC`: the build refuses any other input.
   - `HEADERS`: known dumps (file CRC32 → description, patch suffix, header). The build writes each patch for every listed header variant.
   - `TARGETS`: output name, sources, and the PRG bank count after expansion (`0` = same size).
   - `PATCHES`: which targets get a BPS patch, with its metadata.
   - Optional `LAYOUT_NOTE`: an extra paragraph for the free-space section of `make layout`.
4. Write the patches in `src/*.asm`. Every block declares the bytes it replaces (`.expect`), so a wrong ROM or a wrong address fails the build. Then `make GAME=<name>`.
5. For tests, put Lua scripts in `games/<name>/tests/` and run them with `scripts/run_fceux.py`. The runner gives the script these environment variables: `GAME_DIR`, `TEST_OUT`, `TEST_ROM`, `TEST_LOG` and `TEST_TAG`. A script passes by writing `RESULT PASS` to `TEST_LOG`. Add a `run_tests.py` so `make test` works.

**Limit:** the assembler, the disassembler and the ROM expansion assume UxROM banking (mapper 2: the last 16 KiB bank fixed at `$C000`, the others switched in at `$8000`). A game on another mapper (MMC1, MMC3, …) needs `bank_window` in `scripts/asm6502.py` and `scripts/dis6502.py` generalized first.

## Requirements

- Python 3. The build uses only the standard library.
- FCEUX 2.6.x for the tests, and Pillow for the screenshot comparisons.

## Legal

All games are © their publishers. This project distributes only original
patch code, tools and documentation. Do not commit or share ROM images;
`.gitignore` excludes `*.nes`, `rom/` and `build/`.

The code, tools and documentation in this repository are under the MIT
license ([LICENSE](LICENSE)). It covers this project's own work only, not
the games or any data from them.
