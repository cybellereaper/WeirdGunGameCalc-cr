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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config: calc.Config = .{};
    var include_list = std.array_list.Managed([]const u8).init(allocator);
    defer include_list.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            printHelp();
            return;
        } else if (std.mem.eql(u8, arg, "--data")) {
            i += 1;
            config.data_path = args[i];
        } else if (std.mem.eql(u8, arg, "--top")) {
            i += 1;
            config.top_n = try std.fmt.parseInt(usize, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--mh")) {
            i += 1;
            config.player_max_health = try std.fmt.parseFloat(f64, args[i]);
        } else if (std.mem.eql(u8, arg, "--sort")) {
            i += 1;
            config.sort_key = try parseSort(args[i]);
        } else if (std.mem.eql(u8, arg, "--priority")) {
            i += 1;
            config.priority = try parsePriority(args[i]);
        } else if (std.mem.eql(u8, arg, "--include")) {
            i += 1;
            var split = std.mem.splitScalar(u8, args[i], ',');
            while (split.next()) |part| {
                if (part.len == 0) continue;
                try include_list.append(part);
            }
        } else if (std.mem.eql(u8, arg, "--part-pool")) {
            i += 1;
            config.part_pool_per_type = try std.fmt.parseInt(usize, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--damage-min")) {
            i += 1;
            config.damage_range.min = try std.fmt.parseFloat(f64, args[i]);
        } else if (std.mem.eql(u8, arg, "--damage-max")) {
            i += 1;
            config.damage_range.max = try std.fmt.parseFloat(f64, args[i]);
        } else if (std.mem.eql(u8, arg, "--damage-end-min")) {
            i += 1;
            config.damage_end_range.min = try std.fmt.parseFloat(f64, args[i]);
        } else if (std.mem.eql(u8, arg, "--damage-end-max")) {
            i += 1;
            config.damage_end_range.max = try std.fmt.parseFloat(f64, args[i]);
        } else if (std.mem.eql(u8, arg, "--ttk-min")) {
            i += 1;
            config.ttk_seconds_range.min = try std.fmt.parseFloat(f64, args[i]);
        } else if (std.mem.eql(u8, arg, "--ttk-max")) {
            i += 1;
            config.ttk_seconds_range.max = try std.fmt.parseFloat(f64, args[i]);
        } else if (std.mem.eql(u8, arg, "--dps-min")) {
            i += 1;
            config.dps_range.min = try std.fmt.parseFloat(f64, args[i]);
        } else if (std.mem.eql(u8, arg, "--dps-max")) {
            i += 1;
            config.dps_range.max = try std.fmt.parseFloat(f64, args[i]);
        } else {
            std.debug.print("Unknown option: {s}\n", .{arg});
            printHelp();
            return error.InvalidArgs;
        }
    }

    config.include_categories = try include_list.toOwnedSlice();
    defer allocator.free(config.include_categories);

    var data = try calc.loadData(allocator, config.data_path);
    defer data.deinit(allocator);

    var results = try calc.calculateTop(allocator, config, &data);
    defer results.deinit();

    const out = std.fs.File.stdout().deprecatedWriter();
    try out.print("Loaded {d} cores, {d} magazines, {d} barrels, {d} stocks, {d} grips\n\n", .{
        data.cores.items.len,
        data.magazines.items.len,
        data.barrels.items.len,
        data.stocks.items.len,
        data.grips.items.len,
    });
    try calc.writeResults(out, results.items);
}
