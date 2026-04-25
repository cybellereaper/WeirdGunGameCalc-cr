use clap::Parser;
use wggcalc::{
    calculator::Engine,
    data::{Config, PriceType, Range, SortKey, SortPriority},
    parser::load_data,
    presenter::write_results,
};

#[derive(Parser, Debug)]
#[command(name = "wggcalc")]
struct Cli {
    #[arg(long = "data", default_value = "Data/FullData.sqlite3")]
    data_path: String,
    #[arg(long = "top", default_value_t = 10)]
    top_n: usize,
    #[arg(long = "mh", default_value_t = 100.0)]
    player_max_health: f64,
    #[arg(long = "sort", default_value = "ttk")]
    sort: String,
    #[arg(long = "priority", default_value = "auto")]
    priority: String,
    #[arg(long = "include")]
    include_categories: Option<String>,
    #[arg(long = "part-pool", default_value_t = 20)]
    part_pool_per_type: usize,

    #[arg(long = "damage", value_delimiter = ',', num_args = 2)]
    damage: Option<Vec<f64>>,
    #[arg(long = "damage-min")]
    damage_min: Option<f64>,
    #[arg(long = "damage-max")]
    damage_max: Option<f64>,

    #[arg(
        long = "damageStart",
        alias = "range",
        value_delimiter = ',',
        num_args = 2
    )]
    damage_start: Option<Vec<f64>>,
    #[arg(long = "damage-end", value_delimiter = ',', num_args = 2)]
    damage_end: Option<Vec<f64>>,
    #[arg(long = "damage-end-min")]
    damage_end_min: Option<f64>,
    #[arg(long = "damage-end-max")]
    damage_end_max: Option<f64>,

    #[arg(long = "magazine", value_delimiter = ',', num_args = 2)]
    magazine: Option<Vec<f64>>,
    #[arg(long = "magazine-min")]
    magazine_min: Option<f64>,
    #[arg(long = "magazine-max")]
    magazine_max: Option<f64>,

    #[arg(long = "spreadHip", value_delimiter = ',', num_args = 2)]
    spread_hip: Option<Vec<f64>>,
    #[arg(long = "spread-hip-min")]
    spread_hip_min: Option<f64>,
    #[arg(long = "spread-hip-max")]
    spread_hip_max: Option<f64>,

    #[arg(long = "spreadAim", value_delimiter = ',', num_args = 2)]
    spread_aim: Option<Vec<f64>>,
    #[arg(long = "spread-aim-min")]
    spread_aim_min: Option<f64>,
    #[arg(long = "spread-aim-max")]
    spread_aim_max: Option<f64>,

    #[arg(long = "recoilHip", value_delimiter = ',', num_args = 2)]
    recoil_hip: Option<Vec<f64>>,
    #[arg(long = "recoil-hip-min")]
    recoil_hip_min: Option<f64>,
    #[arg(long = "recoil-hip-max")]
    recoil_hip_max: Option<f64>,

    #[arg(long = "recoilAim", value_delimiter = ',', num_args = 2)]
    recoil_aim: Option<Vec<f64>>,
    #[arg(long = "recoil-aim-min")]
    recoil_aim_min: Option<f64>,
    #[arg(long = "recoil-aim-max")]
    recoil_aim_max: Option<f64>,

    #[arg(long = "speed", value_delimiter = ',', num_args = 2)]
    speed: Option<Vec<f64>>,
    #[arg(long = "speed-min")]
    speed_min: Option<f64>,
    #[arg(long = "speed-max")]
    speed_max: Option<f64>,

    #[arg(long = "fireRate", value_delimiter = ',', num_args = 2)]
    fire_rate: Option<Vec<f64>>,
    #[arg(long = "fire-rate-min")]
    fire_rate_min: Option<f64>,
    #[arg(long = "fire-rate-max")]
    fire_rate_max: Option<f64>,

    #[arg(long = "health", value_delimiter = ',', num_args = 2)]
    health: Option<Vec<f64>>,
    #[arg(long = "health-min")]
    health_min: Option<f64>,
    #[arg(long = "health-max")]
    health_max: Option<f64>,

    #[arg(long = "pellet", value_delimiter = ',', num_args = 2)]
    pellet: Option<Vec<f64>>,
    #[arg(long = "pellet-min")]
    pellet_min: Option<f64>,
    #[arg(long = "pellet-max")]
    pellet_max: Option<f64>,

    #[arg(long = "timeToAim", value_delimiter = ',', num_args = 2)]
    time_to_aim: Option<Vec<f64>>,
    #[arg(long = "time-to-aim-min")]
    time_to_aim_min: Option<f64>,
    #[arg(long = "time-to-aim-max")]
    time_to_aim_max: Option<f64>,

    #[arg(long = "reload", value_delimiter = ',', num_args = 2)]
    reload: Option<Vec<f64>>,
    #[arg(long = "reload-min")]
    reload_min: Option<f64>,
    #[arg(long = "reload-max")]
    reload_max: Option<f64>,

    #[arg(long = "detectionRadius", value_delimiter = ',', num_args = 2)]
    detection_radius: Option<Vec<f64>>,
    #[arg(long = "detection-radius-min")]
    detection_radius_min: Option<f64>,
    #[arg(long = "detection-radius-max")]
    detection_radius_max: Option<f64>,

    #[arg(
        long = "range",
        alias = "rangeStart",
        value_delimiter = ',',
        num_args = 2
    )]
    range_start: Option<Vec<f64>>,
    #[arg(long = "range-min")]
    range_start_min: Option<f64>,
    #[arg(long = "range-max")]
    range_start_max: Option<f64>,

    #[arg(long = "rangeEnd", value_delimiter = ',', num_args = 2)]
    range_end: Option<Vec<f64>>,
    #[arg(long = "range-end-min")]
    range_end_min: Option<f64>,
    #[arg(long = "range-end-max")]
    range_end_max: Option<f64>,

    #[arg(long = "burst", value_delimiter = ',', num_args = 2)]
    burst: Option<Vec<f64>>,
    #[arg(long = "burst-min")]
    burst_min: Option<f64>,
    #[arg(long = "burst-max")]
    burst_max: Option<f64>,

    #[arg(long = "TTK", value_delimiter = ',', num_args = 2)]
    ttk: Option<Vec<f64>>,
    #[arg(long = "ttk-min")]
    ttk_min: Option<f64>,
    #[arg(long = "ttk-max")]
    ttk_max: Option<f64>,

    #[arg(long = "DPS", value_delimiter = ',', num_args = 2)]
    dps: Option<Vec<f64>>,
    #[arg(long = "dps-min")]
    dps_min: Option<f64>,
    #[arg(long = "dps-max")]
    dps_max: Option<f64>,

    #[arg(long = "fb", long = "forceBarrel", value_delimiter = ',')]
    force_barrels: Vec<String>,
    #[arg(long = "fm", long = "forceMagazine", value_delimiter = ',')]
    force_magazines: Vec<String>,
    #[arg(long = "fg", long = "forceGrip", value_delimiter = ',')]
    force_grips: Vec<String>,
    #[arg(long = "fs", long = "forceStock", value_delimiter = ',')]
    force_stocks: Vec<String>,
    #[arg(long = "fc", long = "forceCore", value_delimiter = ',')]
    force_cores: Vec<String>,

    #[arg(long = "bb", long = "banBarrel", value_delimiter = ',')]
    ban_barrels: Vec<String>,
    #[arg(long = "bm", long = "banMagazine", value_delimiter = ',')]
    ban_magazines: Vec<String>,
    #[arg(long = "bg", long = "banGrip", value_delimiter = ',')]
    ban_grips: Vec<String>,
    #[arg(long = "bs", long = "banStock", value_delimiter = ',')]
    ban_stocks: Vec<String>,
    #[arg(long = "bc", long = "banCore", value_delimiter = ',')]
    ban_cores: Vec<String>,

    #[arg(long = "banPriceType", value_delimiter = ',')]
    ban_price_types: Vec<String>,

    #[arg(long = "metrics", default_value_t = false)]
    metrics: bool,
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    let config = Config {
        data_path: cli.data_path.clone(),
        top_n: cli.top_n,
        player_max_health: cli.player_max_health,
        sort_key: parse_sort(&cli.sort)?,
        priority: parse_priority(&cli.priority)?,
        include_categories: split_csv(cli.include_categories),
        damage_range: range_from_args(cli.damage, cli.damage_start, cli.damage_min, cli.damage_max),
        damage_end_range: range_from_args(
            cli.damage_end,
            None,
            cli.damage_end_min,
            cli.damage_end_max,
        ),
        magazine_range: range_from_args(cli.magazine, None, cli.magazine_min, cli.magazine_max),
        spread_hip_range: range_from_args(
            cli.spread_hip,
            None,
            cli.spread_hip_min,
            cli.spread_hip_max,
        ),
        spread_aim_range: range_from_args(
            cli.spread_aim,
            None,
            cli.spread_aim_min,
            cli.spread_aim_max,
        ),
        recoil_hip_range: range_from_args(
            cli.recoil_hip,
            None,
            cli.recoil_hip_min,
            cli.recoil_hip_max,
        ),
        recoil_aim_range: range_from_args(
            cli.recoil_aim,
            None,
            cli.recoil_aim_min,
            cli.recoil_aim_max,
        ),
        speed_range: range_from_args(cli.speed, None, cli.speed_min, cli.speed_max),
        fire_rate_range: range_from_args(cli.fire_rate, None, cli.fire_rate_min, cli.fire_rate_max),
        health_range: range_from_args(cli.health, None, cli.health_min, cli.health_max),
        pellet_range: range_from_args(cli.pellet, None, cli.pellet_min, cli.pellet_max),
        time_to_aim_range: range_from_args(
            cli.time_to_aim,
            None,
            cli.time_to_aim_min,
            cli.time_to_aim_max,
        ),
        reload_range: range_from_args(cli.reload, None, cli.reload_min, cli.reload_max),
        detection_radius_range: range_from_args(
            cli.detection_radius,
            None,
            cli.detection_radius_min,
            cli.detection_radius_max,
        ),
        range_start_range: range_from_args(
            cli.range_start,
            None,
            cli.range_start_min,
            cli.range_start_max,
        ),
        range_end_range: range_from_args(cli.range_end, None, cli.range_end_min, cli.range_end_max),
        burst_range: range_from_args(cli.burst, None, cli.burst_min, cli.burst_max),
        ttk_seconds_range: range_from_args(cli.ttk, None, cli.ttk_min, cli.ttk_max),
        dps_range: range_from_args(cli.dps, None, cli.dps_min, cli.dps_max),
        force_cores: cli.force_cores,
        force_magazines: cli.force_magazines,
        force_barrels: cli.force_barrels,
        force_stocks: cli.force_stocks,
        force_grips: cli.force_grips,
        ban_cores: cli.ban_cores,
        ban_magazines: cli.ban_magazines,
        ban_barrels: cli.ban_barrels,
        ban_stocks: cli.ban_stocks,
        ban_grips: cli.ban_grips,
        ban_price_types: parse_price_types(&cli.ban_price_types)?,
        part_pool_per_type: cli.part_pool_per_type,
    };

    let total_start = std::time::Instant::now();
    let load_start = std::time::Instant::now();
    let data = load_data(&config.data_path)?;
    let load_ms = load_start.elapsed().as_secs_f64() * 1000.0;

    let calc_start = std::time::Instant::now();
    let engine = Engine::new(data.clone());
    let (results, stats) = engine.calculate_top(&config);
    let calc_ms = calc_start.elapsed().as_secs_f64() * 1000.0;

    println!(
        "Loaded {} cores, {} magazines, {} barrels, {} stocks, {} grips\n",
        data.cores.len(),
        data.magazines.len(),
        data.barrels.len(),
        data.stocks.len(),
        data.grips.len()
    );
    write_results(&results, std::io::stdout())?;

    if cli.metrics {
        println!("Performance metrics:");
        println!("  Data load: {:.3} ms", load_ms);
        println!("  Calculation: {:.3} ms", calc_ms);
        println!(
            "  Total runtime: {:.3} ms",
            total_start.elapsed().as_secs_f64() * 1000.0
        );
        println!("  Cores considered: {}", stats.cores_considered);
        println!(
            "  Cores skipped by category: {}",
            stats.cores_skipped_by_category
        );
        println!("  Combinations evaluated: {}", stats.combinations_evaluated);
        println!("  Combinations filtered: {}", stats.combinations_filtered);
        println!("  Results kept: {}", stats.results_kept);
    }

    Ok(())
}

