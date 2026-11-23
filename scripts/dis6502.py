#!/usr/bin/env python3
"""Minimal bank-aware 6502 disassembler for UNROM images.

Usage:
  dis6502.py <rom.nes> <bank> <start> [end]      linear disassembly
  dis6502.py <rom.nes> <bank> <start> --count N  N instructions

The last bank (7, or 15 in the expanded ROM) is fixed at $C000; the others map at $8000.
Addresses are hex (with or without $ / 0x).
"""
import sys

# mode: (operand bytes, format)
MODES = {
    "imp": (0, "{op}"), "acc": (0, "{op} A"), "imm": (1, "{op} #${v:02X}"),
    "zp": (1, "{op} ${v:02X}"), "zpx": (1, "{op} ${v:02X},X"), "zpy": (1, "{op} ${v:02X},Y"),
    "izx": (1, "{op} (${v:02X},X)"), "izy": (1, "{op} (${v:02X}),Y"),
    "abs": (2, "{op} ${v:04X}"), "abx": (2, "{op} ${v:04X},X"), "aby": (2, "{op} ${v:04X},Y"),
    "ind": (2, "{op} (${v:04X})"), "rel": (1, "{op} ${t:04X}"),
}

_T = """
00 BRK imp|01 ORA izx|05 ORA zp|06 ASL zp|08 PHP imp|09 ORA imm|0A ASL acc|0D ORA abs|0E ASL abs
10 BPL rel|11 ORA izy|15 ORA zpx|16 ASL zpx|18 CLC imp|19 ORA aby|1D ORA abx|1E ASL abx
20 JSR abs|21 AND izx|24 BIT zp|25 AND zp|26 ROL zp|28 PLP imp|29 AND imm|2A ROL acc|2C BIT abs|2D AND abs|2E ROL abs
30 BMI rel|31 AND izy|35 AND zpx|36 ROL zpx|38 SEC imp|39 AND aby|3D AND abx|3E ROL abx
40 RTI imp|41 EOR izx|45 EOR zp|46 LSR zp|48 PHA imp|49 EOR imm|4A LSR acc|4C JMP abs|4D EOR abs|4E LSR abs
50 BVC rel|51 EOR izy|55 EOR zpx|56 LSR zpx|58 CLI imp|59 EOR aby|5D EOR abx|5E LSR abx
60 RTS imp|61 ADC izx|65 ADC zp|66 ROR zp|68 PLA imp|69 ADC imm|6A ROR acc|6C JMP ind|6D ADC abs|6E ROR abs
70 BVS rel|71 ADC izy|75 ADC zpx|76 ROR zpx|78 SEI imp|79 ADC aby|7D ADC abx|7E ROR abx
81 STA izx|84 STY zp|85 STA zp|86 STX zp|88 DEY imp|8A TXA imp|8C STY abs|8D STA abs|8E STX abs
90 BCC rel|91 STA izy|94 STY zpx|95 STA zpx|96 STX zpy|98 TYA imp|99 STA aby|9A TXS imp|9D STA abx
A0 LDY imm|A1 LDA izx|A2 LDX imm|A4 LDY zp|A5 LDA zp|A6 LDX zp|A8 TAY imp|A9 LDA imm|AA TAX imp|AC LDY abs|AD LDA abs|AE LDX abs
B0 BCS rel|B1 LDA izy|B4 LDY zpx|B5 LDA zpx|B6 LDX zpy|B8 CLV imp|B9 LDA aby|BA TSX imp|BC LDY abx|BD LDA abx|BE LDX aby
C0 CPY imm|C1 CMP izx|C4 CPY zp|C5 CMP zp|C6 DEC zp|C8 INY imp|C9 CMP imm|CA DEX imp|CC CPY abs|CD CMP abs|CE DEC abs
D0 BNE rel|D1 CMP izy|D5 CMP zpx|D6 DEC zpx|D8 CLD imp|D9 CMP aby|DD CMP abx|DE DEC abx
E0 CPX imm|E1 SBC izx|E4 CPX zp|E5 SBC zp|E6 INC zp|E8 INX imp|E9 SBC imm|EA NOP imp|EC CPX abs|ED SBC abs|EE INC abs
F0 BEQ rel|F1 SBC izy|F5 SBC zpx|F6 INC zpx|F8 SED imp|F9 SBC aby|FD SBC abx|FE INC abx
"""
OPS = {}
for ent in _T.replace("\n", "|").split("|"):
    ent = ent.strip()
    if ent:
        h, m, mode = ent.split()
        OPS[int(h, 16)] = (m, mode)


def load_prg(path):
    d = open(path, "rb").read()
    return d[16:16 + d[4] * 0x4000]


def bank_base(bank, fixed=7):
    return 0xC000 if bank == fixed else 0x8000


def cpu_to_off(bank, addr):
    return bank * 0x4000 + (addr - bank_base(bank))


def read(prg, bank, addr):
    """Read a byte as the CPU sees it with `bank` in the switchable window."""
    addr &= 0xFFFF
    if addr >= 0xC000:
        return prg[len(prg) - 0x4000 + addr - 0xC000]     # fixed (last) bank
    return prg[bank * 0x4000 + addr - 0x8000]


def decode(prg, bank, addr):
    """Return (length, mnemonic, mode, operand_value, text)."""
    op = read(prg, bank, addr)
    if op not in OPS:
        return 1, ".db", "imp", op, f".db ${op:02X}"
    m, mode = OPS[op]
    n, fmt = MODES[mode]
    v = 0
    if n == 1:
        v = read(prg, bank, addr + 1)
    elif n == 2:
        v = read(prg, bank, addr + 1) | read(prg, bank, addr + 2) << 8
    t = 0
    if mode == "rel":
        t = (addr + 2 + (v - 256 if v >= 128 else v)) & 0xFFFF
        v = t
    return n + 1, m, mode, v, fmt.format(op=m, v=v, t=t)


def disasm(prg, bank, start, end=None, count=None):
    out = []
    a = start
    i = 0
    while (end is None or a < end) and (count is None or i < count):
        n, m, mode, v, text = decode(prg, bank, a)
        raw = " ".join(f"{read(prg, bank, a + k):02X}" for k in range(n))
        tag = f"{bank:02d}:{a:04X}" if a < 0xC000 else f"{len(prg) // 0x4000 - 1:02d}:{a:04X}"
        out.append(f"{tag}  {raw:<9} {text}")
        a += n
        i += 1
    return out


def parse_hex(s):
    return int(s.replace("$", "").replace("0x", ""), 16)


def main():
    args = sys.argv[1:]
    if len(args) < 3:
        print(__doc__)
        sys.exit(1)
    prg = load_prg(args[0])
    bank = int(args[1])
    start = parse_hex(args[2])
    end = count = None
    if "--count" in args:
        count = int(args[args.index("--count") + 1])
    elif len(args) > 3:
        end = parse_hex(args[3])
    else:
        count = 40
    print("\n".join(disasm(prg, bank, start, end, count)))


if __name__ == "__main__":
    main()
