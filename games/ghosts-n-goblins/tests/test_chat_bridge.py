#!/usr/bin/env python3
"""Offline tests for tools/chaos/chat_bridge.py (no network, no emulator)."""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools" / "chaos"))
import chat_bridge as cb  # noqa: E402

fails = []


def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        fails.append(what)


allowed = set(cb.COMMANDS)
check(cb.parse_command("!Torch please", allowed) == "torch", "parse: case and trailing text")
check(cb.parse_command("torch", allowed) is None, "parse: needs !")
check(cb.parse_command("!nuke", allowed) is None, "parse: unknown command")
check(cb.parse_command("!", allowed) is None, "parse: bare !")

# the command list matches chaos.lua's COMMANDS table
lua = (ROOT / "tools" / "chaos" / "chaos.lua").read_text()
import re  # noqa: E402
lua_cmds = set(re.findall(r"^\s+(\w+)\s+=\s+\{\"", lua, re.M))
check(lua_cmds == allowed, f"bridge list == chaos.lua COMMANDS ({len(allowed)} commands)")

t = [0.0]
gate = cb.Gate(cooldown=20, user_cooldown=10, vote=0, clock=lambda: t[0])
out = gate.offer("a", "torch")
t[0] = 1
out += gate.offer("b", "torch")         # command cooldown
out += gate.offer("a", "axe")           # user cooldown
t[0] = 12
out += gate.offer("a", "axe")           # user cooldown over
t[0] = 21
out += gate.offer("c", "torch")         # command cooldown over
check(out == [("a", "torch"), ("a", "axe"), ("c", "torch")], f"cooldowns: {out}")

t[0] = 0.0
vote = cb.Gate(cooldown=0, user_cooldown=0, vote=30, clock=lambda: t[0])
for user, cmd in [("a", "blood"), ("b", "life"), ("c", "life"), ("a", "life"), ("d", "blood")]:
    vote.offer(user, cmd)               # a's second vote ignored
t[0] = 10
check(vote.tick() == [], "vote: round still open")
t[0] = 30
check(vote.tick() == [("vote(2)", "blood")], "vote: tie 2-2 goes to the earliest (blood)")

with tempfile.TemporaryDirectory() as d:
    out_file = pathlib.Path(d) / "cmds.txt"
    p = subprocess.run([sys.executable, str(ROOT / "tools" / "chaos" / "chat_bridge.py"), "--stdin",
                        "--out", str(out_file), "--cooldown", "0", "--user-cooldown", "0", "--deny", "naked"],
                       input="alice !torch\n!life\nbob hello\nbob !naked\ncarol !NUKE\n", text=True,
                       capture_output=True)
    lines = out_file.read_text().splitlines()
    check(p.returncode == 0 and lines == ["alice !torch", "you !life"], f"stdin end-to-end: {lines}")

print("RESULT " + ("PASS" if not fails else "FAIL " + fails[0]))
sys.exit(1 if fails else 0)
