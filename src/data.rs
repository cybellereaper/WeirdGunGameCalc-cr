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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PriceType {
    Coin,
    Wc,
    Robux,
    Limited,
    Special,
    Unknown,
}

impl PriceType {
    pub fn parse(value: &str) -> Self {
        match value.trim().to_ascii_uppercase().as_str() {
            "COIN" => Self::Coin,
            "WC" => Self::Wc,
            "ROBUX" => Self::Robux,
            "LIMITED" => Self::Limited,
            "SPECIAL" => Self::Special,
            _ => Self::Unknown,
        }
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
    pub magazine_range: Range,
    pub fire_rate_range: Range,
    pub reload_range: Range,
    pub speed_range: Range,
    pub health_range: Range,
    pub pellet_range: Range,
    pub time_to_aim_range: Range,
    pub detection_radius_range: Range,
    pub range_start_range: Range,
    pub range_end_range: Range,
    pub burst_range: Range,
    pub spread_hip_range: Range,
    pub spread_aim_range: Range,
    pub recoil_hip_range: Range,
    pub recoil_aim_range: Range,
    pub force_cores: Vec<String>,
    pub force_magazines: Vec<String>,
    pub force_barrels: Vec<String>,
    pub force_stocks: Vec<String>,
    pub force_grips: Vec<String>,
    pub ban_cores: Vec<String>,
    pub ban_magazines: Vec<String>,
    pub ban_barrels: Vec<String>,
    pub ban_stocks: Vec<String>,
    pub ban_grips: Vec<String>,
    pub ban_price_types: Vec<PriceType>,
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
            magazine_range: Range::default(),
            fire_rate_range: Range::default(),
            reload_range: Range::default(),
            speed_range: Range::default(),
            health_range: Range::default(),
            pellet_range: Range::default(),
            time_to_aim_range: Range::default(),
            detection_radius_range: Range::default(),
            range_start_range: Range::default(),
            range_end_range: Range::default(),
            burst_range: Range::default(),
            spread_hip_range: Range::default(),
            spread_aim_range: Range::default(),
            recoil_hip_range: Range::default(),
            recoil_aim_range: Range::default(),
            force_cores: Vec::new(),
            force_magazines: Vec::new(),
            force_barrels: Vec::new(),
            force_stocks: Vec::new(),
            force_grips: Vec::new(),
            ban_cores: Vec::new(),
            ban_magazines: Vec::new(),
            ban_barrels: Vec::new(),
            ban_stocks: Vec::new(),
            ban_grips: Vec::new(),
            ban_price_types: Vec::new(),
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
    pub price_type: PriceType,
    pub spread_hip: f64,
    pub spread_aim: f64,
    pub recoil_hip: f64,
    pub recoil_aim: f64,
    pub movement_speed: f64,
    pub health: f64,
    pub pellets: f64,
    pub time_to_aim: f64,
    pub detection_radius: f64,
    pub range_start: f64,
    pub range_end: f64,
    pub burst: f64,
}
#[derive(Debug, Clone)]
pub struct Magazine {
    pub name: String,
    pub category: String,
    pub magazine_size: f64,
    pub reload_time: f64,
    pub damage_mod: f64,
    pub fire_rate_mod: f64,
    pub price_type: PriceType,
}
#[derive(Debug, Clone)]
pub struct Part {
    pub name: String,
    pub category: String,
    pub damage_mod: f64,
    pub fire_rate_mod: f64,
    pub price_type: PriceType,
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
    pub reload: f64,
    pub spread_hip: f64,
    pub spread_aim: f64,
    pub recoil_hip: f64,
    pub recoil_aim: f64,
    pub speed: f64,
    pub health: f64,
    pub pellet: f64,
    pub time_to_aim: f64,
    pub detection_radius: f64,
    pub range_start: f64,
    pub range_end: f64,
    pub burst: f64,
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
