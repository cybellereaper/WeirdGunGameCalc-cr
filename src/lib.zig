const std = @import("std");

pub const Range = struct {
    min: ?f64 = null,
    max: ?f64 = null,

    pub fn contains(self: Range, value: f64) bool {
        if (self.min) |m| if (value < m) return false;
        if (self.max) |m| if (value > m) return false;
        return true;
    }
};

pub const Config = struct {
    data_path: []const u8 = "Data/FullData.json",
    top_n: usize = 10,
    player_max_health: f64 = 100,
    sort_key: SortKey = .ttk,
    priority: SortPriority = .auto,
    include_categories: [][]const u8 = &.{},
    damage_range: Range = .{},
    damage_end_range: Range = .{},
    ttk_seconds_range: Range = .{},
    dps_range: Range = .{},
    part_pool_per_type: usize = 20,
};

pub const CalculationStats = struct {
    cores_considered: usize = 0,
    cores_skipped_by_category: usize = 0,
    combinations_evaluated: usize = 0,
    combinations_filtered: usize = 0,
    results_kept: usize = 0,
};

pub const SortKey = enum {
    ttk,
    dps,
    damage,
    damage_end,
    fire_rate,
    magazine,
};

pub const SortPriority = enum { highest, lowest, auto };

pub const Core = struct {
    name: []const u8,
    category: []const u8,
    damage: f64,
    damage_end: f64,
    fire_rate: f64,
};

pub const Magazine = struct {
    name: []const u8,
    category: []const u8,
    magazine_size: f64,
    reload_time: f64,
    damage_mod: f64,
    fire_rate_mod: f64,
};

pub const Part = struct {
    name: []const u8,
    category: []const u8,
    damage_mod: f64,
    fire_rate_mod: f64,
};

pub const DataSet = struct {
    cores: std.array_list.Managed(Core),
    magazines: std.array_list.Managed(Magazine),
    barrels: std.array_list.Managed(Part),
    grips: std.array_list.Managed(Part),
    stocks: std.array_list.Managed(Part),
    penalties: [][]f64,
    categories: std.StringHashMap(usize),

    pub fn deinit(self: *DataSet, allocator: std.mem.Allocator) void {
        for (self.cores.items) |c| {
            allocator.free(c.name);
            allocator.free(c.category);
        }
        for (self.magazines.items) |m| {
            allocator.free(m.name);
            allocator.free(m.category);
        }
        for (self.barrels.items) |p| {
            allocator.free(p.name);
            allocator.free(p.category);
        }
        for (self.grips.items) |p| {
            allocator.free(p.name);
            allocator.free(p.category);
        }
        for (self.stocks.items) |p| {
            allocator.free(p.name);
            allocator.free(p.category);
        }
        self.cores.deinit();
        self.magazines.deinit();
        self.barrels.deinit();
        self.grips.deinit();
        self.stocks.deinit();
        for (self.penalties) |row| allocator.free(row);
        allocator.free(self.penalties);
        var it = self.categories.iterator();
        while (it.next()) |entry| allocator.free(entry.key_ptr.*);
        self.categories.deinit();
    }
};

pub const Result = struct {
    core: []const u8,
    magazine: []const u8,
    barrel: []const u8,
    stock: []const u8,
    grip: []const u8,
    damage: f64,
    damage_end: f64,
    fire_rate: f64,
    magazine_size: f64,
    ttk_seconds: f64,
    dps: f64,
};

fn parseNumber(v: std.json.Value) !f64 {
    return switch (v) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        else => error.InvalidNumber,
    };
}

fn dupStr(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    return allocator.dupe(u8, s);
}

fn parseIndex(v: std.json.Value) !usize {
    return switch (v) {
        .integer => |i| @intCast(i),
        .float => |f| @intFromFloat(f),
        else => error.InvalidNumber,
    };
}

fn getObj(v: std.json.Value, key: []const u8) !std.json.ObjectMap {
    const child = v.object.get(key) orelse return error.MissingField;
    if (child != .object) return error.InvalidType;
    return child.object;
}

fn getString(v: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const val = v.get(key) orelse return error.MissingField;
    if (val != .string) return error.InvalidType;
    return val.string;
}

fn getNumberDefault(v: std.json.ObjectMap, key: []const u8, default_value: f64) !f64 {
    const val = v.get(key) orelse return default_value;
    return parseNumber(val);
}

