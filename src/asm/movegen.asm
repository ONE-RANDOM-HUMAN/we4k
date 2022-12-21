%ifndef MOVEGEN_ASM
%define MOVEGEN_ASM

DEFAULT rel

%include "common.asm"

SPECIAL_ONE_FLAG equ 0001b
SPECIAL_TWO_FLAG equ 0010b
CAPTURE_FLAG equ 0100b
PROMO_FLAG equ 1000b
DOUBLE_PAWN_PUSH equ SPECIAL_ONE_FLAG
EN_PASSANT_CAPTURE equ CAPTURE_FLAG | SPECIAL_ONE_FLAG
KINGSIDE_CASTLE equ SPECIAL_TWO_FLAG
QUEENSIDE_CASTLE equ SPECIAL_ONE_FLAG | SPECIAL_TWO_FLAG

SECTION .rodata
alignb 8
pawn_offsets:
    db 8
    db 16
    db 7
    db 9
    db 24
    db 0
    db 0
    db 0
    
    db 248
    db 240
    db 247
    db 249
    db 32
    db 0
    db 0
    db 0

alignb 8
knight_shifts:
   dq 17
   dq 15
   dq 10
   dq 6
bishop_shifts:
    dq 9
    dq 7
rook_shifts:
    dq 8
    dq 1

SECTION .text
; rdi - board, rsi - move buffer.
global gen_pseudo_legal_asm
gen_pseudo_legal_asm:
    push rbx
    ; pawn moves
    
    ; eax - side to move
    movzx eax, byte [rdi + Board.side_to_move]
    
    ; offsets pointer
    lea r10, [pawn_offsets + rax*8 + 4]

    ; r8 - pieces of side to move
    mov r8, qword [rdi + Board.colors + rax*8]

    ; r9 - pieces of enemy side
    xor al, 1
    mov r9, qword [rdi + Board.colors + rax*8]

    ; rdx - pawns
    mov rdx, qword [rdi + Board.pawn]
    and rdx, r8

    ; generalised shifts using rotates
    lea rax, [r10 - 4] ; size savings thanks to @sqrmax
.make_squares:
    mov r11, rdx
    mov cl, byte [rax]
    rol r11, cl
    push r11

    inc rax
    cmp rax, r10
    jne .make_squares

    ; mask the rotates
    vmovdqa xmm0, oword [rsp]
    vpand xmm0, xmm0, oword [not_a_file]
    vmovdqa oword [rsp], xmm0

    xor ecx, ecx

    ; en passant
    movzx eax, byte [rdi + Board.ep]
    cmp al, 64
    je .no_ep

    bts rcx, rax
    ; flags and dest for ep captures
    lea ebx, [rax + (EN_PASSANT_CAPTURE << 6)] ; one byte shorter than move/or
    shl ebx, 6
    test rcx, qword [rsp]
    jz .no_queenside

    ; queenside ep
    lea edx, [eax + ebx]
    sub dl, byte [r10 - 1]
    mov word [rsi], dx
    add rsi, 2
.no_queenside:
    ; kingside ep
    test rcx, qword [rsp + 8]
    jz .no_kingside

    lea edx, [eax + ebx]
    sub dl, byte [r10 - 2]
    mov word [rsi], dx
    add rsi, 2
.no_kingside:
.no_ep:
    mov r11d, CAPTURE_FLAG << 12,
    pop rax
    and rax, r9
    dec r10
    call pawn_serialise
    pop rax
    and rax, r9
    dec r10
    call pawn_serialise

    pop rax
    pop rbx

    ; occupied
    mov rdx, r8
    or rdx, r9
    not rdx

    ; mask off occupied squares
    and rax, rdx
    and rbx, rdx

    ; mask for blocked double pawn pushes
    mov cl, byte [r10 - 2]
    rol rdx, cl
    and rax, rdx

    ; mask for double pawn push rank
    mov edx, 0FFh
    mov cl, byte [r10 + 2]
    shl rdx, cl
    and rax, rdx

    dec r10
    mov r11d, DOUBLE_PAWN_PUSH << 12
    call pawn_serialise

    mov rax, rbx
    dec r10
    xor r11d, r11d
    call pawn_serialise
    
    ; king moves
    ; rdx - king bb
    mov rdx, r8
    and rdx, qword[rdi + Board.king]

    call king_moves

    ; exclude own pieces
    ; rax - king moves
    andn rax, r8, rax

    ; rdx - king position
    tzcnt rdx, rdx
    call serialise

    ; castling
    mov al, [rdi + Board.side_to_move]
    lea rcx, [r8 + r9] ; addition of disjoint bb for occ
    test al, al
    mov al, [rdi + Board.castling] ; al - castling flags
    jnz .black_castling
    jmp .end_color_castling
.black_castling:
    shr al, 2
    shr rcx, 56
.end_color_castling:
    test al, 10b ; second bit is kingside to allow pext in make move
    jz .no_kingside_castle
    test cl, 0110_0000b
    jnz .no_kingside_castle
    mov ebx, edx
    shl ebx, 6
    or ebx, edx
    add bx, (KINGSIDE_CASTLE << 12) + (2 << 6)
    mov word [rsi], bx
    add rsi, 2
.no_kingside_castle:
    test al, 1b 
    jz .no_queenside_castle
    test cl, 0000_1110b
    jnz .no_queenside_castle
    mov ebx, edx
    shl ebx, 6
    or ebx, edx
    add bx, (QUEENSIDE_CASTLE << 12) - (2 << 6)
    mov word [rsi], bx
    add rsi, 2
