use crate::data::{
    CalculationStats, Config, Core, DataSet, Magazine, Part, ResultRow, SortKey, SortPriority,
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
            if !include_category(&config.include_categories, &core.category) {
                stats.cores_skipped_by_category += 1;
                continue;
            }

            let Some(&core_idx) = self.data.categories.get(&core.category) else {
                continue;
            };
            let mags = self.top_magazines(core, core_idx, config.part_pool_per_type);
            let barrels = self.top_parts(
                &self.data.barrels,
                core,
                core_idx,
                config.part_pool_per_type,
            );
            let stocks =
                self.top_parts(&self.data.stocks, core, core_idx, config.part_pool_per_type);
            let grips = self.top_parts(&self.data.grips, core, core_idx, config.part_pool_per_type);

            for mag in mags {
                for barrel in &barrels {
                    for stock in &stocks {
                        for grip in &grips {
                            stats.combinations_evaluated += 1;
                            let Some(res) =
                                self.build_result(config, core, core_idx, mag, barrel, stock, grip)
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
        mag: &Magazine,
        barrel: &Part,
        stock: &Part,
        grip: &Part,
    ) -> Option<ResultRow> {
        let dmg_mult = self.percent_multiplier(
            core,
            core_idx,
            [
                (&mag.name, &mag.category, mag.damage_mod),
                (&barrel.name, &barrel.category, barrel.damage_mod),
                (&stock.name, &stock.category, stock.damage_mod),
                (&grip.name, &grip.category, grip.damage_mod),
            ],
        );
        let fr_mult = self.percent_multiplier(
            core,
            core_idx,
            [
                (&mag.name, &mag.category, mag.fire_rate_mod),
                (&barrel.name, &barrel.category, barrel.fire_rate_mod),
                (&stock.name, &stock.category, stock.fire_rate_mod),
                (&grip.name, &grip.category, grip.fire_rate_mod),
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
            magazine: mag.name.clone(),
            barrel: barrel.name.clone(),
            stock: stock.name.clone(),
            grip: grip.name.clone(),
            damage,
            damage_end: core.damage_end * dmg_mult,
            fire_rate,
            magazine_size: mag.magazine_size,
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
    ) -> Vec<&'a Part> {
        let mut ranked: Vec<&Part> = pool.iter().collect();
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
    ) -> Vec<&'a Magazine> {
        let mut ranked: Vec<&Magazine> = self.data.magazines.iter().collect();
        ranked.sort_by(|a, b| {
            let sb = part_score_mag(self, core, core_idx, b) + b.magazine_size * 0.05;
            let sa = part_score_mag(self, core, core_idx, a) + a.magazine_size * 0.05;
            sb.total_cmp(&sa)
        });
        ranked.into_iter().take(max_count).collect()
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
    allowed.is_empty() || allowed.iter().any(|c| c.eq_ignore_ascii_case(category))
}

fn passes_filters(config: &Config, result: &ResultRow) -> bool {
    config.damage_range.contains(result.damage)
        && config.damage_end_range.contains(result.damage_end)
        && config.ttk_seconds_range.contains(result.ttk_seconds)
        && config.dps_range.contains(result.dps)
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
