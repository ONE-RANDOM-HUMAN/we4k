
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

CLONE_THREAD_SIGHAND_VM equ 0x00010900
CLONE_SYSCALL equ 56
MUNMAP_SYSCALL equ 11

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

; args:
; rbx - search
; rdx - time
; rcx - inc
; clobbers all registers except rbx, rsp and rbp
search_begin_asm:
    ; stop panicking
    mov byte [rbx + Search.panicking], 0
    
    ; time management
    ; rdx - time
    ; rcx - inc
    add rcx, rdx ; time + inc
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

    sub rsp, 512 + 256 * SearchMove_size + 8 ; for alignment

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

    test ebp, ebp
    jz .not_main_thread ; no threads to create

    ; r12 number of moves
    cmp r12d, 1
    jbe .print_and_exit ; go to end if only 1 legal move on main thread

    ; set up extra threads
%if EXTRA_THREAD_COUNT > 0
    mov r13d, EXTRA_THREAD_COUNT
.thread_loop_head:
    mov esi, THREAD_STACK_SIZE
    call mmap

    add rax, THREAD_STACK_SIZE - BOARD_LIST_SIZE - Search_size

    ; copy the search
    push rbx ; search to copy from
    pop rsi

    push rax ; search to copy to
    pop rdi

    push Search_size
    pop rcx
    rep movsb
    
    ; rdi now contains game start
    mov qword [rax + Game.start], rdi
    mov rsi, qword [rbx + Game.start] ; pointer to copy from

    ; size - upper bits don't matter
    mov ecx, dword [rbx + Game.end]
    sub ecx, esi ; upper bits don't matter

    lea rdx, [rdi + rcx] ; end
    mov qword [rax + Game.end], rdi

    add ecx, Board_size ; required because end is not one past the end

    ; copy the boards
    rep movsb

    push rax ; stack
    pop rsi

    mov edi, CLONE_THREAD_SIGHAND_VM ; flags
    
    push CLONE_SYSCALL
    pop rax

    syscall
    test eax, eax ; least significant byte of a real thread id may be 0
    jz thread_search
    dec r13d
    jnz .thread_loop_head
%endif

.not_main_thread:
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
    test ebp, ebp
    jz .exit ; not main thread

%if EXTRA_THREAD_COUNT > 0
    ; stop other threads now
    or byte [rbx + Search_size], 0b1000_0000 ; thread data guaranteed to be there for main thread
.wait_loop_head:
    cmp byte [rbx + Search_size], 0b1000_0000  ; wait for threads to finish
    ja .wait_loop_head
%endif
    ; sort the moves
    push rsp ; pointer
    pop rdi
    push r13 ; searched
    pop rsi
    call search_moves_sort
.print_and_exit:
    mov edi, dword [rsp + SearchMove.move] ; the high bits can be anything
    call print_move_asm
.exit:
    add rsp, 512 + 256 * SearchMove_size + 8
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
    mov rdx, qword [rdi + Search.thread_data]
    cmp byte [rdx], 1000_0000b

    ; will be above since extra thread count > 0
    ja .end ; seta will return true

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
.end:
    seta al ; rest of eax is 0
    ret

thread_search:
    push rsp
    pop rbx

    ; time - the overflow won't matter because the multiplies are signed
    push -1
    pop rdx

    xor ecx, ecx ; inc

    xor ebp, ebp ; no threads
    call search_begin_asm

    mov rdx, qword [rsp + Search.thread_data]
    lock dec byte [rdx] ; decrement thread count

    push EXIT_SYSCALL
    pop rbx ; save value

    ; unmap stack
    lea rdi, [rsp - (THREAD_STACK_SIZE - BOARD_LIST_SIZE - Search_size)]
    mov esi, THREAD_STACK_SIZE
    push MUNMAP_SYSCALL
    pop rax
    syscall

    xchg eax, ebx
    syscall ; exit
%endif