fn getDamagePair(v: std.json.ObjectMap) !struct { start: f64, end: f64 } {
    const maybe = v.get("Damage") orelse return .{ .start = 0, .end = 0 };
    return switch (maybe) {
        .array => |arr| .{ .start = try parseNumber(arr.items[0]), .end = try parseNumber(arr.items[1]) },
        .integer, .float => blk: {
            const n = try parseNumber(maybe);
            break :blk .{ .start = n, .end = n };
        },
        else => error.InvalidType,
    };
}

fn parseCategoryMap(allocator: std.mem.Allocator, root: std.json.Value) !std.StringHashMap(usize) {
    var map = std.StringHashMap(usize).init(allocator);
    const categories = try getObj(root, "Categories");
    const primary = categories.get("Primary") orelse return error.MissingField;
    const secondary = categories.get("Secondary") orelse return error.MissingField;

    if (primary != .object or secondary != .object) return error.InvalidType;

    var it1 = primary.object.iterator();
    while (it1.next()) |entry| {
        const idx = try parseIndex(entry.value_ptr.*);
        try map.put(try dupStr(allocator, entry.key_ptr.*), idx);
    }
    var it2 = secondary.object.iterator();
    while (it2.next()) |entry| {
        const idx = try parseIndex(entry.value_ptr.*);
        try map.put(try dupStr(allocator, entry.key_ptr.*), idx);
    }
    return map;
}

pub fn loadData(allocator: std.mem.Allocator, path: []const u8) !DataSet {
    const text = try std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024 * 1024);
    defer allocator.free(text);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
    defer parsed.deinit();
    const root = parsed.value;

    var categories = try parseCategoryMap(allocator, root);
    errdefer categories.deinit();

    const penalties_value = root.object.get("Penalties") orelse return error.MissingField;
    if (penalties_value != .array) return error.InvalidType;

    const rows = penalties_value.array.items.len;
    var penalties = try allocator.alloc([]f64, rows);
    errdefer allocator.free(penalties);

    for (penalties_value.array.items, 0..) |row, i| {
        if (row != .array) return error.InvalidType;
        penalties[i] = try allocator.alloc(f64, row.array.items.len);
        for (row.array.items, 0..) |cell, j| penalties[i][j] = try parseNumber(cell);
    }

    const data = try getObj(root, "Data");

    var cores = std.array_list.Managed(Core).init(allocator);
    var magazines = std.array_list.Managed(Magazine).init(allocator);
    var barrels = std.array_list.Managed(Part).init(allocator);
    var grips = std.array_list.Managed(Part).init(allocator);
    var stocks = std.array_list.Managed(Part).init(allocator);

    const core_arr = data.get("Cores") orelse return error.MissingField;
    if (core_arr != .array) return error.InvalidType;
    for (core_arr.array.items) |node| {
        if (node != .object) return error.InvalidType;
        const obj = node.object;
        const dmg = try getDamagePair(obj);
        try cores.append(.{
            .name = try dupStr(allocator, try getString(obj, "Name")),
            .category = try dupStr(allocator, try getString(obj, "Category")),
            .damage = dmg.start,
            .damage_end = dmg.end,
            .fire_rate = try getNumberDefault(obj, "Fire_Rate", 0),
        });
    }

    const mag_arr = data.get("Magazines") orelse return error.MissingField;
    if (mag_arr != .array) return error.InvalidType;
    for (mag_arr.array.items) |node| {
        if (node != .object) return error.InvalidType;
        const obj = node.object;
        try magazines.append(.{
            .name = try dupStr(allocator, try getString(obj, "Name")),
            .category = try dupStr(allocator, try getString(obj, "Category")),
            .magazine_size = try getNumberDefault(obj, "Magazine_Size", 0),
            .reload_time = try getNumberDefault(obj, "Reload_Time", 0),
            .damage_mod = try getNumberDefault(obj, "Damage", 0),
            .fire_rate_mod = try getNumberDefault(obj, "Fire_Rate", 0),
        });
    }

    inline for (.{ "Barrels", "Grips", "Stocks" }, .{ &barrels, &grips, &stocks }) |key, target| {
        const arr = data.get(key) orelse return error.MissingField;
        if (arr != .array) return error.InvalidType;
        for (arr.array.items) |node| {
            if (node != .object) return error.InvalidType;
            const obj = node.object;
            try target.append(.{
                .name = try dupStr(allocator, try getString(obj, "Name")),
                .category = try dupStr(allocator, try getString(obj, "Category")),
                .damage_mod = try getNumberDefault(obj, "Damage", 0),
                .fire_rate_mod = try getNumberDefault(obj, "Fire_Rate", 0),
            });
        }
    }

    return .{
        .cores = cores,
        .magazines = magazines,
        .barrels = barrels,
        .grips = grips,
        .stocks = stocks,
        .penalties = penalties,
        .categories = categories,
    };
}

