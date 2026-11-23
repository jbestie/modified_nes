; =============================================================================
; Commando: Super C's jump (part of the castlevania-commando target since the
; user's playtest of the test variant, 2026-11-19). Assembled after commando.asm,
; whose symbols it uses.
;
;   * Arc: 58 px high, 56 frames in the air (Simon: 36 px, 40 frames), from
;     Super C's measured physics (start -4.0625 px/frame, gravity 35/256).
;     The interpreter b6:$9B1E plays the rise table forward, then backward and
;     negated for the fall; $80 before the table = fall at 8 px/frame after it.
;   * Ceiling: the wall check (b6:$9ECE) probes at head height too (-9/-4), so a
;     low ceiling stopped the horizontal motion of a high jump (stage 5, floor 1,
;     x 192). During jumps it now probes only the body (+15/+16, +8, 0).
;     Gap survey with this arc and these probes: no jump lost, 14 new shortcuts.
; =============================================================================

JumpDir     = $0514         ; slot 0: 0 rising, 1 falling (flipped by $9B1E)
ProbeTableA = $9F70         ; standing/walking/rising: +15, +8, 0, -9, -4
ProbeTableB = $9F75         ; falling: +16, +8, 0, -9, -4
ProbeLoop   = $9F36         ; LDA #4 / STA $4F: the probe loop, pointer in $00/$01

.bank 6

; ---- the jump's rise table (read by the jump start $940C into $04DC/$04F8)
.org $9B8D
.expect 90 9B
    .word SCJumpRise

; ---- wall check: pick the probe table
.org $9F1C
.expect A0 00 AD 6C 04 C9 01 D0 07 AD 14 05 F0 02 A0 02 B9 6C 9F 85 00 B9 6D 9F 85 01
    JSR ProbeSel
    JMP ProbeLoop

; ---- after commando.asm's code in bank 6's free space
.org FreeEnd6
.expectfill $FF, $C000 - FreeEnd6
    .byte $80               ; before the table: keep falling at 8 px/frame
SCJumpRise:
    .byte $FD, $FC, $FC, $FD, $FC, $FD, $FD, $FD, $FD, $FD     ; -3 -4 -4 -3 -4 -3 -3 -3 -3 -3
    .byte $FE, $FD, $FE, $FE, $FE, $FE, $FE, $FF, $FE, $FF     ; -2 -3 -2 -2 -2 -2 -2 -1 -2 -1
    .byte $FF, $FF, $FF, $FF, $FF, $00, $FF, $00               ; -1 -1 -1 -1 -1  0 -1  0 (58 px, 28 frames)
    .byte $81               ; peak: the interpreter turns around

; ProbeSel: $00/$01 = the wall probes. Jumps use body-only tables.
ProbeSel:
    LDY #0
    LDA SimonState
    CMP #$01
    BNE @set
    LDY #4
    LDA JumpDir
    BEQ @set
    LDY #6
@set:
    LDA ProbePtrs,Y
    STA $00
    LDA ProbePtrs + 1,Y
    STA $01
    RTS
ProbePtrs:
    .word ProbeTableA, ProbeTableB, ProbeRise, ProbeFall
ProbeRise:
    .byte $0F, $08, $00, $00, $00
ProbeFall:
    .byte $10, $08, $00, $00, $00
JumpEnd:
.assert JumpEnd <= $C000, "bank 6 free space overflow"
