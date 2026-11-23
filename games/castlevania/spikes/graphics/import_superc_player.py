#!/usr/bin/env python3
"""Spike: draw the Super C commando in place of Simon, importing the graphics from the user's own Super C dump.

This is the "asset route 1" prototype (TODO.md item 2): the installer reads BOTH ROMs that the user owns and writes a
new Castlevania image. Neither this file nor anything in this repository contains Super C data: the script only knows
addresses and frame numbers, and copies the tiles, frame layouts and (optionally) the colours from the Super C file at
run time. The output ROM contains Super C graphics, so it must stay on the user's machine: never commit or share it.

What it does (details and measurements: README.md next to this file):
  1. Reads Super C's player frames (PRG bank $36, pointer table $8F31; entries [Y, tile, attr, X]) and the 8x16
     sprite tiles of stage 1 (MMC3 1 KiB CHR banks $44-$47, mapped at PPU $1000 during play).
  2. Picks the frames named in a preset (Castlevania frame id -> Super C frame id), collects their distinct
     8x16 tiles and writes them into Simon's tile pairs (and the whip's pairs for the "full" preset) in the raw
     tile block at b1:$9008 + 16 * tile, which the game uploads to CHR-RAM table 0.
  3. Writes new metasprites in Castlevania's format ([2*Y (+1 = keep attr)] [tile] [attr] [X]) into bank 0's free
     space $BB01-$BFFF and points the frame table (b0:$8FBE / $90BE) at them. Frames 00-04 and 93 are moved too,
     which frees the pointer slots of the unused ids $EF-$FF for new poses (aim up, prone, ...).
  4. Aligns each Super C pose on the feet of the Simon frame it replaces (bottom opaque row).
  5. Colours: "pal2" (default) draws the whole commando with Castlevania's sprite palette 2 (skin, blue, black),
     which has the same colour order as Super C's player palettes, so no palette is changed. "p1" draws the
     torso with palette 0 and overwrites palette 0 with Super C's player-1 torso colours read from the Super C
     file (legs stay on palette 2).

Usage:
  import_superc_player.py --cv <castlevania usa v1.1 .nes> --superc <Super C (U) .nes> --out <new .nes>
                          [--preset looks|full] [--colours pal2|p1] [--report]
"""
import argparse
import sys
import zlib

CV_PRG_CRC = 0xB668C7FC          # Castlevania (USA) Rev 1, PRG only
SC_PRG_CRC = 0xC7FBECC3          # Super C (USA), PRG only (checked on the user's dump)
SC_CHR_CRC = 0x153295C1          # Super C (USA), CHR-ROM

# ---- Super C facts (addresses only; data is read from the user's file)
SC_PRG_SIZE = 0x20000
SC_BANK36 = 0xC000               # PRG offset of 8 KiB bank $36 (mapped at $8000 when the sprite engine runs)
SC_PLAYER_TABLE = 0x8F31         # word table, entry for frame id 1 first
SC_SPR_BANKS = (0x44, 0x45, 0x46, 0x47)   # 1 KiB CHR banks of PPU $1000-$1FFF in stage 1 (measured)
SC_AREA1_SPR_PAL = 0xF8D5        # PRG offset: area-1 sprite palettes, 3 bytes each (pal 0 = P1 legs, pal 1 = torso)

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

# Simon's frames -> Super C side-view frames (Super C ids: 06-0A run with the gun forward, 08 stand, 0B stand
# firing, 07 = stride, 23/24 kneel (+fire), 1E curled (death 1), 22 lying dead). Castlevania keeps its moveset.
LOOKS = {
    0x01: 0x08,                               # stand
    0x02: 0x06, 0x03: 0x07, 0x04: 0x09,       # walk
    0x05: 0x23,                               # crouch, also the jump frame
    0x06: 0x08, 0x07: 0x08, 0x08: 0x0B,       # whip: wind-up, swing, hit frame -> recoil
    0x09: 0x23, 0x0A: 0x23, 0x0B: 0x24,       # crouching whip
    0x0D: 0x07, 0x0E: 0x07, 0x0F: 0x07,       # stairs step frames
    0x97: 0x1E,                               # hurt (knockback)
    0x98: 0x22,                               # dead
    0x99: 0x23,                               # kneel
    0xA4: 0x08, 0xA5: 0x08, 0xA6: 0x0B,       # whip on stairs (up)
    0xA7: 0x08, 0xA8: 0x08, 0xA9: 0x08, 0xAA: 0x08, 0xAB: 0x08, 0xAC: 0x0B,   # whip on stairs (down)
}
# New poses for a Super C moveset, at the freed ids $EF-$FF; the feet line is that of Simon's stand frame.
NEW = {
    0xEF: 0x18, 0xF0: 0x19,                   # aim up, aim up firing
    0xF1: 0x0C, 0xF2: 0x0D, 0xF3: 0x0E,       # run aiming diagonally up
    0xF4: 0x11, 0xF5: 0x12, 0xF6: 0x13,       # run aiming diagonally down
    0xF7: 0x16, 0xF8: 0x17,                   # prone, prone firing
    0xF9: 0x1A, 0xFA: 0x1B, 0xFB: 0x1C, 0xFC: 0x1D,   # somersault
}
# Super C bullet tiles (8x16, single sprites): default, M/F, S (object frames $05, $19, $06)
BULLET_TILES = [0x01, 0xA1, 0xA3]


