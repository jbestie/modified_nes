; =============================================================================
; Castlevania (USA, Rev 1 / V1.1): Super C commando (mechanics)
; PRG CRC32 B668C7FC, mapper 2 (UNROM). Milestones M1-M3 of docs/commando-estimate.md.
;
; What changes (addresses: notes/addresses.md):
;   * Run-and-gun: B fires at once while standing, walking, jumping, falling,
;     crouching or on stairs. No attack state, no whip, no subweapons.
;   * Super C's weapons, from the subweapon pickups: dagger = M (auto-fire),
;     cross = S (5-way spread), holy water = L (laser train), axe = F (fire ball
;     that bursts; hold B to charge). Whip upgrade = R (faster bullets), potion and
;     stopwatch = B (Super C's barrier: 510 frames of invincibility, enemies
;     that touch the commando die, bosses don't). A new weapon clears R; death
;     clears both.
;   * Aiming with Super C's rules: on the ground Up aims straight up, Up or Down
;     while walking aims diagonally; in the air Up/Down aim up/down, with
;     Left/Right diagonally; on stairs Up/Down aim along the steps.
;   * Prone: Down alone; smaller contact box. Down + Left/Right walks instead.
;   * Stairs: Up/Down next to a staircase climbs only after 16 frames without B,
;     so shooting up (or prone) beside stairs doesn't step onto them.
;   * Air control: Left/Right in a jump turns or starts the horizontal motion.
;   * Poses: aim up, diagonal runs, stand and prone firing, somersault (PoseMap).
;   * Bullets run in their own pass in the NMI's sprite-0 wait (bank 5); they
;     break the whip-only wall blocks and don't freeze bosses.
;   * No knockback: a hit costs health and gives the usual invincibility, nothing
;     else, also on stairs. At zero health Simon dies where he is.
;   * The whip-upgrade pickup no longer freezes the game for 24 frames.
;   * No attract demos (they replay recorded input and desync with these rules).
;
; Graphics stay Simon's: bullets show the dagger's metasprite (BulletFrames,
; LaserFrames) and PoseMap holds Simon's own frames. The art installer
; (tools/commando_art.py) rewrites BulletFrames and LaserFrames (bank 5), PoseMap
; and BackTiles (bank 6) when it imports the commando from the user's own Super C
; dump. The intro uploads BackTiles to table-0 pairs $E0-$EA (IntroTiles).
;
; Space: bank 5 free space from $9E49; bank 6 from $BA3C; bank 7 $FF2A-$FF5C and
; $FFF0-$FFF9. Code in banks 5 and 6 calls only its own bank or bank 7.
; RAM: $01B4-$01D4 and $0100-$012F, never written in the 50,000-frame explore session.
; =============================================================================

; ---- RAM
Health      = $45
Invinc      = $5B           ; invincibility timer, -1 every 2nd frame
Hearts      = $71
Multiplier  = $64           ; 0-2: subweapon slots $14..$14+$64
Floor       = $46
Stage       = $28
Quest       = $2B
GameState   = $18
SubState    = $19
PauseFlag   = $22
ItemFreeze  = $7E
PotionPickup = $E7D6       ; the potion branch of the item pickup $E762
CurBank     = $27           ; last bank selected through $C1D6
FrameCount  = $1A
ScrollX     = $2E
ScrollPage  = $2F
SlotArg     = $4E           ; slot argument of SpawnTail
PadNew      = $F5
PadHeld     = $F7
ObjFrame    = $031C
ObjY        = $0354
ObjX        = $038C
ObjType     = $0434         ; slot 0: Simon's attack flag
ObjFacing   = $0450
ObjState    = $046C         ; slot 0: Simon's movement state
ObjAnim     = $0488         ; animation timer; bit 7 = stopped
ObjKind     = $0584
ObjXSpeed   = $03FC         ; 8.8, along the facing
ObjXSpeedLo = $0418
ObjYSpeed   = $03C4
ObjYSpeedLo = $03E0
ObjYDir     = $04DC         ; 0 down, 1 up ($EC7A)
ObjXLo      = $03A8
ObjYLo      = $0370
ObjHidden   = $0300
SimonFlags  = $0584         ; slot 0: input copy; bits 0-1 = the jump's direction
SimonAtk    = $0434
SimonState  = $046C
BlocksBroken = $0146
Subweapon   = $015B
SubwLock    = $015C         ; set while the stopwatch runs
LastHitKind = $01B4         ; new: kind of the last projectile hit
BulletSlot  = $01B5         ; new: slot under test in BlockTick
FireAnim    = $01B6         ; new: frames left of the firing pose
AimCode     = $01B7         ; new: aim code of the shot being spawned (also scratch)
PassSlot    = $01B8         ; new: bullet under BulletPass
PassX       = $01B9         ; new: its position
PassY       = $01BA
PassIdx     = $01BB         ; new: index into BulletSlots
HitQN       = $01BC         ; new: hits found before the split, applied in the object loop
HitQSlot    = $01BD         ; 4 entries: target slot
HitQType    = $01C1         ; 4 entries: its type when hit (the slot may change before the hit is applied)
HitQBullet  = $01C5         ; 4 entries: the bullet's slot ($0F for the hit chain)
PassTmp     = $01C9         ; new: scratch
TgtN        = $01CA         ; new: entries in the target list
TgtSlot     = $0100         ; target list (never used by the game: $C18E clears $0130-$01B0)
TgtHW       = $0110         ;   half-width + the bullet's
TgtHH       = $0120         ;   half-height + the bullet's
HitQDmg     = $010C         ; 4 entries: damage (in the unused tail of TgtSlot: MAX_TARGETS = 12)
FireTimer   = $011C         ; M: frames to the next auto-fire shot
Charge      = $011D         ; F: frames B has been held
WeaponIdx   = $011E         ; W_* of the current weapon
ShotAngle   = $011F         ; aimed angle (11.25-degree steps, relative to the facing; - = up)
ShotLevel   = $012C         ; speed table: 0 = 4.0, 1 = 5.5, 2 = 7.0 px/frame
ShotKind    = $012D         ; K_* of the bullet being made
ShotCount   = $012E         ; scratch while spawning several bullets
ShotTmp     = $012F
VelAng      = $01CB         ; SetVelocity scratch
VelBase     = $01CC
VelD        = $01CD
BurstMemo   = $01CE         ; Burst: the target hit (+1), position, angle, count
BurstX      = $01CF
BurstY      = $01D0
BurstAng    = $01D1
BurstN      = $01D2
BarrierOn   = $01D3         ; B's barrier: non-zero while the potion's invincibility runs
StairHold   = $01D4         ; frames Up/Down has been held on the ground without B
ObjTimer    = $0568         ; per slot: laser launch delay, fragment lifetime
ObjMemo     = $04F8         ; per slot: the target a fragment must not hit (+1)
WhipLevel   = $70           ; R: non-zero (the whip-upgrade pickup increments it; death clears it)

; ---- original routines
StageCheck  = $99F0         ; the call FireTick replaces
JumpCamera  = $9479         ; the call AirSteer replaces
AttackSetup = $9A4B         ; attack timer = 0, return C=1 (enter the attack state)
DeathStart  = $A1E5
BlockWhip   = $A825         ; debris update + whip-vs-block check
BoxTest     = $A048         ; block ($00 Y, $01 X, $02 page; half $10/$12) vs X/$03, Y (half $11/$13); C=0 hit
BreakBlock  = $A8D8         ; the rest of $A825 after a hit ($00-$02, $4C, $4F, $0E/$0F set)
PlaySound   = $C1A7
SpawnTail   = $DABC         ; type $17 in slot $4E: kind A, frame Y, at Simon's X and sprite Y - 8
SubwThrow   = $FA26         ; subweapon check and spawn; C=1 = enter the attack state
ObjLoop     = $E922         ; the stock object loop (slots $16..$03)
HudTick     = $A08A         ; called before the sprite-0 wait when the frame isn't a lag frame
SetBank     = $C1D6         ; Y = bank (bus-conflict safe, keeps $27)
HomeBank    = $C1D4         ; back to bank $24 (6)
OnHit       = $E562         ; hit SFX, spark, then the target's on-hit handler (X = target)
HalfSizes   = $E46A         ; per type: half-width, half-height
CamDXHi     = $52           ; camera motion this frame (8.8), added to every object's X ($EACB)
CamDXLo     = $53
BlockLists  = $FC71         ; per stage: pointer to the wall-block list (bank 6)
ScreenOff   = $C132         ; PPUCTRL = PPUMASK = 0 (NMI and rendering off)
PpuCopy     = $FD7E         ; ($00) -> PPU ($03:$02), $04:$05 bytes (hi:lo)
LoadTileSet = $FD23         ; A = tile set: its uploads, then NMI on

; ---- tuning
PROJ_FIRST  = $14           ; Simon's projectile slots $14-$16
PROJ_LAST   = $16
FIRE_ANIM   = 8             ; frames of the firing pose
SND_SHOT    = $02           ; an unused 9-frame noise effect
DAGGER_GRAPHIC = $17        ; graphic ID of the dagger (animation entry: frame $50, static)
BULLET_FRAME = $50          ; the dagger's metasprite
BULLET_HALF_W = 4
BULLET_HALF_H = 8
TYPE_PROJ   = $17
TYPE_ERASE  = $32
BULLET_TYPE = $97           ; bit 7: the stock object loop skips the slot (BulletPass runs it)
; weapons (WeaponIdx) and bullet kinds (ObjKind; >= 6, so the stock collision skips them)
W_RIFLE     = 0
W_MG        = 1
W_SPREAD    = 2
W_LASER     = 3
W_FIRE      = 4
K_RIFLE     = $10
K_MG        = $11
K_SPREAD    = $12
K_LASER     = $13
K_FIRE      = $14
K_FIRE_CH   = $15
K_FRAG      = $16
MG_PERIOD   = 7             ; Super C: auto-fire every 7 frames
CHARGE_FULL = 32
FRAG_LIFE   = 10            ; Super C: fragments fly 10 frames
LASER_SEGS  = 5
BULLET_HW   = 8             ; hit box added to the target's half-sizes (the dagger's)
BULLET_HH   = 6
STAIR_HOLD  = 16            ; frames Up/Down must be held without B to step onto stairs (more than
                            ; the gap between rifle shots, so tapping B while aiming up never climbs)
