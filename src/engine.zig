const std = @import("std");
const model = @import("model.zig");

pub const Config = struct {
    max_health: f64 = 100,
    top_n: usize = 10,
    sort_metric: model.SortMetric = .ttk,
    include_categories: []const []const u8 = &.{},
};

fn moreIsBetter(stat: model.Stat) bool {
    return switch (stat) {
        .damage, .fire_rate, .magazine, .movement_speed, .health, .pellets, .detection_radius, .range, .dps => true,
        .spread, .recoil, .reload, .equip_time, .ttk => false,
    };
}

fn shouldPenaltyApply(base: f64, stat: model.Stat) bool {
    return (base > 0 and moreIsBetter(stat)) or (base < 0 and !moreIsBetter(stat));
}

fn withPenalty(db: *const model.Database, core: model.Core, part: model.Part, stat: model.Stat, base: f64) f64 {
    if (std.mem.eql(u8, core.name, part.name)) return 0;
    const core_idx = db.category_to_idx.get(core.category) orelse return base;
    const part_idx = db.category_to_idx.get(part.category) orelse return base;
    if (!shouldPenaltyApply(base, stat)) return base;
    if (core_idx >= db.penalties.items.len) return base;
    if (part_idx >= db.penalties.items[core_idx].items.len) return base;
    return base * db.penalties.items[core_idx].items[part_idx];
}

fn applyPercent(value: f64, pct: f64) f64 {
    return value * (1 + (pct / 100));
}

pub fn evaluate(db: *const model.Database, core: model.Core, mag: model.Part, barrel: model.Part, grip: model.Part, stock: model.Part, max_health: f64) model.GunStats {
    var damage = core.damage_start;
    var damage_end = core.damage_end;
    var fire_rate = core.fire_rate;
    var reload_time = mag.reload_time;
    var magazine_size = mag.magazine_size;
    var hip_spread = core.hip_spread;
    var ads_spread = core.ads_spread;

    const parts = [_]model.Part{ mag, barrel, grip, stock };
    for (parts) |p| {
        damage = applyPercent(damage, withPenalty(db, core, p, .damage, p.damage));
        damage_end = applyPercent(damage_end, withPenalty(db, core, p, .damage, p.damage));
        fire_rate = applyPercent(fire_rate, withPenalty(db, core, p, .fire_rate, p.fire_rate));
        reload_time = applyPercent(reload_time, withPenalty(db, core, p, .reload, p.reload_speed));
        magazine_size = @round(applyPercent(magazine_size, withPenalty(db, core, p, .magazine, p.magazine_cap)));
        const spread_mod = withPenalty(db, core, p, .spread, p.spread);
        hip_spread = applyPercent(hip_spread, spread_mod);
        ads_spread = applyPercent(ads_spread, spread_mod);
    }

    if (damage <= 0 or fire_rate <= 0) {
        return .{
            .damage = damage,
            .damage_end = damage_end,
            .fire_rate = fire_rate,
            .ttk_seconds = std.math.inf(f64),
            .dps = 0,
            .reload_time = reload_time,
            .magazine_size = magazine_size,
            .hip_spread = hip_spread,
            .ads_spread = ads_spread,
        };
    }

    const shots_needed = @ceil(max_health / damage);
    const ttk_seconds = (shots_needed - 1) / (fire_rate / 60.0);
    const dps = damage * fire_rate / 60.0;

    return .{
        .damage = damage,
        .damage_end = damage_end,
        .fire_rate = fire_rate,
        .ttk_seconds = ttk_seconds,
        .dps = dps,
        .reload_time = reload_time,
        .magazine_size = magazine_size,
        .hip_spread = hip_spread,
        .ads_spread = ads_spread,
    };
}

fn scoreForMetric(stats: model.GunStats, metric: model.SortMetric) f64 {
    return switch (metric) {
        .ttk => -stats.ttk_seconds,
        .damage => stats.damage,
        .damage_end => stats.damage_end,
        .fire_rate => stats.fire_rate,
        .dps => stats.dps,
    };
}

pub fn computeTop(allocator: std.mem.Allocator, db: *const model.Database, cfg: Config) !std.ArrayListUnmanaged(model.Candidate) {
    var result: std.ArrayListUnmanaged(model.Candidate) = .{};

    for (db.cores.items, 0..) |core, core_idx| {
        if (cfg.include_categories.len > 0) {
            var found = false;
            for (cfg.include_categories) |cat| {
                if (std.ascii.eqlIgnoreCase(cat, core.category)) {
                    found = true;
                    break;
                }
            }
            if (!found) continue;
        }

        for (db.magazines.items, 0..) |mag, mag_idx| {
            for (db.barrels.items, 0..) |barrel, barrel_idx| {
                for (db.grips.items, 0..) |grip, grip_idx| {
                    for (db.stocks.items, 0..) |stock, stock_idx| {
                        const stats = evaluate(db, core, mag, barrel, grip, stock, cfg.max_health);
                        try result.append(allocator, .{
                            .core_idx = core_idx,
                            .magazine_idx = mag_idx,
                            .barrel_idx = barrel_idx,
                            .grip_idx = grip_idx,
                            .stock_idx = stock_idx,
                            .stats = stats,
                        });
                    }
                }
            }
        }
    }

    std.mem.sort(model.Candidate, result.items, cfg.sort_metric, struct {
        fn lessThan(metric: model.SortMetric, a: model.Candidate, b: model.Candidate) bool {
            return scoreForMetric(a.stats, metric) > scoreForMetric(b.stats, metric);
        }
    }.lessThan);

    if (result.items.len > cfg.top_n) result.shrinkRetainingCapacity(cfg.top_n);
    return result;
}

test "evaluate computes reasonable ttk and dps" {
    var db = model.Database.init(std.testing.allocator);
    defer db.deinit();
    const cat = try std.testing.allocator.dupe(u8, "AR");
    try db.category_to_idx.put(cat, 0);
    var row: std.ArrayListUnmanaged(f64) = .{};
    try row.append(std.testing.allocator, 1);
    try db.penalties.append(std.testing.allocator, row);

    const core = model.Core{ .name = "AK", .category = "AR", .price_type = "Free", .damage_start = 20, .damage_end = 18, .range_start = 100, .range_end = 200, .fire_rate = 600, .hip_spread = 5, .ads_spread = 1, .time_to_aim = 0.5, .equip_time = 0.7, .movement_speed_modifier = 0, .health = 0, .pellets = 1, .burst = 1, .detection_radius = 100, .recoil_hip_v = .{ 0, 0 }, .recoil_aim_v = .{ 0, 0 } };
    const p = model.Part{ .name = "X", .category = "AR", .price_type = "Free", .damage = 10, .reload_time = 2.0, .magazine_size = 30 };

    const stats = evaluate(&db, core, p, p, p, p, 100);
    try std.testing.expectApproxEqAbs(0.3, stats.ttk_seconds, 0.001);
    try std.testing.expect(stats.dps > 200);
}
