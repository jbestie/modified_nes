# Spike: run-and-gun

A proof of concept for item 2 of `../../TODO.md` (a Super C commando replacing Simon). It answers one question: can Simon shoot while he keeps moving, without the whip? **Yes.** The patch is 63 bytes, and an automated test checks it.

**Superseded:** the production version is `src/commando/commando.asm` (the `castlevania-commando` build target). This folder stays as the record of the spike.

This folder holds no ROM. The patch isn't a target in `game.py`, so you build it in a scratch copy (below).

## What it does

- **B (without Up)** fires a dagger at once: object type `$17`, kind 0, 4 px/frame, erased on its first hit.
  - It reuses the game's own subweapon spawner tail `$DABC`.
  - It uses the three subweapon slots `$14-$16`, so at most 3 shots are on screen.
  - The shot is free: no hearts.
- **No attack state:** Simon keeps walking, jumping, crouching or climbing, and the whip never appears.
- **Up+B with a subweapon** still throws it the original way, in the attack state. **Up+B without one** fires a dagger.

**How:** the attack start `b6:$9A2A` is called by every movement state, and the state enters the attack only if it returns with carry set. The hook at `b6:$9A35` jumps to 60 bytes in bank 6's free space (`$BA3C`). That code spawns the dagger and returns with carry clear. Simon's code runs with bank 6 mapped, so there's no bank switch and no bank-7 space is used. Details are in the header of `run_and_gun.asm`.

## Build (scratch copy; leaves the repository untouched)

```sh
S=/path/to/scratch/cv            # any scratch directory
mkdir -p $S/src/spikes
cp -r games/castlevania/game.py games/castlevania/src games/castlevania/notes $S/
cp games/castlevania/spikes/run-and-gun/run_and_gun.asm $S/src/spikes/
sed -i 's|^TARGETS = \[\]|TARGETS = [("spike-run-and-gun", ["src/spikes/run_and_gun.asm"], 0)]|' $S/game.py
python3 scripts/build.py $S --rom games/castlevania/rom/original.nes
# -> $S/build/spike-run-and-gun.nes (63 bytes changed, preimages checked)
```

## Test

```sh
python3 scripts/run_fceux.py $S/build/spike-run-and-gun.nes games/castlevania/spikes/run-and-gun/t_run_and_gun.lua \
  --game-dir games/castlevania --out $S/out --tag rng --timeout 300
```

The test plays stage 1 and makes 10 behaviour checks. It holds invincibility (`$5B`) so that knockback can't disturb the movement checks; that only skips contact damage, not shot hits.

| Check | Spike ROM | Original ROM (negative control) |
|---|---|---|
| A. Walk right 150 frames, B every 10 frames: X keeps rising 1 px per unfrozen frame | ok (+103 px, plus 47 frames frozen by a whip-upgrade pickup) | FAIL (+40 px) |
| A. Daggers spawn while walking | ok (8) | FAIL (0) |
| A. No attack state (`$046C` = 2) | ok (0 frames) | FAIL (110 frames) |
| A. Whip never shown (slots 1-2) | ok | FAIL (105 frames) |
| B. Jump keeps its arc while firing (40 frames, 41 px) | ok | ok (the jumping whip doesn't stop a jump either) |
| B. Daggers in the air, no whip | ok (2) | FAIL |
| C. Crouch + B stays crouched, dagger spawns | ok (30 of 30 frames crouched) | FAIL (8 of 30) |
| D. Up+B with the dagger subweapon: original throw (`$0434` = `$81`, −1 heart) | ok | ok |
| E. A dagger kills an enemy | ok (zombie in slot 5, 14 frames in) | FAIL (the whip kills it; no subweapon hit) |
| F. On stairs + B: keeps climbing at 0.5 px/frame, dagger spawns | ok (24 px in 48 frames) | FAIL (7 px) |

Result: **RESULT PASS** on the spike ROM. The original ROM fails 8 of the 10 checks, so the test does tell the two apart.

## Findings for the estimate

- **The hook point is clean.** One attack-start routine serves all four movement states, so run-and-gun needs no change to the state machine.
- **Pickup freeze.** Shooting candles from a distance drops items more often. The whip upgrade (item 3) then triggers the game's ~48-frame pickup freeze (`$7E`). The item table has to be remapped for a commando (weapons/items work).
- **Stairs drop some presses.** The stairs state calls the attack start only on some step phases (`b6:$959E-$95A7`), so some B presses on stairs are ignored. A full version should fire from a once-per-frame hook, not from inside the attack start.
- **Not done in the spike:**
  - a bullet of its own (it reuses the dagger)
  - auto-fire
  - muzzle offsets per pose and a shooting pose
  - aiming
  - breaking the 29 whip-only breakable blocks (`b6:$A825`)
- **Demos.** Attract demos replay recorded inputs through the same code. With this patch they play out differently: verified, the stage-7 demo gains a death.
