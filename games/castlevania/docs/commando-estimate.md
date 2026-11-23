# Super C commando replacing Simon: deep estimate

Item 2 of `../TODO.md`, written 2026-11-17 for Castlevania (USA, Rev 1).

**What this estimate covers:**
- the commando's moves, in Simon's engine
- his weapons and pickups
- his graphics
- everything that has to change around them: items, HUD, sound, bosses, cutscenes, demos

**What it is based on:**
- the engine map `../notes/addresses.md`
- four investigations: Super C measured on the user's own dump; Castlevania movement, weapons/items/HUD and graphics
- two working proofs of concept in `../spikes/`

## How to read the numbers

- **Work-day:** one focused day of an experienced NES romhacker using this repository's tools (assembler with preimage checks, FCEUX Lua tests). Calibration from this repository:
  - the Ghosts'n Goblins main hack (one invincibility hook, a 5-way spread on existing projectile code, tests, docs) ≈ 3-4 days
  - the Ghosts'n Goblins remix ROM ≈ 5-7 days
  - item 0 of the TODO (the engine map) was sized M (2-5 days)
- **Three numbers per line:** low / likely / high. Totals add the columns, so the low and high totals are deliberately pessimistic and optimistic extremes; the likely column is the planning figure.
- **What a work-day means here:** a lot of the code and test work can be done by Claude in this repository much faster than a human's day. Three things still need human time: play-feel tuning, boss balance, and pixel art if new art is chosen.

## Bottom line

| Scope | Low | Likely | High |
|---|---|---|---|
| **A. Commando MVP**: commando look, run-and-gun forward shots, Castlevania rules, every stage playable | 9 | **15.5** | 24.5 |
| **B. Full commando** (A plus): 8-way aiming, prone, air control, somersault, the 6 Super C weapons, falcon pickups, HUD letter | +12.75 | **+22.5** | +37.75 |
| **Full commando total** (A + B) | 22 | **38** | 62 |

Optional add-ons and alternatives:

| Add-on / alternative | Low | Likely | High |
|---|---|---|---|
| Contra rules: one hit kills, Castlevania-style respawn | +0.5 | +1 | +2 |
| Contra rules: respawn in place (needs a safe spot over pits) | +3 | +5 | +8 |
| 2-3 new sound effects (instead of reusing existing ones) | +1 | +1.5 | +2 |
| Art route 2 (new original art) instead of route 1 | +2 | +3 | +6 |
| Placeholder build (route 3) as well, for a shareable mechanics patch | +0.25 | +0.5 | +1 |
| Super C's arc with its 15 shortcuts closed by level edits. The level format is decoded and the terrain follows the tiles, so these are same-size data edits in bank 4 (`../notes/addresses.md` section 13, `../tools/level_data.py`) | +0.5 | +1 | +2 |

The four investigations estimated their own areas independently, and their sums agree with the table: movement ~17 days likely, weapons/items/HUD ~17, graphics route 1 ~4, total ~38.

**What is already proven:**
- **`spikes/run-and-gun/`:** a 63-byte patch makes B fire while walking, jumping, crouching and climbing, with no whip. Its test passes 10 behaviour checks on the patched ROM, and 8 of them fail on the original (re-run independently).
- **`spikes/graphics/`:** an importer that reads the commando from the user's own Super C dump at install time. Scratch ROMs show him standing, walking, kneeling, climbing, hurt and dead in the courtyard, stages 1, 7 and 12, the castle map and the intro walk. The extra poses render and mirror correctly: aim up, diagonals, prone, somersault.

## Reference: Simon vs the commando

All measured in FCEUX; Super C on the user's dump (PRG CRC32 `C7FBECC3`).

| | Simon (Castlevania) | Commando (Super C) |
|---|---|---|
| Run speed | 1.0 px/frame | 1.0 px/frame, no acceleration, instant turn |
| Jump | 36 px high, 40 frames, 41 px long; no air control | 58-59 px high, 55-56 frames, 56-57 px long; full air control (you can reverse in the air, not stop); always a 4-frame somersault |
| Crouch / prone | crouch, can't move, contact half-height `$0A` vs `$0C` | prone, can't move, 10 px tall × 30 wide |
| Attack | whip, ~22 frames, movement frozen; Up+B throws the subweapon | shoots while running and jumping |
| Aiming | none | standing: forward or up. Running: forward or diagonal up/down. Prone: forward. Jumping: all 8 directions |
| Hits to die | health bar (8-16 per hit, by stage), knockback | one hit; pits always kill |
| Respawn | stage start point | drops in where he died, 128 frames invulnerable |
| Sprites per frame | 3-4 (16 px wide) | 4-6 (16-25 px wide, 32 when prone) |

