use clap::Parser;
use wggcalc::{
    calculator::Engine,
    data::{Config, Range, SortKey, SortPriority},
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
    #[arg(long = "damage-min")]
    damage_min: Option<f64>,
    #[arg(long = "damage-max")]
    damage_max: Option<f64>,
    #[arg(long = "damage-end-min")]
    damage_end_min: Option<f64>,
    #[arg(long = "damage-end-max")]
    damage_end_max: Option<f64>,
    #[arg(long = "ttk-min")]
    ttk_min: Option<f64>,
    #[arg(long = "ttk-max")]
    ttk_max: Option<f64>,
    #[arg(long = "dps-min")]
    dps_min: Option<f64>,
    #[arg(long = "dps-max")]
    dps_max: Option<f64>,
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
        include_categories: cli
            .include_categories
            .map(|v| {
                v.split(',')
                    .filter(|x| !x.is_empty())
                    .map(String::from)
                    .collect()
            })
            .unwrap_or_default(),
        damage_range: Range {
            min: cli.damage_min,
            max: cli.damage_max,
        },
        damage_end_range: Range {
            min: cli.damage_end_min,
            max: cli.damage_end_max,
        },
        ttk_seconds_range: Range {
            min: cli.ttk_min,
            max: cli.ttk_max,
        },
        dps_range: Range {
            min: cli.dps_min,
            max: cli.dps_max,
        },
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
