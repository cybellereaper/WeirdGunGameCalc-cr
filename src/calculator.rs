use crate::data::{
    CalculationStats, Config, Core, DataSet, Magazine, Part, PriceType, ResultRow, SortKey,
    SortPriority,
};

pub struct Engine {
    data: DataSet,
}

impl Engine {
    pub fn new(data: DataSet) -> Self {
        Self { data }
    }

    pub fn calculate_top(&self, config: &Config) -> (Vec<ResultRow>, CalculationStats) {
        let mut results = Vec::new();
        let mut stats = CalculationStats::default();

        for core in &self.data.cores {
            stats.cores_considered += 1;
            if !include_category(&config.include_categories, &core.category)
                || !allowed_name(&core.name, &config.force_cores, &config.ban_cores)
                || config.ban_price_types.contains(&core.price_type)
            {
                stats.cores_skipped_by_category += 1;
                continue;
            }

            let Some(&core_idx) = self.data.categories.get(&core.category) else {
                continue;
            };

            let mags = self.top_magazines(
                core,
                core_idx,
                config.part_pool_per_type,
                PartSelectionFilter {
                    forced_names: &config.force_magazines,
                    banned_names: &config.ban_magazines,
                    banned_price_types: &config.ban_price_types,
                },
            );
            let barrels = self.top_parts(
                &self.data.barrels,
                core,
                core_idx,
                config.part_pool_per_type,
                PartSelectionFilter {
                    forced_names: &config.force_barrels,
                    banned_names: &config.ban_barrels,
                    banned_price_types: &config.ban_price_types,
                },
            );
            let stocks = self.top_parts(
                &self.data.stocks,
                core,
                core_idx,
                config.part_pool_per_type,
                PartSelectionFilter {
                    forced_names: &config.force_stocks,
                    banned_names: &config.ban_stocks,
                    banned_price_types: &config.ban_price_types,
                },
            );
            let grips = self.top_parts(
                &self.data.grips,
                core,
                core_idx,
                config.part_pool_per_type,
                PartSelectionFilter {
                    forced_names: &config.force_grips,
                    banned_names: &config.ban_grips,
                    banned_price_types: &config.ban_price_types,
                },
            );

            for mag in mags {
                for barrel in &barrels {
                    for stock in &stocks {
                        for grip in &grips {
                            stats.combinations_evaluated += 1;
                            let selection = Selection {
                                mag,
                                barrel,
                                stock,
                                grip,
                            };
                            let Some(res) = self.build_result(config, core, core_idx, &selection)
                            else {
                                continue;
                            };
                            if !passes_filters(config, &res) {
                                stats.combinations_filtered += 1;
                                continue;
                            }
                            push_top(&mut results, res, config);
                        }
                    }
                }
            }
        }

        stats.results_kept = results.len();
        (results, stats)
    }

