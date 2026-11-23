# Spike: the Super C commando drawn in Castlevania

Proof of concept for `TODO.md` item 2, asset route 1 ("import at install time"). The spike ran on 2026-11-17 against Castlevania (USA) Rev 1 and Super C (USA).

**Superseded:** the production version is `tools/commando_art.py` (run by `make GAME=castlevania art`). This folder stays as the record of the spike.

**Nothing from Super C is in this folder.** The script knows only addresses and frame numbers, and reads the tiles, frame layouts and colours from your own Super C dump when it runs. The ROM it writes contains Super C graphics. Keep it on your machine (for example in your scratch folder). Never commit it, never share it.

## Files

| File | What it is |
|---|---|
| `import_superc_player.py` | Reads both ROMs and writes a new Castlevania image with the commando in place of Simon |
| `spike_shots.lua` | FCEUX screenshot script: intro walk, courtyard poses, forced frame ids, stage warps. Works on any USA V1.1 image |

## Run

```sh
python3 games/castlevania/spikes/graphics/import_superc_player.py \
    --cv games/castlevania/rom/original.nes --superc "<your Super C (U).nes>" \
    --out <scratch>/cv_commando.nes [--preset looks|full] [--colours pal2|p1] [--report]
python3 scripts/run_fceux.py <scratch>/cv_commando.nes games/castlevania/spikes/graphics/spike_shots.lua \
    --game-dir games/castlevania --out <scratch>/shots --tag looks \
    --env FRAMES=01,02,03,04,05,97,98 --env WARP=01,07,0C
```

The script refuses other dumps. It checks the PRG CRC32s: Castlevania `B668C7FC`, Super C `C7FBECC3` (plus CHR `153295C1`).

## What the script does

**1. Super C side.** Player frames are read from PRG bank `$36`, pointer table `$8F31`. Entries are `[Y, tile, attr, X]`, with `$80 lo hi` meaning "continue there". Sprites are 8×16, from the stage-1 sprite CHR (MMC3 1 KiB banks `$44-$47` at PPU `$1000`).

**2. Tiles.** Each 8×16 Super C tile is copied as 32 bytes into one of Simon's table-0 pairs, in the raw block at `b1:$9008 + 16 × pair`. Both games use 8×16 sprites, so no re-pairing is needed. Only the tile numbers change: odd in Super C, even in Castlevania.

**3. Frames.** New metasprites go into bank 0's free space at `$BB01`, in Castlevania's format `[2Y][tile][attr][X]`. Then:
- Simon's frame pointers (`b0:$8FBE` / `$90BE`) are redirected to them.
- Frames 00-04 and 93 are moved as well. That frees the pointer slots of ids `$EF-$FF` (at `$919C-$91BD`) for new poses.

**4. Alignment.** Each Super C pose is placed on the feet line of the Simon frame it replaces: the lowest opaque row, measured in both games.

**5. Colours.** Two options:
- `pal2` (default) draws everything with Castlevania sprite palette 2 (`37 11 0F`: skin, blue, black). It has the same colour order as Super C's player palettes, so no palette changes.
- `p1` draws the torso with palette 0, overwritten with Super C's player-1 torso colours (read from the Super C file), and the legs with palette 2.

**6. Presets.**

| Preset | Imports | Tiles | Frame data |
|---|---|---|---|
| `looks` | Simon's frames only; the whip is untouched | 20 tiles into Simon's 28 pairs | 373 bytes |
| `full` | Adds aim up, diagonal up/down, prone and somersault at ids `$EF-$FC`, plus 3 bullet tiles. The whip pairs are reused, so the whip shows garbage | 38 + 3 = 41 pairs, exactly Simon's and the whip's | 647 bytes |

Pose table (Castlevania frame → Super C frame):

| Castlevania pose | Castlevania frame | Super C frame |
|---|---|---|
| stand | 01 | 08 |
| walk | 02 / 03 / 04 | 06 / 07 / 09 (run with the gun forward) |
| crouch and jump | 05 | 23 (kneel) |
| whip | 06 / 07 / 08 | 08 / 08 / 0B (recoil) |
| crouching whip | 09-0B | 23 / 23 / 24 |
| stairs | 0D-0F | 07 |
| hurt | 97 | 1E |
| dead | 98 | 22 |
| kneel | 99 | 23 |
| whip on stairs | A4-AC | 08 / 0B |

## What we saw (screenshots stayed in the scratch folder)

**Courtyard, stage 1, stages 7 and 12 (warp), castle map, intro walk.** The commando is drawn cleanly:
- feet on the floor, mirrors correctly when facing left
- walk cycle, kneel for crouch and jump, recoil frame on the whip's hit frame

The whip still comes out of the gun in the `looks` preset.

**Colours.**
- `p1` looks like Super C's player 1: red bandana and skin shading, blue trousers.
- `pal2` gives a "blue commando": the torso shading turns blue.

**New poses.** All of them render at ids `$EF-$FC` and mirror. They were checked by forcing slot 0's frame, as `tests/explore/gfx_frame_viewer.lua` does.

**Not covered.**
- **Intro back view.** At the castle gate the intro shows Simon from behind: frame 19, built from intro-only tiles in table 1. It stays Simon and needs its own replacement.
- **Ending.** Not checked.

**Sprite pressure.** Measured with `tests/explore/gfx_oam_survey.lua` (12,000 frames, the same bot), `looks` preset against the original. The commando uses 4-6 sprites per frame (Simon uses 3-4); his gun arm makes his upper rows 3 sprites wide.

| Where | Frames with more than 8 sprites on a line | Max sprites on one line |
|---|---|---|
| stage 1 | 23% → 33% | 18 → 19 |
| courtyard | 4% → 13% | |
| demo stage 7 | 5% → 10% | |
| demo stage 8 | 2% → 9% | |
| demo stage 12 | 12% → 20% | 17 → 19 |

**What-if: re-cutting to a 2-row grid.** Re-cutting the poses into Simon's 16 px rows would save no sprites (50 against 48 for the `looks` poses). It would double the tiles (41 against 20), because Super C reuses torso and leg tiles at different offsets. Keep Super C's own layout.
