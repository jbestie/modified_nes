"""Ghosts'n Goblins (NES, USA): game definition for the shared tools.

Read by scripts/build.py (input checks, targets, patches) and
scripts/rom_info.py --game (layout report).  Paths are relative to this
directory.
"""

TITLE = "Ghosts'n Goblins (USA)"

# Expected input image (fields of rom_info.parse); the build refuses anything else.
MAPPER = 2                      # UNROM
PRG_BANKS = 8                   # 8 x 16 KiB
CHR_BANKS = 0                   # CHR-RAM
PRG_CRC = 0xB4E4879E

# Known dumps of that PRG: file CRC32 -> (description, patch suffix, 16-byte header).
# Every patch is also written for the header variants the input doesn't have.
HEADERS = {
    0x87ED54AA: ("iNES 1.0 header (GoodNES '[!]' style)", "ines1-header",
                 bytes.fromhex("4e45531a080021000000000000000000")),
    0x102A8B76: ("NES 2.0 header (No-Intro style)", "nes2-header",
                 bytes.fromhex("4e45531a080021082000000700000001")),
}

# (output name, sources, PRG banks after expansion; 0 = same size)
TARGETS = [
    ("invincible", ["src/invincible.asm"], 0),
    ("ghosts-n-goblins-spread", ["src/invincible.asm", "src/spread.asm"], 0),
    ("ghosts-n-goblins-remix", ["src/remix/bank8.asm", "src/remix/hooks.asm"], 16),
]

# (target, patch file stem, BPS metadata)
PATCHES = [
    ("ghosts-n-goblins-spread", "ghosts-n-goblins-invincible-spread",
     b"Ghosts'n Goblins (USA) - Invincible Arthur + five-way spread shot"),
    ("ghosts-n-goblins-remix", "ghosts-n-goblins-remix",
     b"Ghosts'n Goblins (USA) - Remix: title-menu shot/armor modes, rainbow burst, "
     b"weapon cycling (256 KiB UOROM)"),
]

# Extra paragraph for the free-space section of notes/rom_layout.md
LAYOUT_NOTE = ("A fill run can still be live data: for example $CA76 (32 × $FF) is a blank "
               "nametable row that $CA63 copies to the PPU to clear the screen. Verified caves and the "
               "ones that were rejected are listed in notes/addresses.md.")