    fn build_result(
        &self,
        config: &Config,
        core: &Core,
        core_idx: usize,
        selection: &Selection<'_>,
    ) -> Option<ResultRow> {
        let dmg_mult = self.percent_multiplier(
            core,
            core_idx,
            [
                (
                    &selection.mag.name,
                    &selection.mag.category,
                    selection.mag.damage_mod,
                ),
                (
                    &selection.barrel.name,
                    &selection.barrel.category,
                    selection.barrel.damage_mod,
                ),
                (
                    &selection.stock.name,
                    &selection.stock.category,
                    selection.stock.damage_mod,
                ),
                (
                    &selection.grip.name,
                    &selection.grip.category,
                    selection.grip.damage_mod,
                ),
            ],
        );
        let fr_mult = self.percent_multiplier(
            core,
            core_idx,
            [
                (
                    &selection.mag.name,
                    &selection.mag.category,
                    selection.mag.fire_rate_mod,
                ),
                (
                    &selection.barrel.name,
                    &selection.barrel.category,
                    selection.barrel.fire_rate_mod,
                ),
                (
                    &selection.stock.name,
                    &selection.stock.category,
                    selection.stock.fire_rate_mod,
                ),
                (
                    &selection.grip.name,
                    &selection.grip.category,
                    selection.grip.fire_rate_mod,
                ),
            ],
        );

        let damage = core.damage * dmg_mult;
        let fire_rate = core.fire_rate * fr_mult;
        if damage <= 0.0 || fire_rate <= 0.0 {
            return None;
        }

        let shots = (config.player_max_health / damage).ceil();
        let ttk_seconds = ((shots - 1.0) / fire_rate) * 60.0;

        Some(ResultRow {
            core: core.name.clone(),
            magazine: selection.mag.name.clone(),
            barrel: selection.barrel.name.clone(),
            stock: selection.stock.name.clone(),
            grip: selection.grip.name.clone(),
            damage,
            damage_end: core.damage_end * dmg_mult,
            fire_rate,
            magazine_size: selection.mag.magazine_size,
            reload: selection.mag.reload_time,
            spread_hip: core.spread_hip,
            spread_aim: core.spread_aim,
            recoil_hip: core.recoil_hip,
            recoil_aim: core.recoil_aim,
            speed: core.movement_speed,
            health: core.health,
            pellet: core.pellets,
            time_to_aim: core.time_to_aim,
            detection_radius: core.detection_radius,
            range_start: core.range_start,
            range_end: core.range_end,
            burst: core.burst,
            ttk_seconds,
            dps: (damage * fire_rate) / 60.0,
        })
    }

    fn percent_multiplier<const N: usize>(
        &self,
        core: &Core,
        core_idx: usize,
        parts: [(&String, &String, f64); N],
    ) -> f64 {
        let mut mult = 1.0;
        for (name, category, raw_mod) in parts {
            let penalty = self.penalty_for(core_idx, category);
            mult *= 1.0 + adjusted_mod(raw_mod, &core.name, name, penalty) / 100.0;
        }
        mult
    }

    fn penalty_for(&self, core_idx: usize, category: &str) -> f64 {
        let Some(&part_idx) = self.data.categories.get(category) else {
            return 1.0;
        };
        self.data
            .penalties
            .get(core_idx)
            .and_then(|row| row.get(part_idx).copied())
            .unwrap_or(1.0)
    }

    fn top_parts<'a>(
        &'a self,
        pool: &'a [Part],
        core: &Core,
        core_idx: usize,
        max_count: usize,
        filter: PartSelectionFilter<'_>,
    ) -> Vec<&'a Part> {
        let mut ranked: Vec<&Part> = pool
            .iter()
            .filter(|part| filter.allows(&part.name, part.price_type))
            .collect();
        ranked.sort_by(|a, b| {
            part_score(self, core, core_idx, b).total_cmp(&part_score(self, core, core_idx, a))
        });
        ranked.into_iter().take(max_count).collect()
    }

    fn top_magazines<'a>(
        &'a self,
        core: &Core,
        core_idx: usize,
        max_count: usize,
        filter: PartSelectionFilter<'_>,
    ) -> Vec<&'a Magazine> {
        let mut ranked: Vec<&Magazine> = self
            .data
            .magazines
            .iter()
            .filter(|mag| filter.allows(&mag.name, mag.price_type))
            .collect();
        ranked.sort_by(|a, b| {
            let sb = part_score_mag(self, core, core_idx, b) + b.magazine_size * 0.05;
            let sa = part_score_mag(self, core, core_idx, a) + a.magazine_size * 0.05;
            sb.total_cmp(&sa)
        });
        ranked.into_iter().take(max_count).collect()
    }
}

struct Selection<'a> {
    mag: &'a Magazine,
    barrel: &'a Part,
    stock: &'a Part,
    grip: &'a Part,
}

#[derive(Clone, Copy)]
struct PartSelectionFilter<'a> {
    forced_names: &'a [String],
    banned_names: &'a [String],
    banned_price_types: &'a [PriceType],
}

