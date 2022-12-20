%ifndef EVALUATE_ASM
%define EVALUATE_ASM

DEFAULT rel

%include "common.asm"

SECTION .rodata
eval:
material:
    dw %( 200,  256)
    dw %( 800,  800)
    dw %( 816,  816)
    dw %(1344, 1344)
    dw %(2496, 2496)

mobility:
    dw %(32, 32)
    dw %(16, 32)
    dw %(16, 16)
    dw %( 8,  8)

passed:
    dw %( 32,  64)
    dw %( 48,  80)
    dw %( 64,  96)
    dw %( 80, 112)
    dw %( 96, 128)
    dw %(128, 256)

mobility_fns:
    dq knight_moves
    dq bishop_moves
    dq rook_moves
    dq queen_moves


SECTION .text
; rdi - board
global evaluate_asm
evaluate_asm:
    push rbx
    push r15
    push r14
    push r13
    push r12

    lea r15, [eval] ; r15 - pointer to weights
    mov r12, qword [rdi + Board.white] ; r12 white pieces
    mov r13, qword [rdi + Board.black] ; r13 black pieces

    xor eax, eax ; mg
    xor edx, edx ; eg
    xor ecx, ecx

.material_loop_head:
    mov rbx, qword [rdi + Board.pieces + 8 * rcx]
    mov rsi, rbx
    and rbx, r12
    and rsi, r13
    popcnt rbx, rbx
    popcnt rsi, rsi
    sub ebx, esi
    mov esi, ebx

    imul si, word [r15 + 4 * rcx]
    add eax, esi
    imul bx, word [r15 + 4 * rcx + 2]
    add edx, ebx

    inc ecx
    cmp ecx, 5
    jne .material_loop_head

    ; bishop pair
    mov r8, 55AA_55AA_55AA_55AAh ; light squares
    mov r9, r8
    not r9; dark squares

    mov r10, [rdi + Board.bishop]
    mov r11, r10 ; make a copy for black

    and r10, r12 ; white bishops
    test r10, r8
    jz .no_white_pair
    test r10, r9
    jz .no_white_pair
    sub eax, -128
    sub edx, -128
.no_white_pair:
    and r11, r13 ; black bishops
    test r11, r8
    jz .no_black_pair
    test r11, r9
    jz .no_black_pair
    add eax, -128
    add edx, -128
.no_black_pair:

    ; mobility
    push rdx
    push rax

    mov r14, qword [not_a_file]
    mov rdx, qword [rdi + Board.pawn]
    mov rcx, rdx
    and rcx, r12
    and rdx, r13

    push rdi

    ; black pawn attacks
    mov rdi, rdx
    call pawn_south
    mov r9, rax

    ; white pawn attacks
    mov rdi, rcx
    call pawn_north
    mov r14, rax
    pop rdi
    
    lea rsi, [r12 + r13] ; rsi occ
    mov r8, r12 ; r8 - white pieces
    not r9 ; not black pawn attacks
    mov r12, rdi ; save board ptr - would be smaller as push/pop
    call side_mobility
    push rax

    mov rdi, r12 ; rdi - board
    ; rsi is preserved
    mov r8, r13 ; r8 black pieces
    mov r9, r14
    not r9 ; r9 - not white pawn attacks

    mov r14, rdi ; save board
    call side_mobility
    push rax

    ; pawn eval
    ; board was in r14
    ; r12 - white pawns
    ; r13 - black pawns
    mov r12, qword [r14 + Board.pawn]
    and r13, r12
    and r12, qword [r14 + Board.white]

    mov r14, qword [not_a_file]

    ; board and occ no longer needed
    mov rdi, r13
    call pawn_spans
    mov r10, r8 ; black north span
    mov r11, r9 ; black south span
    
    mov rdi, r12
    call pawn_spans
    ; r8 white north span
    ; r9 white south span

    mov rdi, r12
    mov rsi, r8
    or rsi, r9
    call isolated_count
    mov ebx, eax

    mov rdi, r13
    mov rsi, r10
    or rsi, r11
    call isolated_count
    sub ebx, eax
    imul ecx, ebx, -64 ; eg
    imul ebx, ebx, -32 ; mg

    mov rax, r9 ; white southspan
    shr rax, 8
    and rax, r12
    popcnt rdx, rax

    mov rax, r10 ; black northspan
    shl rax, 8
    and rax, r13
    popcnt rax, rax
    sub edx, eax
    imul eax, edx, -32 ; mg
    add ebx, eax
    imul eax, edx, -96 ; eg
    add ecx, eax

    push rcx ; isolated + doubled eg
    push rbx ; isolated + doubled mg

    ; backward
    mov rdx, r12
    shl rdx, 8 ; white stops

    ; b attacks
    mov rdi, r13
    call pawn_south
    and rdx, rax ; w stops & b attacks

    ; w attack spans
    mov rdi, r8
    call pawn_north
    andn rdx, rax, rdx ; w backward
    or r8, rax ; w attack spans | w north spans
    
    popcnt rbx, rdx

    mov rdx, r13 ; b stops
    shr rdx, 8

    ; w attacks
    mov rdi, r12
    call pawn_north
    and rdx, rax ; b stops & white attacks

    ; b attack spans
    mov rdi, r11
    call pawn_south
    andn rdx, rax, rdx ; b backward
    or r11, rax ; b attack spans | b south spans

    popcnt rax, rdx
    sub ebx, eax

    imul eax, ebx, 0 ; backward mg
    imul edx, ebx, -32 ; backward eg
    pop rbx
    pop rcx

    add ebx, eax
    add ecx, edx

    ; passed pawns
    shr r9, 8
    or r11, r9 ; (w south spans >> 8) | (b attack spans | b south spans)
    andn rax, r11, r12
