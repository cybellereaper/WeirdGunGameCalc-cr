const std = @import("std");
const model = @import("model.zig");

fn getNum(v: std.json.Value, key: []const u8, default: f64) f64 {
    if (v.object.get(key)) |node| {
        return switch (node) {
            .integer => @floatFromInt(node.integer),
            .float => node.float,
            else => default,
        };
    }
    return default;
}

fn getStr(v: std.json.Value, key: []const u8, default: []const u8) []const u8 {
    if (v.object.get(key)) |node| {
        if (node == .string) return node.string;
    }
    return default;
}

fn copyStr(allocator: std.mem.Allocator, v: []const u8) ![]const u8 {
    return try allocator.dupe(u8, v);
}

fn getPair(v: std.json.Value, key: []const u8, default: [2]f64) [2]f64 {
    if (v.object.get(key)) |node| {
        if (node == .array and node.array.items.len >= 2) {
            const a = switch (node.array.items[0]) {
                .integer => |x| @as(f64, @floatFromInt(x)),
                .float => |x| x,
                else => default[0],
            };
            const b = switch (node.array.items[1]) {
                .integer => |x| @as(f64, @floatFromInt(x)),
                .float => |x| x,
                else => default[1],
            };
            return .{ a, b };
        }
    }
    return default;
}

fn parsePart(allocator: std.mem.Allocator, value: std.json.Value) !model.Part {
    return .{
        .name = try copyStr(allocator, getStr(value, "Name", "Unknown")),
        .category = try copyStr(allocator, getStr(value, "Category", "Weird")),
        .price_type = try copyStr(allocator, getStr(value, "Price_Type", "Free")),
        .damage = getNum(value, "Damage", 0),
        .fire_rate = getNum(value, "Fire_Rate", 0),
        .spread = getNum(value, "Spread", 0),
        .recoil = getNum(value, "Recoil", 0),
        .reload_speed = getNum(value, "Reload_Speed", 0),
        .magazine_cap = getNum(value, "Magazine_Cap", 0),
        .movement_speed = getNum(value, "Movement_Speed", 0),
        .health = getNum(value, "Health", 0),
        .equip_time = getNum(value, "Equip_Time", 0),
        .pellets = getNum(value, "Pellets", 0),
        .detection_radius = getNum(value, "Detection_Radius", 0),
        .range = getNum(value, "Range", 0),
        .reload_time = getNum(value, "Reload_Time", 0),
        .magazine_size = getNum(value, "Magazine_Size", 0),
    };
}

fn parseCore(allocator: std.mem.Allocator, value: std.json.Value) !model.Core {
    const damage = getPair(value, "Damage", .{ 0, 0 });
    const range = getPair(value, "Dropoff_Studs", .{ 0, 0 });
    return .{
        .name = try copyStr(allocator, getStr(value, "Name", "Unknown")),
        .category = try copyStr(allocator, getStr(value, "Category", "Weird")),
        .price_type = try copyStr(allocator, getStr(value, "Price_Type", "Free")),
        .damage_start = damage[0],
        .damage_end = damage[1],
        .range_start = range[0],
        .range_end = range[1],
        .fire_rate = getNum(value, "Fire_Rate", 1),
        .hip_spread = getNum(value, "Hipfire_Spread", 0),
        .ads_spread = getNum(value, "ADS_Spread", 0),
        .time_to_aim = getNum(value, "Time_To_Aim", 0),
        .equip_time = getNum(value, "Equip_Time", 0),
        .movement_speed_modifier = getNum(value, "Movement_Speed_Modifier", 0),
        .health = getNum(value, "Health", 0),
        .pellets = getNum(value, "Pellets", 1),
        .burst = getNum(value, "Burst", 1),
        .detection_radius = getNum(value, "Detection_Radius", 0),
        .recoil_hip_v = getPair(value, "Recoil_Hip_Vertical", .{ 0, 0 }),
        .recoil_aim_v = getPair(value, "Recoil_Aim_Vertical", .{ 0, 0 }),
    };
}

pub fn parseDatabase(allocator: std.mem.Allocator, bytes: []const u8) !model.Database {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();

    var db = model.Database.init(allocator);
    errdefer db.deinit();

    const root = parsed.value.object;
    const categories = root.get("Categories").?.object;
    const primary = categories.get("Primary").?.object;
    const secondary = categories.get("Secondary").?.object;

    var it = primary.iterator();
    while (it.next()) |entry| {
        try db.category_to_idx.put(try copyStr(allocator, entry.key_ptr.*), @intCast(entry.value_ptr.*.integer));
    }
    it = secondary.iterator();
    while (it.next()) |entry| {
        try db.category_to_idx.put(try copyStr(allocator, entry.key_ptr.*), @intCast(entry.value_ptr.*.integer));
    }

    const penalties = root.get("Penalties").?.array;
    for (penalties.items) |row| {
        var out: std.ArrayListUnmanaged(f64) = .{};
        for (row.array.items) |v| {
            const value: f64 = switch (v) {
                .integer => @floatFromInt(v.integer),
                .float => v.float,
                else => 1,
            };
            try out.append(allocator, value);
        }
        try db.penalties.append(allocator, out);
    }

    const data = root.get("Data").?.object;
    for (data.get("Cores").?.array.items) |v| try db.cores.append(allocator, try parseCore(allocator, v));
    for (data.get("Magazines").?.array.items) |v| try db.magazines.append(allocator, try parsePart(allocator, v));
    for (data.get("Barrels").?.array.items) |v| try db.barrels.append(allocator, try parsePart(allocator, v));
    for (data.get("Grips").?.array.items) |v| try db.grips.append(allocator, try parsePart(allocator, v));
    for (data.get("Stocks").?.array.items) |v| try db.stocks.append(allocator, try parsePart(allocator, v));

    return db;
}
