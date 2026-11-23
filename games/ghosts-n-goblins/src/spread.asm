; =============================================================================
; Feature B - Contra-style five-way spread shot
; Ghosts'n Goblins (USA), PRG CRC32 B4E4879E, mapper 2 (UNROM)
;
; Engine facts this relies on (see notes/addresses.md):
;   * 25 object slots ($00-$18).  Original partition:
;       $00 Arthur, $01-$10 enemies, $11-$13 player weapons,
;       $14-$15 enemy projectiles, $16-$18 sprite-only effects.
;   * Weapons are ordinary objects (types $23-$27) updated by the generic
;     object loop (bank 4 $9CC8, slots $01-$15), drawn by the generic renderer
;     (bank 4 $8000, slots $00-$18) and hit enemies through the shared
;     enemy-vs-weapon test $F5F2 (loop over weapon slots at $F5F9).
;   * Weapon motion uses the engine's 16-direction fixed-point table at $F2A3
;     indexed by $05F1,X (Y,X pairs; dir 4 = right, 12 = left, 22.5 deg/step).
;
; Patch:
;   * Repartition: enemies $01-$0E, player weapons $0F-$13 (five slots).
;     Every loop that bounds the enemy range at $11 is changed to $0F; the
;     weapon collision loop starts at $0F.
;   * The attack routine ($E045) fires only when all five weapon slots are
;     free and then spawns five copies of Arthur's current weapon through the
;     original initialiser ($E0BE), overriding only the direction:
;         dir = facing + (slot - $11), facing = 4 (right) or 12 (left)
;         facing right: dirs 2..6   = up 45, up 22.5, level, down 22.5, down 45
;         facing left : dirs 10..14 = the exact mirror image of that fan
;     Each projectile is a full engine object: its own position, lifetime,
;     wall/off-screen removal, enemy collision, damage ($0647,X) and sprite.
;   * Global player-projectile cap: 5 (one burst).  A new burst is refused
;     until every projectile of the previous one has been removed, so the
;     weapon table can never overflow.
; =============================================================================

ENEMY_END    = $0F          ; enemies use slots $01..ENEMY_END-1 ($01-$0E)
WEAPON_FIRST = $0F          ; player weapons use slots $0F-$13
WEAPON_END   = $14

ObjFlags     = $04F0
ObjDir       = $05F1        ; 16-direction index for weapon motion
ArthurAtk    = $061D        ; Arthur: bit 1 = attack in progress
ArthurAnim   = $0631        ; Arthur: attack animation counter
WeaponInit   = $E0BE        ; original: init weapon slot Y from Arthur (slot X)
FireNone     = $E074        ; original: LDA #0 / STA $85 / RTS

.bank 7

; --- 1. Shrink the enemy range from $01-$10 to $01-$0E -----------------------
.org $DA20                  ; FindFreeEnemySlot ($DA18): LDY #1 .. CPY #$11
.expect C0 11
    CPY #ENEMY_END
.org $DA4E                  ; RecycleEnemySlot ($DA28): round-robin wrap
.expect C0 11
    CPY #ENEMY_END
.org $DA60                  ; RecycleEnemySlot: next-start pointer $CE wrap
.expect C9 11
    CMP #ENEMY_END
.org $D763                  ; enemy census loop ($D744)
.expect E0 11
    CPX #ENEMY_END
.org $D381                  ; dormant-enemy sweep ($D374)
.expect E0 11
    CPX #ENEMY_END
.org $D531                  ; enemy wipe on stage (re)start ($D529)
.expect C0 11
    CPY #ENEMY_END

; --- 2. Enemy-vs-weapon collision covers the five weapon slots ---------------
.org $F5F9                  ; LDY #$11 .. CPY #$14 (end unchanged)
.expect A0 11
    LDY #WEAPON_FIRST

; --- 3. Attack: five-way burst ------------------------------------------------
; Original $E045-$E073: find a free slot in $11-$12 ($13 for the dagger),
; mark the attack, call $E0BE once, set the $85 fire latch.  The replacement
; fits in exactly the same 47 bytes (no free space elsewhere is needed;
; $E074 "no shot" is still the original LDA #0 / STA $85 / RTS).
.org $E045
.expect A0 11 B9 F0 04 F0 13 C8 C0 13 90 F6 C0 14 B0 1F AD 3A 05 C9 42 F0 EB 4C 74 E0 BD 1D 06 09 02 9D 1D 06 A9 00 9D 31 06 20 BE E0 A9 FF 4C 76 E0
SpreadFire:                 ; X = Arthur's slot (0); entered only when $85 == 0
    LDY #WEAPON_FIRST
@check:
    LDA ObjFlags,Y
    BNE FireNone            ; previous burst still alive: no shot
    INY
    CPY #WEAPON_END
    BCC @check
    STA ArthurAnim,X        ; A = 0 here: restart throw animation (as original)
    LDA ArthurAtk,X
    ORA #$02
    STA ArthurAtk,X         ; attack in progress (as original)
@spawn:                     ; Y = $14 on entry; spawn $13 down to $0F
    DEY
    TYA
    PHA
    JSR WeaponInit          ; original init: position, type, facing, sprite, sound
    PLA                     ; (the sound driver may clobber Y; X is preserved)
    TAY                     ; A = Y = slot
    CLC
    ADC ObjDir,Y            ; + facing direction set by WeaponInit (4 or 12)
    ADC #[$100 - $11]       ; - $11  -> dir = facing + (slot - $11): -2..+2
    STA ObjDir,Y
    CPY #WEAPON_FIRST
    BNE @spawn
    DEC $85                 ; $85: 0 -> $FF, fire latch (as original)
    RTS
SpreadFireEnd:
.assert SpreadFireEnd == FireNone, "SpreadFire must end exactly at $E074"

; --- 5. Impact spark faces the throw direction, not "dir == 4" ---------------
; Original $EBE9: LDA $05F1,X / CMP #$04 / BEQ  (spark $F8 only for dir 4).
; Diagonal right-facing shots would show the left spark; test the facing bit.
.org $EBE9
.expect BD F1 05 C9 04 F0 05
    LDA ObjFlags,X
    AND #$04
    BEQ $EBF5
