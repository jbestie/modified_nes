#!/usr/bin/env python3
"""Run the Castlevania test suite and write tests/out/summary.txt.

Usage: run_tests.py [--quick]     (--quick skips the negative control on the original ROM)

Every test drives FCEUX with a Lua script (see tests/*.lua) through the
shared scripts/run_fceux.py.
"""
import argparse
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent          # this game's directory
SCRIPTS = ROOT.parent.parent / "scripts"                 # shared tools
ORIG = "rom/original.nes"
COMMANDO = "build/castlevania-commando.nes"
SUPERC = ROOT / "rom" / "Super C (U) [!].nes"           # optional: the user's own dump, for the art install
ART = "tests/out/private/castlevania-commando-superc.nes"  # contains Super C graphics: never commit or share


def run(cmd):
    p = subprocess.run(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return p.returncode, p.stdout


def lua(rom, script, tag, env=(), timeout=300):
    cmd = [sys.executable, str(SCRIPTS / "run_fceux.py"), rom, f"tests/{script}", "--tag", tag,
           "--timeout", str(timeout)]
    for e in env:
        cmd += ["--env", e]
    return run(cmd)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true")
    args = ap.parse_args()
    results = []

    def record(name, code, out, expect_pass=True):
        ok = (code == 0) == expect_pass
        last = [l for l in out.strip().splitlines() if l.strip()][-1:] or [""]
        results.append((name, ok, last[0]))
        print(f"[{'PASS' if ok else 'FAIL'}] {name}: {last[0]}")
        return out

    record("build: input ROM checks, commando target (preimages), BPS round-trip",
           *run([sys.executable, str(SCRIPTS / "build.py"), str(ROOT)]))
    record("boot: power-on, region timing, title, Start begins a game (not the demo)",
           *lua(ORIG, "t_boot.lua", "boot_orig"))
    record("practice overlay: text, drawing, infinite mode, stage warp",
           *lua(ORIG, "t_overlay.lua", "overlay"))
    record("commando: run-and-gun, aiming, air control, weapons, pickups, no knockback, blocks, boss freeze, no demo",
           *lua(COMMANDO, "t_commando.lua", "commando", timeout=600))
    if not args.quick:
        record("commando test on the ORIGINAL ROM must fail (negative control)",
               *lua(ORIG, "t_commando.lua", "commando_orig", timeout=600), expect_pass=False)
    record("Super C jump: arc, and the stage 5 low-ceiling jump",
           *lua(COMMANDO, "t_jump_superc.lua", "jump_superc"))
    if SUPERC.exists():
        code, out = run([sys.executable, "tools/commando_art.py", "--base", COMMANDO,
                         "--sym", "build/castlevania-commando.sym", "--orig", ORIG,
                         "--superc", str(SUPERC), "--out", ART])
        record("commando art install from the Super C dump", code, out)
        if code == 0:
            record("commando with Super C art: the same checks, plus the commando poses",
                   *lua(ART, "t_commando.lua", "commando_art", env=["ART=1"], timeout=600))
    else:
        print(f"[SKIP] commando art install: no {SUPERC.relative_to(ROOT)}")

    (ROOT / "tests" / "out").mkdir(parents=True, exist_ok=True)
    lines = [f"{'PASS' if ok else 'FAIL'}  {name}  --  {msg}" for name, ok, msg in results]
    (ROOT / "tests" / "out" / "summary.txt").write_text("\n".join(lines) + "\n")
    failed = [r for r in results if not r[1]]
    print(f"\n{len(results) - len(failed)}/{len(results)} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
