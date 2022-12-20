const std = @import("std");
const board = @import("board.zig");
const movegen = @import("movegen.zig");

  
extern fn evaluate_asm(position: *const board.Board) callconv(.SysV) Eval;

const Eval = extern struct {
    mg: i16,
    eg: i16,

    fn zero() Eval {
        return Eval {
            .mg = 0,
            .eg = 0,
        };
    }

    fn accum(self: *Eval, other: Eval) void {
        self.mg += other.mg;
        self.eg += other.eg;
    }
    
    fn naccum(self: *Eval, other: Eval) void {
        self.mg -= other.mg;
        self.eg -= other.eg;
    }

    fn mul(self: Eval, v: i16) Eval {
        return Eval {
            .mg = self.mg * v,
            .eg = self.eg * v,
        };
    }
};

pub const MAX_EVAL: i32 = 256 * 256 - 1;
pub const MIN_EVAL: i32 = -MAX_EVAL;

fn e(mg: i16, eg: i16) Eval {
    return Eval {
        .mg = mg,
        .eg = eg,
    };
}

const NOT_A_FILE = ~@as(u64, 0x0101_0101_0101_0101);

fn popcnt(bb: u64) i16 {
    return @as(i16, @popCount(bb));
}

fn material(position: *const board.Board) Eval {
    const weights = [5]Eval{
        e( 200,  256),
        e( 800,  800),
        e( 816,  816),
        e(1344, 1344),
        e(2496, 2496),
    };
    
    var i: usize = 0;
    var eval = Eval.zero();
    while (i < 5) : (i += 1) {
        const count = popcnt(position.pieces[i] & position.colors[0])
            - popcnt(position.pieces[i] & position.colors[1]);
        
        eval.accum(weights[i].mul(count));
    }

    return eval;
}

fn piece_mobility(_pieces: u64, occ: u64, squares: u64, movement: *const fn(u64, u64) callconv(.SysV) u64) i16 {
    var pieces = _pieces;
    var mob: i16 = 0;

    while (pieces != 0) {
        const square = pieces & -%pieces;
        mob += popcnt(movement(square, occ) & squares);
        pieces ^= square;
    }
    return mob;
}

fn side_mobility(position: *const board.Board, squares: u64, side: u8) [4]i16 {
    const occ = position.colors[0] | position.colors[1];
    var mob = [4]i16{ 0, 0, 0, 0 };

    const pieces = [4]u64 {
        position.pieces[@enumToInt(board.Piece.Knight)] & position.colors[side],
        position.pieces[@enumToInt(board.Piece.Bishop)] & position.colors[side],
        position.pieces[@enumToInt(board.Piece.Rook)] & position.colors[side],
        position.pieces[@enumToInt(board.Piece.Queen)] & position.colors[side],
    };

    const fns = [4]*const fn(u64, u64) callconv(.SysV) u64 {
        movegen.knight_moves_occ,
        movegen.bishop_moves,
        movegen.rook_moves,
        movegen.queen_moves,
    };

    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        mob[i] = piece_mobility(pieces[i], occ, squares, fns[i]);
    }

    return mob;
}

fn mobility(position: *const board.Board) Eval {
    const weights = [4]Eval {
        e(32, 32),
        e(16, 32),
        e(16, 16),
        e( 8,  8),
    };

    var mob: [4]i16 = undefined;
    {
        const black_pawns = position.pieces[@enumToInt(board.Piece.Pawn)] & position.colors[1];
        const pawn_attacked = ((black_pawns >> 7) & NOT_A_FILE)
            | (black_pawns & NOT_A_FILE) >> 9;

        mob = side_mobility(position, ~pawn_attacked, 0);
    }

    {
        const white_pawns = position.pieces[@enumToInt(board.Piece.Pawn)] & position.colors[0];
        const pawn_attacked = ((white_pawns << 9) & NOT_A_FILE)
            | (white_pawns & NOT_A_FILE) << 7;

        
        const bmob = side_mobility(position, ~pawn_attacked, 1);
        mob[0] -= bmob[0];
        mob[1] -= bmob[1];
        mob[2] -= bmob[2];
        mob[3] -= bmob[3];
    }

    var eval = Eval.zero();
    eval.accum(weights[0].mul(mob[0]));
    eval.accum(weights[1].mul(mob[1]));
    eval.accum(weights[2].mul(mob[2]));
    eval.accum(weights[3].mul(mob[3]));
    return eval;
}

fn bishop_pair(position: *const board.Board) Eval {
    const bishops = position.pieces[@enumToInt(board.Piece.Bishop)];
    const white_bishops = position.colors[0] & bishops;
    const black_bishops = position.colors[1] & bishops;

    const LIGHT_SQUARES: u64 = 0x55AA_55AA_55AA_55AA;
    const white_bishop_pair = (white_bishops & LIGHT_SQUARES) != 0
        and (white_bishops & ~LIGHT_SQUARES) != 0;

    
    const black_bishop_pair = (black_bishops & LIGHT_SQUARES) != 0
        and (black_bishops & ~LIGHT_SQUARES) != 0;

    if (white_bishop_pair == black_bishop_pair) {
        return Eval.zero();
    } else if (white_bishop_pair) {
        return e(128, 128);
    } else {
        return e(-128, -128);
    }
}


