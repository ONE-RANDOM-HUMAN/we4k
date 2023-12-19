const std = @import("std");
const board = @import("board.zig");
const movegen = @import("movegen.zig");

  
extern fn evaluate_asm(position: *const board.Board) callconv(.SysV) Eval;

const Eval = extern struct {
    mg: i16,
    eg: i16,
};

pub const MAX_EVAL: i32 = 256 * 256 - 1;
pub const MIN_EVAL: i32 = -MAX_EVAL;

fn popcnt(bb: u64) i16 {
    return @as(i16, @popCount(bb));
}

pub fn evaluate(position: *const board.Board) i32 {
    var eval = evaluate_asm(position);
    const score = resolve(position, eval);

    return if (position.side_to_move == 0) score else -score;
}

fn resolve(position: *const board.Board, eval: Eval) i32 {
    const phase = popcnt(position.pieces[@intFromEnum(board.Piece.Knight)])
        + popcnt(position.pieces[@intFromEnum(board.Piece.Bishop)])
        + 2 * popcnt(position.pieces[@intFromEnum(board.Piece.Rook)])
        + 4 * popcnt(position.pieces[@intFromEnum(board.Piece.Queen)]);

    return @divTrunc(phase * @as(i32, eval.mg) + (24 - phase) * @as(i32, eval.eg), 24);
}
