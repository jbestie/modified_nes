#!/usr/bin/env python3
"""Minimal BPS patch encoder/decoder (beat format, "BPS1").

Usage:
  bps.py create <source> <target> <patch.bps> [--meta TEXT]
  bps.py apply  <patch.bps> <source> <target>

The encoder emits SourceRead for unchanged bytes, SourceCopy for data moved
within the image (e.g. the fixed bank relocated by a ROM expansion),
run-length TargetCopy for fill, and TargetRead for new bytes, so a patch never
embeds the source ROM's contents.  apply verifies source, target and patch
CRC32s.
"""
import sys
import zlib

SOURCE_READ, TARGET_READ, SOURCE_COPY, TARGET_COPY = range(4)


def _enc(n):
    out = bytearray()
    while True:
        x = n & 0x7F
        n >>= 7
        if n == 0:
            out.append(0x80 | x)
            return bytes(out)
        out.append(x)
        n -= 1


def _dec(buf, pos):
    data, shift = 0, 1
    while True:
        x = buf[pos]
        pos += 1
        data += (x & 0x7F) * shift
        if x & 0x80:
            return data, pos
        shift <<= 7
        data += shift


MIN_COPY = 32   # shortest SourceCopy / run-length TargetCopy worth emitting
BLOCK = 16      # source index granularity for SourceCopy lookups


def _signed(n):
    return (abs(n) << 1) | (1 if n < 0 else 0)


def create(source, target, meta=b""):
    """Encode target as a patch against source.

    Bytes equal at the same offset become SourceRead.  Longer stretches that
    exist elsewhere in the source (for example a bank copied to a new
    position when a ROM is expanded) become SourceCopy, and long runs of one
    byte (new empty banks) become TargetCopy, so the patch carries only the
    genuinely new bytes and none of the source image.  Everything else is
    TargetRead.  Small in-place edits encode exactly as SourceRead/TargetRead.
    """
    out = bytearray(b"BPS1")
    out += _enc(len(source)) + _enc(len(target)) + _enc(len(meta)) + meta
    index = {}
    for k in range(0, len(source) - BLOCK + 1, BLOCK):
        index.setdefault(source[k:k + BLOCK], []).append(k)
    src_rel = dst_rel = 0
    delta = None            # source - target offset of the last SourceCopy
    literal = bytearray()

    def flush():
        nonlocal literal
        if literal:
            out.extend(_enc(((len(literal) - 1) << 2) | TARGET_READ) + literal)
            literal = bytearray()

    i, n = 0, len(target)
    while i < n:
        # 1. unchanged at the same offset
        j = i
        while j < n and j < len(source) and source[j] == target[j]:
            j += 1
        if j > i:
            flush()
            out += _enc(((j - i - 1) << 2) | SOURCE_READ)
            i = j
            continue
        # 2. copy from elsewhere in the source: first the continuation of the
        # previous copy (short gaps between edits in a moved bank), then any
        # long match found through the block index
        best_len, best_pos = 0, 0
        if delta is not None and 0 <= i + delta < len(source):
            pos = i + delta
            m = 0
            while i + m < n and pos + m < len(source) and source[pos + m] == target[i + m]:
                m += 1
            if m >= 4:
                best_len, best_pos = m, pos
        for a in range(max(0, i - BLOCK + 1), i + 1):
            if best_len >= MIN_COPY:
                break
            for cand in index.get(target[a:a + BLOCK], ()):
                pos = cand + (i - a)
                if pos < 0:
                    continue
                m = 0
                while i + m < n and pos + m < len(source) and source[pos + m] == target[i + m]:
                    m += 1
                if m > best_len:
                    best_len, best_pos = m, pos
            if best_len >= 4 * MIN_COPY:
                break
        if best_len >= MIN_COPY or (best_len >= 4 and best_pos == i + (delta or 0) and delta is not None):
            flush()
            out += _enc(((best_len - 1) << 2) | SOURCE_COPY) + _enc(_signed(best_pos - src_rel))
            src_rel = best_pos + best_len
            delta = best_pos - i
            i += best_len
            continue
        # 3. run of a single byte: TargetCopy from the previous byte
        if i > 0:
            r = 0
            while i + r < n and target[i + r] == target[i - 1]:
                r += 1
            if r >= MIN_COPY:
                flush()
                out += _enc(((r - 1) << 2) | TARGET_COPY) + _enc(_signed(i - 1 - dst_rel))
                dst_rel = i - 1 + r
                i += r
                continue
        literal.append(target[i])
        i += 1
    flush()
    out += zlib.crc32(source).to_bytes(4, "little")
    out += zlib.crc32(target).to_bytes(4, "little")
    out += zlib.crc32(out).to_bytes(4, "little")
    return bytes(out)


def apply(patch, source):
    if patch[:4] != b"BPS1":
        raise ValueError("not a BPS1 patch")
    if zlib.crc32(patch[:-4]) != int.from_bytes(patch[-4:], "little"):
        raise ValueError("patch CRC mismatch (corrupt patch)")
    src_crc = int.from_bytes(patch[-12:-8], "little")
    dst_crc = int.from_bytes(patch[-8:-4], "little")
    if zlib.crc32(source) != src_crc:
        raise ValueError(f"source CRC32 {zlib.crc32(source):08X} != expected {src_crc:08X} "
                         "(wrong or modified input ROM)")
    pos = 4
    ssize, pos = _dec(patch, pos)
    tsize, pos = _dec(patch, pos)
    msize, pos = _dec(patch, pos)
    pos += msize
    if ssize != len(source):
        raise ValueError("source size mismatch")
    out = bytearray()
    src_rel = dst_rel = 0
    end = len(patch) - 12
    while pos < end:
        data, pos = _dec(patch, pos)
        cmd, length = data & 3, (data >> 2) + 1
        if cmd == SOURCE_READ:
            out += source[len(out):len(out) + length]
        elif cmd == TARGET_READ:
            out += patch[pos:pos + length]
            pos += length
        else:
            off, pos = _dec(patch, pos)
            off = -(off >> 1) if off & 1 else off >> 1
            if cmd == SOURCE_COPY:
                src_rel += off
                out += source[src_rel:src_rel + length]
                src_rel += length
            else:
                dst_rel += off
                for _ in range(length):
                    out.append(out[dst_rel])
                    dst_rel += 1
    if len(out) != tsize or zlib.crc32(out) != dst_crc:
        raise ValueError("target CRC/size mismatch after applying patch")
    return bytes(out)


def main():
    a = sys.argv[1:]
    if len(a) >= 4 and a[0] == "create":
        meta = a[a.index("--meta") + 1].encode() if "--meta" in a else b""
        p = create(open(a[1], "rb").read(), open(a[2], "rb").read(), meta)
        open(a[3], "wb").write(p)
        print(f"wrote {a[3]} ({len(p)} bytes)")
    elif len(a) == 4 and a[0] == "apply":
        try:
            t = apply(open(a[1], "rb").read(), open(a[2], "rb").read())
        except ValueError as e:
            print(f"error: {e}", file=sys.stderr)
            sys.exit(1)
        open(a[3], "wb").write(t)
        print(f"wrote {a[3]} (CRC32 {zlib.crc32(t):08X})")
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
