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

MMAP equ 9
EXIT equ 60

TT_SIZE equ 32 * 1048576 ; update together with value in tt.rs
PROT_READ_OR_WRITE equ 3
MAP_PRIVATE_ANONYMOUS equ 22h
BOARD_LIST_SIZE equ Board_size * 4096

SECTION .text

global _start
_start:
    ; push rbx ; no need to save registers

    ; set up search
    push MMAP
    pop rax

    xor edi, edi
    mov rsi, TT_SIZE ; usi rsi for large tt
    push PROT_READ_OR_WRITE
    pop rdx
    push MAP_PRIVATE_ANONYMOUS
    pop r10
    push -1
    pop r8
    xor r9d, r9d
    syscall
    push rax ; tt

    ; add 6 qwords of 0
    push 6
    pop rcx
.gsearch_push_head:
    push 0 ; nodes
    loop .gsearch_push_head

    push MMAP
    pop rax
    
    mov esi, BOARD_LIST_SIZE
    syscall
    
    push rax
    push rax
    mov rbx, rsp
    sub rsp, 512 + 8 ; for alignment

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
    ; behave nicely for now
    mov dl, `\n`
    call read_until

    ; no need to fix stack

    ; call exit
    push 60
    pop rax
    xor edi, edi

    syscall
.i:
    mov rax, `readyok\n`
    call write8
    jmp .read_until_newline_end
.u:
    ; mov rdi, rbx
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
    ; mov rsi, rsp
    push rsp
    pop rsi
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
    call read

    ; rdi - time in ms - starts at 0 from previous syscall
    call parse_num

    pop rdx ; stack contains side to move
    push rdi ; time
    call read_until

    ; 'inc '
    push 4
    pop rdx
    call read

    ; rdi - inc in ms - starts at 0 from previous syscall
    call parse_num
    push rdi ; inc
    cmp al, `\n`
    je .g_parse_inc_end

    mov dl, `\n`
    call read_until
.g_parse_inc_end:
    ; call search
    pop rcx ; inc
    pop rdx ; time

    push rsp
    pop rsi

    push rbx
    pop rdi

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
    pext eax, eax, ecx

    push rsp
    pop rsi
    push rsi
    push rax
    mov rdi, qword[rbx]
    call gen_pseudo_legal_asm

    pop rax ; ax - origin and dest squares
    pop rsi ; rsi - move buffer
.p_find_move_loop_head:
    movzx edx, word [rsi] ; move from movegen
    mov ecx, edx
    and ch, 0000_1111b ; mask off bits
    cmp ecx, eax ; check that the squares match
    je .p_move_found
    add rsi, 2
    jmp .p_find_move_loop_head ; assume move will be found
.p_move_found:
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
    ; mov rsi, rsp
    push rsp
    pop rsi

    syscall
    pop rax
    pop rdx
    ret

; accumulates to rdi
; next char in al
parse_num:
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
    ; mov rsi, rsp
    push rsp
    pop rsi

    push 8
    pop rdx

    syscall
    pop rax
    ret


%endif
