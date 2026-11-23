# Ghosts ’n Goblins (NES) — Invincible Arthur + Contra Spread Gun

> **Implementation task for Claude Code / Opus.** This is an actionable ROM-hacking project, not a request for a feasibility essay. Work against the supplied legally obtained original ROM and deliver reproducible code, a working patched ROM for local testing, and a distributable *patch only*.

## 0. Target and environment

- Target: **Ghosts ’n Goblins, NES / USA (NTSC)**, not the arcade, Famicom, SNES or PAL version.
- Expected cartridge layout: **mapper 2 / UNROM**, **8 × 16 KiB PRG-ROM banks (128 KiB PRG)**, **CHR-RAM** (no CHR-ROM). This is reference information; **inspect the actual iNES header**.
- Repository input: `rom/original.nes` (do not fetch or redistribute copyrighted ROM images).
- Track both the entire `.nes` file and PRG-only checksums. A reference US cart's **PRG-only CRC32 is `B4E4879E`**; this is *not* the CRC of the entire `.nes` file. Some ROM listings give **`87ED54AA` for the complete US iNES dump**. Do not patch blind based on either checksum: verify the actual image and document its hash and layout.
- Host: Ubuntu / Linux. Available/expected: Python 3, Git, `ca65` / `ld65` (`cc65` package), and Mesen Community Edition (MesenCE) for debugging.
- If tools or input files are missing, explain precisely what is missing, perform all possible static work, and give a concrete next command. Do not invent successful tests.

## 1. Feature A — Proper invincibility

Arthur must be **immune to enemy contact damage and enemy projectiles**, preserving armor and lives, with no interruption to movement or controls.

Required behavior:

- Do not permanently force the engine's *temporary* post-hit invulnerability state if it causes flicker, freezes, disables item pickup, or breaks other logic.
- Prefer identifying and patching the **damage/armor-loss routine**, not merely overwriting a RAM flag every frame.
- Preserve jumping, ladders, gravity, crouching, weapon pickup, stage transitions, boss triggers, enemies and normal collisions.
- Keep intentional gameplay interactions functional. Test pit/fall death and timeout separately; report whether each remains lethal. Default: **do not silently rewrite stage progression** just to prevent all deaths.
- Do not introduce immortality for enemies or bosses.

**Pass criterion:** repeat hits from enemy bodies and projectiles cannot strip Arthur's armor or cost a life; normal controls and pickups continue working.

## 2. Feature B — Contra-style “S” Spread Gun

Implement an exaggerated forward five-shot spread when Arthur attacks, using existing weapon graphics initially (e.g. dagger-like graphics) to avoid unnecessary CHR work.

Required behavior:

- **Five independently simulated, damaging projectiles** fired at the same moment in a forward-facing fan.
- Suggested angles in screen space: `-30°, -15°, 0°, +15°, +30°` relative to the horizontal firing direction. Use practical integer or fixed-point X/Y deltas, not floating point on the NES CPU.
- Mirror correctly when Arthur faces left; symmetric trajectory and equivalent damage in either direction.
- Each projectile updates position, lifetime, hit detection, impact/removal, and OAM rendering independently.
- Multiple bursts must work repeatedly. Decide and document a sensible global projectile cap; when it is reached, avoid buffer overruns or corrupted state.
- Do not turn this into a *cosmetic* five-shot: all five must really hit enemies/bosses and cause damage.
- Preserve stage and boss behavior. If speed/number of projectiles needs balancing for the NES, document the tradeoff, but deliver a five-shot by default.

### NES-specific constraints to investigate

- 2A03/6502 CPU time budget, available RAM, per-frame object-processing time.
- 64 hardware sprites total, **8 sprites per scanline**; overlaps may flicker. This does not necessarily prevent logical hits.
- Game's original projectile object slots and projectile-to-enemy collision logic. A renderer-only sprite duplication is **not acceptable**.
- UNROM bank switching and CPU-to-PRG file-offset mapping. Track both bank index and CPU address for every hook.
- Fixed bank vs switchable banks, vectors, reset/NMI behavior.
- Available free space versus safe code caves; bank expansion/mapper conversion only if justified and tested. Prefer original mapper/ROM dimensions when feasible.

## 3. Investigation and implementation workflow

**Do the work in the following order. Do not stop at a report.**

