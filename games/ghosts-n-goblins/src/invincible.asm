; =============================================================================
; Feature A - Invincible Arthur (enemy bodies and enemy projectiles)
; Ghosts'n Goblins (USA), PRG CRC32 B4E4879E, mapper 2 (UNROM)
;
; How the original game handles a hit (all in the fixed bank, see
; notes/addresses.md):
;   * Enemy collision code ($F5E3, and others) sets bit 0 of Arthur's object
;     flags $04F0 ("hit pending").
;   * The expired-timer handler ($D3B8) also sets bit 0 and sets $BD=$FF.
;   * Every Arthur state routine polls HitPending ($E014) once per frame:
;         JSR $E014 / BCC no_hit / JMP $E171
;   * $E171 is the damage routine: if $BD!=0 -> death; else if no armor
;     (bit 5) -> death; else knockback, armor loss, post-hit blinking.
;
; Patch: HitPending now swallows the hit (clears bit 0, reports "no hit")
; unless $BD is set.  Arthur never enters $E171 for enemy damage, so no
; knockback, armor loss, blinking or life loss happen, and the current state
; (walking, jumping, ladder, crouching, attacking) continues uninterrupted.
; Timer expiry still kills ($BD path).  Pits/water kill through separate
; death entries ($E1BA etc.) that do not use bit 0, so they stay lethal.
; =============================================================================

ArthurFlags = $04F0         ; object flags array, slot 0 = Arthur
TimeUp      = $BD           ; set to $FF when the stage timer expires
TestBit0    = $F2E3         ; A = $04F0,X & $01  (Z set if clear)
ClearBit0   = $F32A         ; $04F0,X &= $FE

.bank 7

; --- HitPending entry: redirect to the filtered version ---------------------
.org $E014
.expect 20 E3 F2 F0 02 38 60 18 60      ; JSR $F2E3 / BEQ +2 / SEC / RTS / CLC / RTS
HitPending:
    JMP InvHitPending

; --- Code cave: 18 bytes of $FF padding before the CPU vectors --------------
.org $FFE8
.expectfill $FF, 18
InvHitPending:
    JSR TestBit0
    BEQ @nohit
    LDA TimeUp
    BNE @hit                ; timer expired: keep original death behaviour
    JSR ClearBit0           ; enemy/projectile hit: acknowledge and discard
@nohit:
    CLC
    RTS
@hit:
    SEC
    RTS
InvEnd:
.assert InvEnd <= $FFFA, "invincibility cave overruns the vectors"
