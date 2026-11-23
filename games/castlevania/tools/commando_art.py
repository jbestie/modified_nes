#!/usr/bin/env python3
"""Draw the Super C commando in the commando build, importing his graphics from the user's own Super C dump.

Asset route 1 of docs/commando-estimate.md, the production version of spikes/graphics/. The installer reads
BOTH ROMs that the user owns and writes a new image. Neither this file nor anything in this repository contains
Super C data: the script only knows addresses and frame numbers, and copies the tiles, frame layouts and
(optionally) colours from the Super C file at run time. The output contains Super C graphics, so it must stay
on the user's machine: never commit it or share it (build/ is ignored by git).

What it does:
  1. Super C side: player frames from PRG bank $36, pointer table $8F31 (entries [Y, tile, attr, X]), bullet
     sprites from the object table $8205 of the same bank, and the 8x16 sprite tiles of stage 1 (MMC3 1 KiB CHR
     banks $44-$47).
  2. Copies the tiles of every pose into Simon's and the whip's tile pairs (raw block b1:$9008 + 16 * pair,
     uploaded to CHR-RAM table 0). The commando build never shows the whip, so its 13 pairs are free:
     28 + 13 = 41 pairs = 38 commando tiles + 3 bullet tiles.
  3. Writes metasprites in Castlevania's format ([2Y (+1 = keep attr)] [tile] [attr] [X]) into bank 0's free
     space $BB01-$BFFF and points Simon's frame ids at them. Frames 00-04 and 93 move too, which frees the
     pointer slots of ids $EF-$FF: the new poses go to $EF-$FC (for milestone 2).
  4. Aligns each pose on the feet line of the Simon frame it replaces (lowest opaque row).
  4a. Pickups become Super C's falcon letters (wing | letter | mirrored wing, palette 3): dagger M, cross S,
     holy water L, axe F, whip upgrade R, potion (and stopwatch) B, rosary falcon; the HUD weapon icon shows
     wing | letter. All of them share one wing tile, which frees the other items' second tiles.
  4b. Bullets: Super C's sprite for each kind (rifle, M, S, the laser in 4 directions, the fire ball, the
     charged ball; fragments use S's ball) at the whip's frame ids $10-$18, in sprite palette 0 (cream, orange,
     brown for Super C's white, salmon, red). 6 tiles go into the freed item tiles (the wings and the
     never-dropped multiplier).
  4c. Intro back view (frame $19 at the castle gate): Super C has no such pose, so it is an original 16 x 48
     drawing (BACK_VIEW), the commando's height. Its 6 tiles go into the build's BackTiles (bank 6), which the
     intro uploads to table-0 pairs $E0-$EA.
  5. Points the build's bullets (BulletFrames and LaserFrames in bank 5, from the build's .sym) at the bullet
     frames, and fills the build's PoseMap (aim up, diagonal runs, somersault, stand and prone firing) with
     the commando's frame ids.
  6. Colours: "pal2" (default) uses Castlevania sprite palette 2 for the commando (same colour order as Super
     C's player palettes); "p1" overwrites sprite palette 0 with Super C's player-1 torso colours for the torso.

Safety: the base must be the commando build of Castlevania (USA) Rev 1. Every byte this script writes, except
the build's own tables (BulletFrames, LaserFrames, PoseMap, BackTiles), must still hold the original Castlevania
value in the base (checked against --orig), so a build that moved into these regions is refused instead of
overwritten.

Usage:
  commando_art.py --base build/castlevania-commando.nes --sym build/castlevania-commando.sym
                  --orig rom/original.nes --superc "<Super C (U).nes>" --out build/private/<name>.nes
                  [--colours pal2|p1] [--report]
"""
import argparse
import os
import re
import sys
import zlib

CV_PRG_CRC = 0xB668C7FC          # Castlevania (USA) Rev 1, PRG only
SC_PRG_CRC = 0xC7FBECC3          # Super C (USA), PRG only
SC_CHR_CRC = 0x153295C1          # Super C (USA), CHR-ROM

