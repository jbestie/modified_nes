# Shared entry point for every game under games/.  Pick one with GAME=<dir>.
PY   ?= python3
GAME ?= ghosts-n-goblins
G    := games/$(GAME)
ROM  ?= $(G)/rom/original.nes

ifeq ($(wildcard $(G)/game.py),)
$(error unknown GAME '$(GAME)' (known: $(notdir $(patsubst %/game.py,%,$(wildcard games/*/game.py)))))
endif
# Per-game defaults and extra targets (e.g. PATCH); they don't change the default goal
.DEFAULT_GOAL := all
-include $(G)/game.mk

.PHONY: all build layout test quicktest patch clean games

all: build

# Assemble the game's src/*.asm against its original ROM (with preimage checks):
# $(G)/build/*.nes, listings, patch maps, notes/patch_ranges.md and dist/*.bps.
build:
	$(PY) scripts/build.py $(G) --rom $(ROM)

# Regenerate $(G)/notes/rom_layout.md from the actual ROM bytes.
layout:
	$(PY) scripts/rom_info.py $(ROM) --game $(G) --md $(G)/notes/rom_layout.md

# The game's FCEUX-driven test suite; summary in $(G)/tests/out/summary.txt
test: build
	$(PY) $(G)/run_tests.py

# Same without the long sweeps
quicktest: build
	$(PY) $(G)/run_tests.py --quick

# Apply a distributable patch: make patch IN=your.nes OUT=patched.nes [PATCH=...]
patch:
	$(PY) scripts/bps.py apply $(PATCH) $(IN) $(OUT)

clean:
	rm -rf $(G)/build $(G)/tests/out

# List the games
games:
	@echo $(notdir $(patsubst %/game.py,%,$(wildcard games/*/game.py)))