BACK_PPU    = $0E00         ; the back view's tiles: table-0 pairs $E0-$EA
BACK_LEN    = 6 * 32
TARGET_FIRST = $04          ; enemies $04-$0D, candles $0E-$13
TARGET_LAST = $13
MAX_TARGETS = 12            ; caps the pre-split work
HIT_QUEUE   = 4

; aim codes (tables at AimDX...)
AIM_FWD       = 0
AIM_UP        = 1
AIM_DIAG_UP   = 2
AIM_CROUCH    = 3
AIM_STAIRS    = 4
AIM_AIR_FWD   = 5
AIM_AIR_UP    = 6           ; +1 = diagonal up
AIM_AIR_DOWN  = 8           ; +1 = diagonal down
AIM_DIAG_DOWN = 10          ; walking with Down + Left/Right, or Down on stairs
; aim class by Simon's state (AimClass)
AC_GROUND   = 0
AC_AIR      = 1
AC_STAIRS   = 2             ; forward; Up/Down = along the steps
AC_FIXED    = $10           ; + a fixed aim code
AC_CROUCH   = AC_FIXED + AIM_CROUCH
AC_STAIR_WALK = AC_FIXED + AIM_STAIRS
AC_NONE     = $80
; PoseMap indices
POSE_UP     = 0
POSE_UP_FIRE = 1
POSE_DIAG_UP = 2            ; 2-4: walk frames 2-4 (and stair steps) aiming diagonally up
POSE_SPIN   = 5
POSE_FIRE   = 9
POSE_DIAG_DOWN = 10         ; 10-12: the same aiming diagonally down
POSE_PRONE  = 13
POSE_PRONE_FIRE = 14
PRONE_HALF_H = $04          ; contact half-height while prone (crouching: $0A)

; =============================================================================
.bank 6

; ---- Simon's update, before the state dispatch: the fire check runs every frame
.org $9363
.expect 20 F0 99            ; JSR $99F0
    JSR FireTick

; ---- attack start: Select instead of B, and only the subweapon throw
.org $9A32
.expect 40                  ; AND #$40 (B newly pressed)
    .byte $20               ; Select
.org $9A35
.expect 8E 34 04            ; STX $0434 (attack type in X)
    JMP AtkStart

; ---- jump state: air control
.org $948E
.expect 20 79 94            ; JSR $9479
    JSR AirSteer

; ---- Simon's frame store: aiming, firing, prone and somersault poses
.org $9BE3
.expect 8E 1C 03            ; STX $031C
    JSR PoseHook

; ---- stand/walk: Down crouches only without Left/Right (else walk aiming down)
.org $944A
.expect A5 F7 29 04 F0 08   ; LDA $F7 / AND #$04 / BEQ $9458
    JSR DownOnly
    BNE $9458
    NOP

; ---- crouch (also the landing crouch): Left/Right stands up and walks
.org $9561
.expect A5 F7 29 04 F0 11   ; LDA $F7 / AND #$04 / BEQ $9578
    JSR DownOnly
    BNE $9578
    NOP

; ---- hit reaction: no knockback, no stairs stun. It runs before the damage is
; subtracted ($FC97, then $E754), so the death check is in FireTick.
.org $96C1
.expect AD 6C 04 C9 04
HitReact:
    LDA #$30                ; the post-hit invincibility of the original
    STA Invinc
    RTS

; ---- wall blocks: the item behind a block, index 4 = double shot -> R (b6:$AA4F)
.org $AA53
.expect 0C
    .byte $03

; ---- title: the timer that starts the attract demo never runs out
.org $B83E
.expect C6 1E               ; DEC $1E (then BNE: keep waiting)
    LDA #$01

; ---- intro setup: the back view's tiles before the intro's tile set
.org $B928
.expect 20 23 FD            ; JSR $FD23 (A = 1)
    JSR IntroTiles

; ---- stand/walk: Up/Down next to a staircase ($9C10) only after StairGate
.org $93E9
.expect A5 F7 29 0C         ; LDA $F7 / AND #$0C (then BEQ: no stairs check)
    JSR StairGate
    NOP

; ---- free space
.org $BA3C
.expectfill $FF, $5C4       ; $BA3C-$BFFF

; FireTick: the death check that knockback used to make: health zero or
; negative (the damage can underflow) kills in any state, as the stand handler
; b6:$9380 does. Also counts down the firing pose. (Shooting is in bank 5.)
FireTick:
    JSR StageCheck
    LDA Invinc              ; B's barrier ends with its invincibility
    BNE @inv
    STA BarrierOn