# ---- Super C facts (addresses only; data is read from the user's file)
SC_PRG_SIZE = 0x20000
SC_BANK36 = 0xC000               # PRG offset of 8 KiB bank $36 (mapped at $8000 when the sprite engine runs)
SC_PLAYER_TABLE = 0x8F31         # word table, entry for frame id 1 first
SC_SPR_BANKS = (0x44, 0x45, 0x46, 0x47)   # 1 KiB CHR banks of PPU $1000-$1FFF in stage 1 (measured)
SC_AREA1_SPR_PAL = 0xF8D5        # PRG offset: area-1 sprite palettes, 3 bytes each (pal 0 = P1 legs, pal 1 = torso)
SC_OBJ_TABLE = 0x8205            # object sprites: word per graphic id; byte 0 >= $80: one sprite, tile 2b+1 at (-8, -4)
SC_WING = 0x91                   # falcon letters: wing tile (stage-1 sprite CHR); letters 93 M 95 S 97 L 99 F 9B R 9D B 9F falcon

# ---- Castlevania facts (notes/addresses.md section 11)
CV_TILE_BASE = 1 * 0x4000 + 0x1008   # PRG offset of b1:$9008, raw tiles uploaded to table 0 ($0000-$0DFF)
CV_PTR_LO = 0x8FBE                   # frames $00-$7F
CV_PTR_HI = 0x90BE                   # frames $80-$FF
CV_FREE0 = (0xBB01, 0xC000)          # bank 0 free space (verified unused)
CV_SPRPAL0 = 7 * 0x4000 + (0xCDEC - 0xC000)   # sprite palette 0 colours 1-3 in the PPU string at b7:$CDE9
SIMON_PAIRS = [0x02 + 2 * i for i in range(14)] + [0x22, 0x28, 0x2A] + [0x32 + 2 * i for i in range(7)] + \
              [0x4C, 0x4E, 0x5E, 0x6E]
WHIP_PAIRS = [0x1E, 0x20, 0x24, 0x26, 0x2C, 0x2E, 0x30, 0x46, 0x48, 0x56, 0x58, 0x6A, 0x6C]
EMPTY_FRAME_USERS = [0x00, 0x93]     # frames pointing at the empty frame $919C
MOVED_FRAMES = (0x00, 0x01, 0x02, 0x03, 0x04, 0x93)   # their data sits on the pointer slots of $EF-$FF
CV_BACK_FRAME = 0x19                 # Simon from behind at the castle gate (intro)
CV_BACK_TILES = [0xE0, 0xE2, 0xE4, 0xE6, 0xE8, 0xEA]   # table-0 pairs the build's IntroTiles uploads BackTiles to
CV_BACK_PAL = 2                      # sprite palette 2: skin, blue, black (the commando's)
# The commando seen from behind (16 x 48: 33 px tall like his side view, feet on the last row), an original
# drawing for this project (Super C has no such pose): bandana tails, bare back with blue shading, rifle held
# at his right side. . transparent, s skin (1), b blue (2), k black (3).
BACK_VIEW = [
"................",
"................",
"................",
"................",
"................",
"................",
"................",
"................",
"................",
"................",
"................",
"................",
"..............k.",
"..............k.",
".............kbk",
".....kkk.....ksk",
"....kkkkk....kbk",
"...bbbbbbb...kbk",
"..bbkkkkkk...ksk",
".bb.kkkkkk...kbk",
".b..skkkks...kbk",
"b....kkkk....ksk",
"......ss.....kbk",
"..kssssssk...kbk",
".ksssbsbsssk.ksk",
"ksbssbsbssbskkbk",
"ksbsssbsssbskkbb",
"ksbbssbssbbskkbk",
"ksk.bsbsb.kskkbk",
"ksk.kbbbk.kskkbk",
"ksk.kbbbk.kssskk",
"ss..kkkkk..ssssk",
"...kbbbbbk..kbbk",
"...kbbbbbbk.kbbk",
"..kbbbbkbbk.kbbk",
"..kbbbbkbbk..kk.",
"..kbbbkkbbbk....",
"..kbbbk.kbbk....",
"..kbbbk.kbbbk...",
"..kbbk..kbbbk...",
"..kbbbk.kbbbk...",
"..kbbbk..kbbk...",
"..kbbbk..kbbk...",
"..kbbk...kbbk...",
"..kbbk...kbbk...",
".kkkkk...kkkkk..",
".kkkkkk..kkkkkk.",
".kkkkkk..kkkkkk.",
]
CV_ITEM_T1 = 1 * 0x4000 + 0x2008     # PRG offset of b1:$A008: table-1 pair p at + 16 * p (tile set 3, b1:$9FE8 -> $0FE0)
CV_HUD_ICONS = 6 * 0x4000 + 0x2151   # b6:$A151 + 3 * (weapon id - 8): attribute, left tile, right tile
LETTER_PAL = 3                       # sprite palette 3 (red, light pink, black)
LETTER_COLOURS = [0, 2, 1, 3]        # Super C white -> light pink, red -> red
WING_TILE = 0xBB                     # the one wing tile (the dagger's second tile)
# Castlevania item -> Super C letter: (Super C letter tile, item frames, letter tile, HUD weapon id or None).
# The item's first tile takes the letter; the frame becomes wing | letter | mirrored wing.
FALCON = [
    (0x93, [0x50], 0xBD, 0x08),         # dagger -> M
    (0x95, [0x28], 0x52, 0x09),         # cross -> S
    (0x97, [0x2B], 0xA1, 0x0B),         # holy water -> L
    (0x99, [0x4C], 0xB7, 0x0D),         # axe -> F
    (0x9B, [0x6E, 0x6F], 0xC1, None),   # whip upgrade (6E is a copy of 6F) -> R
    (0x9D, [0x2C], 0x42, None),         # potion (and the stopwatch, drawn as it) -> B
    (0x9F, [0x72], 0xAD, None),         # rosary (clears the screen) -> falcon
]
# Free item tiles for bullets: the other items' second tiles (only their item frames, now falcons, and the
# thrown axe used them) and the multiplier's two (it never drops: no subweapon hits).
BULLET_ITEM_TILES = [0xA3, 0xB9, 0xC3, 0xAF, 0xA5, 0xA7]
BULLET_PAL = 0                       # sprite palette 0: orange, cream, brown
BULLET_COLOURS = [0, 2, 1, 3]        # Super C white -> cream, salmon -> orange, red -> brown