fn moreIsBetter(sort_key: SortKey) bool {
    return switch (sort_key) {
        .ttk => false,
        else => true,
    };
}

fn cmp(config: Config, a: Result, b: Result) bool {
    const pri = if (config.priority == .auto) if (moreIsBetter(config.sort_key)) SortPriority.highest else SortPriority.lowest else config.priority;
    const av = switch (config.sort_key) {
        .ttk => a.ttk_seconds,
        .dps => a.dps,
        .damage => a.damage,
        .damage_end => a.damage_end,
        .fire_rate => a.fire_rate,
        .magazine => a.magazine_size,
    };
    const bv = switch (config.sort_key) {
        .ttk => b.ttk_seconds,
        .dps => b.dps,
        .damage => b.damage,
        .damage_end => b.damage_end,
        .fire_rate => b.fire_rate,
        .magazine => b.magazine_size,
    };
    return switch (pri) {
        .highest => av > bv,
        .lowest => av < bv,
        .auto => unreachable,
    };
}

fn adjustedMod(raw: f64, core_name: []const u8, part_name: []const u8, penalty: f64) f64 {
    if (std.mem.eql(u8, core_name, part_name)) return 0;
    return raw * penalty;
}

fn partScore(core_name: []const u8, part_name: []const u8, dmg: f64, fr: f64, penalty: f64) f64 {
    const dm = adjustedMod(dmg, core_name, part_name, penalty);
    const fm = adjustedMod(fr, core_name, part_name, penalty);
    return dm * 1.0 + fm * 0.6;
}

const PartSelection = struct {
    all: []Part,
    view: []const Part,
};

const MagazineSelection = struct {
    all: []Magazine,
    view: []const Magazine,
};

const PartSortCtx = struct {
    core_name: []const u8,
    core_idx: usize,
    data: *const DataSet,
};

const MagazineSortCtx = struct {
    core_name: []const u8,
    core_idx: usize,
    data: *const DataSet,
};

fn topParts(
    allocator: std.mem.Allocator,
    parts: []const Part,
    core_name: []const u8,
    core_idx: usize,
    data: *const DataSet,
    max_count: usize,
) !PartSelection {
    var copied = try allocator.dupe(Part, parts);
    std.mem.sort(Part, copied, PartSortCtx{ .core_name = core_name, .core_idx = core_idx, .data = data }, struct {
        fn lessThan(ctx: PartSortCtx, a: Part, b: Part) bool {
            const a_idx = ctx.data.categories.get(a.category) orelse return false;
            const b_idx = ctx.data.categories.get(b.category) orelse return false;
            const a_pen = ctx.data.penalties[ctx.core_idx][a_idx];
            const b_pen = ctx.data.penalties[ctx.core_idx][b_idx];
            return partScore(ctx.core_name, a.name, a.damage_mod, a.fire_rate_mod, a_pen) >
                partScore(ctx.core_name, b.name, b.damage_mod, b.fire_rate_mod, b_pen);
        }
    }.lessThan);
    return .{ .all = copied, .view = copied[0..@min(max_count, copied.len)] };
}

fn topMagazines(
    allocator: std.mem.Allocator,
    mags: []const Magazine,
    core_name: []const u8,
    core_idx: usize,
    data: *const DataSet,
    max_count: usize,
) !MagazineSelection {
    var copied = try allocator.dupe(Magazine, mags);
    std.mem.sort(Magazine, copied, MagazineSortCtx{ .core_name = core_name, .core_idx = core_idx, .data = data }, struct {
        fn lessThan(ctx: MagazineSortCtx, a: Magazine, b: Magazine) bool {
            const a_idx = ctx.data.categories.get(a.category) orelse return false;
            const b_idx = ctx.data.categories.get(b.category) orelse return false;
            const a_pen = ctx.data.penalties[ctx.core_idx][a_idx];
            const b_pen = ctx.data.penalties[ctx.core_idx][b_idx];
            const as = partScore(ctx.core_name, a.name, a.damage_mod, a.fire_rate_mod, a_pen) + a.magazine_size * 0.05;
            const bs = partScore(ctx.core_name, b.name, b.damage_mod, b.fire_rate_mod, b_pen) + b.magazine_size * 0.05;
            return as > bs;
        }
    }.lessThan);
    return .{ .all = copied, .view = copied[0..@min(max_count, copied.len)] };
}