fn pawn_spans(bb: u64) [2]u64 {
    var north = bb;
    north |= north << 8;
    north |= north << 16;
    north |= north << 32;

    var south = bb;
    south |= south >> 8;
    south |= south >> 16;
    south |= south >> 32;

    return [2]u64{ north, south };
}

fn isolated_count(_pawns: u64, pawn_files: u64) i16 {
    var result: i16 = 0;
    var pawns = _pawns;
    while (pawns != 0) {
        const pawn = pawns & -%pawns;
        const adjacent = ((pawn << 1) & NOT_A_FILE) | ((pawn & NOT_A_FILE) >> 1);
        if (adjacent & pawn_files == 0) {
            result += 1;
        }

        pawns &= pawns - 1;
    }

    return result;
}


fn pawn_eval(position: *const board.Board) Eval {
    const DOUBLED = e(-32, -96);
    const BACKWARD = e(0, -32);
    const ISOLATED = e(-32, -64);

    const PASSED = [6]Eval {
        e(32, 64),
        e(48, 80),
        e(64, 96),
        e(80, 112),
        e(96, 128),
        e(128, 256),
    };

    const white_pawns = position.pieces[@enumToInt(board.Piece.Pawn)] & position.colors[0];
    const black_pawns = position.pieces[@enumToInt(board.Piece.Pawn)] & position.colors[1];

    const w_spans = pawn_spans(white_pawns);
    const b_spans = pawn_spans(black_pawns);

    var eval = ISOLATED.mul(
        isolated_count(white_pawns, w_spans[0] | w_spans[1])
            - isolated_count(black_pawns, b_spans[0] | b_spans[1])
    );

    eval.accum(DOUBLED.mul(
        popcnt(white_pawns & (w_spans[1] >> 8))
            - popcnt(black_pawns & (b_spans[0] << 8))
    ));

    const w_stops = white_pawns << 8;
    const w_attack_spans = ((w_spans[0] << 9) & NOT_A_FILE) | ((w_spans[0] & NOT_A_FILE) << 7);
    const b_attacks = ((black_pawns >> 7) & NOT_A_FILE) | ((black_pawns & NOT_A_FILE) >> 9);

    const b_stops = black_pawns >> 8;
    const b_attack_spans = ((b_spans[1] >> 7) & NOT_A_FILE) | ((b_spans[1] & NOT_A_FILE) >> 9);
    const w_attacks = ((white_pawns << 9) & NOT_A_FILE) | ((white_pawns & NOT_A_FILE) << 7);

    eval.accum(BACKWARD.mul(
        popcnt(w_stops & ~w_attack_spans & b_attacks)
            - popcnt(b_stops & ~b_attack_spans & w_attacks)
    ));

    const white_passed = white_pawns & ~((w_spans[1] >> 8) | b_spans[1] | b_attack_spans);
    {
        var passed = white_passed;
        while (passed != 0) {
            const square = @ctz(passed);
            eval.accum(PASSED[square / 8 - 1]);
            passed &= passed - 1;
        }
    }

    const black_passed = black_pawns & ~((b_spans[0] << 8) | w_spans[0] | w_attack_spans);
    {
        var passed = black_passed;
        while (passed != 0) {
            const square = @ctz(passed);
            eval.naccum(PASSED[7 - square / 8 - 1]);
            passed &= passed - 1;
        }
    }
    

    return eval;
}

pub fn evaluate(position: *const board.Board) i32 {
    var eval = evaluate_asm(position);
    // var old_eval = material(position);
    // old_eval.accum(mobility(position));
    // old_eval.accum(bishop_pair(position));
    // old_eval.accum(pawn_eval(position));
    // if (old_eval.mg != eval.mg or old_eval.eg != eval.eg) {
    //     std.debug.print("old: {} new: {}\n{}\n", .{ old_eval, eval, position });
    // }
    const score = resolve(position, eval);

    return if (position.side_to_move == 0) score else -score;
}



fn resolve(position: *const board.Board, eval: Eval) i32 {
    const phase = popcnt(position.pieces[@enumToInt(board.Piece.Knight)])
        + popcnt(position.pieces[@enumToInt(board.Piece.Bishop)])
        + 2 * popcnt(position.pieces[@enumToInt(board.Piece.Rook)])
        + 4 * popcnt(position.pieces[@enumToInt(board.Piece.Queen)]);

    return @divTrunc(phase * @as(i32, eval.mg) + (24 - phase) * @as(i32, eval.eg), 24);
}
