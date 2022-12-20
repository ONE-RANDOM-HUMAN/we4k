%ifndef GAME_ASM
%define GAME_ASM

DEFAULT rel

%include "common.asm"
%include "board.asm"

SECTION .text
global game_make_move
game_make_move:
    push rbx
    mov rdx, qword [rdi + Game.end]
    lea rbx, [rdx + Board_size]
    
    vmovdqu ymm0, yword [rdx]
    vmovdqu yword [rbx], ymm0
    vmovdqu ymm0, yword [rdx + 32]
    vmovdqu yword [rbx + 32], ymm0
    mov edx, dword [rdx + 64]
    mov dword [rbx + 64], edx

    ; preserves rdi
    xchg rdi, rbx
    call board_make_move
    test al, al
    jz .illegal
    mov qword [rbx + Game.end], rdi
.illegal:
    pop rbx
    ret
%endif
