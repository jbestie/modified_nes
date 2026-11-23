"""Locate and load a game definition: games/<name>/game.py.

A game directory holds everything for one game (game.py, src/, tests/,
notes/, rom/, build/, dist/); the tools in scripts/ are shared.
"""
import importlib.util
import os
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
GAMES = ROOT / "games"


def names():
    return sorted(p.parent.name for p in GAMES.glob("*/game.py"))


def game_dir(arg):
    """A name under games/ or a path to a game directory."""
    p = pathlib.Path(arg)
    if not (p / "game.py").exists():
        p = GAMES / arg
    return p.resolve()


def load(arg):
    d = game_dir(arg)
    f = d / "game.py"
    if not f.exists():
        raise SystemExit(f"no game definition {f} (known games: {', '.join(names()) or 'none'})")
    spec = importlib.util.spec_from_file_location("game_" + d.name.replace("-", "_"), f)
    game = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(game)
    game.DIR, game.NAME = d, d.name
    return game


def rel(path):
    """Path relative to the repository root when inside it (for messages; symlinks kept)."""
    path = pathlib.Path(os.path.abspath(path))
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)