**Weapons in Super C** (`$B8`; bit 7 = R):

| Weapon | Speed (px/frame) | Max on screen | Holding B | Behaviour | Damage |
|---|---|---|---|---|---|
| Default | 4.0 | 4 | 1 shot | single shot | 1 |
| M | 4.0 | 6 | fires every 7 frames | single shots | 1 |
| S | 4.0 | 10 | 1 volley | 5 at 0°, ±11.25°, ±22.5° | 1 each |
| L | 4.0 | 1 laser | refires when gone | 5 segments 8 px apart, not piercing; a new shot restarts it | 1 each |
| F | 5.5 | 2 | charges 32 frames | bursts into 4 diagonal fragments on a hit; a charged shot gives 8 fragments | 1, charged 5 |

- **R:** raises bullet speed one step (4.0 → 5.5 → 7.0); no effect on L.
- **B:** barrier for 521 frames.
- **Falcon:** clears the screen.
- All weapons are lost on death.

## Feature breakdown

Effort in work-days. The asm sizes are rough. Addresses are in `../notes/addresses.md` and in the investigation notes that the spikes' READMEs summarise.

### Movement and control

| Feature | What changes in Castlevania | Size | Low | Likely | High | Scope |
|---|---|---|---|---|---|---|
| Run speed | Nothing: both heroes run at 1 px/frame. A faster run would break scrolling (the camera unlocks only at exactly X = `$80`; the 64-px spawn columns, the boss lock and the door walk-out use exact positions), but the commando doesn't need one | 0 | 0 | 0 | 0 | A |
| Run-and-gun core | Production version of the spike: a fire hook that runs every frame (the stairs code only checks attacks on some steps), muzzle offset per pose, firing pose, cooldown | 150-250 B | 1.5 | 2.5 | 4 | A |
| 8-way aiming with Super C's rules | Pad → aim direction; vertical bullet speed. The subweapon throw moves off Up+B (Select is free: gameplay never reads it). Stairs keep priority: Up/Down next to a staircase climbs (0 B); optional polish: Up must be held ~10 frames to climb (~20 B) | 110-160 B | 2 | 3 | 5 | B |
| Prone | Smaller contact height `$5F`; shift the sprite/contact Y (`$0354`), not the master Y `$3F` | 20-30 B | 0.5 | 1 | 2 | B |
| Air control | Hook at `b6:$948E` re-reads the pad in the air (tested in a scratch build: release stops, reverse turns). Super C's version keeps drifting until you reverse | 19 B | 0.5 | 1 | 1.5 | B |
| Jump arc | **Decision.** Keep Simon's arc (0 days, every stage stays passable), or use Super C's: point `b6:$9B8D` at a new table, plus a ~6-byte fix so the head doesn't stop the jump under a low ceiling. Measured on all 38 stage/floor collision maps: Super C's arc loses 1 jump (stage 5, floor 1, the low ceiling the fix covers) and opens 15 shortcuts past intended routes | 30-50 B | 0.5 | 1 | 2 | B (optional) |
| Somersault (code) | Pose cycle in the jump state, optionally a smaller jump hitbox | ~26 B | 0.5 | 1 | 1.5 | B |
| Stairs | Climbing code unchanged; shooting poses on stairs and aiming along the stair diagonal | 30-50 B | 0.5 | 1.5 | 3 | B |
| Hurt | Keep the health bar, drop the knockback (~6 B). Contra rules are an add-on (above) | 6 B | 0.5 | 0.5 | 1 | A |
| Outside gameplay | The attract demos replay recorded input through the player code and desync (the stage-7 demo gains a death): disable or re-record. Redirect the intro's back-view frame (`$19`). The ending was not reached; budget a check | data | 0.5 | 1.5 | 2.5 | A |

### Weapons, items, HUD, sound, balance

