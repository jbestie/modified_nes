#!/usr/bin/env python3
"""Tiny two-pass 6502 patch assembler for bank-aware ROM hacks.

Source syntax (one statement per line, ';' starts a comment):

    NAME = expr              constant
    label:                   label at current PC (may precede a statement)
    .bank N                  select PRG bank (the last bank is fixed at $C000,
                             all others are switched in at $8000)
    .org $ADDR               set CPU address inside the selected bank
    .expect HH HH ...        original bytes at the current PC (preimage)
    .expectfill HH, N        original bytes at the current PC are N copies of HH
    .byte e, e, ...          raw bytes
    .word e, ...             little-endian words
    .textmap "C", base, n    map n consecutive characters starting at C to tiles
                             base, base+1, ... (for .text)
    .text "STRING"           emit STRING through the .textmap (unmapped char = error)
    .assert expr, "message"  fail the build if expr is zero (evaluated in pass 2)
    LDA #$10 / STA a:$0040,X / JMP (vec) / BNE label   instructions

Every emitted byte must fall inside a region covered by .expect/.expectfill in
the same bank; the original ROM bytes there must match exactly, otherwise the
build fails.  This makes each patch self-documenting and refuses to patch an
unexpected ROM revision.

Expressions: $hex, %bin, decimal, 'c', labels, + - * / & | ^ << >> <= >= == !=, unary
- < (low byte) > (high byte), parentheses via [ ] (to avoid confusion with
indirect addressing).
"""
import re
import sys

sys.path.insert(0, __import__("os").path.dirname(__file__))
from dis6502 import OPS  # noqa: E402

# (mnemonic, mode) -> opcode
OPC = {(m, mode): op for op, (m, mode) in OPS.items()}
BRANCHES = {"BPL", "BMI", "BVC", "BVS", "BCC", "BCS", "BNE", "BEQ"}
SIZES = {"imp": 1, "acc": 1, "imm": 2, "zp": 2, "zpx": 2, "zpy": 2, "izx": 2, "izy": 2,
         "rel": 2, "abs": 3, "abx": 3, "aby": 3, "ind": 3}


class AsmError(Exception):
    pass


class Expr:
    TOK = re.compile(r"\s*(\$[0-9A-Fa-f]+|%[01]+|\d+|'.'|[A-Za-z_@.][A-Za-z0-9_@.]*|<=|>=|==|!=|<<|>>|[-+*/&|^<>\[\]])")

    def __init__(self, text, symbols, local_scope):
        self.toks = []
        pos = 0
        text = text.strip()
        while pos < len(text):
            m = self.TOK.match(text, pos)
            if not m:
                raise AsmError(f"bad expression near '{text[pos:]}'")
            self.toks.append(m.group(1))
            pos = m.end()
        self.i = 0
        self.sym = symbols
        self.scope = local_scope
        self.unknown = False

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else None

    def take(self):
        t = self.peek()
        self.i += 1
        return t

    def parse(self):
        v = self.binop(0)
        if self.peek() is not None:
            raise AsmError(f"trailing tokens in expression: {self.toks[self.i:]}")
        return v

    PREC = [("<=", ">=", "==", "!="), ("|",), ("^",), ("&",), ("<<", ">>"), ("+", "-"), ("*", "/")]

    def binop(self, level):
        if level == len(self.PREC):
            return self.unary()
        v = self.binop(level + 1)
        while self.peek() in self.PREC[level]:
            op = self.take()
            r = self.binop(level + 1)
            v = {"|": lambda a, b: a | b, "^": lambda a, b: a ^ b, "&": lambda a, b: a & b,
                 "<<": lambda a, b: a << b, ">>": lambda a, b: a >> b,
                 "+": lambda a, b: a + b, "-": lambda a, b: a - b,
                 "*": lambda a, b: a * b, "/": lambda a, b: a // b if b else 0,
                 "<=": lambda a, b: int(a <= b), ">=": lambda a, b: int(a >= b),
                 "==": lambda a, b: int(a == b), "!=": lambda a, b: int(a != b)}[op](v, r)
        return v

    def unary(self):
        t = self.peek()
        if t == "-":
            self.take()
            return -self.unary()
        if t == "<":
            self.take()
            return self.unary() & 0xFF
        if t == ">":
            self.take()
            return (self.unary() >> 8) & 0xFF
        return self.atom()

    def atom(self):
        t = self.take()
        if t is None:
            raise AsmError("unexpected end of expression")
        if t == "[":
            v = self.binop(0)
            if self.take() != "]":
                raise AsmError("missing ]")
            return v
        if t.startswith("$"):
            return int(t[1:], 16)
        if t.startswith("%"):
            return int(t[1:], 2)
        if t.isdigit():
            return int(t)
        if t.startswith("'"):
            return ord(t[1])
        name = self.scope + t if t.startswith("@") else t
        if name in self.sym:
            return self.sym[name]
        self.unknown = True
        return 0


def strip_comment(line):
    out, q = [], False
    for ch in line:
        if ch == '"':
            q = not q
        if ch == ";" and not q:
            break
        out.append(ch)
    return "".join(out).strip()


