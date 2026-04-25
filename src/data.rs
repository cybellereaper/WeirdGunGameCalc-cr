use std::collections::HashMap;

#[derive(Debug, Clone, Copy, Default)]
pub struct Range {
    pub min: Option<f64>,
    pub max: Option<f64>,
}

impl Range {
    pub fn contains(&self, value: f64) -> bool {
        if self.min.is_some_and(|min| value < min) {
            return false;
        }
        if self.max.is_some_and(|max| value > max) {
            return false;
        }
        true
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SortKey {
    Ttk,
    Dps,
    Damage,
    DamageEnd,
    FireRate,
    Magazine,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SortPriority {
    Highest,
    Lowest,
    Auto,
}

#[derive(Debug, Clone)]
pub struct Config {
    pub data_path: String,
    pub top_n: usize,
    pub player_max_health: f64,
    pub sort_key: SortKey,
    pub priority: SortPriority,
    pub include_categories: Vec<String>,
    pub damage_range: Range,
    pub damage_end_range: Range,
    pub ttk_seconds_range: Range,
    pub dps_range: Range,
    pub part_pool_per_type: usize,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            data_path: "Data/FullData.sqlite3".to_string(),
            top_n: 10,
            player_max_health: 100.0,
            sort_key: SortKey::Ttk,
            priority: SortPriority::Auto,
            include_categories: Vec::new(),
            damage_range: Range::default(),
            damage_end_range: Range::default(),
            ttk_seconds_range: Range::default(),
            dps_range: Range::default(),
            part_pool_per_type: 20,
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct CalculationStats {
    pub cores_considered: usize,
    pub cores_skipped_by_category: usize,
    pub combinations_evaluated: u64,
    pub combinations_filtered: u64,
    pub results_kept: usize,
}

#[derive(Debug, Clone)]
pub struct Core {
    pub name: String,
    pub category: String,
    pub damage: f64,
    pub damage_end: f64,
    pub fire_rate: f64,
}
#[derive(Debug, Clone)]
pub struct Magazine {
    pub name: String,
    pub category: String,
    pub magazine_size: f64,
    pub reload_time: f64,
    pub damage_mod: f64,
    pub fire_rate_mod: f64,
}
#[derive(Debug, Clone)]
pub struct Part {
    pub name: String,
    pub category: String,
    pub damage_mod: f64,
    pub fire_rate_mod: f64,
}
#[derive(Debug, Clone)]
pub struct ResultRow {
    pub core: String,
    pub magazine: String,
    pub barrel: String,
    pub stock: String,
    pub grip: String,
    pub damage: f64,
    pub damage_end: f64,
    pub fire_rate: f64,
    pub magazine_size: f64,
    pub ttk_seconds: f64,
    pub dps: f64,
}

#[derive(Debug, Clone)]
pub struct DataSet {
    pub cores: Vec<Core>,
    pub magazines: Vec<Magazine>,
    pub barrels: Vec<Part>,
    pub grips: Vec<Part>,
    pub stocks: Vec<Part>,
    pub penalties: Vec<Vec<f64>>,
    pub categories: HashMap<String, usize>,
}