def crc(b):
    return zlib.crc32(b) & 0xFFFFFFFF


class SuperC:
    def __init__(self, data):
        if data[:4] != b"NES\x1a" or (data[6] >> 4 | (data[7] & 0xF0)) != 4:
            sys.exit("Super C: not an MMC3 iNES image")
        self.prg = data[16:16 + SC_PRG_SIZE]
        self.chr = data[16 + SC_PRG_SIZE:16 + SC_PRG_SIZE + 0x20000]
        if crc(self.prg) != SC_PRG_CRC or crc(self.chr) != SC_CHR_CRC:
            sys.exit("Super C: unexpected dump (PRG %08X CHR %08X); this spike knows only Super C (USA)" %
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

    def tile16(self, t):
        """32 bytes of the 8x16 sprite t (odd = PPU $1000 table): top 8x8 then bottom 8x8."""
        base = (t & 0xFE) * 16
        return self.spr[base:base + 32]

    def p1_colours(self):
        return self.prg[SC_AREA1_SPR_PAL:SC_AREA1_SPR_PAL + 6]   # legs (3), torso (3)


class Castlevania:
    def __init__(self, data):
        self.hdr, self.prg = bytearray(data[:16]), bytearray(data[16:])
        if len(self.prg) != 0x20000 or crc(bytes(self.prg)) != CV_PRG_CRC:
            sys.exit("Castlevania: expected the USA Rev 1 PRG (CRC32 %08X)" % CV_PRG_CRC)

    def off(self, bank, a):
        return bank * 0x4000 + a - (0xC000 if bank == 7 else 0x8000)

    def rd0(self, a):
        return self.prg[self.off(0, a)]

    def ptr_addr(self, f):
        return (CV_PTR_LO if f < 0x80 else CV_PTR_HI) + 2 * (f & 0x7F)

    def frame_ptr(self, f):
        a = self.ptr_addr(f)
        return self.rd0(a) | self.rd0(a + 1) << 8

    def set_ptr(self, f, p):
        o = self.off(0, self.ptr_addr(f))
        self.prg[o], self.prg[o + 1] = p & 0xFF, p >> 8

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

    def put_tile16(self, pair, data):
        o = CV_TILE_BASE + 16 * pair
        self.prg[o:o + 32] = data


def opaque_rows(tile32, vflip):
    """16 booleans: does row r of the 8x16 tile have an opaque pixel?"""
    out = []
    for r in range(16):
        half, rr = (0, r) if r < 8 else (16, r - 8)
        out.append(bool(tile32[half + rr] | tile32[half + rr + 8]))
    return out[::-1] if vflip else out


def bottom(entries, tile_of):
    """Lowest opaque row (relative to the origin) of a frame."""
    best = -999
    for y, t, a, x in entries:
        rows = opaque_rows(tile_of(t), a & 0x80)
        for r in range(16):
            if rows[r]:
                best = max(best, y + r)
    return best


def remap_colours(tile32, mapping):
    """Re-index the 2-bit colours of an 8x16 tile (mapping[c] for c = 0..3)."""
    if mapping == [0, 1, 2, 3]:
        return tile32
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


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cv", required=True)
    ap.add_argument("--superc", required=True)
    ap.add_argument("--out", required=True, help="new ROM (contains Super C graphics: keep it private)")
    ap.add_argument("--preset", choices=["looks", "full"], default="looks",
                    help="looks: Simon's frames only, into Simon's 28 pairs (whip untouched); "
                         "full: plus new poses at ids $EF-$FC and 3 bullet tiles, into Simon's + the whip's 41 pairs")
    ap.add_argument("--colours", choices=["pal2", "p1"], default="pal2")
    ap.add_argument("--report", action="store_true")
    a = ap.parse_args()

    sc = SuperC(open(a.superc, "rb").read())
    cv = Castlevania(open(a.cv, "rb").read())
    orig_tile = cv.tile16

    # palette per Super C sprite palette (0 = legs, 1 = torso)
    cv_pal = {0: 2, 1: 2} if a.colours == "pal2" else {0: 2, 1: 0}

    mapping = dict(LOOKS)
    new = dict(NEW) if a.preset == "full" else {}
    pairs = SIMON_PAIRS + (WHIP_PAIRS if a.preset == "full" else [])

    # tiles to import, in order of first use
    want = []
    for f in list(mapping.values()) + list(new.values()):
        for y, t, at, x in sc.frame(f):
            if t not in want:
                want.append(t)
    extra = BULLET_TILES if a.preset == "full" else []
    if len(want) + len(extra) > len(pairs):
        sys.exit("tile budget exceeded: %d commando + %d bullet tiles > %d pairs" % (len(want), len(extra), len(pairs)))
    slot = dict(zip(want + extra, pairs))

    # feet lines: Simon's frames with the original tiles, Super C frames with Super C tiles
    cv_bottom = {f: bottom(cv.frame(f), orig_tile) for f in mapping}
    stand_bottom = cv_bottom[0x01]

    # write tiles (colour indices of Super C's player tiles: 1 skin, 2 colour, 3 black = Castlevania palette 2 order;
    # palette 0 in "p1" mode is overwritten with the same order, so no re-indexing is needed in either mode)
    for t, p in slot.items():
        cv.put_tile16(p, sc.tile16(t))

    # build frame data
    blob = bytearray([0])                      # empty frame for ids 00 and 93
    addr = {}
    rep = []

    def emit(sc_id, dy):
        ents = sc.frame(sc_id)
        out = bytearray([len(ents)])
        for y, t, at, x in ents:
            yy = y + dy
            if not -63 <= yy <= 63:
                sys.exit("Y offset out of range")
            out += bytes([(2 * yy) & 0xFF, slot[t], (at & 0xE0) | cv_pal[at & 1], x & 0xFF])
        return bytes(out)

    cache = {}
    for f in sorted(mapping) + sorted(new):
        s = mapping.get(f, new.get(f))
        target = cv_bottom.get(f, stand_bottom)
        dy = target - bottom(sc.frame(s), sc.tile16)
        key = (s, dy)
        if key not in cache:
            cache[key] = CV_FREE0[0] + len(blob)
            blob += emit(s, dy)
        addr[f] = cache[key]
        ents = sc.frame(s)
        xs = [x for _, _, _, x in ents]
        rep.append("  CV %02X <- SC %02X  dy %+d  %d sprites  %d px wide" % (f, s, dy, len(ents), max(xs) + 8 - min(xs)))
    if CV_FREE0[0] + len(blob) > CV_FREE0[1]:
        sys.exit("frame data does not fit in bank 0 free space")
    o = cv.off(0, CV_FREE0[0])
    cv.prg[o:o + len(blob)] = blob
    for f in EMPTY_FRAME_USERS:
        cv.set_ptr(f, CV_FREE0[0])
    for f, p in addr.items():
        cv.set_ptr(f, p)
    # frames 00-04 and 93 no longer use $919C-$91C3, so the pointer slots $EF-$FF (at $919C-$91BD) are free.
    for f in (0x00, 0x01, 0x02, 0x03, 0x04, 0x93):
        assert cv.frame_ptr(f) >= CV_FREE0[0]

    if a.colours == "p1":
        torso = sc.p1_colours()[3:6]
        o = CV_SPRPAL0
        cv.prg[o:o + 3] = torso

    open(a.out, "wb").write(bytes(cv.hdr) + bytes(cv.prg))
    print("wrote %s: %d commando tiles + %d bullet tiles into %d pairs, %d frame bytes at b0:$%04X, colours %s" %
          (a.out, len(want), len(extra), len(pairs), len(blob), CV_FREE0[0], a.colours))
    if a.report:
        print("\n".join(rep))
        print("  tile pairs used: " + " ".join("%02X" % slot[t] for t in want + extra))


if __name__ == "__main__":
    main()