# ---- the commando build (src/commando/commando.asm)
BUILD_BANK = 6                       # PoseMap
BULLET_BANK = 5                      # BulletFrames, LaserFrames
BULLET_SYMBOL = "BulletFrames"       # metasprite per bullet kind: rifle, M, S, L, F, charged F, fragment
BUILD_BULLET_FRAMES = bytes([0x50] * 7)   # the dagger's metasprite, as built
LASER_SYMBOL = "LaserFrames"         # laser segment by direction: right, down-right, down, ... up-right
BUILD_LASER_FRAMES = bytes([0x50] * 8)
BACK_SYMBOL = "BackTiles"            # bank 6: the back view's 6 tile pairs, zero as built
BACK_LEN = 6 * 32
POSEMAP_SYMBOL = "PoseMap"           # aim up (+firing), diagonal up x3, somersault x4, stand firing, diagonal down x3, prone (+firing)
BUILD_POSEMAP = bytes([0x01, 0x01, 0x02, 0x03, 0x04, 0x05, 0x05, 0x05, 0x05, 0x01,
                       0x02, 0x03, 0x04, 0x05, 0x05])                        # Simon's frames, as built
COMMANDO_POSEMAP = bytes([0xEF, 0xF0, 0xF1, 0xF2, 0xF3, 0xF9, 0xFA, 0xFB, 0xFC, 0x08,
                          0xF4, 0xF5, 0xF6, 0xF7, 0xF8])                     # 08 <- Super C 0B (stand firing)

