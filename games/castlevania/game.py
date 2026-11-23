"""Castlevania (NES, USA, revision 1 / "V1.1"): game definition for the shared tools.

Read by scripts/build.py (input checks, targets, patches) and
scripts/rom_info.py --game (layout report).  Paths are relative to this
directory.
"""

TITLE = "Castlevania (USA, Rev 1)"

# Expected input image (fields of rom_info.parse); the build refuses anything else.
MAPPER = 2                      # UNROM
PRG_BANKS = 8                   # 8 x 16 KiB
CHR_BANKS = 0                   # CHR-RAM
PRG_CRC = 0xB668C7FC            # USA V1.1; the European (PAL) PRG A93527E2 is not accepted

# Known dumps of that PRG: file CRC32 -> (description, patch suffix, 16-byte header).
# Every patch is also written for the header variants the input doesn't have.
# Only the dump checked so far is listed; add other variants once verified.
HEADERS = {
    0x12A6CB14: ("NES 2.0 header, NTSC (\"Castlevania (U) (V1.1) [!]\")", "nes2-header",
                 bytes.fromhex("4e45531a080021082000000700000001")),
}

# (output name, sources, PRG banks after expansion; 0 = same size)
TARGETS = [
    ("castlevania-commando", ["src/commando/commando.asm", "src/commando/jump_superc.asm"], 0),
]

# (target, patch file stem, BPS metadata)
PATCHES = [
    ("castlevania-commando", "castlevania-commando-mechanics",
     b"Castlevania (USA Rev 1) - Commando prototype 1: run-and-gun mechanics (Simon's graphics)"),
]

# Extra paragraph for the free-space section of notes/rom_layout.md
LAYOUT_NOTE = ("Nothing is verified yet. Most short $00 runs are probably inside data (with CHR-RAM, "
               "the tile graphics are stored in PRG). The long $FF runs at the ends of banks 0-6 are the "
               "usual candidates; the fixed bank 7 has no run of 100 bytes or more. Check every run for "
               "references before using it (notes/addresses.md).")
