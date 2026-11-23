; Ghosts'n Goblins (USA) "Remix": new code in PRG bank 8 of the 256 KiB
; (UOROM) expanded image.  The fixed bank reaches it through Far8
; (src/remix/hooks.asm), which maps bank 8 at $8000 and calls Dispatch8 with
; Y = function number.
;
; Bank 8 is the only new bank used for code: the NMI handler and the sound
; routine restore banks with `STA $C000,Y`, Y = $C7.  For Y = 8 that writes
; to $C008, which holds $78 (SEI); $08 AND $78 = $08, so the write is safe
; on boards with bus conflicts.  Banks 9-14 would not be.
;
; Code here must never yield ($C336/$C313): the scheduler would run other
; tasks, which switch banks, and return into an unmapped bank.

; ---- engine RAM (notes/addresses.md) ----
CurBank     = $C7       ; current switchable bank (NMI restores it)
CurPlayer   = $BA
Pad1        = $42       ; controller 1, held buttons (A=$80 B=$40 Sel=$20 Start=$10)
PlayerPad   = $CC       ; current player's buttons during gameplay
TitleTimer  = $86       ; 16-bit title idle countdown -> attract demo
TimeUp      = $BD
FireLatch   = $85
PlayerWeapon = $C5      ; ,Y per player: held weapon (sprite id)
ObjFlags    = $04F0
ObjDir      = $05F1
ArthurAtk   = $061D
ArthurAnim  = $0631
ArthurInv   = $0647     ; Arthur: post-hit invulnerability tick counter
HeldWeapon  = $053A     ; current weapon; also the HUD icon (slot $18 sprite)
HeldAttr    = $0553     ; HUD icon palette (slot $18 attributes)
PPUQueue    = $EECF     ; queue $22 rows of $23 bytes from ($26) to PPU $25:$24
PPURows     = $22
PPUCount    = $23
PPUAddrLo   = $24
PPUAddrHi   = $25
PPUSrc      = $26

; ---- engine routines (fixed bank) ----
TestBit0    = $F2E3
ClearBit0   = $F32A
SetBit6     = $F31D     ; post-hit invulnerability (blink, no collisions)
WeaponInit  = $E0BE     ; spawn the held weapon in slot Y (preserves X, clobbers Y)
PlaySound   = $ED51     ; A = sound id; preserves X; returns to CurBank

; ---- new RAM (never written by the original game; checked in all 14
; areas.  Zero page >= $8B and $0300-$07FF survive a console reset, so the
; settings persist until power-off.  Cold boot clears them to 0 = defaults.)
EnemyEnd    = $BE       ; first weapon slot = end of the enemy range
ShotMode    = $071A
ArmorMode   = $071B
TitlePrev   = $071C     ; title: previous controller-1 state
SelPrev     = $071D     ; gameplay: previous Select state
Absorbed    = $071E     ; 4-hit armor: hits absorbed by the current armor piece
AbsorbArmor = $071F     ; 4-hit armor: no-armor bit ($20) the count belongs to

SHOT_SPREAD   = 0
SHOT_RAINBOW  = 1
SHOT_NORMAL   = 2
ARMOR_INVINCIBLE = 0
ARMOR_4HITS   = 1
ARMOR_NORMAL  = 2
TOUGH_HITS    = 4       ; the 4th hit on an armor piece goes through

WEAPON_FIRST  = $0F     ; five-way modes: weapons in $0F-$13, enemies $01-$0E
WEAPON_END    = $14
CLASSIC_FIRST = $11     ; original: weapons in $11-$13, enemies $01-$10

SND_THROW     = $11
SND_ARMOR_HIT = $1D     ; the original "armor knocked off" clank
SND_PICKUP    = $14

FN_ARTHUR = 0
FN_FIRE   = 2
FN_TITLE  = 4

.bank 8
.org $8000
.expectfill $FF, $4000          ; new bank: all $FF in the expanded image

; Y = function number (even).  Jumps through the table with the RTS trick;
; the function's RTS returns to Far8.
Dispatch8:
    LDA FarTable+1,Y
    PHA
    LDA FarTable,Y
    PHA
    RTS
FarTable:
    .word ArthurTick-1, Fire-1, TitleTick-1

