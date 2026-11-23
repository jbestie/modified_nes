#!/usr/bin/env python3
"""Castlevania (USA Rev 1) level data: decode any stage and floor from the user's ROM.

The format came from CadEditor's stage-1 config (spiiin/CadEditor, MIT; written for the European ROM, whose bank 4
is identical) and was extended to every stage with the engine's own tables (notes/addresses.md section 13).
This file holds addresses only; the level data is read from the ROM at run time.

  layout   $FB23 + 2 x stage -> floor table; + 2 x floor -> L. Screen data in bank 4, column-major, 6 metatile
           numbers per 32-px column; page p shows columns 8p..8p+7 starting at L + 24.
  blocks   $F9FA + 2 x stage -> B. Metatile m = 17 bytes at B + 17m: an attribute byte, then 4x4 tile ids
           (row-major). Metatile row 0 starts at nametable row 4; its first two tile rows are hidden under the HUD.
  terrain  built from the tile ids as they are drawn ($F9D4): $60-$6B -> 1, $66 -> 2, others 0. Any non-zero
           cell stops Simon (b6:$9F4E). RAM copy: $05A0 + $B0 x ((page + $FBD6[stage]) & 1), 8 bytes per 8-px row,
           2 bits per 8x8 cell (leftmost cell in the top bits), rows from screen Y $30 down to $DF.
  pages    $FBB0 (right) / $FBC3 (left) per stage, high nibble = floor 0; left $F means 0, else nibble + 1.

Usage:
  level_data.py ROM map STAGE FLOOR      ASCII terrain map ('#' = 1, '=' = 2, '.' = 0, '|' every page)
  level_data.py ROM check LOG [LOG...]   compare with tests/explore/lvl_flythrough.lua / lvl_starts.lua logs
"""
import re
import sys
import zlib

PRG_CRC = 0xB668C7FC
LAYOUT, BLOCKSETS, RIGHT, LEFT, PARITY = 0xFB23, 0xF9FA, 0xFBB0, 0xFBC3, 0xFBD6
LEVEL_BANK = 4
FIRST_COLUMN = 24          # L points 4 columns (4 x 6 bytes) before the first shown column
ROWS = 22                  # terrain rows, screen Y $30-$DF = nametable rows 6-27


class Levels:
    def __init__(self, path):
        data = open(path, "rb").read()
        trainer = 512 if data[6] & 4 else 0
        self.prg = data[16 + trainer:16 + trainer + data[4] * 0x4000]
        if zlib.crc32(self.prg) != PRG_CRC:
            sys.exit(f"{path}: PRG CRC {zlib.crc32(self.prg):08X}, expected {PRG_CRC:08X} (Castlevania USA Rev 1)")

    def rd(self, a):
        if a >= 0xC000:
            return self.prg[7 * 0x4000 + a - 0xC000]
        if a >= 0x8000:
            return self.prg[LEVEL_BANK * 0x4000 + a - 0x8000]
        return None                        # below the ROM: never shown

    def word(self, a):
        return self.rd(a) | self.rd(a + 1) << 8

    def pages(self, stage, floor):
        """first and last camera page of a floor"""
        right, left = self.rd(RIGHT + stage), self.rd(LEFT + stage)
        r, l = (right >> 4, left >> 4) if floor == 0 else (right & 15, left & 15)
        return (0 if l == 15 else l + 1), r

    def metatile(self, stage, floor, column, row):
        """metatile number at 32-px column `column` (0 = level x 0) and metatile row 0-5"""
        layout = self.word(self.word(LAYOUT + 2 * stage) + 2 * floor)
        return self.rd(layout + FIRST_COLUMN + 6 * column + row)

    def tile(self, stage, floor, tx, ty):
        """nametable tile id at level tile column tx and nametable row ty (4-27)"""
        m = self.metatile(stage, floor, tx // 4, (ty - 4) // 4)
        if m is None:
            return None
        return self.rd(self.word(BLOCKSETS + 2 * stage) + 1 + 17 * m + (ty - 4) % 4 * 4 + tx % 4)

    def terrain(self, stage, floor, cx, row):
        """terrain code (0, 1, 2) of 8x8 cell column cx and terrain row 0-21, or None"""
        t = self.tile(stage, floor, cx, row + 6)
        return None if t is None else (2 if t == 0x66 else 1 if 0x60 <= t < 0x6C else 0)


def show_map(lv, stage, floor):
    first, last = lv.pages(stage, floor)
    print(f"stage {stage:02X} floor {floor}: pages {first}-{last}")
    for row in range(ROWS):
        line = []
        for cx in range(first * 32, (last + 1) * 32):
            if cx % 32 == 0 and cx > first * 32:
                line.append("|")
            v = lv.terrain(stage, floor, cx, row)
            line.append("?" if v is None else ".#="[v])
        print(f"Y {0x30 + 8 * row:02X} " + "".join(line))


def check(lv, paths):
    """compare decoded terrain and tiles with emulator logs; returns the number of mismatches"""
    bad = total = 0
    for path in paths:
        text = open(path).read()
        # fly-through: "stage SS floor F: reload=.. cam=.. L=<first page> ..." then "SSS FF ROW rr <cells>"
        firsts = {(int(s, 16), int(f)): int(l) for s, f, l in re.findall(r"stage (\w\w) floor (\d): reload=\S+ cam=\d+ L=(\d+)", text)}
        for s, f, r, cells in re.findall(r"S(\w\w) F(\d) ROW (\d\d) (\S+)", text):
            s, f, r = int(s, 16), int(f), int(r)
            for i, ch in enumerate(cells):
                v = lv.terrain(s, f, firsts[(s, f)] * 32 + i, r)
                if ch != "?" and v is not None:
                    total += 1
                    bad += v != int(ch)
        # stage starts: "<tag> stage=S floor=F scroll=0 page=P", then both nametables, then $05A0-$06FF
        lines = text.split("\n")
        for i, line in enumerate(lines):
            m = re.search(r"stage=(\d+) floor=(\d+) scroll=0 page=(\d+)", line)
            if not m:
                continue
            s, f, page = map(int, m.groups())
            half = (page + lv.rd(PARITY + s)) & 1
            nt = bytes.fromhex(lines[i + 1])[half * 0x400:]
            buf = bytes.fromhex(lines[i + 2])[half * 0xB0:]
            for cx in range(32):
                for ty in range(6, 28):
                    total += 2
                    bad += lv.tile(s, f, page * 32 + cx, ty) != nt[ty * 32 + cx]
                    got = buf[(ty - 6) * 8 + cx // 4] >> (2 * (3 - cx % 4)) & 3
                    bad += lv.terrain(s, f, page * 32 + cx, ty - 6) != got
    print(f"{total - bad}/{total} cells and tiles match")
    return bad


def main(argv):
    if len(argv) >= 5 and argv[2] == "map":
        show_map(Levels(argv[1]), int(argv[3], 16), int(argv[4]))
    elif len(argv) >= 4 and argv[2] == "check":
        sys.exit(1 if check(Levels(argv[1]), argv[3:]) else 0)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
