%ifndef BOARD_ASM
%define BOARD_ASM

DEFAULT rel

%include "common.asm"
%include "movegen.asm"

SECTION .text

; rdi - board
; rsi - area
global board_is_area_attacked_asm
board_is_area_attacked_asm:
    movzx eax, byte [rdi + Board.side_to_move]
    xor al, 1

    ; enemy pieces - r8
    mov r8, qword [rdi + Board.colors + rax*8]

    mov r9, qword [rdi + Board.pawn]
    and r9, r8

    ; pawns

    ; get the correct rotates for a generalised shift
    ; a conditional jump would by 5 bytes shorter
    mov ecx, 0F9F7_0709h
    mov edx, ecx
    bswap edx 
    test al, al
    cmovnz ecx, edx ; enemy pawns are black

    mov rdx, qword [not_a_file]

    mov rax, r9
    rol r9, cl
    and r9, rdx

    and rax, rdx
    mov cl, ch
    rol rax, cl
    or r9, rax
    

    ; bishop like
    mov rdx, qword [rdi + Board.bishop]
    or rdx, qword [rdi + Board.queen]
    and rdx, r8

    ; occ
    mov rcx, qword [rdi + Board.white]
    or rcx, qword [rdi + Board.black]

    call bishop_moves
    or r9, rax

    ; rook like
    mov rdx, qword [rdi + Board.rook]
    or rdx, qword [rdi + Board.queen]
    and rdx, r8

    call rook_moves
    or r9, rax

    mov rdx, qword [rdi + Board.knight]
    and rdx, r8
    call knight_moves
    or r9, rax

    mov rdx, qword [rdi + Board.king]
    and rdx, r8
    call king_moves
    or r9, rax

    xor eax, eax
    test r9, rsi
    setnz al
    ret

global board_hash_asm
board_hash_asm:
    mov eax, dword [rdi + Board.fifty_moves]
    shr eax, 8 ; ignore fifty moves

    vmovd xmm0, eax
    mov ecx, Board.colors
.loop_head:
    vaesenc xmm0, xmm0, oword [rdi + rcx]
    sub rcx, 8
    jnc .loop_head
    vaesenc xmm0, xmm0, xmm0
    vaesenc xmm0, xmm0, xmm0
    vmovq rax, xmm0
    ret

global board_make_move
board_make_move:
    push rbx
    ; get masks for pieces
    movzx edx, byte [rdi + Board.side_to_move]
    lea r8, [rdi + Board.colors + rdx * 8] ; side_pieces
    xor dl, 1
    lea r9, [rdi + Board.colors + rdx * 8] ; enemy pieces

    call board_get_piece_asm
    xchg ebx, eax ; ebx origin piece - shorter than mov

    movzx r11d, si ; r11 move
    shr esi, 6
    bt esi, 6 + 2
    jnc .no_capture

    
    xor edx, edx
    bt esi, 6 + 3
    jc .no_ep
    test sil, (EN_PASSANT_CAPTURE - CAPTURE_FLAG) << 6
    jz .no_ep

    ; en passant capture
    ; rank moves from third (2) to fourth (3) for sixth to fifth
    mov al, 1000b
    xor eax, esi
    bts rdx, rax
    xor qword [rdi + Board.pawn], rdx
    jmp .capture_remove_color
.no_ep:
    call board_get_piece_asm
    bts rdx, rsi
    xor qword [rdi + Board.pieces + rax * 8], rdx
.capture_remove_color:
    xor qword [r9], rdx
.no_capture:
    xor ecx, ecx
    xor eax, eax
    bts rcx, r11 ; origin bb
    bts rax, rsi ; desination bb
    lea rdx, [rcx + rax] ; changed
    xor qword [r8], rdx

    bt esi, 6 + 3
    jc .promo
    xor qword [rdi + Board.pieces + rbx * 8], rdx
    jmp .end_promo
.promo:
    xor qword [rdi + Board.pawn], rcx
    shr esi, 6
    and esi, 11b
    xor qword [rdi + Board.pieces + rsi * 8 + 8], rax
.end_promo:
    ; do 50mr here to free up ebx
    inc byte [rdi + Board.fifty_moves]
    cmp ebx, PIECE_PAWN
    je .reset_fifty_moves

    bt r11d, 12 + 2
    jnc .end_reset_fifty_moves
.reset_fifty_moves:
    mov byte [rdi + Board.fifty_moves], 0
.end_reset_fifty_moves:
    ; last use of ebx for piece
    cmp ebx, PIECE_KING
    mov cl, 12
    shrx ebx, r11d, ecx ; ebx ; flags
    je .king_move

    ; rsi - location of king
    mov rsi, qword [rdi + Board.king]
    and rsi, qword [r8]
    jmp .end_king_move
.king_move:
    ; set king pos = dest
    mov rsi, rax

    ; remove castling rights
    mov cl, byte [rdi + Board.side_to_move]
    add cl, cl
    mov al, 1100b
    shr al, cl
    and [rdi + Board.castling], al

    ; common for castling
    mov eax, r11d
    shr eax, 6
    xor ecx, ecx
    inc eax
    bts rcx, rax

    cmp bl, QUEENSIDE_CASTLE
    je .queenside_castle
    cmp bl, KINGSIDE_CASTLE
    jne .end_king_move ; no castle
.kingside_castle:
    inc eax
.queenside_castle:
    sub al, 3
.castle_common:
    bts rcx, rax
    xor qword [rdi + Board.rook], rcx
    xor qword [r8], rcx
    lea rsi, [rdx + rcx] ; king and rook origin + dest
    ; would be 1 byte shorter with cx
    mov ecx, 7E7Eh ; ignore rook squares of 1 and h files
    ror rcx, 8
    and rsi, rcx
.end_king_move:
    push rdx
    call board_is_area_attacked_asm
    pop rdx
    xor al, 1
    jz .ret

    ; remove castling rights
    mov ax, 8181h ; top of rax guaranteed to be zero
    ror rax, 8
    pext rdx, rdx, rax ; rdx - origin | dest
    not edx
    and byte [rdi + Board.castling], dl

    ; set ep square
    mov al, 64
    cmp bl, DOUBLE_PAWN_PUSH
    jne .no_double_pawn_push

    mov eax, r11d
    shr eax, 6
    and al, 3Fh
    and r11b, 3Fh
    add eax, r11d
    shr al, 1
    and al, 3Fh
.no_double_pawn_push:
    mov byte [rdi + Board.ep], al

    mov al, 1
    xor byte [rdi + Board.side_to_move], al
.ret:
    pop rbx
    ret

; clobbers ecx, eax
; only requires low 6 bits of rsi
; guaranteed to return 6 if there is no piece
global board_get_piece_asm
board_get_piece_asm:
    xor ecx, ecx
    bts rcx, rsi
    xor eax, eax
.loop_head:
    test rcx, qword[rdi + rax * 8 + Board.pieces]
    jnz .end
    inc eax
    cmp al, 6
    jne .loop_head
.end:
    ret

%endif
