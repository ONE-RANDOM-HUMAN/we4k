const std = @import("std");
pub extern fn knight_moves(knights: u64) callconv(.SysV) u64;
pub extern fn knight_moves_occ(knights: u64, occ: u64) callconv(.SysV) u64;
pub extern fn bishop_moves(bishops: u64, occ: u64) callconv(.SysV) u64;
pub extern fn rook_moves(rooks: u64, occ: u64) callconv(.SysV) u64;
pub extern fn queen_moves(queens: u64, occ: u64) callconv(.SysV) u64;
pub extern fn king_moves(kings: u64) callconv(.SysV) u64;

extern fn gen_pseudo_legal_asm(board: *const Board, moves: [*]Move) callconv(.SysV) [*]Move;

const position = @import("board.zig");
const Board = position.Board;
const Move = position.Move;
const Piece = position.Piece;
const Square = position.Square;

pub inline fn gen_pseudo_legal(board: *const Board, buffer: *[256]Move) []Move {
    const start: [*]Move = buffer;
    const end = gen_pseudo_legal_raw(board, start);

    const len = (@ptrToInt(end) - @ptrToInt(start)) / @sizeOf(Move);
    return buffer[0..len];
}

pub fn gen_pseudo_legal_raw(board: *const Board, moves: [*]Move) [*]Move {
    return gen_pseudo_legal_asm(board, moves);
}