def bank_window(bank, fixed=7):
    return (0xC000, 0x10000) if bank == fixed else (0x8000, 0xC000)


class Assembler:
    def __init__(self, prg):
        self.orig = bytes(prg)
        self.symbols = {}
        self.fixed = len(prg) // 0x4000 - 1     # 7 for 128 KiB, 15 for 256 KiB
        self.textmap = {}

    def run(self, path):
        lines = []
        for n, raw in enumerate(open(path), 1):
            lines.append((n, raw.rstrip("\n")))
        self.size_cache = {}
        self.passno = 1
        self._pass(lines, path)
        self.passno = 2
        return self._pass(lines, path)

    def ev(self, text, line_no, need=False):
        e = Expr(text, self.symbols, self.scope)
        v = e.parse()
        if e.unknown and (need or self.passno == 2):
            raise AsmError(f"line {line_no}: undefined symbol in '{text}'")
        return v, e.unknown

    def _pass(self, lines, path):
        self.bank = None
        self.pc = None
        self.scope = ""
        self.out = {}           # (bank, addr) -> byte
        self.expect = {}        # (bank, addr) -> byte
        self.listing = []
        for n, raw in lines:
            line = strip_comment(raw)
            if not line:
                continue
            try:
                self._stmt(line, n)
            except AsmError as e:
                raise AsmError(f"{path}:{n}: {e}") from None
        return self.out, self.expect, self.listing

    def define(self, name, value, n):
        if self.passno == 1 and name in self.symbols and self.symbols[name] != value:
            raise AsmError(f"symbol {name} redefined")
        self.symbols[name] = value

    def emit(self, bs, n, text):
        if self.bank is None or self.pc is None:
            raise AsmError("emit before .bank/.org")
        lo, hi = bank_window(self.bank, self.fixed)
        start = self.pc
        for b in bs:
            if not lo <= self.pc < hi:
                raise AsmError(f"PC ${self.pc:04X} outside bank {self.bank} window")
            key = (self.bank, self.pc)
            if key in self.out:
                raise AsmError(f"overlapping output at {self.bank}:{self.pc:04X}")
            self.out[key] = b & 0xFF
            self.pc += 1
        if self.passno == 2:
            self.listing.append((self.bank, start, bytes(x & 0xFF for x in bs), text))

    def _stmt(self, line, n):
        m = re.match(r"^([A-Za-z_@.][A-Za-z0-9_@.]*)\s*=\s*(.+)$", line)
        if m:
            v, unk = self.ev(m.group(2), n, need=True)
            self.define(m.group(1), v, n)
            return
        m = re.match(r"^([A-Za-z_@][A-Za-z0-9_@]*):\s*(.*)$", line)
        if m:
            name = m.group(1)
            if not name.startswith("@"):
                self.scope = name
            else:
                name = self.scope + name
            if self.pc is None:
                raise AsmError("label before .org")
            self.define(name, self.pc, n)
            line = m.group(2).strip()
            if not line:
                return
        parts = line.split(None, 1)
        op = parts[0]
        arg = parts[1].strip() if len(parts) > 1 else ""
        lop = op.lower()
        if lop == ".bank":
            self.bank = self.ev(arg, n, need=True)[0]
            self.pc = None
        elif lop == ".org":
            self.pc = self.ev(arg, n, need=True)[0]
            lo, hi = bank_window(self.bank, self.fixed)
            if not lo <= self.pc < hi:
                raise AsmError(f".org ${self.pc:04X} outside bank {self.bank}")
            if not 0 <= self.bank <= self.fixed:
                raise AsmError(f"bank {self.bank} does not exist (last bank is {self.fixed})")
        elif lop == ".expect":
            vals = [int(x, 16) for x in arg.replace(",", " ").split()]
            self._expect(vals, n)
        elif lop == ".expectfill":
            v, cnt = [self.ev(x, n, need=True)[0] for x in arg.split(",")]
            self._expect([v] * cnt, n)
        elif lop == ".byte":
            vals = [self.ev(x, n)[0] for x in self._split_args(arg)]
            self.emit(vals, n, line)
        elif lop == ".word":
            vals = []
            for x in self._split_args(arg):
                v = self.ev(x, n)[0]
                vals += [v & 0xFF, (v >> 8) & 0xFF]
            self.emit(vals, n, line)
        elif lop == ".textmap":
            m = re.match(r'^"(.)"\s*,\s*(.+?)\s*,\s*(.+)$', arg)
            if not m:
                raise AsmError('.textmap needs "C", base, count')
            base = self.ev(m.group(2), n, need=True)[0]
            count = self.ev(m.group(3), n, need=True)[0]
            for k in range(count):
                self.textmap[chr(ord(m.group(1)) + k)] = (base + k) & 0xFF
        elif lop == ".text":
            m = re.match(r'^"(.*)"$', arg)
            if not m:
                raise AsmError('.text needs a quoted string')
            bad = [c for c in m.group(1) if c not in self.textmap]
            if bad:
                raise AsmError(f".text: no .textmap entry for {bad[0]!r}")
            self.emit([self.textmap[c] for c in m.group(1)], n, line)
        elif lop == ".assert":
            expr, _, msg = arg.partition(",")
            if self.passno == 2 and not self.ev(expr, n)[0]:
                raise AsmError(f"assertion failed: {msg.strip()}")
        elif lop.startswith("."):
            raise AsmError(f"unknown directive {op}")
        else:
            self._insn(op.upper(), arg, n, line)

    @staticmethod
    def _split_args(arg):
        return [a.strip() for a in arg.split(",") if a.strip()]

    def _expect(self, vals, n):
        for i, v in enumerate(vals):
            a = self.pc + i
            lo, hi = bank_window(self.bank, self.fixed)
            if not lo <= a < hi:
                raise AsmError(".expect runs outside bank window")
            off = self.bank * 0x4000 + a - lo
            if self.orig[off] != v:
                got = self.orig[off:off + len(vals) - i]
                raise AsmError(
                    f"PREIMAGE MISMATCH at bank {self.bank} ${a:04X} (PRG ${off:05X}): "
                    f"expected ${v:02X}, ROM has ${self.orig[off]:02X} "
                    f"(ROM bytes from here: {got[:16].hex(' ')})")
            self.expect[(self.bank, a)] = v

    def _insn(self, m, arg, n, text):
        key = (self.bank, self.pc, n)
        if m in BRANCHES:
            v, unk = self.ev(arg, n)
            if self.passno == 2:
                d = v - (self.pc + 2)
                if not -128 <= d <= 127:
                    raise AsmError(f"branch out of range ({d})")
            else:
                d = 0
            self.emit([OPC[(m, "rel")], d & 0xFF], n, text)
            return
        a = arg.strip()
        mode, val, force_abs = None, None, False
        if a == "" or a.upper() == "A":
            mode = "acc" if (m, "acc") in OPC and a.upper() == "A" else "imp"
            if (m, mode) not in OPC and (m, "acc") in OPC:
                mode = "acc"
            self.emit([OPC[(m, mode)]], n, text) if (m, mode) in OPC else self._bad(m, a)
            return
        if a.startswith("#"):
            val = self.ev(a[1:], n)[0]
            if self.passno == 2 and not -128 <= val <= 255:
                raise AsmError(f"immediate out of range: {val}")
            return self._out(m, "imm", val, n, text)
        mi = re.match(r"^\((.+),\s*[xX]\)$", a)
        if mi:
            return self._out(m, "izx", self.ev(mi.group(1), n)[0], n, text)
        mi = re.match(r"^\((.+)\)\s*,\s*[yY]$", a)
        if mi:
            return self._out(m, "izy", self.ev(mi.group(1), n)[0], n, text)
        mi = re.match(r"^\((.+)\)$", a)
        if mi:
            return self._out(m, "ind", self.ev(mi.group(1), n)[0], n, text)
        idx = None
        mi = re.match(r"^(.+),\s*([xXyY])$", a)
        if mi:
            a, idx = mi.group(1).strip(), mi.group(2).upper()
        if a.lower().startswith("a:"):
            force_abs, a = True, a[2:]
        val, unk = self.ev(a, n)
        zmode = {None: "zp", "X": "zpx", "Y": "zpy"}[idx]
        amode = {None: "abs", "X": "abx", "Y": "aby"}[idx]
        if self.passno == 1:
            use_zp = (not force_abs and not unk and 0 <= val < 0x100 and (m, zmode) in OPC)
            self.size_cache[key] = use_zp
        else:
            use_zp = self.size_cache.get(key, False)
            if use_zp and not 0 <= val < 0x100:
                raise AsmError("zero-page operand changed size between passes")
        return self._out(m, zmode if use_zp else amode, val, n, text)

    def _bad(self, m, a):
        raise AsmError(f"invalid instruction/mode: {m} {a}")

    def _out(self, m, mode, val, n, text):
        if (m, mode) not in OPC:
            self._bad(m, mode)
        size = SIZES[mode]
        bs = [OPC[(m, mode)]]
        if size == 2:
            bs.append(val & 0xFF)
        elif size == 3:
            bs += [val & 0xFF, (val >> 8) & 0xFF]
        self.emit(bs, n, text)


def assemble(prg, sources):
    """Assemble sources against prg; return (new_prg, records, listing, symbols)."""
    new = bytearray(prg)
    records = []
    listing = []
    asm = Assembler(prg)
    for src in sources:
        out, expect, lst = asm.run(src)
        for (bank, addr), b in out.items():
            if (bank, addr) not in expect:
                raise AsmError(f"{src}: byte at bank {bank} ${addr:04X} written without .expect preimage")
        for (bank, addr), b in sorted(out.items()):
            lo, _ = bank_window(bank, asm.fixed)
            off = bank * 0x4000 + addr - lo
            records.append((bank, addr, off, prg[off], b, src))
            new[off] = b
        listing += [(src,) + x for x in lst]
    return bytes(new), records, listing, asm.symbols


if __name__ == "__main__":
    print(__doc__)
