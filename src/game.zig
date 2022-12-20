const std = @import("std");
const board = @import("board.zig");

extern fn game_make_move(self: *Game, move: u16) callconv(.SysV) bool;

pub const Game = extern struct {
    // the current position, not one past the end
    // put first becaused it is accessed more often
    // and avoids the offset
    end: [*]board.Board,
    start: [*]board.Board,

    pub fn new() Game {
        // 4096 positions should be enough.
        const buffer = std.os.linux.mmap(
            null,
            @sizeOf(board.Board) * 4096,
            std.os.PROT.READ | std.os.PROT.WRITE,
            std.os.MAP.PRIVATE | std.os.MAP.ANONYMOUS,
            -1,
            0
        );

        // buffer
        const ptr = @intToPtr([*]board.Board, buffer);
        ptr[0] = board.Board.STARTPOS;
        return Game {
            .end = ptr,
            .start = ptr,
        };
    }

    pub fn reset(self: *Game) void {
        // first position must be startpos
        self.end = self.start;
    }

    pub fn position(self: *const Game) *const board.Board {
        return &self.end[0];
    }

    pub inline fn make_move(self: *Game, move: board.Move) bool {
        return game_make_move(self, @bitCast(u16, move));
    }

    pub fn unmake_move(self: *Game) void {
        self.end -= 1;
    }

    pub fn is_repetition(self: Game) bool {
        const current = self.position();
        var reps: u32 = 0;
        var ptr = self.end - 1;
        while (true) {
            if (ptr[0].repetition_eq(current)) {
                reps += 1;
                if (reps == 2) {
                    return true;
                }
            }

            // fifty_moves for startpos is 0, so we can
            // never go past the end
            if (ptr[0].fifty_moves == 0) {
                return false;
            }

            ptr -= 1;
        }
    }
};

