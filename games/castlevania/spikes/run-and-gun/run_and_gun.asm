; =============================================================================
; Spike: run-and-gun for Simon (proof of concept, not a release patch)
; Castlevania (USA, Rev 1 / V1.1), PRG CRC32 B668C7FC, mapper 2 (UNROM)
;
; B (without Up) fires a dagger projectile (object type $17, kind 0) at once
; and does NOT enter the attack state, so Simon keeps walking, jumping,
; crouching or climbing while he shoots. The whip never comes out.
; Up+B with a subweapon still throws it the original way (attack state).
;
; Engine facts this relies on (notes/addresses.md, sections 6-9):
;   * b6:$9A2A is the attack start. Every movement state calls it (stand/walk
;     $943E, jump $949E, crouch $9569, stairs $95AB) and enters the attack
;     only when it returns with carry set. Carry clear = carry on moving.
;   * $DABC (bank 7) is the tail of the subweapon spawner $DA5F: with the slot
;     in $4E, A = kind and Y = graphic, it creates type $17 in that slot at
;     Simon's X and sprite Y - 8, facing like Simon. The dagger (kind 0)
;     flies 4 px/frame and is erased on its first hit.
;   * The subweapon collision loop $E5EB always checks slots $14-$16, so all
;     three projectile slots hit enemies regardless of the multiplier $64.
;   * $C1A7 plays sound A (8 = dagger throw), restores the bank from $27.
;
; Bank use: everything runs from bank 6 (Simon's code is in bank 6, so bank 6
; is mapped whenever $9A2A runs). No bank switch, no bank-7 space used.
; Free space: bank 6 $BA3C-$BFFF (notes/addresses.md section 14); this uses
; 60 bytes of it.
; =============================================================================

SimonAtk    = $0434         ; slot 0: attack flag (0 none, bit 7 = subweapon)
ObjType     = $0434         ; object type per slot
PadHeld     = $F7
SlotTmp     = $4E           ; slot argument of $DABC
SubwThrow   = $FA26         ; Up+B subweapon check (hearts, slot), C=1 accepted
AttackSetup = $9A4B         ; original: attack timer = 0, return C=1
SpawnTail   = $DABC         ; create type $17 kind A, graphic Y, in slot $4E
PlaySound   = $C1A7
SND_DAGGER  = $08
PROJ_FIRST  = $14           ; Simon's projectile slots $14-$16
PROJ_END    = $17

.bank 6

; --- hook: b6:$9A35, right after "B newly pressed and no attack running" ----
.org $9A35
.expect 8E 34 04            ; STX $0434 (attack type from the caller in X)
    JMP GunStart

; --- free space ------------------------------------------------------------
.org $BA3C
.expectfill $FF, 60
GunStart:
    LDA PadHeld
    AND #$08
    BEQ Fire                ; B without Up: shoot
    STX SimonAtk            ; Up+B: the original subweapon throw
    JSR SubwThrow
    BCC NoSubweapon
    LDA SimonAtk
    ORA #$80
    STA SimonAtk
    JMP AttackSetup         ; attack state as in the original (C=1)
NoSubweapon:
    LDA #$00                ; no subweapon (or no hearts): shoot instead of
    STA SimonAtk            ; the whip
Fire:
    LDX #PROJ_FIRST
@scan:
    LDA ObjType,X
    BEQ @free
    INX
    CPX #PROJ_END
    BCC @scan
    CLC                     ; all three slots busy: no shot, keep moving
    RTS
@free:
    STX SlotTmp
    LDA #SND_DAGGER
    JSR PlaySound
    LDY #$17                ; graphic: dagger
    LDA #$00                ; kind 0: dagger
    JSR SpawnTail
    CLC                     ; C=0: the caller does not enter the attack
    RTS
GunEnd:
.assert GunEnd - GunStart == 60, "GunStart size changed: update .expectfill"