fn range_from_args(
    primary: Option<Vec<f64>>,
    alias: Option<Vec<f64>>,
    min: Option<f64>,
    max: Option<f64>,
) -> Range {
    let pair = primary.or(alias).unwrap_or_default();
    let pair_min = pair.first().copied();
    let pair_max = pair.get(1).copied();
    Range {
        min: min.or(pair_min),
        max: max.or(pair_max),
    }
}

fn split_csv(value: Option<String>) -> Vec<String> {
    value
        .map(|v| {
            v.split(',')
                .map(str::trim)
                .filter(|x| !x.is_empty())
                .map(String::from)
                .collect()
        })
        .unwrap_or_default()
}

fn parse_price_types(values: &[String]) -> anyhow::Result<Vec<PriceType>> {
    values
        .iter()
        .map(|value| match PriceType::parse(value) {
            PriceType::Unknown => anyhow::bail!("Invalid --banPriceType value: {value}"),
            parsed => Ok(parsed),
        })
        .collect()
}

fn parse_sort(value: &str) -> anyhow::Result<SortKey> {
    match value.to_ascii_lowercase().as_str() {
        "ttk" => Ok(SortKey::Ttk),
        "dps" => Ok(SortKey::Dps),
        "damage" => Ok(SortKey::Damage),
        "damageend" => Ok(SortKey::DamageEnd),
        "firerate" => Ok(SortKey::FireRate),
        "magazine" => Ok(SortKey::Magazine),
        _ => anyhow::bail!("Invalid sort key: {value}"),
    }
}

fn parse_priority(value: &str) -> anyhow::Result<SortPriority> {
    match value.to_ascii_lowercase().as_str() {
        "highest" => Ok(SortPriority::Highest),
        "lowest" => Ok(SortPriority::Lowest),
        "auto" => Ok(SortPriority::Auto),
        _ => anyhow::bail!("Invalid priority: {value}"),
    }
}