.no_queenside_castle:
    ; TODO: size improvements by reusing addresses
    ; other pieces
    ; knight
    mov r10, qword [rdi + Board.knight]
    lea r11, [knight_moves]
    call gen_piece

    ; bishop like
    mov r10, qword [rdi + Board.bishop]
    or r10, qword [rdi + Board.queen]
    add r11, bishop_moves - knight_moves
    call gen_piece

    ; rook like
    mov r10, qword [rdi + Board.rook]
    or r10, qword [rdi + Board.queen]
    add r11, rook_moves - bishop_moves
    call gen_piece

    mov rax, rsi
    pop rbx
    ret    

; moves - rsi
; squares - rax
; offset - r10b
; extra flags - r11w
; modifies rcx, rdx
pawn_serialise:
.loop_start:
    ; rdx - dest
    tzcnt rdx, rax
    jc .end

    ; move without promo flags
    mov ecx, edx
    shl ecx, 6
    or ecx, edx
    sub cl, byte [r10]
    or ecx, r11d

    cmp dl, 56
    jae .promo
    cmp dl, 8
    jb .promo

    mov word [rsi], cx
    add rsi, 2

    ; no promo
    jmp .loop_tail
.promo:
    or ch, PROMO_FLAG << 4
.promo_loop:
    mov word [rsi], cx
    add rsi, 2
    add ch, 0001_0000b
    test ch, 0011_0000b
    jnz .promo_loop
.loop_tail:
    blsr rax, rax
    jmp .loop_start
.end:
    ret

; rdi - board
; rsi - move list
; r8 - side pieces
; r9 - enemy pieces
; r10 - pieces
; r11 - move_fn
gen_piece:
    and r10, r8
    
.loop_head:
    blsi rdx, r10 ; rdx - origin
    jz .end
    lea rcx, [r8 + r9] ; addition of disjoint bb for occ
    call r11 ; rax - destination squares
    andn rax, r8, rax
    tzcnt rdx, r10 ; dl - origin square
    call serialise
    blsr r10, r10
    jmp .loop_head
.end:
    ret

; rax - destinations (bb)
; rdx - origin square
; r9 - enemy pieces
; rsi - move ptr
; clobbers rbx, rcx
serialise:
    tzcnt rcx, rax
    jc .end
    mov ebx, edx
    bt r9, rcx
    jnc .nocapture ; bh is zero from edx tzcnt
    mov bh, CAPTURE_FLAG << 4
.nocapture:
    shl ecx, 6
    or ebx, ecx
    mov word [rsi], bx
    add rsi, 2
    blsr rax, rax
    jmp serialise
.end:
    ret

; rdx - king positions
king_moves:
    mov r10, qword [not_a_file]
    mov rcx, rdx

    ; right shift
    and rcx, r10
    shr rcx, 1

    ; left shift
    lea rax, [rdx+rdx]
    and rax, r10

    or rax, rcx
    or rax, rdx

    ; north/south shifts
    mov rcx, rax
    shl rcx, 8
    or rcx, rax
    shr rax, 8
    or rax, rcx

    ret

; rdx - knight positions
knight_moves:
    vmovq xmm0, rdx
    vpbroadcastq ymm0, xmm0
    vmovdqu ymm1, yword [knight_shifts]
    vmovdqu ymm2, yword [not_a_file]

    vpsllvq ymm3, ymm0, ymm1
    vpand ymm3, ymm3, ymm2

    vpand ymm0, ymm0, ymm2
    vpsrlvq ymm0, ymm0, ymm1

    vpor ymm0, ymm0, ymm3
    vextracti128 xmm1, ymm0, 1
    vpor xmm0, xmm0, xmm1
    vpextrq rdx, xmm0, 1
    vmovq rax, xmm0
    or rax, rdx
    ret

; rdx - queen positions
; rcx - occ
queen_moves:
    ; preserves rdx, rcx
    call bishop_moves
    mov r8, rax ; r8 is preserved
    call rook_moves
    or rax, r8
    ret

bishop_moves:
    vmovdqu xmm0, [bishop_shifts]
    vmovdqu xmm1, [not_a_file]
    jmp dumb7fill

rook_moves:
    vmovdqu xmm0, [rook_shifts]
    vmovdqu xmm1, [all_mask]
    ; jmp dumb7fill not necessary because dumb7fill is already next

; xmm0 - shifts
; xmm1 - masks
; rdx - value
; rcx - occ
dumb7fill:
    andn rax, rdx, rcx
    vmovq xmm3, rax,
    vmovq xmm2, rdx,

    ; xmm7 - mask excluding occ
    vpunpcklqdq xmm3, xmm3
    vpandn xmm7, xmm3, xmm1

    ; left shifts in xmm2,
    ; right shifts in xmm4
    vpunpcklqdq xmm2, xmm2
    vmovdqa xmm4, xmm2

    mov al, 7
.loop_head:
    vpsllvq xmm5, xmm2, xmm0
    vpand xmm6, xmm4, xmm7

    vpand xmm5, xmm5, xmm7
    vpsrlvq xmm6, xmm6, xmm0

    vpor xmm2, xmm2, xmm5
    vpor xmm4, xmm4, xmm6
    dec al
    jnz .loop_head

    ; mask off the occupied squares
    ; because the right shfits are pre-masked
    vpandn xmm4, xmm3, xmm4
    ; include occ
    vpsllvq xmm5, xmm2, xmm0
    vpand xmm6, xmm4, xmm1

    vpand xmm5, xmm5, xmm1
    vpsrlvq xmm6, xmm6, xmm0

    vpor xmm0, xmm5, xmm6
    vpunpckhqdq xmm1, xmm0, xmm0
    vpor xmm0, xmm0, xmm1
    vmovq rax, xmm0
    ret

%endif
