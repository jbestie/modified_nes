#!/usr/bin/env python3
"""Run the whole Ghosts'n Goblins test suite and write tests/out/summary.txt.

Usage: run_tests.py [--quick]     (--quick skips the 14-area sweeps)

Every test drives FCEUX with a Lua script (see tests/*.lua); results come
from the game's own code paths (execution hooks, RAM), not from screenshots,
except the pixel-exact screen regression against the original ROM.
"""
import argparse
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent          # this game's directory
SCRIPTS = ROOT.parent.parent / "scripts"                 # shared tools
ORIG = "rom/original.nes"
INV = "build/invincible.nes"
FINAL = "build/ghosts-n-goblins-spread.nes"
REMIX = "build/ghosts-n-goblins-remix.nes"
# remix title-menu text (nametable rows 23-24, columns 5-26) in the 256x224
# screenshots (FCEUX crops the top 8 scanlines)
MENU_MASK = "40,176,216,192"


def run(cmd):
    p = subprocess.run(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return p.returncode, p.stdout


def lua(rom, script, tag, env=(), timeout=300):
    cmd = [sys.executable, str(SCRIPTS / "run_fceux.py"), rom, f"tests/{script}", "--tag", tag,
           "--timeout", str(timeout)]
    for e in env:
        cmd += ["--env", e]
    return run(cmd)


def apu_trace(tag):
    return [l for l in (ROOT / "tests" / "out" / f"{tag}.log").read_text().splitlines()
            if l.startswith("APU")]


def apu_compare(a, b):
    ta, tb = apu_trace(a), apu_trace(b)
    same = ta == tb and len(ta) > 1000
    return 0 if same else 1, f"{len(ta)} frames compared, {'identical' if same else 'DIFFERENT'}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true")
    a = ap.parse_args()
    results = []

    def record(name, code, out, expect_pass=True):
        ok = (code == 0) == expect_pass
        last = [l for l in out.strip().splitlines() if l.strip()][-1:] or [""]
        results.append((name, ok, last[0]))
        print(f"[{'PASS' if ok else 'FAIL'}] {name}: {last[0]}")
        return out

    record("build + preimage checks + BPS round-trip",
           *run([sys.executable, str(SCRIPTS / "build.py"), str(ROOT)]))
    for rom, tag in ((ORIG, "scr_orig"), (INV, "scr_inv"), (FINAL, "scr_spread")):
        lua(rom, "t_screens.lua", tag)
    record("screens: invincible == original (pixel-exact)",
           *run([sys.executable, str(SCRIPTS / "compare_shots.py"), "tests/out", "scr_orig", "scr_inv"]))
    record("screens: final == original (pixel-exact)",
           *run([sys.executable, str(SCRIPTS / "compare_shots.py"), "tests/out", "scr_orig", "scr_spread"]))
    lua(ORIG, "t_sound.lua", "snd_orig")
    lua(FINAL, "t_sound.lua", "snd_spread")
    record("sound: final APU trace == original (per frame)", *apu_compare("snd_orig", "snd_spread"))
    record("control: original ROM takes damage", *lua(ORIG, "t_invincible.lua", "inv_vanilla", ["GNG_MODE=vanilla"]))
    record("invincibility (invincible.nes)", *lua(INV, "t_invincible.lua", "inv_patched"))
    record("invincibility (final ROM)", *lua(FINAL, "t_invincible.lua", "inv_final"))
    record("ladder climb among enemies (final ROM)", *lua(FINAL, "t_ladder.lua", "ladder"))
    record("spread geometry right/left/repeat", *lua(FINAL, "t_spread.lua", "spread"))
    record("spread with all five weapons", *lua(FINAL, "t_weapons.lua", "weapons"))
    record("2-player mode: player 2 invincible + 5-way bursts", *lua(FINAL, "t_2p.lua", "twoplayer"))
    record("5-minute play session (audit, damage per slot)",
           *lua(FINAL, "t_play.lua", "play_spread", ["GNG_FRAMES=18000"]))
    if not a.quick:
        for area in range(14):
            record(f"area {area:2d} warp + aiming bot (3 min)",
                   *lua(FINAL, "t_area.lua", f"sweep{area}", [f"GNG_AREA={area}"]))

    # ---- remix ROM (256 KiB, title-menu modes) ----
    lua(REMIX, "t_screens.lua", "scr_remix")
    record("remix screens: default modes == spread build (outside the menu text)",
           *run([sys.executable, str(SCRIPTS / "compare_shots.py"), "tests/out", "scr_spread", "scr_remix",
                 "--mask", MENU_MASK]))
    lua(ORIG, "t_screens.lua", "scr_orig_late", ["GNG_START=220"])
    lua(REMIX, "t_screens.lua", "scr_classic", ["GNG_START=220", "GNG_MODES=2,2"])
    record("remix screens: NORMAL/NORMAL == original (menu drawn, nothing else differs)",
           *run([sys.executable, str(SCRIPTS / "compare_shots.py"), "tests/out", "scr_orig_late", "scr_classic",
                 "--mask", MENU_MASK, "--expect-masked-diff"]))
    lua(REMIX, "t_sound.lua", "snd_remix")
    record("remix sound: default modes == spread build", *apu_compare("snd_spread", "snd_remix"))
    lua(REMIX, "t_sound.lua", "snd_classic", ["GNG_MODES=2,2"])
    record("remix sound: NORMAL/NORMAL == original", *apu_compare("snd_orig", "snd_classic"))
    record("remix title menu (draw, cycle, partition, reset, demo)",
           *lua(REMIX, "t_remix_menu.lua", "remix_menu"))
    for check, what in (("rainbow", "RAINBOW bursts right/left/repeat"),
                        ("cycle", "Select weapon cycling (+ kept after death)"),
                        ("classic", "NORMAL/NORMAL: original single shot and damage"),
                        ("armor4", "4 HITS EACH armor (3 absorbed per piece, blink, timer)")):
        record(f"remix: {what}", *lua(REMIX, "t_remix.lua", f"remix_{check}", [f"GNG_CHECK={check}"]))
    record("remix: absorbed hit while climbing a ladder",
           *lua(REMIX, "t_ladder.lua", "remix_ladderhit", ["GNG_LADDER_HIT=1"]))
    record("remix default: invincibility", *lua(REMIX, "t_invincible.lua", "remix_inv"))
    record("remix default: ladder among enemies", *lua(REMIX, "t_ladder.lua", "remix_ladder"))
    record("remix default: spread geometry", *lua(REMIX, "t_spread.lua", "remix_spread"))
    record("remix default: all five weapons", *lua(REMIX, "t_weapons.lua", "remix_weapons"))
    record("remix default: 2-player mode", *lua(REMIX, "t_2p.lua", "remix_2p", ["GNG_REMIX=1"]))
    record("remix default: 5-minute play session",
           *lua(REMIX, "t_play.lua", "remix_play", ["GNG_FRAMES=18000"]))
    if not a.quick:
        for area in range(14):
            record(f"remix area {area:2d} warp + bot + bank audit (3 min)",
                   *lua(REMIX, "t_area.lua", f"rsweep{area}", [f"GNG_AREA={area}", "GNG_BANK_AUDIT=1"]))

    # ---- chat chaos mode (Lua only, any ROM) ----
    record("chaos: chat bridge parsing, cooldowns, votes (offline)",
           *run([sys.executable, "tests/test_chat_bridge.py"]))
    record("chaos: commands applied on the remix ROM", *lua(REMIX, "t_chaos.lua", "chaos_remix"))
    record("chaos: commands applied on the original ROM", *lua(ORIG, "t_chaos.lua", "chaos_orig"))
    lines = [f"{'PASS' if ok else 'FAIL'}  {name}  --  {msg}" for name, ok, msg in results]
    (ROOT / "tests" / "out" / "summary.txt").write_text("\n".join(lines) + "\n")
    failed = [r for r in results if not r[1]]
    print(f"\n{len(results) - len(failed)}/{len(results)} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