| Feature | What changes | Size | Low | Likely | High | Scope |
|---|---|---|---|---|---|---|
| Bullet slots, minimal | Widen the stock object and collision loops to slots `$14-$1B`, with a type filter. Fine up to ~5 bullets; a stock projectile costs ~353 cycles plus ~107 per target per frame, so 5 bullets lag ~4% of play frames | 60-100 B | 1 | 1.5 | 2.5 | A |
| Bullet pass, full | A dedicated bullet update and collision pass (bank 5, hooked at `$CF19`) costing ~90 + 40 cycles per target per bullet: 8 bullets lag 0.8% of frames, 10 bullets 1.5%. Reuses the stock on-hit handlers. Replaces the minimal version (the delta is counted) | 300-450 B | +1.5 | +2.5 | +3.5 | B |
| Default rifle | Bullet kind row and direction speed table (projectiles already move at any angle: independent X/Y speeds) | ~55 B | 0.25 | 0.5 | 1 | A |
| M | Auto-fire every 7 frames, up to 6 | ~20 B | 0.25 | 0.5 | 1 | B |
| S | 5-way volley, centre first, as many as free slots (partial volleys in stages 4, 5 and 10 and around debris) | ~200 B | 1 | 1.5 | 2.5 | B |
| L | 5-segment chain, restarted by a new shot | 80-100 B | 1 | 1.5 | 2.5 | B |
| F | Burst into 4 fragments on a hit; charged shot with 8 fragments and damage 5 | ~150 B | 1.5 | 2.5 | 4 | B |
| R | Takes over the whip-upgrade item (`03`): random drops already exist; level in `$70` (reset on death); speed step | ~15 B | 0.25 | 0.5 | 1 | B |
| B | Takes over the potion (`0E`, invulnerability `$5B`); a 521-frame duration needs a separate counter | ~20 B | 0.25 | 0.5 | 0.75 | B |
| Bullets break wall blocks | Today only the whip breaks the 29 blocks (verified: daggers and axes pass through). Loop the live bullets through the stock block test and break sequence. Alternative: keep a short melee attack for blocks | 80-120 B | 1 | 1.5 | 2.5 | A |
| Items and drops | M/S/L/F replace the dagger/cross/holy-water/axe item IDs, so every candle and enemy drop keeps working; R replaces the whip upgrade, B the potion. The rosary stays (it is Super C's falcon screen-clear). Remove double/triple shot: bullets must not count toward it, and 8 blocks need another item. Hearts stay as a collectible counter | 20-60 B | 0.5 | 1 | 1.5 | A |
| HUD weapon letter | The letters exist as HUD background tiles: write the weapon letter where the double/triple icon goes (the routine already redraws it on every pickup). A sprite icon comes free with the graphics (falcon letters reuse the item tiles) | 15-25 B | 0.5 | 1 | 1.5 | B |
| Sound | Reuse existing effects: `$01` (an unused 3-frame noise tick) as the gunshot, `$1C`/`$25` for the laser, `$18` for pickups | 0-10 B | 0.25 | 0.5 | 0.5 | A |
| Bosses and balance | Every hit freezes a boss for 8 frames and there is no damage cooldown, so auto-fire would stun-lock bosses: skip the freeze for bullets. Give bullets their own boss damage (bosses take full, half or quarter damage today). Playtest the 6 bosses | 30-60 B | 1 | 2 | 3 | A |
| Weapon balance pass | Each weapon against the 6 bosses and the tough enemies | — | 0.5 | 1 | 2 | B |

### Graphics (route 1: import from the user's own Super C dump)

| Feature | Low | Likely | High | Scope |
|---|---|---|---|---|
| Converter → build step; Castlevania-moveset poses; bullets; pose tuning; regression screenshots | 1.5 | 2.5 | 3.5 | A |
| Full pose set (aim up, diagonals, prone, somersault), falcon letters and HUD icon, intro back view, flicker survey | 1 | 1.5 | 2.5 | B |

The tile budget fits exactly. The full side-view set is 38 tile pairs plus 3 bullet tiles = Simon's 28 + the whip's 13 = 41, and no stage load touches those tiles. Super C's arm-swinging run and death tumble are cut (no room); the gun-forward run and the kneel replace them.

The commando draws more sprites: stage-1 frames with a scanline over 8 sprites go from 23% to 33% (flicker).

### Integration

| Feature | Low | Likely | High | Scope |
|---|---|---|---|---|
| Tests, full play-through of all 18 stages, docs, release packaging | 1 | 1.5 | 2.5 | A |
| More of the same for the full scope | 0.5 | 1 | 1.5 | B |

### Totals check

| Scope | Lines | Low | Likely | High |
|---|---|---|---|---|
| A | run-and-gun 2.5, hurt 0.5, outside 1.5, minimal slots 1.5, rifle 0.5, blocks 1.5, items 1, sound 0.5, bosses 2, graphics 2.5, integration 1.5 | 9 | 15.5 | 24.5 |
| B | aiming 3, prone 1, air control 1, arc 1, somersault 1, stairs 1.5, bullet-pass delta 2.5, M 0.5, S 1.5, L 1.5, F 2.5, R 0.5, B 0.5, HUD 1, weapon balance 1, graphics 1.5, integration 1 | 12.75 | 22.5 | 37.75 |

## Art routes

The BPS patches in this repository never carry game data, and Super C's graphics are Konami data in another ROM.

| Route | What you get | Graphics effort (included above for route 1) | Can it be shared? |
|---|---|---|---|
| 1. Import from your own Super C dump | The real commando, both colour schemes (blue, or exact player-1 colours via 3 palette bytes). The importer already works | 2.5 / 4 / 6 | **No.** The output ROM stays on your machine; others need their own Super C dump and the installer. Good for your own stream. |
| 2. New original pixel art | ~35 pieces: ~23 poses, bullets, capsule and letters, back view. It must reuse torso and leg tiles to fit 41 pairs | 4.5 / 7 / 12 | **Yes**, but a convincing result needs a human pixel artist. Claude or a romhacker would produce programmer art. It must not be traced from Super C. |
| 3. Placeholder | Recoloured Simon with a gun barrel | 0.25 / 0.5 / 1 | Yes. Mechanics only. |

A Super C dump is already in `../rom/` (ignored by git). Route 1 can use it.

## Decisions that change the cost

| # | Question | Options (cost) | Recommendation |
|---|---|---|---|
| 1 | Art route | 1 import (private), 2 new art (shareable, needs an artist), 3 placeholder | 1 for your stream ROM; build the mechanics first with route 1 or 3 |
| 2 | Rules | Castlevania health, no knockback (0.5); one hit kills + Castlevania respawn (+1); respawn in place (+5) | Health bar, no knockback. The stages and bosses are tuned for a health bar, and stage damage already rises to 16 |
| 3 | Jump | Simon's arc + air control (safe); Super C's arc (+1, 15 shortcuts; closing them by level edits +1) | Simon's arc + air control first; try Super C's arc as an option |
| 4 | Wall blocks | Bullets break them (+1.5); a melee knife | Bullets break them (simpler to play) |
| 5 | Stairs vs aiming up | Stairs keep priority (0); hold Up to climb (+0.25) | Stairs keep priority |
| 6 | Weapon set | All 6; or default + M + S first | All 6, built in milestone 3; S is the crowd pleaser |
| 7 | Hearts | Collectible counter (0); 100 hearts = 1UP (+0.5) | Counter first |
| 8 | Bosses | Bullets don't stun; damage columns per weapon | As stated, then playtest |

## Plan (milestones; each ends with a playable, tested ROM)

| Milestone | Contents | Likely days |
|---|---|---|
| **M1 MVP** (scope A) | Run-and-gun rifle forward, whip removed, bullets break blocks, boss stun fix, items remap, reused SFX, demos off, commando look (route 1 Castlevania-moveset set, or route 3); all 18 stages played through | ~15.5 |
| **M2 Moves** | 8-way aiming, prone, air control, somersault, stairs shooting, optional Super C arc | ~8.5 |
| **M3 Weapons** | Full bullet pass, M, S, L, F, R, B, HUD letter, falcon letters, weapon balance | ~11.5 |
| **M4 Polish** | Full pose set, intro back view, flicker survey, final play-through, installer and docs | ~2.5 |

## Progress

**Prototype 1** (2026-11-17): `../src/commando/commando.asm`, `../tools/commando_art.py`, test `../tests/t_commando.lua`. It uses the recommended defaults while the decisions above are open: art route 1 (private) with a shareable mechanics patch, the health bar without knockback, Simon's jump arc, bullets break blocks, and the rifle only.

| M1 item | Status |
|---|---|
| Run-and-gun rifle, forward | Done: fires in every movement state, 3 bullets (slots `$14-$16`), dagger semantics (4 px/frame, damage 6) |
| Whip removed | Done |
| Bullets break wall blocks | Done: tested in stage 3; the bot soak also broke blocks in stages 2, 4 and 12 |
| Boss stun fix | Freeze skipped for bullets (tested on a mummy). Own boss damage values still to do |
| Items remap | Partly: the whip-upgrade pickup freeze is gone; subweapons stay on Up+B for now |
| No knockback | Done, including death at zero health in any state |
| Reused SFX | Done: `$02` as the gunshot |
| Demos off | Done |
| Commando look | Done: route 1 installer; poses, bullets and the M2 poses imported |
| All 18 stages played through | Bot soak only (`../tests/explore/cmd_soak.lua`; worst lag 32 of 1,200 frames, stage 12); a human play-through is still needed |

**Milestone 2** (2026-11-18), in the same source; ready-to-run checkpoints in `build/private/checkpoints/`:

| M2 item | Status |
|---|---|
| 8-way aiming, Super C's rules | Done: ground up / diagonal up / diagonal down (walking with Down), air 8 directions, stairs along the steps |
| Subweapon off Up+B | Done: Select (the attack start now reacts to Select, `b6:$9A32`) |
| Prone | Done: Down alone; contact half-height `$04`; Down + Left/Right walks instead of crouching |
| Air control | Done: Left/Right in the air turns or starts the motion and keeps it (Super C's variant) |
| Somersault | Done: the jump shows the 4-frame spin; no smaller hitbox yet |
| Stairs shooting | Done: diagonal poses and shots along the steps |
| Super C's jump arc | Not done (optional; Simon's arc kept) |
| Firing poses | Done: stand firing, aim up firing, prone firing |

The user's playtest of prototype 1 (2026-11-18): it shoots, the first boss dies about as fast as in the original. The missing aiming and the knife throw on Up+B are what M2 changed.

**Milestone 3/4 pieces** (2026-11-18), after the user's playtest of 2a/2b ("solid"):

| Item | Status |
|---|---|
| Bullet pass, full | Done, but placed differently from the plan: the bullets run in the NMI's sprite-0 busy-wait (`$F8C4`, 4,257-5,559 idle cycles every frame), not after the object loop. One pass builds a target list (at most 12), moves up to 4 bullets and tests them; the hits go through the stock hit chain in the object loop. Lag in the stage-12 profile: 73 → 3 frames of 1,200; stage 3: 14 → 1. The pass leaves at least 1,562 cycles of the wait unused |
| More bullets | 4 on screen (Super C's default), slots `$16 $15 $1B $1A` |
| Intro back view | Done: Super C's top-down "walking up" frame `$38` into the intro's own tiles |
| Super C's jump arc | Test variant built (`jump_superc.asm`): 58 px / 56 frames, head probes off during jumps; the stage 5 low-ceiling jump is tested in FCEUX; the gap survey loses no jump and opens 14 shortcuts |

**Milestone 3** (2026-11-19), after the user's playtest of 3b ("not bad at all"; Super C's jump accepted; no subweapons wanted; the top-down back view looked odd):

| M3 item | Status |
|---|---|
| Weapons M, S, L, F, R, B | Done with Super C's rules (M auto-fire 7 frames/6 on screen; S 5-way fan; L 5-segment train, restarted by a press; F 5.5 px/frame, bursts into 4 fragments, charged 8; R one speed step; B = the potion's invincibility). 32-direction speed tables (4.0/5.5/7.0) |
| Pickups | Done: dagger M, cross S, holy water L, axe F, whip R, potion and stopwatch B, rosary falcon; the 8 blocks that hid a double shot now hide R. Subweapons and Select removed |
| Falcon letters, HUD letter | Done in the art install: the letters replace the item tiles; the HUD box shows wing + letter |
| Bullet slots | Up to 8 ($14-$16, $1A/$1B, $17-$19 when free); each bullet is tested every 2nd frame so the pass stays inside the sprite-0 wait (worst case left: 477 cycles) |
| Back view | Redrawn as an original 16 x 32 drawing (straight side-on, like Simon's) |
| Weapon balance pass | Done in M4 (2026-11-21): see "Weapon damage" below; playtesting still to confirm |

**Milestone 4, first pieces** (2026-11-21), after the user's playtest of 4a ("game is good"; reached block 4; the back view looked shorter than the walking commando; a moving platform in "level 2" is a pain with Super C's jump; bullets should look different per weapon):

