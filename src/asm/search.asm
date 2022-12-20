
%ifndef SEARCH_ASM
%define SEARCH_ASM

DEFAULT rel

%include "common.asm"

WRITE_SYSCALL equ 1
STDOUT_FD equ 1

CLOCK_GETTIME equ 228
CLOCK_MONOTONIC equ 1

NS_IN_MS equ 1000000

MAX_EVAL equ 65535
EVAL_PANIC_MARGIN equ 128

extern search_alpha_beta

SECTION .text
global print_move_asm
print_move_asm:
    ; lowest 3 bits of each byte
    mov eax, 07070707h
    pdep edx, edi, eax
    add edx, "a1a1"

    mov al, ' '

    ; shift so that the promo piece is 3 bits from the lowest
    ; and already multiplied by 8
    shr edi, 12 - 3
    test dil, PROMO_FLAG << 3
    jz .no_promo
    mov cl, 11000b
    and ecx, edi ; saves REX prefix
    mov eax, 'nbrq'
    shr eax, cl
.no_promo:
    ; mov rcx, ` \0\0\0\0 \n`
    mov ecx, ` \n\0 ` ; one byte shorter than mov
    ror rcx, 24
    push rcx

    mov dword [rsp + 1], edx
    mov byte [rsp + 5], al
    mov rax, "bestmove" 
    push rax

    push WRITE_SYSCALL
    pop rax

    ; push STDOUT_FD
    push rax ; STDOUT_FD == WRITE_SYSCALL == 1
    pop rdi

    push 0Fh
    pop rdx

    push rsp
    pop rsi

    syscall
    pop rax
    pop rax
    ret

global search_begin_asm
search_begin_asm:
    push rbx
    push r15
    push r14
    push r13
    push r12
    
    
    push rdi
    pop rbx ; search

    push rcx
    pop rax ; inc

    push 16
    pop rcx
    add rdi, Search.start_time ; start time for struct

    ; rsi - start time from args
    rep movsb

    ; stor panicking
    mov byte [rbx + Search.panicking], 0
    
    ; time management
    ; rdx - time
    ; rax - inc
    lea rcx, [rdx + rax] ; rcx - time + inc
    imul rdi, rdx, NS_IN_MS / 2
    imul rsi, rcx, NS_IN_MS / 30
    cmp rdi, rsi
    cmova rdi, rsi ; take the minimum
    mov qword [rbx + Search.stop_time], rdi

    imul rdi, rdx, (2 * NS_IN_MS) / 3
    imul rsi, rcx, NS_IN_MS / 10
    cmp rdi, rsi
    cmova rdi, rsi ; take the minimum
    mov qword [rbx + Search.panic_stop_time], rdi

    sub rsp, 512 + 256 * SearchMove_size

    ; gen moves
    mov rdi, qword [rbx + Game.end] ; board

    lea r14, [rsp + 256 * SearchMove_size] ; r14 - move buffer
    push r14
    pop rsi
    call gen_pseudo_legal_asm


    push rax
    pop r15 ; r15 - end of move buffer

    ; find legal moves
    xor r12d, r12d ; curr move
.legal_move_select_loop_head:
    ; make the move
    push rbx ; game
    pop rdi

    movzx esi, word [r14] ; move
    call game_make_move
    test al, al
    jz .legal_move_select_loop_tail ; move was illegal
    
    movzx eax, word [r14] ; move
    mov dword [rsp + SearchMove_size*r12 + SearchMove.move], eax ; moving 4 bytes is fine

    ; qsearch
    push Board_size ; used for unmake move
    push 0 ; killer table

    push rbx ; search
    pop rdi
    mov esi, MAX_EVAL
    mov edx, esi ; beta
    neg esi ; alpha
    push -1
    pop rcx ; depth
    push rsp
    pop r8 ; killer table
    call search_alpha_beta

    neg eax
    
    pop rcx
    pop rcx ; Board_size

    mov dword [rsp + SearchMove_size*r12 + SearchMove.eval], eax
    sub qword [rbx + Game.end], rcx ; unmake move
    inc r12 ; curr move
