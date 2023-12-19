const std = @import("std");
const board = @import("board.zig");

extern fn gen_pseudo_legal_asm(position: *const board.Board, moves: [*]board.Move) callconv(.SysV) [*]board.Move;


pub inline fn gen_pseudo_legal(position: *const board.Board, buffer: *[256]board.Move) []board.Move {
    const start: [*]board.Move = buffer;
    const end = gen_pseudo_legal_asm(position, start);

    const len = (@intFromPtr(end) - @intFromPtr(start)) / @sizeOf(board.Move);
    return buffer[0..len];
}