fn includeCategory(config: Config, cat: []const u8) bool {
    if (config.include_categories.len == 0) return true;
    for (config.include_categories) |allowed| {
        if (std.ascii.eqlIgnoreCase(allowed, cat)) return true;
    }
    return false;
}

fn passesFilters(config: Config, result: Result) bool {
    return config.damage_range.contains(result.damage) and
        config.damage_end_range.contains(result.damage_end) and
        config.ttk_seconds_range.contains(result.ttk_seconds) and
        config.dps_range.contains(result.dps);
}

pub fn calculateTop(allocator: std.mem.Allocator, config: Config, data: *const DataSet) !std.array_list.Managed(Result) {
    var ignored_stats: CalculationStats = .{};
    return calculateTopWithStats(allocator, config, data, &ignored_stats);
}

pub fn calculateTopWithStats(
    allocator: std.mem.Allocator,
    config: Config,
    data: *const DataSet,
    stats: *CalculationStats,
) !std.array_list.Managed(Result) {
    stats.* = .{};
    var results = std.array_list.Managed(Result).init(allocator);
    errdefer results.deinit();

    const PushTop = struct {
        fn run(list: *std.array_list.Managed(Result), cfg: Config, value: Result) !void {
            if (cfg.top_n == 0) return;
            if (list.items.len < cfg.top_n) {
                try list.append(value);
            } else {
                const worst_idx = list.items.len - 1;
                if (!cmp(cfg, value, list.items[worst_idx])) return;
                list.items[worst_idx] = value;
            }
            std.mem.sort(Result, list.items, cfg, struct {
                fn lessThan(ctx: Config, a: Result, b: Result) bool {
                    return cmp(ctx, a, b);
                }
            }.lessThan);
        }
    };

    for (data.cores.items) |core| {
        stats.cores_considered += 1;
        if (!includeCategory(config, core.category)) {
            stats.cores_skipped_by_category += 1;
            continue;
        }

        const core_idx = data.categories.get(core.category) orelse continue;

        const mag_candidates = try topMagazines(allocator, data.magazines.items, core.name, core_idx, data, config.part_pool_per_type);
        defer allocator.free(mag_candidates.all);
        const barrel_candidates = try topParts(allocator, data.barrels.items, core.name, core_idx, data, config.part_pool_per_type);
        defer allocator.free(barrel_candidates.all);
        const stock_candidates = try topParts(allocator, data.stocks.items, core.name, core_idx, data, config.part_pool_per_type);
        defer allocator.free(stock_candidates.all);
        const grip_candidates = try topParts(allocator, data.grips.items, core.name, core_idx, data, config.part_pool_per_type);
        defer allocator.free(grip_candidates.all);

        for (mag_candidates.view) |mag| {
            const mag_idx = data.categories.get(mag.category) orelse continue;
            const mag_pen = data.penalties[core_idx][mag_idx];

            for (barrel_candidates.view) |barrel| {
                const barrel_idx = data.categories.get(barrel.category) orelse continue;
                const barrel_pen = data.penalties[core_idx][barrel_idx];

                for (stock_candidates.view) |stock| {
                    const stock_idx = data.categories.get(stock.category) orelse continue;
                    const stock_pen = data.penalties[core_idx][stock_idx];

                    for (grip_candidates.view) |grip| {
                        stats.combinations_evaluated += 1;
                        const grip_idx = data.categories.get(grip.category) orelse continue;
                        const grip_pen = data.penalties[core_idx][grip_idx];

                        const dmg_mult =
                            (1 + adjustedMod(mag.damage_mod, core.name, mag.name, mag_pen) / 100.0) *
                            (1 + adjustedMod(barrel.damage_mod, core.name, barrel.name, barrel_pen) / 100.0) *
                            (1 + adjustedMod(stock.damage_mod, core.name, stock.name, stock_pen) / 100.0) *
                            (1 + adjustedMod(grip.damage_mod, core.name, grip.name, grip_pen) / 100.0);

                        const fr_mult =
                            (1 + adjustedMod(mag.fire_rate_mod, core.name, mag.name, mag_pen) / 100.0) *
                            (1 + adjustedMod(barrel.fire_rate_mod, core.name, barrel.name, barrel_pen) / 100.0) *
                            (1 + adjustedMod(stock.fire_rate_mod, core.name, stock.name, stock_pen) / 100.0) *
                            (1 + adjustedMod(grip.fire_rate_mod, core.name, grip.name, grip_pen) / 100.0);

                        const damage = core.damage * dmg_mult;
                        if (damage <= 0) continue;

                        const damage_end = core.damage_end * dmg_mult;
                        const fire_rate = core.fire_rate * fr_mult;
                        if (fire_rate <= 0) continue;

                        const shots = @ceil(config.player_max_health / damage);
                        const ttk_seconds = ((shots - 1) / fire_rate) * 60.0;

                        const res: Result = .{
                            .core = core.name,
                            .magazine = mag.name,
                            .barrel = barrel.name,
                            .stock = stock.name,
                            .grip = grip.name,
                            .damage = damage,
                            .damage_end = damage_end,
                            .fire_rate = fire_rate,
                            .magazine_size = mag.magazine_size,
                            .ttk_seconds = ttk_seconds,
                            .dps = (damage * fire_rate) / 60.0,
                        };

                        if (!passesFilters(config, res)) {
                            stats.combinations_filtered += 1;
                            continue;
                        }
                        try PushTop.run(&results, config, res);
                    }
                }
            }
        }
    }

    stats.results_kept = results.items.len;
    return results;
}