| M4 item | Status |
|---|---|
| Bullet sprites per weapon | Done in the art install: Super C's object sprites (bank $36 table $8205) for rifle, M, S, the laser along its 8 directions (4 frames, `LaserFrames`), the fire ball and the charged ball; fragments use the S ball (CPU). Frames at the whip's ids $10-$18, palette 0. The 6 new tiles go into item tiles freed by sharing one falcon wing tile and by the multiplier, which never drops |
| Back view height | Done: redrawn 16 x 48, 33 px like the side view (was 29). The tiles are uploaded by the intro to table-0 pairs $E0-$EA (`IntroTiles`, bank 6), since the intro's tile set has no room left |
| Weapon damage | Done (user's choice: Super C's ratios, outliers capped): rifle, M, F, fragments 6, S 3, L 4, charged 30. A boss bot (`tests/explore/boss_fights.lua`) fought all 6 bosses with every weapon on a ROM with damage 1, and `boss_replay.py` replayed the hit logs under candidate tables; real fights at the chosen table matched the replay within 0.1 s. At an equal 6, S killed bosses 2.6-8.2x and L 1.1-2.8x faster than the rifle; capped 1.1-2.1x and 0.9-1.9x |
| B (barrier) | Done (2026-11-23): Super C's barrier read from its code (`$80`, -1 every 4th frame = 512 frames; enemies touching the player die unless their HP is `$F0`+, i.e. bosses). Here the potion's invincibility at `$FF` (510 frames) plus a barrier flag; contact with a normal enemy hits it for `$40` through the stock hit chain, bosses are spared |
| Stairs and aiming | Done: Up/Down at a staircase steps onto it only after 16 frames with no B (more than the gap between rifle shots), so aiming up or prone beside stairs keeps shooting |
| Ending, second quest | Checked by bot: Dracula, the crystal, the ending and credits, the second quest's first stage; all moves draw |
| "Killer platform" with Super C's jump | Settled: the user meant stage 6's spike crushers, which kill on touch. The higher, longer jump makes them harder to time; kept on purpose ("makes the game really interesting", 2026-11-21). Measured on the way: at stage 5's moving platforms Super C's arc does better than Simon's (23 vs 10 of 40 timings land) |

