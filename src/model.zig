const std = @import("std");

pub const Stat = enum { damage, fire_rate, spread, recoil, reload, magazine, movement_speed, health, equip_time, pellets, detection_radius, range, ttk, dps };

pub const SortMetric = enum {
    ttk,
    damage,
    damage_end,
    fire_rate,
    dps,

    pub fn parse(value: []const u8) SortMetric {
        if (std.ascii.eqlIgnoreCase(value, "DAMAGE")) return .damage;
        if (std.ascii.eqlIgnoreCase(value, "DAMAGEEND")) return .damage_end;
        if (std.ascii.eqlIgnoreCase(value, "FIRERATE")) return .fire_rate;
        if (std.ascii.eqlIgnoreCase(value, "DPS")) return .dps;
        return .ttk;
    }
};

pub const Part = struct {
    name: []const u8,
    category: []const u8,
    price_type: []const u8,
    damage: f64 = 0,
    fire_rate: f64 = 0,
    spread: f64 = 0,
    recoil: f64 = 0,
    reload_speed: f64 = 0,
    magazine_cap: f64 = 0,
    movement_speed: f64 = 0,
    health: f64 = 0,
    equip_time: f64 = 0,
    pellets: f64 = 0,
    detection_radius: f64 = 0,
    range: f64 = 0,
    reload_time: f64 = 0,
    magazine_size: f64 = 0,
};

pub const Core = struct {
    name: []const u8,
    category: []const u8,
    price_type: []const u8,
    damage_start: f64,
    damage_end: f64,
    range_start: f64,
    range_end: f64,
    fire_rate: f64,
    hip_spread: f64,
    ads_spread: f64,
    time_to_aim: f64,
    equip_time: f64,
    movement_speed_modifier: f64,
    health: f64,
    pellets: f64,
    burst: f64,
    detection_radius: f64,
    recoil_hip_v: [2]f64,
    recoil_aim_v: [2]f64,
};

pub const GunStats = struct {
    damage: f64,
    damage_end: f64,
    fire_rate: f64,
    ttk_seconds: f64,
    dps: f64,
    reload_time: f64,
    magazine_size: f64,
    hip_spread: f64,
    ads_spread: f64,
};

pub const Candidate = struct {
    core_idx: usize,
    magazine_idx: usize,
    barrel_idx: usize,
    grip_idx: usize,
    stock_idx: usize,
    stats: GunStats,
};

pub const Database = struct {
    allocator: std.mem.Allocator,
    cores: std.ArrayListUnmanaged(Core) = .{},
    magazines: std.ArrayListUnmanaged(Part) = .{},
    barrels: std.ArrayListUnmanaged(Part) = .{},
    grips: std.ArrayListUnmanaged(Part) = .{},
    stocks: std.ArrayListUnmanaged(Part) = .{},
    penalties: std.ArrayListUnmanaged(std.ArrayListUnmanaged(f64)) = .{},
    category_to_idx: std.StringHashMap(usize),

    pub fn init(allocator: std.mem.Allocator) Database {
        return .{ .allocator = allocator, .category_to_idx = std.StringHashMap(usize).init(allocator) };
    }

    pub fn deinit(self: *Database) void {
        for (self.cores.items) |item| {
            self.allocator.free(item.name);
            self.allocator.free(item.category);
            self.allocator.free(item.price_type);
        }
        for (self.magazines.items) |item| {
            self.allocator.free(item.name);
            self.allocator.free(item.category);
            self.allocator.free(item.price_type);
        }
        for (self.barrels.items) |item| {
            self.allocator.free(item.name);
            self.allocator.free(item.category);
            self.allocator.free(item.price_type);
        }
        for (self.grips.items) |item| {
            self.allocator.free(item.name);
            self.allocator.free(item.category);
            self.allocator.free(item.price_type);
        }
        for (self.stocks.items) |item| {
            self.allocator.free(item.name);
            self.allocator.free(item.category);
            self.allocator.free(item.price_type);
        }
        var it = self.category_to_idx.iterator();
        while (it.next()) |entry| self.allocator.free(entry.key_ptr.*);
        for (self.penalties.items) |*row| row.deinit(self.allocator);
        self.penalties.deinit(self.allocator);
        self.cores.deinit(self.allocator);
        self.magazines.deinit(self.allocator);
        self.barrels.deinit(self.allocator);
        self.grips.deinit(self.allocator);
        self.stocks.deinit(self.allocator);
        self.category_to_idx.deinit();
    }
};
