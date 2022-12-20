const board = @import("board.zig");
const std = @import("std");

pub extern fn order_noisy_moves_asm(position: *const board.Board, ptr: [*]board.Move, len: usize) callconv(.SysV) usize;

pub fn order_noisy_moves(moves: []board.Move, position: *const board.Board) usize {
    return order_noisy_moves_asm(position, moves.ptr, moves.len);
}

pub fn order_quiet_moves(_moves: []board.Move, position: *const board.Board, kt: KillerTable) void {
    var i: usize = 0;
    var moves = _moves;
    while (i < 4 and kt.killers[i] != 0) : (i += 1) {
        const index = for (moves) |move, index| {
            if (move.eql(@bitCast(board.Move, kt.killers[i]))) break index;
        } else continue;

        moves[index] = moves[0];
        moves[0] = @bitCast(board.Move, kt.killers[i]);
        moves = moves[1..];
    }

    _ = position;
}


pub const KillerTable = extern struct {
    killers: [4]u16,

    pub const EMPTY = KillerTable {
        .killers = [4]u16 { 0, 0, 0, 0 }
    };

    pub fn beta_cutoff(self: *KillerTable, move: board.Move) void {
        const value = @bitCast(u16, move);
        var i: usize = 0;
        while (i < 4) : (i += 1) {
            if (self.killers[i] == 0) {
                self.killers[i] = value;
                return;
            } else if (self.killers[i] == value) {
                if (i != 0) {
                    self.killers[i] = self.killers[i - 1];
                    self.killers[i - 1] = value;
                }

                return;
            }
        }

        self.killers[3] = value;
    }
};