; ---------------------------------------------------------------------------
; ArthurTick: replaces HitPending ($E014), which all eight Arthur state
; routines poll as `JSR $E014 / BCC ok / JMP $E171` (damage).  X = Arthur's
; slot.  Returns carry set = run the original damage routine.
; Also handles weapon cycling, since this runs every Arthur tick in every
; state.
ArthurTick:
    JSR WeaponCycle
    JSR TestBit0                ; A = flags & 1
    BEQ @ok
    LDA TimeUp
    BNE @take                   ; the timer ran out: original death
    LDA ArmorMode
    CMP #ARMOR_NORMAL
    BEQ @take
    CMP #ARMOR_4HITS
    BEQ @tough
    JSR ClearBit0               ; invincible: swallow the hit
@ok:
    CLC
    RTS
@take:
    SEC
    RTS
@tough:
    LDA ObjFlags,X
    AND #$20                    ; armor piece: $00 = armor, $20 = boxers
    CMP AbsorbArmor
    BEQ @same
    STA AbsorbArmor             ; respawned / armor picked up / armor lost
    LDA #0
    STA Absorbed
@same:
    INC Absorbed
    LDA Absorbed
    CMP #TOUGH_HITS
    BCC @absorb
    LDA #0
    STA Absorbed
    SEC                         ; this hit goes through (armor off / death)
    RTS
@absorb:
    JSR ClearBit0
    JSR SetBit6                 ; the engine's own post-hit invulnerability:
    LDA #0                      ; ~1.5 s of blinking with no collisions,
    STA ArthurInv,X             ; but no knockback and no armor loss
    LDA #SND_ARMOR_HIT
    JSR PlaySound
    CLC
    RTS

; Select (new press) cycles lance -> dagger -> torch -> axe -> cross.
; Off in the NORMAL shot mode, so NORMAL + NORMAL is the original game.
WeaponCycle:
    LDA ShotMode
    CMP #SHOT_NORMAL
    BEQ @done
    LDA PlayerPad
    AND #$20
    CMP SelPrev
    BEQ @done
    STA SelPrev
    CMP #0
    BEQ @done                   ; released
    LDY #4
@find:
    LDA WeaponIds,Y
    CMP HeldWeapon
    BEQ @next
    DEY
    BPL @find                   ; not found: Y = $FF -> lance
@next:
    INY
    CPY #5
    BCC @set
    LDY #0
@set:
    LDA WeaponAttr,Y
    STA HeldAttr
    LDA WeaponIds,Y
    STA HeldWeapon
    LDY CurPlayer
    STA a:PlayerWeapon,Y        ; what a pickup writes (bank 4 $BA63-$BA71)
    LDA #SND_PICKUP
    JSR PlaySound
@done:
    RTS

;               lance dagger torch axe  cross
WeaponIds:  .byte $40,  $42,   $44,  $36, $46
WeaponAttr: .byte $00,  $00,   $02,  $01, $00      ; HUD icon palettes ($D1EE)

; ---------------------------------------------------------------------------
; Fire: replaces the slot search at $E045 (reached when B was pressed and the
; fire latch $85 is clear).  X = Arthur's slot.  Sets $85 itself:
; $FF = shot fired (wait for release), 0 = nothing fired.
Fire:
    LDA ShotMode
    CMP #SHOT_NORMAL
    BNE @multi
    ; ---- original single shot, byte-for-byte the logic of $E045-$E073 ----
    LDY #CLASSIC_FIRST
@c_find:
    LDA ObjFlags,Y
    BEQ @c_found
    INY
    CPY #$13
    BCC @c_find
    CPY #$14
    BCS @none
    LDA HeldWeapon
    CMP #$42                    ; the dagger may also use slot $13
    BEQ @c_find
    BNE @none
@c_found:
    LDA ArthurAtk,X
    ORA #$02
    STA ArthurAtk,X
    LDA #0
    STA ArthurAnim,X
    JSR WeaponInit
    JMP @fired
@none:
    LDA #0
    STA FireLatch
    RTS
    ; ---- five-way fan: slots $0F-$13, all free or no shot ----
@multi:
    LDY #WEAPON_FIRST
@m_check:
    LDA ObjFlags,Y
    BNE @none
    INY
    CPY #WEAPON_END
    BCC @m_check
    STA ArthurAnim,X            ; A = 0
    LDA ArthurAtk,X
    ORA #$02
    STA ArthurAtk,X
    LDA HeldWeapon
    PHA
@spawn:
    DEY                         ; $13 down to $0F
    LDA ShotMode
    BEQ @keep                   ; SHOT_SPREAD: five of the held weapon
    LDA RainbowIds-WEAPON_FIRST,Y
    STA HeldWeapon              ; SHOT_RAINBOW: one of each