.legal_move_select_loop_tail:
    add r14, 2
    cmp r14, r15
    jne .legal_move_select_loop_head

    ; r12 number of moves
    cmp r12d, 1
    jbe .print_and_exit

    push 1
    pop r14 ; depth
.iterative_deepening_loop_head:
    xor r13d, r13d ; move num = searched = 0
    mov byte [rbx + Search.panicking], 0 ; stop panicking

    push rsp ; pointer
    pop rdi
    push r12 ; number of moves
    pop rsi
    call search_moves_sort

    mov edx, dword [rsp + SearchMove.eval] ; last best
    mov r15d, -MAX_EVAL ; alpha
    xor edi, edi ; kt out
.root_search_loop_head:
    mov esi, dword [rsp + r13*8 + SearchMove.move]

    push rdx ; last best
    push rdi ; kt
    
    push rbx
    pop rdi
    call game_make_move

    push rbx ; search
    pop rdi
    mov esi, -MAX_EVAL ; -beta
    push r15 ; -alpha
    pop rdx
    neg edx
    push r14 ; depth
    pop rcx
    push rsp ; kt
    pop r8 ; kt
    call search_alpha_beta
    pop rdi ; kt
    pop rdx ; last best

    ; pop rsi
    sub qword [rbx + Game.end], Board_size ; unmake move
    
    neg eax
    jo .iterative_deepening_loop_end

    mov dword [rsp + r13*8 + SearchMove.eval], eax ; mov.eval = score
    cmp r15d, eax ; alpha
    cmovl r15d, eax 

    ; set panicking
    xor eax, eax
    cmp r14d, 4 ; depth
    jae .no_panic
    lea esi, [rdi - EVAL_PANIC_MARGIN]
    cmp r15d, esi
    ja .no_panic
    inc eax ; panic
.no_panic:
    mov byte [rbx + Search.panicking], al

    ; increment searched
    inc r13d
    cmp r13d, r12d
    jne .root_search_loop_head
    inc r14d
    jmp .iterative_deepening_loop_head
.iterative_deepening_loop_end:
    ; sort the moves
    push rsp ; pointer
    pop rdi
    push r13 ; searched
    pop rsi
    call search_moves_sort
.print_and_exit:
    mov edi, dword [rsp + SearchMove.move] ; the high bits can be anything
    call print_move_asm

    add rsp, 512 + 256 * SearchMove_size
    pop r12
    pop r13
    pop r14
    pop r15
    pop rbx
    ret

search_moves_sort:
    push 1
    pop rax ; outer loop counter
.outer_loop_head:
    cmp eax, esi
    jae .end

    mov r8, qword [rdi + rax * 8] ; element to be inserted
    mov edx, eax ; inner loop counter
.inner_loop_head:
    mov r9, qword [rdi + rdx * 8 - 8]
    cmp r8d, r9d ; compare evals
    jle .inner_loop_end

    mov qword [rdi + rdx * 8], r9 ; move the element
    dec edx
    jnz .inner_loop_head
.inner_loop_end:
    mov qword [rdi + rdx * 8], r8 ; insert the element
    inc eax
    jmp .outer_loop_head
.end:
    ret

global search_should_stop_asm
search_should_stop_asm:
    push rdi ; save pointer
    pop rdx
    
    mov eax, CLOCK_GETTIME
    push CLOCK_MONOTONIC
    pop rdi

    push rax ; reserve 16 bytes on stack
    push rax
    push rsp
    pop rsi
    syscall

    pop rax
    sub rax, qword [rdx + Search.start_tv_sec]
    imul rcx, rax, 1_000_000_000 ; get ns

    pop rsi

    add rcx, rsi
    sub rcx, qword [rdx + Search.start_tv_nsec]

    movzx eax, byte [rdx + Search.panicking]
    cmp rcx, qword [rdx + Search.stop_time + rax * 8]
    seta al ; rest of eax is 0
    ret

%endif