## Risks

1. **CPU time:** more than ~5 bullets needs the dedicated bullet pass. The stock projectile code would lag 20% of frames at 8 bullets. Extra CPU time also changes the RNG, so enemy behaviour differs; tests must check behaviour.
2. **Boss balance:** auto-fire stun-locks bosses unless the freeze is skipped, and quarter-damage bosses would take ~34 s. It needs a damage table and playtesting.
3. **Slots `$17-$1B` are shared** with moving platforms (stages 4, 5, 10), block debris (13 stages) and rising treasures (12 stages). S and F volleys are partial there. Super C's 10-bullet S becomes one 5-bullet volley.
4. **Flicker rises** (23% → 33% of stage-1 frames with a scanline over 8 sprites). Removing the whip helps on attack frames.
5. **Not covered by the investigations:** the ending, the second quest, Dracula's phases at runtime, moving platforms and enemy-dependent jumps in the arc survey. Budget is in the high column.
6. **Route 1 can't be shared:** decide the art route before planning a public release.

## Evidence

- `../notes/addresses.md`: engine map (item 0).
- `../spikes/run-and-gun/`: patch, test and README (build in a scratch copy; not a build target).
- `../spikes/graphics/`: importer, screenshot script and README (no Super C data in the repository; the scratch ROMs stay local).
- `../tools/level_data.py`: level and terrain decoder for every stage, checked against the emulator (lead: CadEditor's stage-1 config).
- Investigation notes, probes and contact sheets stay in the session's scratch directory. The contact sheets contain Super C graphics, so they aren't in the repository.
