# Castlevania: defaults for the root Makefile (GAME=castlevania).
PATCH ?= $(G)/dist/castlevania-commando-mechanics.bps

# Private commando ROM: the commando build with the graphics imported from your own Super C (USA) dump.
# The output contains Super C graphics: it stays in build/private/ (ignored by git); never share it.
SUPERC ?= $(G)/rom/Super C (U) [!].nes
ART_OUT ?= $(G)/build/private/castlevania-commando-superc.nes

.PHONY: art
# Plain `make GAME=castlevania` builds the private ROM too when the dump is there.
# (test -f, not $(wildcard): the default name has spaces and a [!] glob.)
ifeq ($(shell test -f "$(SUPERC)" && echo yes),yes)
all: art
endif
art: build
	$(PY) $(G)/tools/commando_art.py --base $(G)/build/castlevania-commando.nes \
	  --sym $(G)/build/castlevania-commando.sym --orig $(ROM) --superc "$(SUPERC)" --out "$(ART_OUT)" $(ART_FLAGS)

# Keep a playable copy of the private ROM at a named checkpoint:
#   make GAME=castlevania checkpoint NAME=m2a-aiming
# -> build/private/checkpoints/castlevania-commando-<NAME>.nes (ART_OUT stays the latest build)
.PHONY: checkpoint
checkpoint: art
	@test -n "$(NAME)" || { echo "usage: make GAME=castlevania checkpoint NAME=<name>"; exit 1; }
	mkdir -p $(G)/build/private/checkpoints
	cp "$(ART_OUT)" "$(G)/build/private/checkpoints/castlevania-commando-$(NAME).nes"
	@echo "checkpoint: $(G)/build/private/checkpoints/castlevania-commando-$(NAME).nes"

