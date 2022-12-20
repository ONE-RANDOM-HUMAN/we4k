%ifndef MOVEORDER_ASM
%define MOVEORDER_ASM

DEFAULT rel
%include "common.asm"
%include "board.asm"

SECTION .text
global order_noisy_moves_asm

; rdi board
; rsi moves
; rdx len
order_noisy_moves_asm:
    cmp rdx, 1
    jna .ret_now

    push rbx
    push rbp
    push r15
    push r14
    push r13
    push r12

    mov rbx, rsi
    mov ebp, edx
    lea r15, [flags_numerical]
    call insertion_sort
    
    xor edx, edx
.promo_loop_head:
    test word [rbx + rdx * 2], PROMO_FLAG << 12
    jz .promo_loop_end

    inc edx
    cmp edx, ebp
    jne .promo_loop_head
    xor edx, edx ; default
.promo_loop_end:
    mov eax, edx
.noisy_loop_head:
    test word [rbx + rax * 2], (PROMO_FLAG | CAPTURE_FLAG) << 12
    jz .noisy_loop_end

    inc eax
    cmp eax, ebp
    jne .noisy_loop_head
    mov eax, edx ; default
.noisy_loop_end:
    mov r14d, eax

    lea rbx, [rbx + rdx * 2] ; moves + promo
    mov ebp, eax
    sub ebp, edx ; noisy - promo

    cmp ebp, 1
    jna .no_sort_noisy

    add r15, mvv_lva - flags_numerical
    call insertion_sort

    mov eax, r14d
.no_sort_noisy:
    pop r12
    pop r13
    pop r14
    pop r15
    pop rbp
    pop rbx
.ret_now:
    ret


; rbx - ptr
; rbp - len (must be >= 2)
; r15 - fn ptr (system v but no stack alignment and must preserve r10 and r11)
; rdi - context
insertion_sort:
    mov r10d, 1 ; r10 - outer loop counter
.outer_loop_head:
    movzx r12d, word [rbx + r10 * 2] ; r12 - current value being inserted
    mov r11d, r10d ; r11 - inner loop counter
.inner_loop_head:
    movzx r13d, word [rbx + r11 * 2 - 2]

    mov esi, r12d
    mov edx, r13d
    call r15
    test al, al
    jz .inner_loop_end

    mov word [rbx + r11 * 2], r13w

    dec r11d
    jnz .inner_loop_head
.inner_loop_end:
    mov word [rbx + r11 * 2], r12w

    inc r10d
    cmp r10d, ebp
    jne .outer_loop_head

    ret

flags_numerical:
    shr esi, 12
    shr edx, 12
    cmp esi, edx
    seta al
    ret

mvv_lva:
    push rbx
    call board_get_piece_asm
    mov ebx, eax
    
    shr esi, 6
    call  board_get_piece_asm
    shl eax, 3
    sub ebx, eax ; -(8 * victim - attacker)

    mov esi, edx
    call board_get_piece_asm
    mov edx, eax

    shr esi, 6
    call board_get_piece_asm
    shl eax, 3
    sub edx, eax

    cmp ebx, edx
    setl al ; less because they are both negative

    pop rbx
    ret

%endif
