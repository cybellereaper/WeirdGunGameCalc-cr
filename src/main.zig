const std = @import("std");
const calc = @import("wggcalc");

fn printHelp() void {
    std.debug.print(
        \\WeirdGunGameCalc (Zig rewrite)
        \\Usage: wggcalc [options]
        \\
        \\Options:
        \\  --data <path>            Path to FullData.json (default: Data/FullData.json)
        \\  --top <n>                Number of results (default: 10)
        \\  --mh <health>            Max player health for TTK (default: 100)
        \\  --sort <key>             ttk|dps|damage|damageend|firerate|magazine
        \\  --priority <mode>        highest|lowest|auto
        \\  --include <cat1,cat2>    Include categories (e.g. AR,SMG)
        \\  --part-pool <n>          Candidate parts per type per core (default: 20)
        \\  --damage-min/--damage-max <v>
        \\  --damage-end-min/--damage-end-max <v>
        \\  --ttk-min/--ttk-max <v>  Seconds
        \\  --dps-min/--dps-max <v>
        \\  --metrics                Print runtime and calculation performance metrics
        \\  --help
        \\
    , .{});
}

fn parseSort(value: []const u8) !calc.SortKey {
    if (std.ascii.eqlIgnoreCase(value, "ttk")) return .ttk;
    if (std.ascii.eqlIgnoreCase(value, "dps")) return .dps;
    if (std.ascii.eqlIgnoreCase(value, "damage")) return .damage;
    if (std.ascii.eqlIgnoreCase(value, "damageend")) return .damage_end;
    if (std.ascii.eqlIgnoreCase(value, "firerate")) return .fire_rate;
    if (std.ascii.eqlIgnoreCase(value, "magazine")) return .magazine;
    return error.InvalidSort;
}

fn parsePriority(value: []const u8) !calc.SortPriority {
    if (std.ascii.eqlIgnoreCase(value, "highest")) return .highest;
    if (std.ascii.eqlIgnoreCase(value, "lowest")) return .lowest;
    if (std.ascii.eqlIgnoreCase(value, "auto")) return .auto;
    return error.InvalidPriority;
}

fn requireNextArg(args: []const []const u8, i: *usize, option_name: []const u8) ![]const u8 {
    i.* += 1;
    if (i.* >= args.len) {
        std.debug.print("Missing value for option: {s}\n", .{option_name});
        return error.InvalidArgs;
    }
    return args[i.*];
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config: calc.Config = .{};
    var include_list = std.array_list.Managed([]const u8).init(allocator);
    defer include_list.deinit();
    var show_performance_metrics = false;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            printHelp();
            return;
        } else if (std.mem.eql(u8, arg, "--data")) {
            config.data_path = try requireNextArg(args, &i, "--data");
        } else if (std.mem.eql(u8, arg, "--top")) {
            config.top_n = try std.fmt.parseInt(usize, try requireNextArg(args, &i, "--top"), 10);
        } else if (std.mem.eql(u8, arg, "--mh")) {
            config.player_max_health = try std.fmt.parseFloat(f64, try requireNextArg(args, &i, "--mh"));
        } else if (std.mem.eql(u8, arg, "--sort")) {
            config.sort_key = try parseSort(try requireNextArg(args, &i, "--sort"));
        } else if (std.mem.eql(u8, arg, "--priority")) {
            config.priority = try parsePriority(try requireNextArg(args, &i, "--priority"));
        } else if (std.mem.eql(u8, arg, "--include")) {
            var split = std.mem.splitScalar(u8, try requireNextArg(args, &i, "--include"), ',');
            while (split.next()) |part| {
                if (part.len == 0) continue;
                try include_list.append(part);
            }
        } else if (std.mem.eql(u8, arg, "--part-pool")) {
            config.part_pool_per_type = try std.fmt.parseInt(usize, try requireNextArg(args, &i, "--part-pool"), 10);
        } else if (std.mem.eql(u8, arg, "--damage-min")) {
            config.damage_range.min = try std.fmt.parseFloat(f64, try requireNextArg(args, &i, "--damage-min"));
        } else if (std.mem.eql(u8, arg, "--damage-max")) {
            config.damage_range.max = try std.fmt.parseFloat(f64, try requireNextArg(args, &i, "--damage-max"));
        } else if (std.mem.eql(u8, arg, "--damage-end-min")) {
            config.damage_end_range.min = try std.fmt.parseFloat(f64, try requireNextArg(args, &i, "--damage-end-min"));
        } else if (std.mem.eql(u8, arg, "--damage-end-max")) {
            config.damage_end_range.max = try std.fmt.parseFloat(f64, try requireNextArg(args, &i, "--damage-end-max"));
        } else if (std.mem.eql(u8, arg, "--ttk-min")) {
            config.ttk_seconds_range.min = try std.fmt.parseFloat(f64, try requireNextArg(args, &i, "--ttk-min"));
        } else if (std.mem.eql(u8, arg, "--ttk-max")) {
            config.ttk_seconds_range.max = try std.fmt.parseFloat(f64, try requireNextArg(args, &i, "--ttk-max"));
        } else if (std.mem.eql(u8, arg, "--dps-min")) {
            config.dps_range.min = try std.fmt.parseFloat(f64, try requireNextArg(args, &i, "--dps-min"));
        } else if (std.mem.eql(u8, arg, "--dps-max")) {
            config.dps_range.max = try std.fmt.parseFloat(f64, try requireNextArg(args, &i, "--dps-max"));
        } else if (std.mem.eql(u8, arg, "--metrics")) {
            show_performance_metrics = true;
        } else {
            std.debug.print("Unknown option: {s}\n", .{arg});
            printHelp();
            return error.InvalidArgs;
        }
    }

    config.include_categories = try include_list.toOwnedSlice();
    defer allocator.free(config.include_categories);

    var total_timer = try std.time.Timer.start();
    var load_timer = try std.time.Timer.start();
    var data = try calc.loadData(allocator, config.data_path);
    defer data.deinit(allocator);
    const load_time_ns = load_timer.read();

    var calc_timer = try std.time.Timer.start();
    var stats: calc.CalculationStats = .{};
    var results = try calc.calculateTopWithStats(allocator, config, &data, &stats);
    defer results.deinit();
    const calc_time_ns = calc_timer.read();
    const total_time_ns = total_timer.read();

    const out = std.fs.File.stdout().deprecatedWriter();
    try out.print("Loaded {d} cores, {d} magazines, {d} barrels, {d} stocks, {d} grips\n\n", .{
        data.cores.items.len,
        data.magazines.items.len,
        data.barrels.items.len,
        data.stocks.items.len,
        data.grips.items.len,
    });
    try calc.writeResults(out, results.items);

    if (show_performance_metrics) {
        try out.print(
            "Performance metrics:\n  Data load: {d:.3} ms\n  Calculation: {d:.3} ms\n  Total runtime: {d:.3} ms\n  Cores considered: {d}\n  Cores skipped by category: {d}\n  Combinations evaluated: {d}\n  Combinations filtered: {d}\n  Results kept: {d}\n",
            .{
                @as(f64, @floatFromInt(load_time_ns)) / @as(f64, std.time.ns_per_ms),
                @as(f64, @floatFromInt(calc_time_ns)) / @as(f64, std.time.ns_per_ms),
                @as(f64, @floatFromInt(total_time_ns)) / @as(f64, std.time.ns_per_ms),
                stats.cores_considered,
                stats.cores_skipped_by_category,
                stats.combinations_evaluated,
                stats.combinations_filtered,
                stats.results_kept,
            },
        );
    }
}
