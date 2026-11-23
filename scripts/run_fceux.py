#!/usr/bin/env python3
"""Run FCEUX with a Lua test script and a hard timeout.

Usage: run_fceux.py <rom.nes> <script.lua> [--timeout S] [--game-dir DIR] [--out DIR]
                    [--tag NAME] [--env K=V ...]

FCEUX resolves relative paths unpredictably inside Lua, so the runner exports
absolute paths for the script:  GAME_DIR (the game directory: by default the
nearest parent of the script with a game.py), TEST_OUT (output dir, default
<game>/tests/out), TEST_ROM, TEST_LOG (the log the script writes) and
TEST_TAG.  FCEUX ignores SIGTERM, so the timeout uses SIGKILL.
Exit status: 0 if the script wrote "RESULT PASS" to its log, 1 otherwise.
"""
import argparse
import os
import pathlib
import subprocess
import sys
import threading
import time

def find_game_dir(script):
    for d in script.parents:
        if (d / "game.py").exists():
            return d
    return script.parent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rom")
    ap.add_argument("script")
    ap.add_argument("--timeout", type=int, default=120)
    ap.add_argument("--game-dir", help="default: nearest parent of the script with a game.py")
    ap.add_argument("--out", help="default: <game dir>/tests/out")
    ap.add_argument("--tag", help="name for log/screenshot prefix (default: script stem)")
    ap.add_argument("--env", action="append", default=[], help="extra KEY=VALUE for the script")
    ap.add_argument("--soundrecord", help="enable sound and record it to this WAV file")
    a = ap.parse_args()

    script = pathlib.Path(a.script).resolve()
    game_dir = pathlib.Path(a.game_dir).resolve() if a.game_dir else find_game_dir(script)
    out = pathlib.Path(a.out).resolve() if a.out else game_dir / "tests" / "out"
    out.mkdir(parents=True, exist_ok=True)
    rom = pathlib.Path(a.rom).resolve()
    name = a.tag or script.stem
    log = out / f"{name}.log"
    if log.exists():
        log.unlink()
    env = dict(os.environ, GAME_DIR=str(game_dir), TEST_OUT=str(out), TEST_ROM=str(rom),
               TEST_LOG=str(log), TEST_TAG=name)
    for kv in a.env:
        k, _, v = kv.partition("=")
        env[k] = v
    sound = ["--sound", "0"]
    if a.soundrecord:
        sound = ["--sound", "1", "--soundrecord", str(pathlib.Path(a.soundrecord).resolve())]
    cmd = ["fceux"] + sound + ["--loadlua", str(script), str(rom)]
    proc = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    chunks = []
    reader = threading.Thread(target=lambda: chunks.extend(iter(proc.stdout.readline, b"")),
                              daemon=True)
    reader.start()
    deadline = time.time() + a.timeout
    note = ""
    while proc.poll() is None:
        text = b"".join(chunks).decode(errors="replace")
        # FCEUX keeps running after a Lua error; stop it right away.
        if "Failed to compile" in text or "bombed out" in text:
            note = "\n[run_fceux] Lua error, emulator killed\n"
            proc.kill()  # SIGKILL: FCEUX ignores SIGTERM
            break
        if time.time() > deadline:
            note = "\n[run_fceux] TIMEOUT\n"
            proc.kill()
            break
        time.sleep(0.5)
    proc.wait()
    reader.join(timeout=2)
    stdout = b"".join(chunks).decode(errors="replace") + note
    (out / f"{name}.stdout").write_text(stdout)
    text = log.read_text() if log.exists() else ""
    sys.stdout.write(text)
    if "bombed out" in stdout or "error" in stdout.lower():
        sys.stdout.write("\n[fceux stdout]\n" + stdout[-2000:])
    sys.exit(0 if "RESULT PASS" in text else 1)


if __name__ == "__main__":
    main()