# Simon's frames -> Super C side-view frames (Super C ids: 06-0A run with the gun forward, 08 stand, 0B stand
# firing, 07 = stride, 23/24 kneel (+fire), 1E curled (death 1), 22 lying dead). Castlevania keeps its moveset.
MOVESET = {
    0x01: 0x08,                               # stand
    0x02: 0x06, 0x03: 0x07, 0x04: 0x09,       # walk
    0x05: 0x23,                               # crouch, also the jump frame
    0x06: 0x08, 0x07: 0x08, 0x08: 0x0B,       # attack (subweapon throw): wind-up, swing, release -> recoil
    0x09: 0x23, 0x0A: 0x23, 0x0B: 0x24,       # crouching attack
    0x0D: 0x07, 0x0E: 0x07, 0x0F: 0x07,       # stairs step frames
    0x97: 0x1E,                               # hurt
    0x98: 0x22,                               # dead
    0x99: 0x23,                               # kneel
    0xA4: 0x08, 0xA5: 0x08, 0xA6: 0x0B,       # attack on stairs (up)
    0xA7: 0x08, 0xA8: 0x08, 0xA9: 0x08, 0xAA: 0x08, 0xAB: 0x08, 0xAC: 0x0B,   # attack on stairs (down)
}
# Poses for the Super C moveset (milestone 2), at the freed ids $EF-$FC; feet line of Simon's stand frame.
POSES = {
    0xEF: 0x18, 0xF0: 0x19,                   # aim up, aim up firing
    0xF1: 0x0C, 0xF2: 0x0D, 0xF3: 0x0E,       # run aiming diagonally up
    0xF4: 0x11, 0xF5: 0x12, 0xF6: 0x13,       # run aiming diagonally down
    0xF7: 0x16, 0xF8: 0x17,                   # prone, prone firing
    0xF9: 0x1A, 0xFA: 0x1B, 0xFB: 0x1C, 0xFC: 0x1D,   # somersault
}
# Bullets: Castlevania frame id <- Super C object graphic (bank 0 code 00:8EF5 and 00:9311 pick them): the whip's
# frame ids, never drawn in the commando build.
BULLETS = {
    0x10: 0x05,                               # rifle
    0x11: 0x19,                               # M (also the fire ball's first frames in Super C)
    0x12: 0x06,                               # S
    0x13: 0x16, 0x14: 0x15,                   # laser: horizontal, vertical
    0x15: 0x17, 0x16: 0x18,                   # laser: up-right "/", down-right "\\" (left ones are mirrored)
    0x17: 0x03,                               # fire ball (Super C's fragments too)
    0x18: 0x1A,                               # charged fire ball
}
# rifle, M, S, L (the laser's frame is picked by direction), F, charged F, fragment. The fragments use S's
# one-sprite ball: Super C's two-sprite ball cost ~20 more lag frames per 1,200 under constant F fire in stage 12.
COMMANDO_BULLET_FRAMES = bytes([0x10, 0x11, 0x12, 0x13, 0x17, 0x18, 0x12])
COMMANDO_LASER_FRAMES = bytes([0x13, 0x16, 0x14, 0x16, 0x13, 0x15, 0x14, 0x15])   # as Super C's 00:9311

def crc(b):
    return zlib.crc32(b) & 0xFFFFFFFF