pub fn writeResults(writer: anytype, results: []const Result) !void {
    for (results, 0..) |r, idx| {
        try writer.print(
            "#{d}\n Core: {s}\n Magazine: {s}\n Barrel: {s}\n Stock: {s}\n Grip: {s}\n Damage: {d:.3}\n Damage End: {d:.3}\n Fire Rate: {d:.3}\n TTK: {d:.3}s\n DPS: {d:.3}\n\n",
            .{ idx + 1, r.core, r.magazine, r.barrel, r.stock, r.grip, r.damage, r.damage_end, r.fire_rate, r.ttk_seconds, r.dps },
        );
    }
}

test "range contains supports open-ended ranges" {
    try std.testing.expect((Range{ .min = 2, .max = 4 }).contains(3));
    try std.testing.expect(!(Range{ .min = 2, .max = 4 }).contains(5));
    try std.testing.expect((Range{ .min = 2 }).contains(500));
    try std.testing.expect((Range{ .max = 10 }).contains(-1));
}

test "adjustedMod zeros when names match" {
    try std.testing.expectEqual(@as(f64, 0), adjustedMod(10, "ABC", "ABC", 0.9));
    try std.testing.expectEqual(@as(f64, 9), adjustedMod(10, "A", "B", 0.9));
}

test "sort comparison honors priority" {
    const a = Result{ .core = "a", .magazine = "", .barrel = "", .stock = "", .grip = "", .damage = 10, .damage_end = 10, .fire_rate = 10, .magazine_size = 1, .ttk_seconds = 2, .dps = 5 };
    const b = Result{ .core = "b", .magazine = "", .barrel = "", .stock = "", .grip = "", .damage = 10, .damage_end = 10, .fire_rate = 10, .magazine_size = 1, .ttk_seconds = 3, .dps = 8 };
    try std.testing.expect(cmp(.{ .sort_key = .ttk, .priority = .auto }, a, b));
    try std.testing.expect(cmp(.{ .sort_key = .dps, .priority = .highest }, b, a));
}

fn appendOwnedPart(list: *std.array_list.Managed(Part), allocator: std.mem.Allocator, name: []const u8, category: []const u8, damage_mod: f64, fire_rate_mod: f64) !void {
    try list.append(.{
        .name = try allocator.dupe(u8, name),
        .category = try allocator.dupe(u8, category),
        .damage_mod = damage_mod,
        .fire_rate_mod = fire_rate_mod,
    });
}

