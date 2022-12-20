const std = @import("std");
const board = @import("board.zig");
const movegen = @import("movegen.zig");
const game = @import("game.zig");
const search = @import("search.zig");
const linux = std.os.linux;

pub extern fn _start() callconv(.Naked) noreturn;

comptime {
    _ = search; // ensure that it is actually compiled
}

fn perft(boards: *std.ArrayList(board.Board), depth: u32) u64 {
    if (depth == 0) {
        return 1;
    }

    var moves: [256]board.Move = undefined;
    const end = movegen.gen_pseudo_legal_raw(&boards.items[boards.items.len - 1], &moves);

    var count = @as(u64, 0);
    var start = @as([*]board.Move, &moves);
    while (start != end) {
        const last_position = boards.items[boards.items.len - 1];
        boards.append(last_position) catch std.debug.panic("OOM", .{});
        if (boards.items[boards.items.len - 1].make_move(start[0])) {
            count += perft(boards, depth - 1);
        }

        _ = boards.pop();
        start += 1;
    }

    return count;
}

test {
    std.testing.refAllDecls(@This());
}

test "perft startpos" {
    const expect = std.testing.expect;
    var list = std.ArrayList(board.Board).init(std.testing.allocator);
    defer list.deinit();

    try list.append(board.Board.STARTPOS);
    
    try expect(perft(&list, 1) == 20);
    try expect(perft(&list, 2) == 400);
    try expect(perft(&list, 3) == 8902);
    try expect(perft(&list, 4) == 197281);
    try expect(perft(&list, 5) == 4865609);
    try expect(perft(&list, 6) == 119060324);

    // try expect(perft(&list, 7) == 3195901860);
}

test "perft kiwipete" {
    const expect = std.testing.expect;
    var list = std.ArrayList(board.Board).init(std.testing.allocator);
    defer list.deinit();
    
    try list.append(board.Board {
        .pieces = [6]u64{
            0x002d_5008_1280_e700,
            0x0000_2210_0004_0000,
            0x0040_0100_0000_1800,
            0x8100_0000_0000_0081,
            0x0010_0000_0020_0000,
            0x1000_0000_0000_0010,
        },
        .colors = [2]u64 {
            0x0000_0018_1024_ff91,
            0x917d_7300_0280_0000,
        },
        .fifty_moves =  0,
        .side_to_move =  0,
        .castling = 0b1111,
        .ep = board.OptionalSquare.none(),
    });

    try expect(perft(&list, 1) == 48);
    try expect(perft(&list, 2) == 2039);
    try expect(perft(&list, 3) == 97862);
    try expect(perft(&list, 4) == 4085603);
    try expect(perft(&list, 5) == 193690690);

    // try expect(perft(&list, 6) == 8031647685);

}

test "perft 8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1" {
    const expect = std.testing.expect;
    var list = std.ArrayList(board.Board).init(std.testing.allocator);
    defer list.deinit();

    try list.append(board.Board {
        .pieces = [6]u64{
            0x0004_0802_2000_5000,
            0x0,
            0x0,
            0x0000_0080_0200_0000,
            0x0,
            0x0000_0001_8000_0000,
        },
        .colors = [2]u64 {
            0x0000_0003_0200_5000,
            0x0004_0880_a000_0000,
        },
        .fifty_moves =  0,
        .side_to_move =  0,
        .castling = 0,
        .ep = board.OptionalSquare.none(),
    });

    try expect(perft(&list, 1) == 14);
    try expect(perft(&list, 2) == 191);
    try expect(perft(&list, 3) == 2812);
    try expect(perft(&list, 4) == 43238);
    try expect(perft(&list, 5) == 674624);
    try expect(perft(&list, 6) == 11030083);
    try expect(perft(&list, 7) == 178633661);

    // try expect(perft(&list, 8) == 3009794393);
}

test "perft r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1" {
    const expect = std.testing.expect;
    var list = std.ArrayList(board.Board).init(std.testing.allocator);
    defer list.deinit();

    try list.append(board.Board {
        .pieces = [6]u64{
            0x00ef_0002_1400_cb00,
            0x0000_a001_0020_0000,
            0x0000_4200_0300_0000,
            0x8100_0000_0000_0021,
            0x0000_0000_0001_0008,
            0x1000_0000_0000_0040,
        },
        .colors = [2]u64 {
            0x0001_8002_1720_c969,
            0x91ee_6201_0001_0200,
        },
        .fifty_moves = 0,
        .side_to_move = 0,
        .castling = 0b1100,
        .ep = board.OptionalSquare.none(),
    });


    try expect(perft(&list, 1) == 6);
    try expect(perft(&list, 2) == 264);
    try expect(perft(&list, 3) == 9467);
    try expect(perft(&list, 4) == 422333);
    try expect(perft(&list, 5) == 15833292);

    // try expect(perft(&list, 6) == 706045033);
}

test "perft rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8" {
    const expect = std.testing.expect;
    var list = std.ArrayList(board.Board).init(std.testing.allocator);
    defer list.deinit();
    
    try list.append(board.Board {
        .pieces = [6]u64{
            0x00EB_0400_0000_C700,
            0x0200_0000_0000_3002,
            0x0410_0000_0400_0004,
            0x8100_0000_0000_0081,
            0x0800_0000_0000_0008,
            0x2000_0000_0000_0010,
        },
        .colors = [2]u64 {
            0x0008_0000_0400_D79F,
            0xAFF3_0400_0000_2000,
        },
        .fifty_moves = 0,
        .side_to_move = 0,
        .castling = 0b0011,
        .ep = board.OptionalSquare.none(),
    });


    try expect(perft(&list, 1) == 44);
    try expect(perft(&list, 2) == 1486);
    try expect(perft(&list, 3) == 62379);
    try expect(perft(&list, 4) == 2103487);
    try expect(perft(&list, 5) == 89941194);

}

test "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10" {
    const expect = std.testing.expect;
    var list = std.ArrayList(board.Board).init(std.testing.allocator);
    defer list.deinit();
    
    try list.append(board.Board {
        .pieces = [6]u64{
            0x00E6_0910_1009_E600,
            0x0000_2400_0024_0000,
            0x0000_0044_4400_0000,
            0x2100_0000_0000_0021,
            0x0010_0000_0000_1000,
            0x4000_0000_0000_0040,
        },
        .colors = [2]u64 {
            0x0000_0040_142D_F661,
            0x61F6_2D14_4000_0000,
        },
        .fifty_moves = 10,
        .side_to_move = 0,
        .castling = 0,
        .ep = board.OptionalSquare.none(),
    });


    try expect(perft(&list, 1) == 46);
    try expect(perft(&list, 2) == 2079);
    try expect(perft(&list, 3) == 89890);
    try expect(perft(&list, 4) == 3894594);
    try expect(perft(&list, 5) == 164075551);

    // try expect(perft(&list, 6) == 6923051137);
}