impl PartSelectionFilter<'_> {
    fn allows(&self, name: &str, price_type: PriceType) -> bool {
        allowed_name(name, self.forced_names, self.banned_names)
            && !self.banned_price_types.contains(&price_type)
    }
}

fn part_score(engine: &Engine, core: &Core, core_idx: usize, part: &Part) -> f64 {
    let penalty = engine.penalty_for(core_idx, &part.category);
    adjusted_mod(part.damage_mod, &core.name, &part.name, penalty)
        + adjusted_mod(part.fire_rate_mod, &core.name, &part.name, penalty) * 0.6
}

fn part_score_mag(engine: &Engine, core: &Core, core_idx: usize, mag: &Magazine) -> f64 {
    let penalty = engine.penalty_for(core_idx, &mag.category);
    adjusted_mod(mag.damage_mod, &core.name, &mag.name, penalty)
        + adjusted_mod(mag.fire_rate_mod, &core.name, &mag.name, penalty) * 0.6
}

fn adjusted_mod(raw: f64, core_name: &str, part_name: &str, penalty: f64) -> f64 {
    if core_name == part_name {
        0.0
    } else {
        raw * penalty
    }
}

fn include_category(allowed: &[String], category: &str) -> bool {
    allowed.is_empty() || contains_ignore_case(allowed, category)
}

fn passes_filters(config: &Config, result: &ResultRow) -> bool {
    config.damage_range.contains(result.damage)
        && config.damage_end_range.contains(result.damage_end)
        && config.magazine_range.contains(result.magazine_size)
        && config.spread_hip_range.contains(result.spread_hip)
        && config.spread_aim_range.contains(result.spread_aim)
        && config.recoil_hip_range.contains(result.recoil_hip)
        && config.recoil_aim_range.contains(result.recoil_aim)
        && config.speed_range.contains(result.speed)
        && config.fire_rate_range.contains(result.fire_rate)
        && config.health_range.contains(result.health)
        && config.pellet_range.contains(result.pellet)
        && config.time_to_aim_range.contains(result.time_to_aim)
        && config.reload_range.contains(result.reload)
        && config
            .detection_radius_range
            .contains(result.detection_radius)
        && config.range_start_range.contains(result.range_start)
        && config.range_end_range.contains(result.range_end)
        && config.burst_range.contains(result.burst)
        && config.ttk_seconds_range.contains(result.ttk_seconds)
        && config.dps_range.contains(result.dps)
}

fn allowed_name(name: &str, forced_names: &[String], banned_names: &[String]) -> bool {
    (forced_names.is_empty() || contains_ignore_case(forced_names, name))
        && !contains_ignore_case(banned_names, name)
}

fn contains_ignore_case(values: &[String], expected: &str) -> bool {
    values
        .iter()
        .any(|value| value.eq_ignore_ascii_case(expected))
}

fn metric(result: &ResultRow, key: SortKey) -> f64 {
    match key {
        SortKey::Ttk => result.ttk_seconds,
        SortKey::Dps => result.dps,
        SortKey::Damage => result.damage,
        SortKey::DamageEnd => result.damage_end,
        SortKey::FireRate => result.fire_rate,
        SortKey::Magazine => result.magazine_size,
    }
}

fn better(a: &ResultRow, b: &ResultRow, config: &Config) -> bool {
    let left = metric(a, config.sort_key);
    let right = metric(b, config.sort_key);
    let priority = if config.priority == SortPriority::Auto {
        if config.sort_key == SortKey::Ttk {
            SortPriority::Lowest
        } else {
            SortPriority::Highest
        }
    } else {
        config.priority
    };
    if priority == SortPriority::Highest {
        left > right
    } else {
        left < right
    }
}