@keep:
    TYA
    PHA
    JSR WeaponInit              ; dir = 4 (right) or $0C (left)
@spawned:
    PLA
    TAY
    CLC
    ADC ObjDir,Y
    ADC #[$100 - $11]           ; dir = facing + (slot - $11): -2..+2 steps
    STA ObjDir,Y                ; of 22.5 degrees
    CPY #WEAPON_FIRST
    BNE @spawn
    PLA
    STA HeldWeapon              ; restore (WeaponInit read it per slot)
@fired:
    LDA #$FF
    STA FireLatch
    RTS

;                slot $0F $10  $11  $12  $13
RainbowIds: .byte    $40, $42, $44, $36, $46

; ---------------------------------------------------------------------------
; TitleTick: runs once per frame in the title-screen loop (hooked at $C4CE,
; before the loop yields).  A = cycle the shot mode, B = cycle the armor mode
; (new presses on controller 1).  Draws the two menu lines below
; "2 PLAYERS" when the title appears and whenever a setting changes.
; Also sets the slot partition for the coming game.
TitleTick:
    TXA
    PHA
    LDY #0                      ; Y: 0 = nothing, 1 = draw, 2 = changed
    LDA TitleTimer+1            ; first frame of this title screen?
    CMP #$01                    ; ($C424 sets the timer to $01C2)
    BNE @buttons
    LDA TitleTimer
    CMP #$C2
    BNE @buttons
    INY
@buttons:
    LDA Pad1
    TAX
    EOR TitlePrev
    STX TitlePrev
    AND Pad1                    ; new presses
    ASL A                       ; A button -> carry
    BCC @no_a
    INC ShotMode
    LDY #2
@no_a:
    ASL A                       ; B button -> carry
    BCC @no_b
    INC ArmorMode
    LDY #2
@no_b:
    ; keep both settings in range (also repairs stray values)
    LDA ShotMode
    CMP #3
    BCC @shot_ok
    LDA #0
    STA ShotMode
@shot_ok:
    LDA ArmorMode
    CMP #3
    BCC @armor_ok
    LDA #0
    STA ArmorMode
@armor_ok:
    LDX ShotMode
    LDA EnemyEndTab,X
    STA EnemyEnd
    TYA
    BEQ @done
    CPY #2
    BCC @draw                   ; first frame only: no sound, no timer reset
    LDA #$C2                    ; a setting changed: restart the idle timer
    STA TitleTimer              ; so the attract demo does not cut in
    LDA #$01
    STA TitleTimer+1
    LDA #SND_THROW
    JSR PlaySound
@draw:
    LDA ShotMode
    LDY #<ROW1
    LDX #>ROW1
    JSR DrawLine
    LDA ArmorMode
    CLC
    ADC #3
    LDY #<ROW2
    LDX #>ROW2
    JSR DrawLine
@done:
    PLA
    TAX
    RTS

; Queue menu line A (0-5) at PPU address X:Y.
DrawLine:
    STY PPUAddrLo
    STX PPUAddrHi
    TAY
    LDA LinePtrLo,Y
    STA PPUSrc
    LDA LinePtrHi,Y
    STA PPUSrc+1
    LDA #LINE_LEN
    STA PPUCount
    LDA #1
    STA PPURows
    JMP PPUQueue                ; NMI copies it during the next vblank

EnemyEndTab: .byte WEAPON_FIRST, WEAPON_FIRST, CLASSIC_FIRST

LINE_LEN = 22
ROW1 = $2000 + 23 * 32 + 5      ; nametable row 23, column 5
ROW2 = $2000 + 24 * 32 + 5

; Title font in CHR: 0-9 = $00-$09, A-Z = $0A-$23, blank = $FF.
.textmap "0", $00, 10
.textmap "A", $0A, 26
.textmap " ", $FF, 1
Line0: .text "A SHOT   5 WAY SPREAD "
Line1: .text "A SHOT   RAINBOW      "
Line2: .text "A SHOT   NORMAL       "
Line3: .text "B ARMOR  INVINCIBLE   "
Line4: .text "B ARMOR  4 HITS EACH  "
Line5: .text "B ARMOR  NORMAL       "
LinePtrLo: .byte <Line0, <Line1, <Line2, <Line3, <Line4, <Line5
LinePtrHi: .byte >Line0, >Line1, >Line2, >Line3, >Line4, >Line5
Bank8End:
.assert Line1 - Line0 == LINE_LEN, "menu lines must be LINE_LEN characters"
.assert Bank8End <= $C000, "bank 8 overflow"
