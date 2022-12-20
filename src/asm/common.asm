%ifndef STRUCTS_ASM
%define STRUCTS_ASM

struc Board
    alignb 8
    .pieces:
    .pawn:
        resq 1
    .knight:
        resq 1
    .bishop:
        resq 1
    .rook:
        resq 1
    .queen:
        resq 1
    .king:
        resq 1
        alignb 8
    .colors: 
    .white:
        resq 1
    .black:
        resq 1
    .fifty_moves: resb 1
    .side_to_move: resb 1
    .castling: resb 1
    .ep: resb 1
    alignb 8
endstruc

struc Game
    alignb 8
    .end:
        resq 1
    .start:
        resq 1
endstruc


struc Search
    alignb 8
    .game:
        resq 2
    .start_time:
    .start_tv_sec:
        resq 1
    .start_tv_nsec:
        resq 1
    .stop_time:
        resq 1
    .panic_stop_time:
        resq 1
    .panicking:
        resb 1
    .nodes:
        alignb 8
        resq 1
    .tt:
        resq 1
    alignb 8
endstruc

struc SearchMove
    alignb 4
    .eval:
        resd 1
    .move:
        resw 1
    alignb 4
endstruc

SECTION .rodata
alignb 8
all_mask:
    dq 0FFFF_FFFF_FFFF_FFFFh
not_a_file:
    dq ~0101_0101_0101_0101h
not_h_file:
    dq ~8080_8080_8080_8080h
not_ab_file:
    dq ~0303_0303_0303_0303h
not_gh_file:
    dq ~0C0C0_C0C0_C0C0_C0C0h

PIECE_PAWN equ 0
PIECE_KNIGHT equ 1
PIECE_BISHOP equ 2
PIECE_ROOK equ 3
PIECE_QUEEN equ 4
PIECE_KING equ 5
%endif