.white_passed_head:
    tzcnt rdx, rax
    jc .white_passed_end

    shr edx, 3
    add bx, word [r15 + passed - eval + rdx * 4 - 4]
    add cx, word [r15 + passed - eval + rdx * 4 - 4 + 2]
    blsr rax, rax
    jmp .white_passed_head
.white_passed_end:

    shl r10, 8
    or r8, r10
    andn rax, r8, r13
.black_passed_head:
    tzcnt rdx, rax
    jc .black_passed_end

    shr edx, 3
    xor edx, 7
    sub bx, word [r15 + passed - eval + rdx * 4 - 4]
    sub cx, word [r15 + passed - eval + rdx * 4 - 4 + 2]
    blsr rax, rax
    jmp .black_passed_head
.black_passed_end:
.end:
    ; pop from stack
    pop rdi
    pop rsi
    pop rax
    pop rdx

    ; use 32 bit operations because the upper 16 bits don't matter
    add eax, esi
    sub eax, edi
    shr esi, 16
    shr edi, 16
    add edx, esi
    sub edx, edi

    add eax, ebx
    add edx, ecx

    ; return value in dx:ax
    pop r12
    pop r13
    pop r14
    pop r15
    pop rbx
    ret
    
; rdi - board
; rsi - occ
; r8 - color bb
; r9 - squares
; clobbers rax, rbx, rcx, rdx, r8, r10, r11
side_mobility:
    mov ecx, 4

.piece_mask_loop_head:
    mov rbx, qword [rdi + Board.pieces + rcx * 8]
    and rbx, r8
    push rbx
    dec ecx
    jnz .piece_mask_loop_head
    xor r10d, r10d

.piece_mobility_loop_head:
    pop r11
    xor ebx, ebx

.piece_square_loop_head:
    blsi rdi, r11
    jz .end_piece_square_loop

    ; save registers
    push rcx

    ; rdi - square rsi - occ
    ; clobbers rax, rcx, rdx, r8
    call qword [r15 + mobility_fns - eval + 8 * rcx]
    pop rcx

    ; r9 is preserved
    and rax, r9
    popcnt rax, rax
    add ebx, eax

    blsr r11, r11
    jmp .piece_square_loop_head
.end_piece_square_loop:
    imul ebx, dword [r15 + mobility - eval + rcx * 4] ; fine as long as nothing is negative
    add r10d, ebx

    inc ecx
    cmp ecx, 4
    jne .piece_mobility_loop_head
    mov eax, r10d
    ret


; pawns - rdi
; clobbers rax, rdi, possibly rcx in the future
; returns in r8, r9
pawn_spans:
    mov r8, rdi
    mov r9, rdi

    ; loop 6 here would be smaller
    mov rax, r8
    shl rax, 8
    shr rdi, 8
    or r8, rax
    or r9, rdi

    mov rax, r8
    mov rdi, r9
    shl rax, 16
    shr rdi, 16
    or r8, rax
    or r9, rdi

    mov rax, r8
    mov rdi, r9
    shl rax, 32
    shr rdi, 32
    or r8, rax
    or r9, rdi

    ret

; rdi - pawns
; rsi - pawn files
; r14 - not a file
isolated_count:
    xor eax, eax
.loop_head:
    blsi rcx, rdi
    jz .end

    mov rdx, rcx
    shl rdx, 1
    and rdx, r14
    and rcx, r14
    shr rcx, 1
    or rdx, rcx

    xor ecx, ecx
    test rdx, rsi
    setz cl
    add eax, ecx
    blsr rdi, rdi
    jmp .loop_head
.end:
    ret

; rdi - bb
; r14 - not a file
pawn_north:
    mov rax, rdi
    shl rdi, 9
    and rdi, r14
    and rax, r14
    shl rax, 7
    or rax, rdi
    ret

; rdi - bb
; r14 - not a file
pawn_south:
    mov rax, rdi
    shr rdi, 7
    and rdi, r14
    and rax, r14
    shr rax, 9
    or rax, rdi
    ret

%endif
