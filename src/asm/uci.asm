%ifndef UCI_ASM
%define UCI_ASM

DEFAULT rel

%include "common.asm"
%include "game.asm"
%include "search.asm"

SECTION .rodata
startpos_piece_placement:
    dq 0x00FF_0000_0000_FF00
    dq 0x4200_0000_0000_0042
    dq 0x2400_0000_0000_0024
    dq 0x8100_0000_0000_0081
    dq 0x0800_0000_0000_0008
    dq 0x1000_0000_0000_0010
    dq 0x0000_0000_0000_FFFF
    dq 0xFFFF_0000_0000_0000
    dd 400F0000h

CLOCK_GETTIME equ 228
CLOCK_MONOTONIC equ 1


TT_SIZE equ 32 * 1048576 ; update together with value in tt.zig
SECTION .text

global _start
_start:
    ; set up search
    push 0
    push rsp ; stop now

    mov rsi, TT_SIZE ; using rsi for large tt
    call mmap
    push rax ; tt

    ; add 6 qwords of 0
    push 6
    pop rcx
.gsearch_push_head:
    push 0
    loop .gsearch_push_head

    push MMAP_SYSCALL
    pop rax
    
    mov esi, BOARD_LIST_SIZE
    syscall
    
    push rax
    push rax
    push rsp
    pop rbx
    sub rsp, 512 + 8

    push rax
    pop rdi
    lea rsi, [startpos_piece_placement]

    push Board_size
    pop rcx
    rep movsb

    mov dl, `\n`
    call read_until

    mov rax, `uciok  \n`
    call write8

.loop_head:
    call read_char
    cmp al, 'p'
    je .p
    cmp al, 'g'
    je .g
    cmp al, 'q'
    jb .i
    ja .u

    ; quit
    ; behave nicely for now and don't leave 'uit'
    mov dl, `\n`
    call read_until

    ; no need to fix stack
.quit:
    push EXIT_SYSCALL
    pop rax
    xor edi, edi

    syscall
.i:
    mov rax, `readyok\n`
    call write8
    jmp .read_until_newline_end
.u:
    ; zero hash
    mov rdi, qword [rbx + Search.tt]
    xor eax, eax
    mov rcx, TT_SIZE ; use rcx for large tt
    rep stosb
.read_until_newline_end:
    mov dl, `\n`
    call read_until
    jmp .loop_head
.g:
    mov eax, CLOCK_GETTIME
    push CLOCK_MONOTONIC
    pop rdi
    lea rsi, [rbx + Search.start_time] ; read directly into search
    syscall

    ; set dl to letter for side to move
    mov rax, qword[rbx]

    push 'w'
    pop rdx
    cmp byte [rax + Board.side_to_move], 0
    je .g_white_to_move

    mov dl, 'b'
.g_white_to_move:
    push rdx ; save side to move
    call read_until ; no need to align stack

    ; ignore 'time '
    push 5
    pop rdx
    call read_parse_num

    pop rdx ; stack contains side to move
    push rdi ; time
    call read_until

    ; 'inc '
    push 4
    pop rdx

    call read_parse_num

    push rdi ; inc
    cmp al, `\n`
    je .g_parse_inc_end

    mov dl, `\n`
    call read_until
.g_parse_inc_end:
    ; call search

    ; don't stop now + set thread count
    mov byte [rbx + Search_size], EXTRA_THREAD_COUNT

    ; indicate main thread
    push 1
    pop rbp

    pop rcx ; inc
    pop rdx ; time


    ; rbx - search
    ; rdx - time
    ; rcx - inc
    call search_begin_asm
    jmp .loop_head
.p:
    ; reset the position
    mov rdi, qword [rbx + 8]
    mov qword [rbx], rdi
         
    ; ignore 'osition startpos'
    push 16
    pop rdx
    call read

    call read_char
    cmp al, `\n`
    je .loop_head

    ; ignore 'moves ' 
    push 6
    pop rdx
    call read
.p_loop_head:
    push 4
    pop rdx
    call read

    ; origin and dest squares in ax
    sub eax, 'a1a1'
    mov ecx, 07070707h
    pext ebp, eax, ecx

    push rsp
    pop rsi
    mov rdi, qword[rbx]
    call gen_pseudo_legal_asm

    xor eax, eax
.p_find_move_loop_head:
    movzx edx, word [rsp + 2*rax] ; move from movegen
    mov ecx, edx
    and ch, 0000_1111b ; mask off bits
    inc eax
    cmp ecx, ebp ; check that the squares match
    jne .p_find_move_loop_head ; assume move will be found
    
    ; move found
    test dh, PROMO_FLAG << 4
    jz .p_no_promo

    ; promo
    and dh, 11001111b ; remove promo piece
    push rdx ; origin and dest
    call read_char ; alignment not necessary
    pop rdx
    
    ; promo piece in dh
    cmp al, 'n'
    je .p_knight_promo
    cmp al, 'q'
    je .p_queen_promo
    jb .p_bishop_promo
    or dh, 01b << 4 ; rook promo
.p_queen_promo:
    xor dh, 10b << 4
.p_bishop_promo:
    xor dh, 01b << 4
.p_knight_promo:
.p_no_promo:
    push rbx
    pop rdi
    mov esi, edx
    call game_make_move

    call read_char
    cmp al, `\n`
    jne .p_loop_head
    jmp .loop_head

; value - dl
read_until:
    push rbx
    mov bl, dl

.loop_head:
    call read_char
    cmp al, bl
    jne .loop_head

    pop rbx
    ret

; clobbers rax, rcx, rdx = 0, rdi = 0, rsi, r11
; rest of rax guaranteed to be 0
read_char:
    push 1
    pop rdx
    ; no need to jump because read is next

    ; jmp read

; len: rdx, up to 16 bytes
; read up to 16 bytes into rdx:rax
; rest of the bytes are zeroed
; clobbers rdi, rsi, rcx, r11
read:
    xor eax, eax
    push rax
    push rax

    xor edi, edi
    push rsp
    pop rsi

    syscall
    pop rax
    pop rdx
    ret

; reads rdx characters, then parses number into rdi
; next char in al
read_parse_num:
    call read
    ; rdi = 0 from read
.loop_head:
    push rdi
    call read_char
    pop rdi

    cmp al, '0'
    jb .end

    ; rest of rax guaranteed to be 0
    ; should never exceed 32 bits
    lea edx, [rdi * 2 + rax - '0']
    lea edi, [rdi * 8 + rdx]
    jmp .loop_head
.end:
    ret

; writes 8 bytes of data specified in rax
write8:
    push rax

    ; syscall 1
    push 1
    pop rax

    ; stdout fd
    mov edi, eax

    ; pointer
    push rsp
    pop rsi

    push 8
    pop rdx

    syscall
    pop rax
    ret


%endif