test "calculateTopWithStats tracks evaluated combinations" {
    const allocator = std.testing.allocator;

    var data: DataSet = .{
        .cores = std.array_list.Managed(Core).init(allocator),
        .magazines = std.array_list.Managed(Magazine).init(allocator),
        .barrels = std.array_list.Managed(Part).init(allocator),
        .grips = std.array_list.Managed(Part).init(allocator),
        .stocks = std.array_list.Managed(Part).init(allocator),
        .penalties = try allocator.alloc([]f64, 1),
        .categories = std.StringHashMap(usize).init(allocator),
    };
    defer data.deinit(allocator);

    data.penalties[0] = try allocator.alloc(f64, 1);
    data.penalties[0][0] = 1.0;
    try data.categories.put(try allocator.dupe(u8, "AR"), 0);

    try data.cores.append(.{
        .name = try allocator.dupe(u8, "Core-1"),
        .category = try allocator.dupe(u8, "AR"),
        .damage = 50,
        .damage_end = 40,
        .fire_rate = 120,
    });
    try data.magazines.append(.{
        .name = try allocator.dupe(u8, "Mag-1"),
        .category = try allocator.dupe(u8, "AR"),
        .magazine_size = 20,
        .reload_time = 1.0,
        .damage_mod = 0,
        .fire_rate_mod = 0,
    });
    try appendOwnedPart(&data.barrels, allocator, "Barrel-1", "AR", 0, 0);
    try appendOwnedPart(&data.stocks, allocator, "Stock-1", "AR", 0, 0);
    try appendOwnedPart(&data.grips, allocator, "Grip-1", "AR", 0, 0);

    var stats: CalculationStats = undefined;
    var results = try calculateTopWithStats(allocator, .{ .top_n = 5 }, &data, &stats);
    defer results.deinit();

    try std.testing.expectEqual(@as(usize, 1), stats.cores_considered);
    try std.testing.expectEqual(@as(usize, 1), stats.combinations_evaluated);
    try std.testing.expectEqual(@as(usize, 0), stats.combinations_filtered);
    try std.testing.expectEqual(@as(usize, 1), stats.results_kept);
    try std.testing.expectEqual(@as(usize, 1), results.items.len);
}

test "calculateTopWithStats tracks filtered combinations" {
    const allocator = std.testing.allocator;

    var data: DataSet = .{
        .cores = std.array_list.Managed(Core).init(allocator),
        .magazines = std.array_list.Managed(Magazine).init(allocator),
        .barrels = std.array_list.Managed(Part).init(allocator),
        .grips = std.array_list.Managed(Part).init(allocator),
        .stocks = std.array_list.Managed(Part).init(allocator),
        .penalties = try allocator.alloc([]f64, 1),
        .categories = std.StringHashMap(usize).init(allocator),
    };
    defer data.deinit(allocator);

    data.penalties[0] = try allocator.alloc(f64, 1);
    data.penalties[0][0] = 1.0;
    try data.categories.put(try allocator.dupe(u8, "AR"), 0);

    try data.cores.append(.{
        .name = try allocator.dupe(u8, "Core-1"),
        .category = try allocator.dupe(u8, "AR"),
        .damage = 50,
        .damage_end = 40,
        .fire_rate = 120,
    });
    try data.magazines.append(.{
        .name = try allocator.dupe(u8, "Mag-1"),
        .category = try allocator.dupe(u8, "AR"),
        .magazine_size = 20,
        .reload_time = 1.0,
        .damage_mod = 0,
        .fire_rate_mod = 0,
    });
    try appendOwnedPart(&data.barrels, allocator, "Barrel-1", "AR", 0, 0);
    try appendOwnedPart(&data.stocks, allocator, "Stock-1", "AR", 0, 0);
    try appendOwnedPart(&data.grips, allocator, "Grip-1", "AR", 0, 0);

    var stats: CalculationStats = undefined;
    var results = try calculateTopWithStats(allocator, .{
        .top_n = 5,
        .damage_range = .{ .min = 9999 },
    }, &data, &stats);
    defer results.deinit();

    try std.testing.expectEqual(@as(usize, 1), stats.combinations_evaluated);
    try std.testing.expectEqual(@as(usize, 1), stats.combinations_filtered);
    try std.testing.expectEqual(@as(usize, 0), stats.results_kept);
    try std.testing.expectEqual(@as(usize, 0), results.items.len);
}