1. Inspect `rom/original.nes` header, ROM size, bank count, mapper, PRG checksum, and note trainer presence. Create `notes/rom_layout.md`. Reject unsupported variants with a clear explanation rather than silently patching guessed offsets.
2. Boot the original ROM in MesenCE if the emulator is available. Identify the Arthur damage path and the existing projectile spawn/update/collision paths. Use debugger breakpoints / trace / code-data logging. If the emulator cannot be driven automatically, generate reproducible manual breakpoint instructions and continue with disassembly and static analysis.
3. Extract and document the *relevant* routines in bank-aware annotated 6502 assembly. A full perfect disassembly is not a prerequisite; trace the exact paths needed.
4. Implement invincibility as an independently testable patch. Build `build/invincible.nes`; test baseline boot and damage behavior.
5. Implement new projectile object allocation, update, collision, draw, cleanup, and attack-spawn hooks as necessary. **Do not assume the original engine has five slots.**
6. Build `build/ghosts-n-goblins-spread.nes` containing both features; keep the baseline `rom/original.nes` unmodified.
7. Use small scripts/build rules to check patched byte ranges and expected preimage bytes; fail loudly if original bytes do not match.
8. Run all automated tests actually available. Document which gameplay tests were performed manually, which were automated, and which **remain unverified**.
9. Export a patch file, ideally `dist/ghosts-n-goblins-invincible-spread.bps` (use IPS only if necessary and explain why), plus `README.md` and reproducible `Makefile` or `build.sh`.
10. Summarize exact implemented behavior, tests, known issues, and command(s) to rebuild and patch from the original ROM.

## 4. Engineering deliverables (must exist on disk)

```text
rom/original.nes                     # Input, never commit or distribute
src/                                 # Assembly hooks / source where applicable
scripts/                             # Deterministic ROM analysis and patch tools
notes/rom_layout.md                  # Header and checksums
notes/addresses.md                   # CPU addresses, bank IDs, PRG offsets, RAM fields
notes/test_report.md                 # What was tested; evidence and limitations
build/invincible.nes                 # Intermediate local test ROM
build/ghosts-n-goblins-spread.nes    # Final local test ROM
README.md                            # Build and play instructions
Makefile or build.sh                  # Reproducible build
.gitignore                           # Exclude ROMs, build output and user files
dist/*.bps                            # Patch only, for sharing
```

If the implemented approach uses a deterministic Python patcher instead of a full assembler, that is acceptable **provided the patch logic/source and byte-level preconditions are clear, reviewable, and reproducible**. Do not submit an undocumented binary edit.

## 5. Acceptance tests

- [ ] Original ROM hash/layout inspected and documented.
- [ ] Original game boots before any modification.
- [ ] Invincibility build boots with normal graphics, controls, sound and progression.
- [ ] Repeated contact with enemy bodies does not damage Arthur.
- [ ] Enemy shots do not strip armor or kill Arthur.
- [ ] Normal movement, ladders, jumping and pickups still work.
- [ ] Exactly five projectiles appear in a forward fan when firing right.
- [ ] Exactly five projectiles appear in a mirrored forward fan when firing left.
- [ ] Every individual projectile can damage an enemy; not merely a visual sprite clone.
- [ ] Repeated button presses and crowded scenes do not overflow projectile tables or crash.
- [ ] Bosses can be damaged and defeated; stage transitions continue normally.
- [ ] Known NES sprite flicker/slowdown situations are noted if present.
- [ ] Both features coexist without regressions.
- [ ] Patch can be reapplied deterministically to the original ROM, reproducing the final binary.
- [ ] Only patch/source/documentation are intended for sharing; no copyrighted ROM distributed.

A test is **not passed** merely because the file builds or the title screen opens. Mark gameplay checks that were not actually exercised **UNVERIFIED**.

## 6. Communication and work style

- **Act as an engineer, not a consultant.** Investigate, change code, run tools, build artifacts, and iterate until the features work or a specific technical blocker is demonstrated.
- Do not invent disassembly, addresses, tool output, test results, or “working” status.
- Prefer useful partial deliverables over superficial discussion. If stuck, show the exact blocker with a trace/address and a reproducible next step.
- Keep a short progress log; focus on actual file changes and evidence.
- If there is a choice between a fancy weapon graphic and five real independent damaging projectiles, choose **five working projectiles**.
- **Livestream priority:** stability and laughably overpowered gameplay outrank code elegance. Still keep the project reproducible and safe from RAM corruption.

## 7. Relevant technical sources

- NES layout and mapper: https://datacrystal.tcrf.net/wiki/Ghosts%27n_Goblins_%28NES%29
- Original US cartridge PRG-ROM CRC: https://nescartdb.com/profile/view/4/ghosts-n-goblins
- NES disassembly collection (game currently listed as *Planning*, not completed): https://github.com/cyneprepou4uk/NES-Games-Disassembly
- Mesen Community Edition current fork: https://github.com/nesdev-org/MesenCE
- Claude Code: https://github.com/anthropics/claude-code

## 8. Start immediately

Read this task file, then inspect the local ROM. Begin by creating `notes/rom_layout.md` from **actual file bytes**, and proceed to the investigation and implementation. The work product is an operational **invincible + spread-shot** NES modification, not just suggestions.
