const std = @import("std");
const movegen = @import("movegen.zig");

extern fn board_is_area_attacked_asm(board: *const Board, area: u64) callconv(.SysV) bool;
extern fn board_hash_asm(board: *const Board) callconv(.SysV) u64;
extern fn board_make_move(board: *Board, move: u16) callconv(.SysV) bool;
extern fn board_get_piece_asm(board: *const Board, square: u8) callconv(.SysV) u8;

pub const Board = extern struct {
    pieces: [6]u64,
    colors: [2]u64,
    fifty_moves: u8,
    side_to_move: u8,
    castling: u8,
    ep: u8,

    // we don't need to care about the full move counter
    pub const STARTPOS = Board {
            .pieces =  [6]u64{
                0x00FF_0000_0000_FF00,
                0x4200_0000_0000_0042,
                0x2400_0000_0000_0024,
                0x8100_0000_0000_0081,
                0x0800_0000_0000_0008,
                0x1000_0000_0000_0010,
            },
            .colors = [2]u64{
                0x0000_0000_0000_FFFF,
                0xFFFF_0000_0000_0000,
            },
            .fifty_moves =  0,
            .side_to_move =  0,
            .castling = 0b1111,
            .ep = 64
    };

    pub inline fn get_piece_unchecked(self: *const Board, sq: Square) Piece {
        return @enumFromInt(board_get_piece_asm(self, @intFromEnum(sq)));
    }

    pub inline fn get_piece_index(self: *const Board, sq: Square) u8 {
        // somehow it is slightly smaller when not inline
        return board_get_piece_asm(self, @intFromEnum(sq));
    }

    pub inline fn make_move(self: *Board, move: Move) bool {
        return board_make_move(self, @bitCast(move));
    }

    pub fn repetition_eq(self: *const Board, other: *const Board) bool {
        const eql = @import("std").mem.eql;

        return eql(u64, @as(*const [8]u64, @ptrCast(self)), @as(*const [8]u64, @ptrCast(other)))
            and self.side_to_move == other.side_to_move
            and self.castling == other.castling
            and self.ep == other.ep;
    }

    pub inline fn is_check(self: *const Board) bool {
        return self.is_area_attacked(self.pieces[@intFromEnum(Piece.King)] & self.colors[self.side_to_move]);
    }

    pub inline fn hash(self: *const Board) u64 {
        return board_hash_asm(self);
    }

    inline fn is_area_attacked(self: *const Board, area: u64) bool {
        return board_is_area_attacked_asm(self, area);
    }
};

pub const Square = enum(u6) {
    A1, B1, C1, D1, E1, F1, G1, H1,
    A2, B2, C2, D2, E2, F2, G2, H2,
    A3, B3, C3, D3, E3, F3, G3, H3,
    A4, B4, C4, D4, E4, F4, G4, H4,
    A5, B5, C5, D5, E5, F5, G5, H5,
    A6, B6, C6, D6, E6, F6, G6, H6,
    A7, B7, C7, D7, E7, F7, G7, H7,
    A8, B8, C8, D8, E8, F8, G8, H8,

    pub fn to_bb(self: Square) u64 {
        return @as(u64, 1) << @intFromEnum(self);
    }

    pub fn offset(self: Square, off: i8) Square {
        return @enumFromInt(@as(i8, @intFromEnum(self)) + off);
    }
};

pub const Piece = enum(u3) {
    Pawn,
    Knight,
    Bishop,
    Rook,
    Queen,
    King,
};

pub const SPECIAL_ONE_FLAG: u4 = 0b0001;
pub const SPECIAL_TWO_FLAG: u4 = 0b0010;
pub const CAPTURE_FLAG: u4 = 0b0100;
pub const PROMO_FLAG: u4 = 0b1000;


pub const DOUBLE_PAWN_PUSH: u4 = SPECIAL_ONE_FLAG;
pub const EN_PASSANT_CAPTURE: u4 = CAPTURE_FLAG | SPECIAL_ONE_FLAG;
pub const KINGSIDE_CASTLE: u4 = SPECIAL_TWO_FLAG;
pub const QUEENSIDE_CASTLE: u4 = SPECIAL_TWO_FLAG | SPECIAL_ONE_FLAG;

pub const Move = packed struct {
    origin: Square,
    destination: Square,
    flags: u4,

    pub const ZERO: Move = @bitCast(@as(u16, 0));

    pub fn is_noisy(self: Move) bool {
        return self.flags & (CAPTURE_FLAG | PROMO_FLAG) != 0;
    }

    pub inline fn eql(lhs: Move, rhs: Move) bool {
        return @as(u16, @bitCast(lhs)) == @as(u16, @bitCast(rhs));
    }
};
