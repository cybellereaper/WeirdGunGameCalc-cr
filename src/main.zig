const std = @import("std");
const parser = @import("parser.zig");
const engine = @import("engine.zig");
const model = @import("model.zig");

const Cli = struct {
    data_path: []const u8 = "Data/FullData.json",
    output_path: []const u8 = "Results.txt",
    sort: model.SortMetric = .ttk,
    top_n: usize = 10,
    max_health: f64 = 100,
    allocator: std.mem.Allocator,
    include_categories: std.ArrayListUnmanaged([]const u8) = .{},

    fn init(allocator: std.mem.Allocator) Cli {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *Cli) void {
        self.include_categories.deinit(self.allocator);
    }
};

fn printUsage() void {
    std.debug.print(
        "Usage: wggcalc [--data PATH] [--output PATH] [--sort TTK|DAMAGE|DAMAGEEND|FIRERATE|DPS] [--top N] [--max-health N] [--include Category ...]\n",
        .{},
    );
}

fn parseArgs(allocator: std.mem.Allocator) !Cli {
    var cli = Cli.init(allocator);
    errdefer cli.deinit();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            return error.DisplayedHelp;
        } else if (std.mem.eql(u8, arg, "--data")) {
            cli.data_path = args.next() orelse return error.MissingArg;
        } else if (std.mem.eql(u8, arg, "--output")) {
            cli.output_path = args.next() orelse return error.MissingArg;
        } else if (std.mem.eql(u8, arg, "--sort")) {
            cli.sort = model.SortMetric.parse(args.next() orelse return error.MissingArg);
        } else if (std.mem.eql(u8, arg, "--top")) {
            const raw = args.next() orelse return error.MissingArg;
            cli.top_n = try std.fmt.parseInt(usize, raw, 10);
        } else if (std.mem.eql(u8, arg, "--max-health")) {
            const raw = args.next() orelse return error.MissingArg;
            cli.max_health = try std.fmt.parseFloat(f64, raw);
        } else if (std.mem.eql(u8, arg, "--include")) {
            try cli.include_categories.append(allocator, args.next() orelse return error.MissingArg);
        } else {
            return error.UnknownArg;
        }
    }

    return cli;
}

fn writeResults(file: std.fs.File, db: *const model.Database, top: []const model.Candidate) !void {
    var buf: [4096]u8 = undefined;
    var writer = file.writer(&buf);
    try writer.interface.print("Top {d} builds\n", .{top.len});

    for (top, 0..) |cand, idx| {
        const core = db.cores.items[cand.core_idx];
        const mag = db.magazines.items[cand.magazine_idx];
        const barrel = db.barrels.items[cand.barrel_idx];
        const grip = db.grips.items[cand.grip_idx];
        const stock = db.stocks.items[cand.stock_idx];

        try writer.interface.print(
            "#{d} {s} | M:{s} B:{s} G:{s} S:{s} | TTK:{d:.3}s DPS:{d:.2} Dmg:{d:.2}\n",
            .{ idx + 1, core.name, mag.name, barrel.name, grip.name, stock.name, cand.stats.ttk_seconds, cand.stats.dps, cand.stats.damage },
        );
    }
    try writer.interface.flush();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli = parseArgs(allocator) catch |err| switch (err) {
        error.DisplayedHelp => return,
        else => return err,
    };
    defer cli.deinit();

    const json_bytes = try std.fs.cwd().readFileAlloc(allocator, cli.data_path, 1024 * 1024 * 64);
    defer allocator.free(json_bytes);

    var db = try parser.parseDatabase(allocator, json_bytes);
    defer db.deinit();

    const cfg = engine.Config{
        .max_health = cli.max_health,
        .top_n = cli.top_n,
        .sort_metric = cli.sort,
        .include_categories = cli.include_categories.items,
    };

    var top = try engine.computeTop(allocator, &db, cfg);
    defer top.deinit(allocator);

    const file = try std.fs.cwd().createFile(cli.output_path, .{});
    defer file.close();
    try writeResults(file, &db, top.items);

    std.debug.print("Wrote {d} builds to {s}\n", .{ top.items.len, cli.output_path });
}

test {
    _ = @import("engine.zig");
}