class SuperC:
    def __init__(self, data):
        if data[:4] != b"NES\x1a" or (data[6] >> 4 | (data[7] & 0xF0)) != 4:
            sys.exit("Super C: not an MMC3 iNES image")
        self.prg = data[16:16 + SC_PRG_SIZE]
        self.chr = data[16 + SC_PRG_SIZE:16 + SC_PRG_SIZE + 0x20000]
        if crc(self.prg) != SC_PRG_CRC or crc(self.chr) != SC_CHR_CRC:
            sys.exit("Super C: unexpected dump (PRG %08X CHR %08X); only Super C (USA) is known" %
                     (crc(self.prg), crc(self.chr)))
        self.spr = b"".join(self.chr[b * 0x400:(b + 1) * 0x400] for b in SC_SPR_BANKS)

    def rd(self, a):
        return self.prg[SC_BANK36 + a - 0x8000]

    def frame(self, f):
        """Super C player frame f (1-based) -> list of (y, tile, attr, x)."""
        a = SC_PLAYER_TABLE + 2 * (f - 1)
        p = self.rd(a) | self.rd(a + 1) << 8
        n, cur, i, out = self.rd(p), p, 1, []
        while len(out) < n:
            b = self.rd(cur + i)
            if b == 0x80:                       # continue at another address
                cur, i = self.rd(cur + i + 1) | self.rd(cur + i + 2) << 8, 0
                continue
            s = lambda v: v - 256 if v >= 128 else v
            out.append((s(b), self.rd(cur + i + 1), self.rd(cur + i + 2), s(self.rd(cur + i + 3))))
            i += 4
        return out

    def obj(self, g):
        """Super C object graphic g (bank $36 table $8205) -> list of (y, tile, attr, x)."""
        p = self.rd(SC_OBJ_TABLE + 2 * g) | self.rd(SC_OBJ_TABLE + 2 * g + 1) << 8
        n = self.rd(p)
        if n & 0x80:                            # one sprite, tile 2n+1, centred ($81E3)
            return [(-8, (n << 1 | 1) & 0xFF, 0, -4)]
        s = lambda v: v - 256 if v >= 128 else v
        return [(s(self.rd(p + 1 + i)), self.rd(p + 2 + i), self.rd(p + 3 + i), s(self.rd(p + 4 + i)))
                for i in range(0, n, 4)]

    def tile16(self, t, banks=SC_SPR_BANKS):
        """32 bytes of the 8x16 sprite t (odd = PPU $1000 table): top 8x8 then bottom 8x8."""
        spr = self.spr if banks == SC_SPR_BANKS else b"".join(self.chr[b * 0x400:(b + 1) * 0x400] for b in banks)
        base = (t & 0xFE) * 16
        return spr[base:base + 32]

    def p1_colours(self):
        return self.prg[SC_AREA1_SPR_PAL:SC_AREA1_SPR_PAL + 6]   # legs (3), torso (3)


class Castlevania:
    def __init__(self, data):
        self.hdr, self.prg = bytearray(data[:16]), bytearray(data[16:])
        if len(self.prg) != 0x20000:
            sys.exit("Castlevania: expected a 128 KiB PRG")
        self.written = set()

    @staticmethod
    def off(bank, a):
        return bank * 0x4000 + a - (0xC000 if bank == 7 else 0x8000)

    def rd0(self, a):
        return self.prg[self.off(0, a)]

    def write(self, o, data):
        self.prg[o:o + len(data)] = data
        self.written.update(range(o, o + len(data)))

    def ptr_addr(self, f):
        return (CV_PTR_LO if f < 0x80 else CV_PTR_HI) + 2 * (f & 0x7F)

    def frame_ptr(self, f):
        a = self.ptr_addr(f)
        return self.rd0(a) | self.rd0(a + 1) << 8

    def set_ptr(self, f, p):
        self.write(self.off(0, self.ptr_addr(f)), bytes([p & 0xFF, p >> 8]))

    def frame(self, f):
        """Castlevania frame -> list of (y, tile, attr, x) (b0:$8052 format, $80/$81 sub-lists)."""
        p = self.frame_ptr(f)
        n, cur, i, out, ret, attr = self.rd0(p), p, 1, [], None, 0
        while len(out) < n:
            b = self.rd0(cur + i)
            if b == 0x80:
                ret, cur, i = (cur, i + 3), self.rd0(cur + i + 1) | self.rd0(cur + i + 2) << 8, 0
                continue
            if b == 0x81:
                cur, i = ret
                continue
            y = (b >> 1) - (128 if b & 0x80 else 0)
            t = self.rd0(cur + i + 1)
            i += 2
            if not b & 1:
                attr = self.rd0(cur + i)
                i += 1
            x = self.rd0(cur + i)
            out.append((y, t, attr, x - 256 if x >= 128 else x))
            i += 1
        return out

    def tile16(self, pair):
        o = CV_TILE_BASE + 16 * pair
        return bytes(self.prg[o:o + 32])

    def put_item_tile(self, t, data):
        """an item tile: odd = table-1 pair (tile set 3 source), even = table-0 pair (raw at b1:$9008)"""
        if t & 1:
            self.write(CV_ITEM_T1 + 16 * (t & 0xFE), data)
        else:
            self.put_tile16(t, data)

    def put_tile16(self, pair, data):
        self.write(CV_TILE_BASE + 16 * pair, data)


