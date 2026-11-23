#!/usr/bin/env python3
"""Chat -> command file bridge for tools/chaos/chaos.lua.

Reads chat messages, keeps the ones that are known `!commands`, applies
cooldowns (or a vote), and appends accepted commands to the command file as
"<user> !<command>" lines.  The FCEUX script polls that file.

Sources:
  --twitch CHANNEL   read a Twitch channel's chat anonymously (read-only IRC,
                     no account or token needed)
  --stdin            read "user !command" or "!command" lines from the
                     keyboard or a pipe (offline testing, or a streamer's
                     own hotkeys)

Modes:
  default            first come, first served, with a per-command cooldown
                     (--cooldown, seconds) and a per-user cooldown (--user-cooldown)
  --vote SECONDS     collect commands for SECONDS, then send only the most
                     voted one (one vote per user per round; ties: earliest)

Examples:
  python3 tools/chaos/chat_bridge.py --twitch mychannel
  python3 tools/chaos/chat_bridge.py --twitch mychannel --vote 30 --deny naked,hurry,mortal
  python3 tools/chaos/chat_bridge.py --stdin --cooldown 0
"""
import argparse
import pathlib
import socket
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
# Keep in sync with COMMANDS in chaos.lua.
COMMANDS = ["lance", "dagger", "torch", "axe", "cross", "life", "time", "hurry", "armor",
            "naked", "blood", "toxic", "grey", "spread", "rainbow", "god", "tough", "mortal"]


def parse_command(text, allowed):
    """'!Torch please' -> 'torch' if allowed, else None."""
    text = text.strip()
    if not text.startswith("!"):
        return None
    word = text[1:].split(None, 1)[0].lower() if len(text) > 1 else ""
    return word if word in allowed else None


class Gate:
    """Cooldowns (default) or vote rounds; emits accepted (user, command)."""

    def __init__(self, cooldown, user_cooldown, vote, clock=time.monotonic):
        self.cooldown, self.user_cooldown, self.vote = cooldown, user_cooldown, vote
        self.clock = clock
        self.last_cmd, self.last_user = {}, {}
        self.round_start, self.ballots = None, {}

    def offer(self, user, cmd):
        now = self.clock()
        if self.vote:
            if self.round_start is None:
                self.round_start = now
            self.ballots.setdefault(user, (cmd, now))     # first vote per user counts
            return []
        if now - self.last_user.get(user, -1e9) < self.user_cooldown:
            return []
        if now - self.last_cmd.get(cmd, -1e9) < self.cooldown:
            return []
        self.last_user[user] = now
        self.last_cmd[cmd] = now
        return [(user, cmd)]

    def tick(self):
        """Close a vote round when its time is up."""
        if not self.vote or self.round_start is None or self.clock() - self.round_start < self.vote:
            return []
        tally = {}
        for cmd, t in self.ballots.values():
            n, first = tally.get(cmd, (0, t))
            tally[cmd] = (n + 1, min(first, t))
        winner = min(tally, key=lambda c: (-tally[c][0], tally[c][1]))
        votes = tally[winner][0]
        self.round_start, self.ballots = None, {}
        return [(f"vote({votes})", winner)]


def twitch_messages(channel):
    """Yield (user, text) from a Twitch channel (anonymous, read-only)."""
    sock = socket.create_connection(("irc.chat.twitch.tv", 6667), timeout=300)
    sock.sendall(b"NICK justinfan%d\r\n" % (int(time.time()) % 100000))
    sock.sendall(f"JOIN #{channel.lower().lstrip('#')}\r\n".encode())
    buf = b""
    while True:
        try:
            data = sock.recv(4096)
        except socket.timeout:
            yield None, None
            continue
        if not data:
            raise ConnectionError("Twitch closed the connection")
        buf += data
        while b"\r\n" in buf:
            raw, buf = buf.split(b"\r\n", 1)
            line = raw.decode("utf-8", "replace")
            if line.startswith("PING"):
                sock.sendall(b"PONG :tmi.twitch.tv\r\n")
            elif " PRIVMSG " in line and line.startswith(":"):
                user = line[1:].split("!", 1)[0]
                text = line.split(" :", 1)[1] if " :" in line else ""
                yield user, text
        yield None, None          # let the caller close vote rounds


def stdin_messages():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        if line.startswith("!"):
            yield "you", line
        else:
            user, _, text = line.partition(" ")
            yield user, text
    yield None, None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--twitch", metavar="CHANNEL")
    src.add_argument("--stdin", action="store_true")
    ap.add_argument("--out", default=str(HERE / "commands.txt"), help="command file (default: %(default)s)")
    ap.add_argument("--cooldown", type=float, default=20, help="seconds between two uses of one command")
    ap.add_argument("--user-cooldown", type=float, default=10, help="seconds between two commands of one user")
    ap.add_argument("--vote", type=float, default=0, help="vote round length in seconds (0 = off)")
    ap.add_argument("--allow", help="comma-separated subset of commands to accept")
    ap.add_argument("--deny", help="comma-separated commands to refuse")
    a = ap.parse_args()

    allowed = set(a.allow.split(",")) if a.allow else set(COMMANDS)
    if a.deny:
        allowed -= set(a.deny.split(","))
    unknown = allowed - set(COMMANDS)
    if unknown:
        ap.error(f"unknown commands: {', '.join(sorted(unknown))}")
    gate = Gate(a.cooldown, a.user_cooldown, a.vote)
    out = open(a.out, "a", encoding="utf-8")
    print(f"bridge: {'twitch #' + a.twitch if a.twitch else 'stdin'} -> {a.out}; "
          f"commands: {' '.join('!' + c for c in sorted(allowed))}", file=sys.stderr)
    messages = twitch_messages(a.twitch) if a.twitch else stdin_messages()
    try:
        for user, text in messages:
            accepted = []
            if user is not None:
                cmd = parse_command(text, allowed)
                if cmd:
                    accepted += gate.offer(user, cmd)
            accepted += gate.tick()
            for u, c in accepted:
                out.write(f"{u} !{c}\n")
                out.flush()
                print(f"-> {u} !{c}", file=sys.stderr)
    except KeyboardInterrupt:
        pass
    finally:
        if a.vote and gate.ballots:            # input ended / Ctrl+C: close the open round
            gate.round_start = gate.clock() - a.vote
            for u, c in gate.tick():
                out.write(f"{u} !{c}\n")
                print(f"-> {u} !{c}", file=sys.stderr)
        out.close()


if __name__ == "__main__":
    main()
