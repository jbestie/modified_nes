; Ghosts'n Goblins (USA) "Remix": fixed-bank hooks (bank 15 of the 256 KiB
; expanded image = the original bank 7).  Assembled after bank8.asm, whose
; symbols (RAM, FN_* numbers, Dispatch8) it uses.
;
; Fixed-bank space: the original single-shot routine $E045-$E073 (47 bytes)
; moves to bank 8 (Fire), which frees it for the trampoline.  Nothing else
; in the fixed bank is used, so the invincibility build's $FFE8 cave stays
; untouched.

BankTable = $C000       ; $C000-$C007 hold 00..07 (bus-conflict-safe writes)
Yield     = $C336       ; scheduler: let the other tasks run this frame

.bank 15

; ---- HitPending -> ArthurTick (damage modes, weapon cycling) ----
; Callers: `JSR $E014 / BCC ok / JMP $E171`.  Far8 returns the callee's carry.
.org $E014
.expect 20 E3 F2 F0 02
HitPending:
    LDY #FN_ARTHUR
    JMP Far8

; ---- $E045: the single-shot slot search becomes the trampoline area ----
.org $E045
.expect A0 11 B9 F0 04 F0 13 C8 C0 13 90 F6 C0 14 B0 1F AD 3A 05 C9 42 F0 EB 4C 74 E0 BD 1D 06 09 02 9D 1D 06 A9 00
FireEntry:                      ; reached from $E043 when B fired and $85 = 0
    LDY #FN_FIRE                ; falls into Far8; Fire sets $85 itself

; Far8: call bank-8 function Y, then restore the previous bank.  Preserves X
; and the callee's carry; clobbers A and Y.
Far8:
    LDA CurBank
    PHA
Bank8Op:
    LDA #8
Bank8Byte = Bank8Op + 1         ; this ROM byte is $08: bus-conflict-safe target
    STA CurBank                 ; shadow first: the NMI restores from $C7
    STA Bank8Byte
    JSR Dispatch8
    PLA                         ; PLA/STA/TAY/STA keep the carry
    STA CurBank
    TAY
    STA BankTable,Y
    RTS

; ---- title loop: run TitleTick, then yield as the original did ----
TitleStub:
    LDY #FN_TITLE
    JSR Far8
    JMP Yield
HooksEnd:
.assert HooksEnd <= $E069, "trampoline area overflow"

.org $C4CE
.expect 20 36 C3
    JSR TitleStub               ; was JSR $C336

; ---- slot partition: every bound reads EnemyEnd ($11 or $0F) ----
; Same instruction lengths: CPY/CPX/CMP/LDY #imm -> zero page.
.org $DA20                      ; FindFreeEnemySlot
.expect C0 11
    CPY EnemyEnd
.org $DA4E                      ; recycle slot, round-robin
.expect C0 11
    CPY EnemyEnd
.org $DA60
.expect C9 11
    CMP EnemyEnd
.org $D763                      ; census before random spawns
.expect E0 11
    CPX EnemyEnd
.org $D381                      ; sweep of non-active slots
.expect E0 11
    CPX EnemyEnd
.org $D531                      ; wipe on stage (re)start
.expect C0 11
    CPY EnemyEnd
.org $F5F9                      ; weapon-vs-enemy loop start
.expect A0 11
    LDY EnemyEnd

; ---- impact spark: facing bit instead of dir == 4 (diagonal shots) ----
; Identical for the original shots, whose direction is always 4 or $0C and
; matches the facing bit copied at spawn ($E110).
.org $EBE9
.expect BD F1 05 C9 04 F0 05
    LDA ObjFlags,X
    AND #$04
    BEQ $EBF5
