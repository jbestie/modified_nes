#!/usr/bin/env python3
"""Boss damage balance: kill times for any bullet damage table, replayed from boss_fights.lua logs.

  boss_replay.py rom BUILD.nes BUILD.sym OUT.nes
      the measurement ROM: DmgTable = rifle/M/S/L 1, F ball 2, charged 3, fragment 1 (the damage logged per hit
      then tells the kinds apart, and no boss dies before the log has enough hits)
  boss_replay.py report LOGDIR "6, S=3, L=4" ["6" ...]
      LOGDIR holds boss_fights.lua logs made on the measurement ROM (one per boss stage). Each table is
      table(D, **overrides): every kind D, the charged ball 5 D (Super C's ratios), then the overrides.
      Prints seconds from the first boss hit to the kill per boss and weapon mode.

Bosses scale bullet damage, so the HP pool is measured, not assumed: damage units to empty 64 HP are 64 (Phantom
Bat), 127 (Medusa, Frankenstein, Death, Dracula's first form), 250 (the two mummies) and 253 (Dracula's second
form). Only hits on the boss's own object types count (19 bat, 1B Medusa, 1A mummies, 1C Frankenstein, 18 Death,
04 Dracula in both forms). Dracula's forms are replayed separately, with the measured transition between them.
Checked against real fights at 6/6/3/4/6/30/6 (2026-11-21): within 0.1 s where the bot's moves don't diverge.
"""
import glob
import re
import statistics
import sys

BOSSES = {3: "Phantom Bat", 6: "Medusa", 9: "Mummies", 12: "Frankenstein", 15: "Death", 18: "Dracula"}
MODES = ["rifle", "M", "S", "L", "F", "FC"]
TYPES = {3: ["19"], 6: ["1B"], 9: ["1A"], 12: ["1C"], 15: ["18"], 18: ["04"]}
MEASURE = bytes([1, 1, 1, 1, 2, 3, 1])          # rifle M S L F F+ frag


def parse(path):
    runs, cur = {}, None
    for line in open(path):
        p = line.split()
        if not p:
            continue
        m = re.match(r"RUN stage (\d+) mode (\w+) frames (\d+) hits \d+ first \S+ deaths (\d+) endhp (\d+)", line)
        if m:
            cur = {"stage": int(m.group(1)), "mode": m.group(2), "frames": int(m.group(3)), "hp": [], "hits": []}
            runs[(cur["stage"], cur["mode"])] = cur
        elif cur and p[0] == "hp":
            cur["hp"].append((int(p[1]), int(p[2])))
        elif cur and p[0] == "hit":
            cur["hits"].append((int(p[1]), int(p[2]), p[3]))
    return runs


def kind_of(mode, dmg):
    return "FC" if dmg == 3 else "F" if dmg == 2 else ("frag" if mode in ("F", "FC") else mode)


def phase_hits(run):
    """[(start frame, [(frame, logged damage)])] per HP pool; a new pool starts when HP rises (Dracula)."""
    rise = [f for (f0, h0), (f, h) in zip(run["hp"], run["hp"][1:]) if h > h0]
    bounds = [0] + rise[:1] + [10 ** 9]
    out = [(bounds[i], [(f, d) for f, d, ty in run["hits"] if ty in TYPES[run["stage"]] and bounds[i] <= f < bounds[i + 1]])
           for i in range(len(bounds) - 1)]
    return out[:2] if run["stage"] == 18 else out[:1]


def first_zero(run, start):
    z = [f for f, hp in run["hp"] if hp == 0 and f >= start]
    return z[0] if z else None


def measured_pool(run, phase):
    start, hits = phase_hits(run)[phase]
    z = first_zero(run, start)
    return sum(d for f, d in hits if f <= z) if z else None


def kill_frames(run, table, pools):
    total, phs = 0, phase_hits(run)
    for i, (start, hits) in enumerate(phs):
        acc, done = 0, None
        for f, d in hits:
            acc += table[kind_of(run["mode"], d)]
            if acc >= pools[i]:
                done = f
                break
        if done is None:
            return None
        total += done - (hits[0][0] if i == 0 else start)
        if i + 1 < len(phs):
            total += phs[i + 1][0] - first_zero(run, start)
    return total


def table(D, FC=None, **caps):
    t = {k: D for k in ["rifle", "M", "S", "L", "F", "frag"]}
    t["FC"] = 5 * D if FC is None else FC
    t.update(caps)
    return t


def report(logdir, specs):
    runs = {}
    for p in glob.glob(logdir + "/*.log"):
        runs.update(parse(p))
    pools = {}
    for st in BOSSES:
        pools[st] = []
        for i in range(2 if st == 18 else 1):
            vals = [v for v in (measured_pool(runs[(st, m)], i) for m in MODES if (st, m) in runs) if v]
            pools[st].append(int(statistics.median(vals)))
    print("damage units per 64 HP:", ", ".join("%s %s" % (BOSSES[s], "/".join(map(str, p))) for s, p in pools.items()))
    for spec in specs:
        t = eval("table(%s)" % spec)
        print("\n" + " ".join("%s=%d" % kv for kv in t.items()) + "   (seconds, first boss hit to kill)")
        print("  %-13s" % "" + "".join("%7s" % m for m in MODES))
        for st in BOSSES:
            cells = []
            for m in MODES:
                k = kill_frames(runs[(st, m)], t, pools[st]) if (st, m) in runs else None
                cells.append("%7s" % ("%.1f" % (k / 60) if k is not None else "-"))
            print("  %-13s" % BOSSES[st] + "".join(cells))


def make_rom(build, sym, out):
    addr = None
    for line in open(sym):
        m = re.match(r"DmgTable = \$([0-9A-Fa-f]+)$", line.strip())
        if m:
            addr = int(m.group(1), 16)
    if addr is None:
        sys.exit("DmgTable not in " + sym)
    d = bytearray(open(build, "rb").read())
    o = 16 + 5 * 0x4000 + addr - 0x8000
    d[o:o + len(MEASURE)] = MEASURE
    open(out, "wb").write(d)
    print("wrote %s (DmgTable at b5:$%04X = %s)" % (out, addr, " ".join(map(str, MEASURE))))


if __name__ == "__main__":
    if len(sys.argv) >= 5 and sys.argv[1] == "rom":
        make_rom(*sys.argv[2:5])
    elif len(sys.argv) >= 4 and sys.argv[1] == "report":
        report(sys.argv[2], sys.argv[3:])
    else:
        sys.exit(__doc__)
