const board = @import("board.zig");
const std = @import("std");
const linux = std.os.linux;

const TT_SIZE_BYTES: usize = 32 * 1024 * 1024;
const TT_SIZE: usize = TT_SIZE_BYTES / @sizeOf(u64);

pub const TTData = packed struct {
    best_move: board.Move,
    eval_mag: u16,
    eval_sign: u1,
    node_type: u2,
    depth: u13,
    hash: u16,

    pub const ZERO: TTData = @bitCast(@as(u64, 0));

    pub fn new(best_move: board.Move, _eval: i32, node_type: u2, depth: u32, hash: u64) TTData {
        return TTData {
            .best_move = best_move,
            .eval_mag = @intCast(@abs(_eval)),
            .eval_sign = @intCast(@as(u32, @bitCast(_eval)) >> 31),
            .node_type = node_type,
            .depth = @intCast(@min(depth, 1 << 13 - 1)),
            .hash = @intCast(hash >> 48),
        };
    }

    pub fn eval(self: TTData) i32 {
        if (self.eval_sign == 0) {
            return @as(i32, self.eval_mag);
        } else {
            return -@as(i32, self.eval_mag);
        }
    }

    pub fn is_zero(self: TTData) bool {
        return @as(u64, @bitCast(self)) == 0;
    }
};

comptime {
    std.debug.assert(@sizeOf(TTData) == 8);
}

pub const TT = extern struct {
    entries: *[TT_SIZE]u64,

    pub fn new() TT {
        const ptr = std.os.linux.mmap(
            null,
            TT_SIZE_BYTES,
            std.os.PROT.READ | std.os.PROT.WRITE,
            std.os.MAP.PRIVATE | std.os.MAP.ANONYMOUS,
            -1,
            0
        );

        // memory zeroed by MAP_ANONYMOUS
        return TT {
            .entries = @ptrFromInt(ptr),
        };
    }

    pub fn clear(self: *TT) void {
        std.mem.set(u64, self.entries, 0);
    }

    pub fn load(self: *const TT, position: *const board.Board) TTData {
        const hash = position.hash();
        const index = hash & (TT_SIZE - 1);

        const data: TTData = @bitCast(@atomicLoad(u64, &self.entries[index], .Unordered));
        if (data.hash == hash >> 48) {
            return data;
        } else {
            return TTData.ZERO;
        }
    }

    pub fn store(self: *const TT, position: *const board.Board, best_move: board.Move, eval: i32, node_type: u2, depth: u32) void {
        const hash = position.hash();
        const index = hash & (TT_SIZE - 1);

        const data = TTData.new(best_move, eval, node_type, depth, hash);
        @atomicStore(u64, &self.entries[index], @bitCast(data), .Unordered);
    }
};