def opaque_rows(tile32, vflip):
    """16 booleans: does row r of the 8x16 tile have an opaque pixel?"""
    out = []
    for r in range(16):
        half, rr = (0, r) if r < 8 else (16, r - 8)
        out.append(bool(tile32[half + rr] | tile32[half + rr + 8]))
    return out[::-1] if vflip else out


def remap_colours(tile32, mapping):
    """Re-index the 2-bit colours of an 8x16 tile (mapping[c] for c = 0..3)."""
    out = bytearray(32)
    for half in (0, 16):
        for r in range(8):
            lo, hi = tile32[half + r], tile32[half + r + 8]
            nlo = nhi = 0
            for bit in range(8):
                c = mapping[((lo >> bit) & 1) | (((hi >> bit) & 1) << 1)]
                nlo |= (c & 1) << bit
                nhi |= (c >> 1) << bit
            out[half + r], out[half + r + 8] = nlo, nhi
    return bytes(out)


def bottom(entries, tile_of):
    """Lowest opaque row (relative to the origin) of a frame."""
    best = -999
    for y, t, a, x in entries:
        rows = opaque_rows(tile_of(t), a & 0x80)
        for r in range(16):
            if rows[r]:
                best = max(best, y + r)
    return best


def read_symbol(path, name):
    for line in open(path):
        m = re.match(r"(\S+) = \$([0-9A-Fa-f]+)$", line.strip())
        if m and m.group(1) == name:
            return int(m.group(2), 16)
    sys.exit(f"{path}: symbol {name} not found (rebuild the commando target)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", required=True, help="the commando build (build/castlevania-commando.nes)")
    ap.add_argument("--sym", required=True, help="its symbols (build/castlevania-commando.sym)")
    ap.add_argument("--orig", required=True, help="the original Castlevania (USA) Rev 1 image")
    ap.add_argument("--superc", required=True, help="your Super C (USA) dump")
    ap.add_argument("--out", required=True, help="new ROM (contains Super C graphics: keep it private)")
    ap.add_argument("--colours", choices=["pal2", "p1"], default="pal2")
    ap.add_argument("--report", action="store_true")
    a = ap.parse_args()

    sc = SuperC(open(a.superc, "rb").read())
    orig = Castlevania(open(a.orig, "rb").read())
    if crc(bytes(orig.prg)) != CV_PRG_CRC:
        sys.exit("--orig: expected the Castlevania (USA) Rev 1 PRG (CRC32 %08X)" % CV_PRG_CRC)
    cv = Castlevania(open(a.base, "rb").read())
    if cv.prg == orig.prg:
        sys.exit("--base is the unmodified game; build the commando target first")
    op = Castlevania.off(BULLET_BANK, read_symbol(a.sym, BULLET_SYMBOL))
    if bytes(cv.prg[op:op + len(BUILD_BULLET_FRAMES)]) != BUILD_BULLET_FRAMES:
        sys.exit("--base: %s doesn't hold the dagger's frames (the .sym doesn't match this build)" % BULLET_SYMBOL)
    ol = Castlevania.off(BULLET_BANK, read_symbol(a.sym, LASER_SYMBOL))
    if bytes(cv.prg[ol:ol + len(BUILD_LASER_FRAMES)]) != BUILD_LASER_FRAMES:
        sys.exit("--base: %s doesn't hold the dagger's frames (the .sym doesn't match this build)" % LASER_SYMBOL)
    ob = Castlevania.off(BUILD_BANK, read_symbol(a.sym, BACK_SYMBOL))
    if any(cv.prg[ob:ob + BACK_LEN]):
        sys.exit("--base: %s isn't empty (the .sym doesn't match this build)" % BACK_SYMBOL)
    pm = Castlevania.off(BUILD_BANK, read_symbol(a.sym, POSEMAP_SYMBOL))
    if bytes(cv.prg[pm:pm + len(BUILD_POSEMAP)]) != BUILD_POSEMAP:
        sys.exit("--base: %s doesn't hold Simon's frames (the .sym doesn't match this build)" % POSEMAP_SYMBOL)
    orig_tile = orig.tile16

    # palette per Super C sprite palette (0 = legs, 1 = torso)
    cv_pal = {0: 2, 1: 2} if a.colours == "pal2" else {0: 2, 1: 0}
    pairs = SIMON_PAIRS + WHIP_PAIRS

    # tiles to import, in order of first use; the bullets take the pairs left over, then the free item tiles
    want = []
    for f in list(MOVESET.values()) + list(POSES.values()):
        for y, t, at, x in sc.frame(f):
            if t not in want:
                want.append(t)
    bullet_tiles = []
    for g in BULLETS.values():
        for y, t, at, x in sc.obj(g):
            if t not in bullet_tiles:
                bullet_tiles.append(t)
    if set(want) & set(bullet_tiles):
        sys.exit("a Super C bullet tile is also a commando tile")
    room = pairs[len(want):] + BULLET_ITEM_TILES
    if len(want) > len(pairs) or len(bullet_tiles) > len(room):
        sys.exit("tile budget exceeded: %d commando + %d bullet tiles > %d pairs + %d item tiles" %
                 (len(want), len(bullet_tiles), len(pairs), len(BULLET_ITEM_TILES)))
    slot = dict(zip(want, pairs))
    for t, p in slot.items():
        cv.put_tile16(p, sc.tile16(t))
    bslot = dict(zip(bullet_tiles, room))
    for t, p in bslot.items():
        cv.put_item_tile(p, remap_colours(sc.tile16(t), BULLET_COLOURS))

    # feet lines: Simon's frames with the original tiles, Super C frames with Super C tiles
    cv_bottom = {f: bottom(orig.frame(f), orig_tile) for f in MOVESET}
    stand_bottom = cv_bottom[0x01]

    blob = bytearray([0])                      # empty frame for ids 00 and 93
    addr, rep, cache = {}, [], {}

    def emit(sc_id, dy):
        out = bytearray([len(sc.frame(sc_id))])
        for y, t, at, x in sc.frame(sc_id):
            yy = y + dy
            if not -63 <= yy <= 63:
                sys.exit("Y offset out of range")
            out += bytes([(2 * yy) & 0xFF, slot[t], (at & 0xE0) | cv_pal[at & 1], x & 0xFF])
        return bytes(out)

    for f in sorted(MOVESET) + sorted(POSES):
        s = MOVESET.get(f, POSES.get(f))
        dy = cv_bottom.get(f, stand_bottom) - bottom(sc.frame(s), sc.tile16)
        if (s, dy) not in cache:
            cache[(s, dy)] = CV_FREE0[0] + len(blob)
            blob += emit(s, dy)
        addr[f] = cache[(s, dy)]
        xs = [x for _, _, _, x in sc.frame(s)]
        rep.append("  CV %02X <- SC %02X  dy %+d  %d sprites  %d px wide" % (f, s, dy, len(sc.frame(s)), max(xs) + 8 - min(xs)))
    # bullets: Super C's object sprites, palette 0
    for f, g in BULLETS.items():
        ents = sc.obj(g)
        addr[f] = CV_FREE0[0] + len(blob)
        blob += bytes([len(ents)])
        for y, t, at, x in ents:
            blob += bytes([(2 * y) & 0xFF, bslot[t], (at & 0xC0) | BULLET_PAL, x & 0xFF])
    rep.append("  bullets: frames %s, %d tiles" % (" ".join("%02X" % f for f in BULLETS), len(bullet_tiles)))
    # intro back view: the drawing above, 2 x 3 tiles into the build's BackTiles (uploaded to CV_BACK_TILES)
    def back_tile(col, row):
        out = bytearray(32)
        for half in (0, 1):
            for r in range(8):
                line = BACK_VIEW[row * 16 + half * 8 + r][col * 8:col * 8 + 8]
                lo = hi = 0
                for c, ch in enumerate(line):
                    v = ".sbk".index(ch)
                    lo |= (v & 1) << (7 - c)
                    hi |= (v >> 1) << (7 - c)
                out[half * 16 + r], out[half * 16 + r + 8] = lo, hi
        return bytes(out)
    assert len(BACK_VIEW) == 48 and all(len(r) == 16 for r in BACK_VIEW)
    back_data, back = bytearray(), []
    top = stand_bottom - 47                    # feet on the walk frames' feet line (Simon's back view is 1 px lower)
    for n, (col, row) in enumerate(((0, 0), (1, 0), (0, 1), (1, 1), (0, 2), (1, 2))):
        data = back_tile(col, row)
        back_data += data
        if any(data):
            back.append((top + 16 * row, CV_BACK_TILES[n], CV_BACK_PAL, 8 * col - 8))
    addr[CV_BACK_FRAME] = CV_FREE0[0] + len(blob)
    blob += bytes([len(back)])
    for y, t, at, x in back:
        blob += bytes([(2 * y) & 0xFF, t, at, x & 0xFF])
    rep.append("  CV %02X <- the drawn back view  top %+d  %d sprites" % (CV_BACK_FRAME, top, len(back)))

    # falcon letters for the pickups, and the HUD weapon icon (wing | letter)
    wing_t = WING_TILE
    cv.put_item_tile(wing_t, remap_colours(sc.tile16(SC_WING), LETTER_COLOURS))
    for sc_letter, frames, letter_t, hud_id in FALCON:
        cv.put_item_tile(letter_t, remap_colours(sc.tile16(sc_letter), LETTER_COLOURS))
        p = CV_FREE0[0] + len(blob)
        for frame in frames:
            addr[frame] = p
        blob += bytes([3, (2 * -8) & 0xFF, wing_t, LETTER_PAL, (-12) & 0xFF,
                          (2 * -8) & 0xFF, letter_t, LETTER_PAL, (-4) & 0xFF,
                          (2 * -8) & 0xFF, wing_t, LETTER_PAL | 0x40, 4])
        if hud_id is not None:
            cv.write(CV_HUD_ICONS + 3 * (hud_id - 8), bytes([LETTER_PAL, wing_t, letter_t]))
    rep.append("  falcon letters: %d items, HUD icons for M S L F" % len(FALCON))
    if CV_FREE0[0] + len(blob) > CV_FREE0[1]:
        sys.exit("frame data does not fit in bank 0 free space")
    cv.write(cv.off(0, CV_FREE0[0]), bytes(blob))
    for f in EMPTY_FRAME_USERS:
        cv.set_ptr(f, CV_FREE0[0])
    for f, p in addr.items():
        cv.set_ptr(f, p)
    for f in MOVED_FRAMES:                     # their old data is now under the pointer slots $EF-$FF
        assert cv.frame_ptr(f) >= CV_FREE0[0]

    if a.colours == "p1":
        cv.write(CV_SPRPAL0, sc.p1_colours()[3:6])

    # everything written so far must still be original in the base
    base_prg = open(a.base, "rb").read()[16:]
    clash = sorted(o for o in cv.written if base_prg[o] != orig.prg[o])
    if clash:
        sys.exit("--base changed bytes this installer overwrites (first at PRG $%05X); refusing" % clash[0])
    cv.prg[op:op + len(COMMANDO_BULLET_FRAMES)] = COMMANDO_BULLET_FRAMES
    cv.prg[ol:ol + len(COMMANDO_LASER_FRAMES)] = COMMANDO_LASER_FRAMES
    cv.prg[ob:ob + BACK_LEN] = back_data
    cv.prg[pm:pm + len(COMMANDO_POSEMAP)] = COMMANDO_POSEMAP

    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    open(a.out, "wb").write(bytes(cv.hdr) + bytes(cv.prg))
    print("wrote %s: %d commando tiles into %d pairs, %d bullet tiles, %d frame bytes at b0:$%04X, colours %s "
          "(keep this ROM private)" %
          (a.out, len(want), len(pairs), len(bullet_tiles), len(blob), CV_FREE0[0], a.colours))
    if a.report:
        print("\n".join(rep))
        print("  tile pairs used: " + " ".join("%02X" % slot[t] for t in want))
        print("  bullet tiles: " + " ".join("SC %02X -> %02X" % (t, p) for t, p in bslot.items()))


if __name__ == "__main__":
    main()