@inv:
    LDA SimonState
    CMP #$08
    BEQ @done               ; already dead
    LDA Health
    BEQ @dead
    BPL @alive
@dead:
    PLA                     ; leave Simon's update like the stand handler does
    PLA
    JMP DeathStart
@alive:
    LDA FireAnim
    BEQ @done
    DEC FireAnim
@done:
    RTS

; AtkStart: from b6:$9A35 (Select newly pressed, b6:$9A32). No subweapons:
; never enter the attack state.
AtkStart:
    CLC
    RTS

; PoseHook: from b6:$9BE3 in place of STX $031C (X = Simon's frame; 0 = the
; blink's empty frame). Swaps in the aiming, firing, prone and somersault poses
; from PoseMap. Mechanics build: Simon's own frames; tools/commando_art.py
; writes the commando's.
PoseHook:
    LDA GameState
    CMP #$05
    BEQ @live
@out:
    STX ObjFrame
    RTS
@live:
    TXA
    BEQ @out
    LDA SimonState
    BEQ @ground
    CMP #$01
    BEQ @jump
    CMP #$03
    BEQ @prone
    CMP #$09
    BEQ @prone
    CMP #$04
    BNE @out
    LDA #POSE_DIAG_UP       ; stairs: frames $02 and $0D-$0F -> diagonal poses
    CPX #$02
    BEQ @diag
    CPX #$0D
    BCC @out
    CPX #$10
    BCS @out
    TXA
    SEC
    SBC #$0D - POSE_DIAG_UP
    JMP @diag
@jump:
    CPX #$01                ; stand or kneel frame -> somersault
    BEQ @spin
    CPX #$05
    BNE @store
@spin:
    LDA FrameCount
    LSR A
    LSR A
    AND #$03
    CLC
    ADC #POSE_SPIN
    TAY
    LDX PoseMap,Y
    JMP @store
@prone:
    CPX #$05
    BNE @store
    LDY #POSE_PRONE
    LDA FireAnim
    BEQ @pick
    INY                     ; POSE_PRONE_FIRE
    BNE @pick
@ground:
    CPX #$01
    BNE @walk
    LDA PadHeld             ; standing
    AND #$08
    BEQ @standfire
    LDY #POSE_UP
    LDA FireAnim
    BEQ @pick
    INY                     ; POSE_UP_FIRE
    BNE @pick
@standfire:
    LDA FireAnim
    BEQ @store
    LDX PoseMap + POSE_FIRE
    JMP @store
@walk:
    CPX #$02
    BCC @store
    CPX #$05
    BCS @store
    TXA                     ; walk frames 2-4 -> POSE_DIAG_UP + 0-2
@diag:
    TAY                     ; Y = POSE_DIAG_UP + step
    LDA PadHeld
    AND #$0C
    BEQ @store
    AND #$08
    BNE @pick
    TYA
    CLC
    ADC #POSE_DIAG_DOWN - POSE_DIAG_UP
    TAY
@pick:
    LDX PoseMap,Y
@store:
    STX ObjFrame
    RTS

; aim up, aim up firing, diagonal up x3, somersault x4, stand firing,
; diagonal down x3, prone, prone firing
PoseMap:
    .byte $01, $01, $02, $03, $04, $05, $05, $05, $05, $01, $02, $03, $04, $05, $05
PoseMapEnd:
.assert PoseMapEnd - PoseMap == 15, "PoseMap size is fixed (tools/commando_art.py)"

; DownOnly: Z=1 when Down is held without Left/Right (Castlevania's crouch).
; Down + Left/Right walks instead (Super C's run aiming diagonally down).
DownOnly:
    LDA PadHeld
    AND #$07
    CMP #$04
    RTS

; AirSteer: from b6:$948E in place of JSR $9479 (the jump state, every frame).
; Super C's air control: Left/Right in the air sets the jump's direction bits in
; $0584 (read by the horizontal mover $9809) and the facing; with neither held
; the jump keeps its direction.
AirSteer:
    JSR JumpCamera
    LDA PadHeld
    AND #$03
    BEQ @keep
    STA AimCode             ; scratch
    LDA SimonFlags
    AND #$FC
    ORA AimCode
    STA SimonFlags
    LDA AimCode
    LSR A                   ; Right (1) -> 0, Left (2) -> 1
    STA ObjFacing
@keep:
    RTS

; BlockTick: from $CEED (gameplay frame, bank 6 mapped) in place of JSR $A825.
; Every 2nd frame each live projectile is tested against the stage's wall
; blocks (a bullet at 4 px/frame stays over a 16-px block for 5 frames).
BlockTick:
    JSR BlockWhip
    LDA FrameCount
    AND #$01
    BNE @done
    LDX #PROJ_FIRST
@loop:
    LDA ObjType,X
    CMP #BULLET_TYPE
    BEQ @test
    CMP #TYPE_PROJ
    BNE @next
    LDA ObjKind,X
    CMP #$06                ; kinds 6+ are effects (potion, stopwatch)
    BCS @next
@test:
    STX BulletSlot
    JSR BulletVsBlocks
    LDX BulletSlot
@next:
    INX
    CPX #$1C                ; bullets also use $1A/$1B
    BCC @loop
@done:
    RTS

; The block scan of b6:$A837-$A8CF with the projectile's box instead of the
; whip's. On a hit it continues in the original break sequence.
BulletVsBlocks:
    LDA Stage
    ASL A
    TAY
    LDA BlockLists,Y
    STA $0E
    LDA BlockLists + 1,Y
    STA $0F
    LDA #$00
    STA $4F
@entry:
    LDY $4F
    LDA ($0E),Y
    BEQ @done
    LDX $4F
    LDA #$01                ; bit of this block in $0146
@mask:
    DEX
    DEX
    BMI @gotmask
    ASL A
    BNE @mask
@gotmask:
    STA $4C
    AND BlocksBroken
    BNE @skip
    LDA ($0E),Y             ; byte 0: Y, floor (bit 3), item
    LSR A
    LSR A
    LSR A
    AND #$01
    CMP Floor
    BNE @skip
    LDA ($0E),Y
    AND #$F0
    CLC
    ADC #$08
    STA $00                 ; block centre Y
    INY
    LDA Quest
    BNE @q2
    LDA ($0E),Y
    AND #$08
    BNE @done               ; second-quest-only block: the original scan stops here too
@q2:
    LDA ($0E),Y             ; byte 1: X, page
    AND #$F0
    CLC
    ADC #$08
    STA $01
    LDA ($0E),Y
    AND #$07
    STA $02
    LDA #$08
    STA $10
    STA $12
    LDA #BULLET_HALF_H
    STA $11
    LDA #BULLET_HALF_W
    STA $13
    LDX BulletSlot
    LDA ObjY,X
    TAY
    LDA ObjX,X              ; level X = screen X + scroll
    CLC
    ADC ScrollX
    PHA
    LDA #$00
    ADC ScrollPage
    STA $03
    PLA
    TAX
    JSR BoxTest
    BCC @hit
@skip:
    INC $4F
    INC $4F
    JMP @entry
@done:
    RTS
@hit:
    LDX BulletSlot
    LDA ObjType,X
    CMP #BULLET_TYPE
    BNE @subw
    JSR EraseBullet         ; a bullet is used up
    JMP BreakBlock
@subw:
    LDA ObjKind,X
    BNE @break              ; cross, axe and holy water keep going
    LDA #TYPE_ERASE         ; a thrown dagger is used up, as on an enemy
    STA ObjType,X
@break:
    JMP BreakBlock

; StairGate: from the stand handler. A = Up/Down of the pad once they have been
; held STAIR_HOLD frames with no B, else 0 (Z set): no stairs this frame.
StairGate:
    LDA PadHeld
    AND #$0C
    BEQ @reset
    LDA PadHeld
    AND #$40                ; B held: aiming up or firing prone, stay on the floor
    BNE @reset
    LDA StairHold
    CMP #STAIR_HOLD
    BCS @go
    INC StairHold
    LDA #$00
    RTS
@go:
    LDA PadHeld
    AND #$0C
    RTS
@reset:
    LDA #$00
    STA StairHold
    RTS

; IntroTiles: from the intro's setup, A = 1 (its tile set). First the back
; view's tiles (BackTiles, filled by tools/commando_art.py) go to table-0 pairs
; $E0-$EA, which no tile set writes before block 4 and nothing draws before
; then; the art installer points the intro's back-view frame at them.
IntroTiles:
    JSR ScreenOff
    LDA $2002
    LDA #<BackTiles
    STA $00
    LDA #>BackTiles
    STA $01
    LDA #<BACK_PPU
    STA $02
    LDA #>BACK_PPU
    STA $03
    LDA #>BACK_LEN
    STA $04
    LDA #<BACK_LEN
    STA $05
    JSR PpuCopy
    LDA #$01
    JMP LoadTileSet
BackTiles:                  ; 6 tile pairs, rewritten by tools/commando_art.py
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
BackTilesEnd:
.assert BackTilesEnd - BackTiles == BACK_LEN, "BackTiles size is fixed (tools/commando_art.py)"


FreeEnd6:
.assert FreeEnd6 <= $C000, "bank 6 free space overflow"

; =============================================================================
.bank 7

; ---- gameplay frame: the wall-block check also tests projectiles
.org $CEED
.expect 20 25 A8            ; JSR $A825
    JSR BlockTick

; ---- projectile hit: remember the kind (the flags stay those of the LDA)
.org $E65F
.expect B9 84 05            ; LDA $0584,Y
    JSR SetKind

; ---- the freezes on a hit: multi-hit enemies (16 frames), bosses (8 frames)
.org $E1BF
.expect A9 10 9D 68 05
    LDA #$10
    JMP Stun

.org $E2A9
.expect A9 08 9D 68 05
    LDA #$08
    JMP Stun

; ---- object loop: then the queued bullet hits (bank 5)
.org $E912
.expect 4C 22 E9            ; JMP $E922
    JMP ObjTramp

; ---- item graphics $EC0A: the stopwatch (F) is drawn as the potion (both give B)
.org $EC19
.expect 46
    .byte $45

; ---- item pickup, subweapon branch: the stopwatch is B too; a weapon clears R
.org $E7AF
.expect A9 00 85 79         ; LDA #0 / STA $79
    JSR WeaponPickup
    NOP

; ---- B: the potion pickup (also the stopwatch's) starts Super C's barrier
.org $E7E4
.expect A9 B4 85 5B         ; LDA #$B4 / STA $5B (bank 5 mapped by $E7DF)
    JSR BarrierStart
    NOP

; ---- contact with an enemy ($E6BA, X = the enemy; bank 5 mapped, as in the
; whole object loop): invincibility skips it, except under the barrier
.org $E6D2
.expect A5 5B F0 01         ; LDA $5B / BEQ $E6D7 / ($E6D6: RTS)
    JMP BarrierGate
.org $E718
.expect BD 34 04            ; LDA $0434,X: the contact hurts the commando
    JMP BarrierHit

; ---- before the sprite-0 wait: the bullet pass
.org $F8C4
.expect 20 8A A0            ; JSR $A08A
    JSR PrePass

; ---- prone: contact half-height while crouching (LDA #$0A at $E458)
.org $E459
.expect 0A
    .byte PRONE_HALF_H

; ---- whip-upgrade pickup: LDA #$18 / STA $7E (pickup freeze) -> LDA #$00
.org $E899
.expect 18
    .byte $00

.org $FF2A
.expectfill $FF, 22         ; $FF2A-$FF3F
; Stun: A = freeze frames, X = the object hit. Kind-0 hits don't freeze.
Stun:
    PHA
    LDA LastHitKind
    BEQ @skip
    PLA
    STA $0568,X
    LDA $0488,X
    ORA #$80
    STA $0488,X
    RTS
@skip:
    PLA
    RTS
StunEnd:
.assert StunEnd <= $FF40, "Stun overflows the $FF run"

.org $FF40
.expect 55 AB D5 AA 5A 4B 95 4A 55 A9 54 D5   ; leftover filler (notes/addresses.md section 14)
; ObjTramp: the object loop, then the queued bullet hits (bank 5, which every
; caller of $E8F0 maps since the handlers below $C000 are there), except in the
; ending (b6:$8693): there bullets can't exist, so the plain loop runs.
ObjTramp:
    LDA CurBank
    CMP #$05
    BNE @plain
    JMP BulletEntry
@plain:
    JMP ObjLoop
ObjTrampEnd:
.assert ObjTrampEnd <= $FF4C, "ObjTramp overflows its .expect"

.org $FF4C
.expect D6 AA A4 35 4B 89 52 55 D9 5B 5F 57 75 2A 49 42 92   ; leftover filler
; EraseBullet: X = slot. As the stock erase $EC60 (type, frame, Y off screen),
; plus state 0 for the treasure allocator. In the fixed bank: called from
; bank 6 (BlockTick) and bank 5 (BulletPass).
EraseBullet:
    LDA #$00
    STA ObjType,X
    STA ObjState,X
    STA ObjFrame,X
    LDA #$F4
    STA ObjY,X
    RTS
EraseBulletEnd:
.assert EraseBulletEnd <= $FF5D, "EraseBullet overflows its .expect"

.org $FF5D
.expect 22 4D D5 76 DB D7 2A A5 24 92 28 52 A9 7F DF DB 6D 4F 89 20 24 82 88 D2 7B 77 AD AA 54 8A 41 48 FF 7F 57 7B 5F 12 02 92
; PrePass: from $F8C4, which runs only when the frame isn't a lag frame ($1B = 0),
; just before the NMI busy-waits 4,257-5,559 cycles for sprite 0. The bullet
; pass runs in that wait, so it costs the game logic nothing; it is capped
; (MAX_TARGETS, 4 bullets) to finish well before the split.
PrePass:
    JSR HudTick
    LDA #$00
    STA HitQN
    LDA GameState
    CMP #$05
    BNE @rts
    LDA SubState
    CMP #$06
    BNE @rts
    LDA ItemFreeze
    ORA PauseFlag
    BNE @rts
    LDY #$05
    JSR SetBank
    JSR BulletPass
    JSR HomeBank
@rts:
    RTS
PrePassEnd:
.assert PrePassEnd <= $FF85, "PrePass overflows its .expect"

.org $FF85
.expect 22 02 6A 7B 57 AA 6A A5 48 10 FF FF 77 73 7F 45 20 40 89 08 2A
; WeaponPickup: from $E7AF (items 2, 7, 8, 9, B, D, F; X = the item). The
; stopwatch (F) takes the potion's branch (B); the others become the weapon,
; and Super C's rule applies: a new weapon ends R. Returns A = 0 for $E7B3.
WeaponPickup:
    LDA ObjKind,X
    AND #$0F
    CMP #$0F
    BNE @weapon
    PLA
    PLA
    JMP PotionPickup
@weapon:
    LDA #$00
    STA WhipLevel
    STA $79
    RTS
WeaponPickupEnd:
.assert WeaponPickupEnd <= $FF9A, "WeaponPickup overflows its .expect"

.org $FFF0
.expectfill $FF, 10         ; $FFF0-$FFF9
SetKind:
    LDA ObjKind,Y
    STA LastHitKind
    RTS
SetKindEnd:
.assert SetKindEnd <= $FFFA, "SetKind runs into the vectors"

; =============================================================================
.bank 5

.org $9E49
.expectfill $FF, $C000 - $9E49
; BulletEntry: from ObjTramp in place of the stock object loop. The loop skips
; bullets (type $97, bit 7 set); BulletPass moved them before the split. Here
; the hits it found go through the stock hit chain, as $E5EB does for a dagger,
; if the target is still the object that was hit. Then the weapons fire.
BulletEntry:
    JSR ObjLoop
    LDY HitQN
    CPY #HIT_QUEUE + 1
    BCS @clear              ; RAM garbage at power-on
@q:
    DEY
    BMI @clear
    STY PassIdx
    LDX HitQSlot,Y
    LDA ObjType,X
    CMP HitQType,Y
    BNE @skip
    STX $4E
    LDA HitQBullet,Y
    STA $0F
    LDA HitQDmg,Y
    STA $0D
    LDA #$00
    STA $0C
    STA $0E                 ; weapon code 0: dagger
    STA LastHitKind         ; no freeze
    JSR OnHit
@skip:
    LDY PassIdx
    JMP @q
@clear:
    LDA #$00
    STA HitQN
    JMP WeaponTick

; =============================================================================
; Weapons. WeaponTick runs once per object loop (after the hits), in stage play.

WeaponTick:
    LDA GameState
    CMP #$05
    BNE @rts
    LDA SubState
    CMP #$06
    BNE @rts
    LDA FireTimer
    BEQ @w
    DEC FireTimer
@w:
    LDA Subweapon           ; the weapon is the subweapon id of the pickup
    LDX #W_MG
    CMP #$08
    BEQ @set
    INX                     ; W_SPREAD
    CMP #$09
    BEQ @set
    INX                     ; W_LASER
    CMP #$0B
    BEQ @set
    INX                     ; W_FIRE
    CMP #$0D
    BEQ @set
    LDX #W_RIFLE
@set:
    STX WeaponIdx
    CPX #W_FIRE
    BEQ @go
    LDA #$00
    STA Charge
@go:
    TXA
    BNE @notrifle
    JMP Rifle
@notrifle:
    CMP #W_MG
    BNE @notmg
    JMP MachineGun
@notmg:
    CMP #W_SPREAD
    BNE @notspread
    JMP Spread
@notspread:
    CMP #W_LASER
    BNE @fire
    JMP Laser
@fire:
    JMP FireBall
@rts:
    RTS

; Default rifle: one shot per press, 4 on screen.
Rifle:
    LDA PadNew
    AND #$40
    BEQ @rts
    LDA #K_RIFLE
    LDX #4
    JMP FireOne
@rts:
    RTS

; M: a shot per press, and every 7 frames while B is held; 6 on screen.
MachineGun:
    LDA PadNew
    AND #$40
    BNE @go
    LDA PadHeld
    AND #$40
    BEQ @rts
    LDA FireTimer
    BNE @rts
@go:
    LDA #MG_PERIOD
    STA FireTimer
    LDA #K_MG
    LDX #6
    JMP FireOne
@rts:
    RTS

; S: one press = 5 bullets at 0, -1, +1, -2, +2 steps (11.25 degrees), centre
; first, as many as there are free slots.
Spread:
    LDA PadNew
    AND #$40
    BEQ @rts
    LDA #K_SPREAD
    STA ShotKind
    JSR AimShot
    BCS @rts
    LDA #$00
    STA ShotCount
    STA ShotTmp
@p:
    LDY ShotTmp
    LDA SpreadSteps,Y
    JSR SpawnShot
    BCS @end
    INC ShotCount
    INC ShotTmp
    LDA ShotTmp
    CMP #5
    BCC @p
@end:
    LDA ShotCount
    BEQ @rts
    JMP ShotFx
@rts:
    RTS
SpreadSteps:
    .byte 0, $FF, 1, $FE, 2

; L: a new press removes the laser and fires a new one; holding B refires when
; the last one is gone. A laser is 5 segments launched 2 frames apart (8 px).
Laser:
    LDA PadNew
    AND #$40
    BEQ @held
    JSR KillLaser
    JMP FireLaser
@held:
    LDA PadHeld
    AND #$40
    BEQ @rts
    JSR LaserAlive
    BEQ FireLaser
@rts:
    RTS

FireLaser:
    LDA #K_LASER
    STA ShotKind
    JSR AimShot
    BCS @rts
    LDA #$00
    STA ShotCount
@s:
    LDA #$00
    JSR SpawnShot
    BCS @end
    LDA ShotCount
    ASL A
    STA ObjTimer,X          ; launch delay: 0, 2, 4, 6, 8 frames
    BEQ @n
    LDA #$01
    STA ObjHidden,X         ; waits hidden at the muzzle
@n:
    INC ShotCount
    LDA ShotCount
    CMP #LASER_SEGS
    BCC @s
@end:
    LDA ShotCount
    BEQ @rts
    JMP ShotFx
@rts:
    RTS

; KillLaser / LaserAlive: over the bullet slots. LaserAlive: Z=0 when a laser
; segment is alive.
KillLaser:
    LDY #BULLET_SLOTS_N - 1
@k:
    LDX BulletSlots5,Y
    LDA ObjType,X
    CMP #BULLET_TYPE
    BNE @n
    LDA ObjKind,X
    CMP #K_LASER
    BNE @n
    JSR EraseBullet
@n:
    DEY
    BPL @k
    RTS

LaserAlive:
    LDY #BULLET_SLOTS_N - 1
@k:
    LDX BulletSlots5,Y
    LDA ObjType,X
    CMP #BULLET_TYPE
    BNE @n
    LDA ObjKind,X
    CMP #K_LASER
    BNE @n
    LDA #$01                ; Z=0
    RTS
@n:
    DEY
    BPL @k
    LDA #$00                ; Z=1
    RTS

; F: a press fires a fire ball (5.5 px/frame, 2 on screen); holding B charges,
; and releasing after 32 frames fires a charged ball. A hit bursts a ball into
; 4 diagonal fragments, a charged one into 8 (TestTargets).
FireBall:
    LDA PadNew
    AND #$40
    BEQ @hold
    LDA #$00
    STA Charge
    LDA #K_FIRE
    LDX #2
    JMP FireOne
@hold:
    LDA PadHeld
    AND #$40
    BEQ @release
    LDA Charge
    CMP #$FF
    BEQ @rts
    INC Charge
    RTS
@release:
    LDA Charge
    LDX #$00
    STX Charge
    CMP #CHARGE_FULL
    BCC @rts
    LDA #K_FIRE_CH
    LDX #2
    JMP FireOne
@rts:
    RTS

; FireOne: A = kind, X = maximum of such shots on screen. One bullet in the
; aimed direction.
FireOne:
    STA ShotKind
    STX ShotTmp
    JSR AimShot
    BCS @rts
    JSR CountBullets
    CMP ShotTmp
    BCS @rts
    LDA #$00
    JSR SpawnShot
    BCS @rts
    JMP ShotFx
@rts:
    RTS

ShotFx:
    LDA #SND_SHOT
    JSR PlaySound           ; restores bank $27 (5)
    LDA #FIRE_ANIM
    STA FireAnim
    RTS

; CountBullets: A = live bullets, fragments not counted.
CountBullets:
    LDA #$00
    STA ShotCount
    LDY #BULLET_SLOTS_N - 1
@c:
    LDX BulletSlots5,Y
    LDA ObjType,X
    CMP #BULLET_TYPE
    BNE @n
    LDA ObjKind,X
    CMP #K_FRAG
    BEQ @n
    INC ShotCount
@n:
    DEY
    BPL @c
    LDA ShotCount
    RTS

; AimShot: C=1 when Simon can't shoot. Else AimCode, ShotAngle (relative to the
; facing) and ShotLevel: L 4.0; F 5.5; the others 4.0; R one step faster
; (not for L). Uses ShotKind.
AimShot:
    JSR GetAim
    BCS @rts
    STY AimCode
    LDA AimAngle,Y
    STA ShotAngle
    LDX #$00
    LDA ShotKind
    CMP #K_LASER
    BEQ @set
    CMP #K_FIRE
    BCC @r
    INX                     ; F: 5.5
@r:
    LDA WhipLevel
    BEQ @set
    INX
@set:
    STX ShotLevel
    CLC
@rts:
    RTS

; SpawnShot: A = extra angle steps. A bullet of ShotKind at the muzzle for
; AimCode, angle ShotAngle + A, speed ShotLevel. C=1: no free slot. X = slot.
SpawnShot:
    CLC
    ADC ShotAngle
    STA VelAng
    JSR FreeSlot
    BCS @rts
    JSR InitBullet
    LDY AimCode
    LDA ObjY                ; Simon's sprite Y - 8 + the muzzle offset (as the dagger's spawner)
    SEC
    SBC #$08
    CLC
    ADC AimDY,Y
    STA ObjY,X
    LDA ObjFacing
    BNE @left
    LDA ObjX
    CLC
    ADC AimDX,Y
    BCC @x
    LDA #$FF                ; past the right edge: removed on its first move
    BCS @x
@left:
    LDA ObjX
    SEC
    SBC AimDX,Y
    BCS @x
    LDA #$00
@x:
    STA ObjX,X
    LDA ObjFacing           ; absolute angle: facing right = the angle, left = mirrored
    BEQ @right
    LDA #$10
    SEC
    SBC VelAng
    STA VelAng
@right:
    LDA VelAng
    LDY ShotLevel
    JSR SetVelocity
    LDA ShotKind            ; a laser segment is drawn along its direction
    CMP #K_LASER
    BNE @done
    LDA VelAng
    CLC
    ADC #$02
    LSR A
    LSR A
    AND #$07
    TAY
    LDA LaserFrames,Y
    STA ObjFrame,X
@done:
    CLC
@rts:
    RTS

; FreeSlot: X = the first free bullet slot (type 0 and state 0, which the
; treasure allocator $A68A also wants), C=1 when none.
FreeSlot:
    LDY #$00
@f:
    LDX BulletSlots5,Y
    LDA ObjType,X
    BNE @busy
    LDA ObjState,X
    BEQ @ok
@busy:
    INY
    CPY #BULLET_SLOTS_N
    BCC @f
    SEC
    RTS
@ok:
    CLC
    RTS

; InitBullet: X = slot. Type, kind (ShotKind), cleared state and scratch, the
; kind's metasprite with the animation stopped.
InitBullet:
    LDA #BULLET_TYPE
    STA ObjType,X
    LDA ShotKind
    STA ObjKind,X
    LDA #$00
    STA ObjState,X
    STA ObjHidden,X
    STA ObjXLo,X
    STA ObjYLo,X
    STA ObjTimer,X
    STA ObjMemo,X
    STA $0338,X             ; the drawer's per-slot flags ($EF04 clears it too)
    LDA #$80
    STA ObjAnim,X
    LDA ShotKind
    SEC
    SBC #K_RIFLE
    TAY
    LDA BulletFrames,Y
    STA ObjFrame,X
    RTS

; SetVelocity: X = slot, A = absolute angle (0-31; 0 right, 8 down, 16 left,
; 24 up), Y = speed table. Sets the X and Y speeds, the facing and $04DC.
SetVelocity:
    AND #$1F
    STA VelAng
    TYA
    ASL A
    ASL A
    ASL A
    STY VelBase
    CLC
    ADC VelBase
    STA VelBase             ; table * 9
    LDA VelAng
    AND #$0F                ; distance from the horizontal: d = min(a & 15, 16 - (a & 15))
    CMP #$09
    BCC @d
    EOR #$FF
    CLC
    ADC #$11
@d:
    STA VelD
    CLC
    ADC VelBase
    TAY
    LDA MagHi,Y
    STA ObjXSpeed,X
    LDA MagLo,Y
    STA ObjXSpeedLo,X
    LDA #$08
    SEC
    SBC VelD
    CLC
    ADC VelBase
    TAY
    LDA MagHi,Y
    STA ObjYSpeed,X
    LDA MagLo,Y
    STA ObjYSpeedLo,X
    LDY #$00                ; facing: angles 9-23 go left
    LDA VelAng
    CMP #$09
    BCC @f
    CMP #$18
    BCS @f
    INY
@f:
    TYA
    STA ObjFacing,X
    LDY #$00                ; angles 17-31 go up
    LDA VelAng
    CMP #$11
    BCC @v
    INY
@v:
    TYA
    STA ObjYDir,X
    RTS

; speed * cos(d * 11.25 degrees), d = 0-8, for 4.0, 5.5 and 7.0 px/frame (8.8)
MagHi:
    .byte $04, $03, $03, $03, $02, $02, $01, $00, $00
    .byte $05, $05, $05, $04, $03, $03, $02, $01, $00
    .byte $07, $06, $06, $05, $04, $03, $02, $01, $00
MagLo:
    .byte $00, $EC, $B2, $53, $D4, $39, $88, $C8, $00
    .byte $80, $65, $15, $93, $E4, $0E, $1B, $13, $00
    .byte $00, $DE, $78, $D2, $F3, $E4, $AE, $5E, $00

; per kind (K_RIFLE...K_FRAG): damage (whole units in $0D) and metasprite.
; Super C's ratios (every bullet the same, the charged ball 5x) at the dagger's
; 6, with the outliers capped: S's 5 bullets and L's 5 segments all hit a big
; boss, so at 6 they killed bosses 2.6-8.2x (S) and 1.1-2.8x (L) faster than the
; rifle (boss bot, 2026-11-21); at 3 and 4 they are 1.1-2.1x and 0.9-1.9x.
;          rifle  M    S    L    F    F+   frag
DmgTable:
    .byte  6,     6,   3,   4,   6,   30,  6
BulletFrames:               ; rewritten by tools/commando_art.py
    .byte  BULLET_FRAME, BULLET_FRAME, BULLET_FRAME, BULLET_FRAME, BULLET_FRAME, BULLET_FRAME, BULLET_FRAME
BulletFramesEnd:
.assert BulletFramesEnd - BulletFrames == 7, "BulletFrames size is fixed (tools/commando_art.py)"
; laser segments by direction (absolute angle + 2) / 4: right, down-right,
; down, down-left, left, up-left, up, up-right (left-going ones are mirrored)
LaserFrames:                ; rewritten by tools/commando_art.py
    .byte  BULLET_FRAME, BULLET_FRAME, BULLET_FRAME, BULLET_FRAME, BULLET_FRAME, BULLET_FRAME, BULLET_FRAME, BULLET_FRAME
LaserFramesEnd:
.assert LaserFramesEnd - LaserFrames == 8, "LaserFrames size is fixed (tools/commando_art.py)"

; GetAim: Super C's aiming rules on Castlevania's states. Y = aim code, C=1 when
; Simon can't shoot (attack, knockback, dead).
;   ground: forward; Up = straight up; Up / Down + Left/Right (walking) = diagonal
;   air (jump, fall): forward; Up/Down = straight up/down; with Left/Right the diagonal
;   stairs: forward; Up/Down = diagonally along the steps. Crouch (prone): forward, low.
GetAim:
    LDY SimonState
    CPY #10
    BCS @no
    LDA AimClass,Y
    BMI @no
    CMP #AC_FIXED
    BCS @fixed
    TAX
    BEQ @ground
    DEX
    BEQ @air
    LDA PadHeld             ; stairs
    AND #$08
    BNE @diagup
    LDA PadHeld
    AND #$04
    BNE @diagdown
    LDY #AIM_STAIRS
    BNE @ok
@ground:
    LDA PadHeld
    AND #$08
    BEQ @gdown
    LDA PadHeld
    AND #$03
    BNE @diagup
    LDY #AIM_UP
    BNE @ok
@gdown:
    LDA PadHeld
    AND #$04
    BEQ @fwd
    LDA PadHeld
    AND #$03
    BEQ @fwd
@diagdown:
    LDY #AIM_DIAG_DOWN
    BNE @ok
@diagup:
    LDY #AIM_DIAG_UP
    BNE @ok
@air:
    LDA PadHeld
    AND #$0C
    BEQ @airfwd
    AND #$08
    BEQ @down
    LDY #AIM_AIR_UP
    BNE @side
@down:
    LDY #AIM_AIR_DOWN
@side:
    LDA PadHeld
    AND #$03
    BEQ @ok
    INY                     ; AIM_AIR_UP+1 = diagonal up, AIM_AIR_DOWN+1 = diagonal down
    BNE @ok
@airfwd:
    LDY #AIM_AIR_FWD
    BNE @ok
@fixed:
    AND #$0F
    TAY
    CLC
    RTS
@fwd:
    LDY #AIM_FWD
@ok:
    CLC
    RTS
@no:
    SEC
    RTS

; Aim class by Simon's state $046C (0 stand/walk, 1 jump, 2 attack, 3 crouch,
; 4 stairs, 5 knockback, 6 walk to a stair, 7 fall, 8 dead, 9 landing crouch)
AimClass:
    .byte AC_GROUND, AC_AIR, AC_NONE, AC_CROUCH, AC_STAIRS
    .byte AC_NONE, AC_STAIR_WALK, AC_AIR, AC_NONE, AC_CROUCH

; Per aim code: muzzle offset (forward, down from Simon's sprite Y - 8) and the
; angle in 11.25-degree steps relative to the facing (- = up).
;              fwd   up    diagU prone stair airF  airU  airUD airD  airDD diagD
AimDX:    .byte 8,    2,    10,   10,    8,    8,    0,    8,    0,    8,    10
AimDY:    .byte $00,  $E8,  $F2,  $0E,   $00,  $02,  $F8,  $FC,  $0C,  $08,  $0A
AimAngle: .byte 0,    $F8,  $FC,  0,     0,    0,    $F8,  $FC,  8,    4,    4

; Bullet slots in order of preference: $14-$16 (no subweapons any more), $1A/$1B
; (debris may use them), then $17-$19 when free (moving platforms and rising
; treasures take theirs first).
BulletSlots5:
    .byte $16, $15, $14, $1B, $1A, $19, $18, $17
BULLET_SLOTS_N = 8

; =============================================================================
; BulletPass: from PrePass (bank 5 mapped). Builds the target list once, then
; moves each bullet and tests it against the list, each bullet every 2nd frame
; (by slot index): at 7 px/frame a bullet still overlaps a target box (>= 14 px
; half-width + the bullet's) for 4 frames, and 8 bullets x 12 targets stay well
; inside the sprite-0 wait.
BulletPass:
    LDY #BULLET_SLOTS_N - 1
@any:
    LDX BulletSlots5,Y
    LDA ObjType,X
    CMP #BULLET_TYPE
    BEQ @go
    DEY
    BPL @any
    RTS
@go:
    JSR BuildTargets
    LDY #BULLET_SLOTS_N - 1
@b:
    STY PassIdx
    LDX BulletSlots5,Y
    LDA ObjType,X
    CMP #BULLET_TYPE
    BNE @nb
    STX PassSlot
    JSR MoveBullet
    BCS @nb
    LDA PassIdx
    EOR FrameCount
    AND #$01
    BNE @nb
    JSR TestTargets
@nb:
    LDY PassIdx
    DEY
    BPL @b
    RTS

; BuildTargets: the targets of $E4D9 (enemies and candles $04-$13): slot and
; hit box (half-sizes $E46A + the dagger's 8 x 6), at most MAX_TARGETS.
BuildTargets:
    LDY #$00
    LDX #TARGET_LAST
@t:
    LDA ObjType,X
    BEQ @n
    CMP #$30                ; effects, items and the rest
    BCS @n
    CMP #$2F                ; item
    BEQ @n
    CMP #TYPE_PROJ
    BEQ @n
    CMP #$21
    BEQ @n
    CMP #$25
    BEQ @n
    PHA
    LDA ObjState,X          ; spawning
    BMI @pop
    LDA ObjHidden,X
    BEQ @vis
    PLA
    PHA
    CMP #$04                ; Dracula's head is hit while hidden
    BNE @pop
@vis:
    PLA
    CMP #$1D                ; Dracula's body in form 2 uses the $30 box
    BNE @box
    LDA $7A
    BEQ @body
    LDA #$30
    BNE @box
@body:
    LDA #$1D
@box:
    STY PassTmp
    ASL A
    TAY
    LDA HalfSizes + 1,Y
    CLC
    ADC #BULLET_HH
    PHA
    LDA HalfSizes,Y
    CLC
    ADC #BULLET_HW
    LDY PassTmp
    STA TgtHW,Y
    PLA
    STA TgtHH,Y
    TXA
    STA TgtSlot,Y
    INY
    CPY #MAX_TARGETS
    BCS @done
@n:
    DEX
    CPX #TARGET_FIRST
    BCS @t
@done:
    STY TgtN
    RTS
@pop:
    PLA
    JMP @n

; MoveBullet: X = slot. Laser segments wait out their launch delay (hidden, no
; motion); fragments live FRAG_LIFE frames. Then 8.8 motion along the facing
; and $04DC, the camera compensation of $EACB and the stock despawn limits.
; C=1: no hit test this frame (removed or waiting). (Before the split, $52/$53
; hold the last frame's camera motion: at most 1 px off when it starts or stops.)
MoveBullet:
    LDA ObjKind,X
    CMP #K_LASER
    BNE @frag
    LDA ObjTimer,X
    BEQ @move
    DEC ObjTimer,X
    BNE @wait
    LDA #$00
    STA ObjHidden,X         ; launched: moves from the next frame
@wait:
    SEC
    RTS
@frag:
    CMP #K_FRAG
    BNE @move
    DEC ObjTimer,X
    BNE @move
    JMP @off
@move:
    LDA ObjFacing,X
    BNE @left
    LDA ObjXLo,X
    CLC
    ADC ObjXSpeedLo,X
    STA ObjXLo,X
    LDA ObjX,X
    ADC ObjXSpeed,X
    STA ObjX,X
    BCS @off
    BCC @y
@left:
    LDA ObjXLo,X
    SEC
    SBC ObjXSpeedLo,X
    STA ObjXLo,X
    LDA ObjX,X
    SBC ObjXSpeed,X
    STA ObjX,X
    BCC @off
@y:
    LDA ObjYDir,X
    BNE @up
    LDA ObjYLo,X
    CLC
    ADC ObjYSpeedLo,X
    STA ObjYLo,X
    LDA ObjY,X
    ADC ObjYSpeed,X
    STA ObjY,X
    BCS @off
    BCC @scroll
@up:
    LDA ObjYLo,X
    SEC
    SBC ObjYSpeedLo,X
    STA ObjYLo,X
    LDA ObjY,X
    SBC ObjYSpeed,X
    STA ObjY,X
    BCC @off
@scroll:
    LDA ObjXLo,X
    CLC
    ADC CamDXLo
    STA ObjXLo,X
    LDA ObjX,X
    ADC CamDXHi
    STA ObjX,X
    CMP #$08
    BCC @off
    CMP #$F9
    BCS @off
    LDA ObjY,X
    CMP #$08
    BCC @off
    CMP #$F8
    BCS @off
    CLC
    RTS
@off:
    JSR EraseBullet
    SEC
    RTS

; TestTargets: X = bullet slot (= PassSlot). The first target in the list
; whose box overlaps ends the bullet and queues the hit with the kind's
; damage; a fire ball also bursts into fragments. A target already hit this
; frame is skipped (the stock loop also gives each target one shot hit per
; frame), and so is the target a fragment came from.
TestTargets:
    LDA ObjX,X
    STA PassX
    LDA ObjY,X
    STA PassY
    LDY TgtN
@l:
    DEY
    BPL @test
    RTS
@test:
    LDX TgtSlot,Y
    LDA PassX
    SEC
    SBC ObjX,X
    BCS @dx
    EOR #$FF
    ADC #$01
@dx:
    CMP TgtHW,Y
    BCS @l
    LDA PassY
    SEC
    SBC ObjY,X
    BCS @dy
    EOR #$FF
    ADC #$01
@dy:
    CMP TgtHH,Y
    BCS @l
    STY PassTmp             ; overlap: not the fragment's own target
    TXA
    CLC
    ADC #$01
    LDX PassSlot
    CMP ObjMemo,X
    BEQ @next
    TAX
    DEX                     ; X = target again
    LDY HitQN               ; not queued already
@dup:
    DEY
    BMI @queue
    TXA
    CMP HitQSlot,Y
    BEQ @next
    JMP @dup
@next:
    LDY PassTmp
    JMP @l
@queue:
    LDY HitQN
    CPY #HIT_QUEUE
    BCS @rts
    TXA
    STA HitQSlot,Y
    LDA ObjType,X
    STA HitQType,Y
    LDA PassSlot
    STA HitQBullet,Y
    TXA                     ; the target, for Burst
    LDX PassSlot
    PHA
    LDA ObjKind,X
    SEC
    SBC #K_RIFLE
    TAX
    LDA DmgTable,X
    STA HitQDmg,Y
    INC HitQN
    PLA
    LDX PassSlot
    LDY ObjKind,X
    CPY #K_FIRE
    BEQ @burst
    CPY #K_FIRE_CH
    BNE @erase
@burst:
    JSR Burst
@erase:
    LDX PassSlot
    JMP EraseBullet
@rts:
    RTS

; Burst: X = fire ball, A = the target it hit. 4 diagonal fragments (8 for a
; charged ball) at the ball's position, 4 px/frame, FRAG_LIFE frames, not
; hitting that target.
Burst:
    CLC
    ADC #$01
    STA BurstMemo
    LDA ObjX,X
    STA BurstX
    LDA ObjY,X
    STA BurstY
    LDA #$04                ; diagonals: 4, 12, 20, 28 (8 steps apart)
    STA BurstAng
    LDY #4
    LDA #$08
    STA ShotCount           ; the step (pre-split: ShotCount is free)
    LDA ObjKind,X
    CMP #K_FIRE_CH
    BNE @n
    LDA #$00                ; charged: 0, 4, 8 ... 28
    STA BurstAng
    LDY #8
    LDA #$04
    STA ShotCount
@n:
    STY BurstN
    LDA #K_FRAG
    STA ShotKind
@f:
    JSR FreeSlot
    BCS @rts
    JSR InitBullet
    LDA BurstX
    STA ObjX,X
    LDA BurstY
    STA ObjY,X
    LDA #FRAG_LIFE
    STA ObjTimer,X
    LDA BurstMemo
    STA ObjMemo,X
    LDA BurstAng
    LDY #$00
    JSR SetVelocity
    LDA BurstAng
    CLC
    ADC ShotCount
    STA BurstAng
    DEC BurstN
    BNE @f
@rts:
    RTS

; =============================================================================
; B: Super C's barrier ($80, -1 every 4th frame = 512 frames; any enemy touching
; the player dies unless its HP is $F0 or more, i.e. bosses). Here: the potion's
; invincibility at $FF (-1 every 2nd frame = 510 frames) with BarrierOn; an enemy
; touching the commando is hit for $40 (more than any normal enemy has), bosses
; are spared. FireTick clears BarrierOn when the invincibility runs out.
BarrierStart:
    LDA #$FF
    STA Invinc
    LDA #$01
    STA BarrierOn
    RTS

; BarrierGate: $E6D2. Invincible without the barrier: no contact. Else the box
; test ($E6D7).
BarrierGate:
    LDA Invinc
    BEQ @test
    LDA BarrierOn
    BNE @test
    RTS
@test:
    JMP $E6D7

; BarrierHit: $E718, X = an enemy touching the commando. Under the barrier it is
; hit like a bullet hit, with a free bullet slot as the projectile (the on-hit
; handlers read its X, speed, state and $04F8); else the stock contact damage.
BarrierHit:
    LDA Invinc
    BEQ @stock
    LDA BarrierOn
    BEQ @stock
    LDA ObjType,X
    CMP #$21                ; the types bullets can't hit either
    BEQ @rts
    CMP #$25
    BEQ @rts
    CMP #TYPE_PROJ
    BEQ @rts
    CMP #$18                ; bosses: Death, Phantom Bat, mummies, Medusa,
    BCC @head               ; Frankenstein, Dracula ($18-$1D)
    CMP #$1E
    BCC @rts
@head:
    CMP #$04                ; Dracula's head
    BNE @hit
    LDA Stage
    CMP #$12
    BEQ @rts
@hit:
    STX $4E
    JSR FreeSlot
    BCS @rts                ; no free slot: next frame
    STX $0F
    LDA #$00
    STA ObjMemo,X
    STA ObjXSpeed,X
    STA ObjXSpeedLo,X
    LDA ObjX
    STA ObjX,X
    LDA ObjY
    STA ObjY,X
    LDA #$40
    STA $0D
    LDA #$00
    STA $0C
    STA $0E                 ; weapon code 0, as the bullets
    STA LastHitKind         ; no freeze
    LDX $4E
    JMP OnHit
@rts:
    RTS
@stock:
    LDA ObjType,X
    JMP $E71B

FreeEnd5:
.assert FreeEnd5 <= $C000, "bank 5 free space overflow"