fn push_top(results: &mut Vec<ResultRow>, candidate: ResultRow, config: &Config) {
    if config.top_n == 0 {
        return;
    }
    if results.len() < config.top_n {
        results.push(candidate);
    } else if better(&candidate, results.last().expect("non-empty"), config) {
        *results.last_mut().expect("non-empty") = candidate;
    } else {
        return;
    }

    results.sort_by(|a, b| {
        if better(a, b, config) {
            std::cmp::Ordering::Less
        } else {
            std::cmp::Ordering::Greater
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::data::{DataSet, Range};
    use std::collections::HashMap;

    fn base_dataset() -> DataSet {
        DataSet {
            cores: vec![Core {
                name: "Core A".into(),
                category: "AR".into(),
                damage: 10.0,
                damage_end: 8.0,
                fire_rate: 600.0,
                price_type: PriceType::Coin,
                spread_hip: 1.0,
                spread_aim: 0.5,
                recoil_hip: 2.0,
                recoil_aim: 1.0,
                movement_speed: 5.0,
                health: 100.0,
                pellets: 1.0,
                time_to_aim: 0.2,
                detection_radius: 20.0,
                range_start: 40.0,
                range_end: 80.0,
                burst: 3.0,
            }],
            magazines: vec![Magazine {
                name: "Mag A".into(),
                category: "AR".into(),
                magazine_size: 30.0,
                reload_time: 2.0,
                damage_mod: 0.0,
                fire_rate_mod: 0.0,
                price_type: PriceType::Coin,
            }],
            barrels: vec![Part {
                name: "Barrel A".into(),
                category: "AR".into(),
                damage_mod: 0.0,
                fire_rate_mod: 0.0,
                price_type: PriceType::Coin,
            }],
            grips: vec![Part {
                name: "Grip A".into(),
                category: "AR".into(),
                damage_mod: 0.0,
                fire_rate_mod: 0.0,
                price_type: PriceType::Coin,
            }],
            stocks: vec![Part {
                name: "Stock A".into(),
                category: "AR".into(),
                damage_mod: 0.0,
                fire_rate_mod: 0.0,
                price_type: PriceType::Coin,
            }],
            penalties: vec![vec![1.0]],
            categories: HashMap::from([(String::from("AR"), 0usize)]),
        }
    }

    #[test]
    fn force_and_ban_filters_apply_to_parts() {
        let mut data = base_dataset();
        data.barrels.push(Part {
            name: "Barrel B".into(),
            category: "AR".into(),
            damage_mod: 10.0,
            fire_rate_mod: 0.0,
            price_type: PriceType::Coin,
        });
        let engine = Engine::new(data);
        let mut config = Config {
            force_barrels: vec![String::from("Barrel A")],
            ..Config::default()
        };
        let (forced_results, _) = engine.calculate_top(&config);
        assert!(forced_results.iter().all(|r| r.barrel == "Barrel A"));

        config.force_barrels.clear();
        config.ban_barrels = vec![String::from("Barrel B")];
        let (ban_results, _) = engine.calculate_top(&config);
        assert!(ban_results.iter().all(|r| r.barrel != "Barrel B"));
    }

    #[test]
    fn price_type_ban_filters_out_matching_parts() {
        let mut data = base_dataset();
        data.magazines[0].price_type = PriceType::Robux;
        let engine = Engine::new(data);
        let config = Config {
            ban_price_types: vec![PriceType::Robux],
            ..Config::default()
        };
        let (results, _) = engine.calculate_top(&config);
        assert!(results.is_empty());
    }

    #[test]
    fn range_filters_apply_to_extended_metrics() {
        let engine = Engine::new(base_dataset());
        let config = Config {
            speed_range: Range {
                min: Some(4.0),
                max: Some(5.5),
            },
            reload_range: Range {
                min: Some(1.5),
                max: Some(2.5),
            },
            ..Config::default()
        };
        let (results, _) = engine.calculate_top(&config);
        assert!(!results.is_empty());
    }
}
