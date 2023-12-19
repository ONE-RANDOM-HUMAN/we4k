const std = @import("std");
const game = @import("game.zig");
const board = @import("board.zig");
const movegen = @import("movegen.zig");
const moveorder = @import("moveorder.zig");
const tt = @import("tt.zig");
const evaluate = @import("evaluate.zig");

const linux = std.os.linux;

const NO_EVAL: i32 = @truncate(0x8000_0000);

extern fn print_move_asm(move: u16) callconv(.SysV) void;
extern fn search_should_stop_asm(self: *const Search) callconv(.SysV) bool;

comptime {
    @export(Search.alpha_beta, .{ .name = "search_alpha_beta", .linkage = .Strong });
}

inline fn neg(eval: i32) !i32 {
    return std.math.negate(eval);
}

const PV_NODE = 0;
const CUT_NODE = 1;
const ALL_NODE = 2;

pub const Search = extern struct {
    game: game.Game,
    start: linux.timespec,
    stop_time: u64,
    panic_stop_time: u64,
    panicking: bool,
    nodes: u64,
    tt: tt.TT,
    thread_data: *u8,

    pub fn new() Search {
        return Search{
            .game = game.Game.new(),
            .start = undefined,
            .stop_time = 0,
            .panic_stop_time = 0,
            .panicking = false,
            .nodes = 0,
            .tt = tt.TT.new(),
        };
    }

    pub fn new_game(self: *Search) callconv(.SysV) void {
        self.tt.clear();
    }

    pub fn search(self: *Search, start: *const linux.timespec, time: u64, inc: u64) callconv(.SysV) void {
        self.start = start.*;
        self.panicking = false;
        self.stop_time = std.math.min(
            time * (1000000 / 2),
            (time + inc) * (1000000 / 30),
        );

        self.panic_stop_time = std.math.min(
            time * (2 * 1000000 / 3),
            (time + inc) * (1000000 / 10),
        );

        // nodes does not need to be reset because it is only used
        // to determine when to check time.
        // self.nodes = 0;

        var buffer: [256]board.Move = undefined;
        const pseudo_moves = movegen.gen_pseudo_legal(self.game.position(), &buffer);

        var move_buffer: [256]SearchMove = undefined;
        var curr_move: usize = 0;
        for (pseudo_moves) |move| {
            if (self.game.make_move(move)) {
                move_buffer[curr_move].move = move;

                // It does not matter if this gives NO_EVAL
                var kt_out = moveorder.KillerTable.EMPTY;
                move_buffer[curr_move].eval = -%self.alpha_beta(-evaluate.MAX_EVAL, -evaluate.MIN_EVAL, -1, &kt_out);
                self.game.unmake_move();
                curr_move += 1;
            }
        }

        const moves = move_buffer[0..curr_move];

        if (moves.len == 1) {
            Search.print_move(moves[0].move);
            return;
        }

        var depth: u32 = 2;
        var searched: usize = undefined;
        loop: while (true) : (depth += 1) {
            searched = 0;
            self.panicking = false;
            std.sort.insertionSort(SearchMove, moves, {}, SearchMove.sort_fn);
            // std.io.getStdOut().writer().print(
            //     "info depth {} nodes {} score cp {}\n",
            //     .{ depth - 1, self.nodes, @divTrunc(moves[0].eval * 100, 256) }
            // ) catch unreachable;
            // std.io.getStdOut().writer().print(
            //     "info string best move: {}\n",
            //     .{ moves[0].move }
            // ) catch unreachable;

            const EVAL_PANIC_MARGIN = 128;
            const beta = evaluate.MAX_EVAL;
            const last_best = moves[0].eval;

            var alpha = evaluate.MIN_EVAL;
            var kt_out = moveorder.KillerTable.EMPTY;

            for (moves) |*move| {
                _ = self.game.make_move(move.move);
                defer self.game.unmake_move();

                const score = neg(self.alpha_beta(-beta, -alpha, @intCast(depth - 1), &kt_out)) catch break :loop;

                move.eval = score;
                alpha = std.math.max(alpha, score);

                self.panicking = depth >= 5 and alpha <= last_best - EVAL_PANIC_MARGIN;
                searched += 1;
            }
        }

        std.sort.insertionSort(SearchMove, moves[0..searched], {}, SearchMove.sort_fn);
        Search.print_move(moves[0].move);
    }

    pub fn alpha_beta(self: *Search, _alpha: i32, beta: i32, _depth_remaining: i32, kt_in: *moveorder.KillerTable) callconv(.SysV) i32 {
        if (self.nodes % 4096 == 0 and self.should_stop()) {
            return NO_EVAL;
        }

        self.nodes += 1;

        // check for repetition
        if (self.game.is_repetition()) {
            return 0;
        }

        var buffer: [256]board.Move = undefined;
        const moves = movegen.gen_pseudo_legal(self.game.position(), &buffer);

        const is_check = self.game.position().is_check();
        if (moves.len == 0) {
            return if (is_check) evaluate.MIN_EVAL else 0;
        }

        // require 101 plies if in check to prevent blundering
        // into mate in 1 on 100th ply
        if (self.game.position().fifty_moves >= 101 // this is the smallest
            or (!is_check and self.game.position().fifty_moves >= 100)
        ) {
            return 0;
        }

        var depth_remaining: i32 = undefined;
        if (is_check) {
            depth_remaining = _depth_remaining;
        } else {
            depth_remaining = _depth_remaining - 1;
        }

        // All negative depths are qsearch
        const quiescence = depth_remaining < 0;
        // mate distance pruning

        // tt
        var ordered: usize = 0;
        if (!quiescence) {
            const tt_entry = self.tt.load(self.game.position());
            if (!tt_entry.is_zero()) {
                const move_index = for (moves, 0..) |move, index| {
                    if (move.eql(tt_entry.best_move)) break index;
                } else null;

                if (move_index) |index| {
                    const tmp = moves[0];
                    moves[0] = moves[index];
                    moves[index] = tmp;
                    ordered = 1;

                    if (tt_entry.depth >= depth_remaining and beta - _alpha == 1) {
                        const eval = tt_entry.eval();
                        if (tt_entry.node_type == PV_NODE
                            or (tt_entry.node_type == CUT_NODE and eval >= beta)
                            or (tt_entry.node_type == ALL_NODE and eval <= _alpha)
                        ) {
                            return eval;
                        }
                    }
                }
            }
        }

        ordered += moveorder.order_noisy_moves(moves[ordered..], self.game.position());

        // NMP
        var alpha = _alpha;
        var best_eval = evaluate.MIN_EVAL - 1;
        var best_move = board.Move.ZERO;
        var node_type: u2 = ALL_NODE;

        if (quiescence) {
            // stand pat
            best_eval = evaluate.evaluate(self.game.position());
            if (best_eval >= beta) {
                return best_eval;
            }

            if (best_eval > alpha) {
                alpha = best_eval;
                // node_type = PV_NODE;
            }
        }

        var kt_out = moveorder.KillerTable.EMPTY;
        var i: usize = 0;
        while (i < moves.len) : (i += 1) {
            if (i == ordered) {
                if (quiescence) {
                    // end of noisy moves for quiescence
                    return best_eval;
                } else {
                    moveorder.order_quiet_moves(moves[ordered..], self.game.position(), kt_in.*);
                }
            }

            const move = moves[i];

            if (!self.game.make_move(move)) {
                continue;
            }

            defer self.game.unmake_move();

            var eval: i32 = undefined;
            if (quiescence or best_move.eql(board.Move.ZERO)) {
                // first move or quiescence
                eval = neg(self.alpha_beta(-beta, -alpha, depth_remaining, &kt_out)) catch return NO_EVAL;
            } else {
                const reduction = if (beta - alpha == 1
                    and !move.is_noisy()
                    and !is_check
                    and !self.game.position().is_check() // is check after making the move
                ) 
                    @min(
                        depth_remaining >> 1,
                        ((depth_remaining + 1) >> 2) + @as(i32, @intCast(i >> 3))
                    )
                else 0;                    

                // Principal variation search
                eval = neg(self.alpha_beta(-alpha - 1, -alpha, depth_remaining - reduction, &kt_out)) catch return NO_EVAL;

                if ((eval > alpha and eval < beta) or (eval >= beta and reduction != 0)) {
                    eval = neg(self.alpha_beta(-beta, -alpha, depth_remaining, &kt_out)) catch return NO_EVAL;
                }
            }

            if (eval > best_eval) {
                best_eval = eval;
                best_move = move;

                if (eval > alpha) {
                    alpha = eval;

                    if (eval >= beta) {
                        node_type = CUT_NODE;
                        if (!move.is_noisy()) {
                            kt_in.beta_cutoff(move);
                        }

                        break;
                    } else {
                        node_type = ALL_NODE;
                    }
                }
            }
        }

        if (!best_move.eql(board.Move.ZERO)) {
            if (!quiescence) {
                self.tt.store(
                    self.game.position(),
                    best_move,
                    best_eval,
                    node_type,
                    @intCast(depth_remaining),
                );
            }
            return best_eval;
        } else {
            // No legal moves
            return if (is_check) evaluate.MIN_EVAL else 0;
        }
    }

    pub inline fn should_stop(self: *Search) bool {
        return search_should_stop_asm(self);
    }

    inline fn print_move(move: board.Move) void {
        print_move_asm(@bitCast(move));
    }
};

const SearchMove = struct {
    eval: i32,
    move: board.Move,
    fn sort_fn(_: void, lhs: SearchMove, rhs: SearchMove) bool {
        return lhs.eval > rhs.eval;
    }
};
