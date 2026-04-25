use anyhow::{anyhow, bail};
use csv::ReaderBuilder;
use reqwest::blocking::Client;
use rusqlite::{params, Connection};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};

pub const SHEET_ID: &str = "1Kc9aME3xlUC_vV5dFRe457OchqUOrwuiX_pQykjCF68";
pub const SHEET_FOLDER: &str = "SheetData";
pub const DATA_FOLDER: &str = "Data";
pub const PARTS_V2_SHEET_GID: &str = "319672878";
pub const CORES_SHEET_GID: &str = "911413911";
pub const PARTS_V2_SHEET: &str = "SheetData/parts2.csv";
pub const CORES_SHEET: &str = "SheetData/cores.csv";
pub const OUTPUT_FILE: &str = "Data/FullData.sqlite3";

pub const VALID_PART_CATEGORIES: [&str; 8] = [
    "AR", "Sniper", "SMG", "LMG", "Shotgun", "BR", "Weird", "Sidearm",
];
pub const VALID_PART_TYPES: [&str; 4] = ["Barrels", "Magazines", "Grips", "Stocks"];
pub const VALID_PRICE_TYPES: [&str; 11] = [
    "Coin",
    "WC",
    "Follow",
    "Robux",
    "Free",
    "Spin",
    "Limited",
    "Missions",
    "Verify discord",
    "Season Pass 1",
    "Unknown",
];

const PART_PROPERTY_NAMES: [&str; 14] = [
    "Magazine_Size",
    "Reload_Time",
    "Damage",
    "Detection_Radius",
    "Equip_Time",
    "Fire_Rate",
    "Health",
    "Magazine_Cap",
    "Movement_Speed",
    "Pellets",
    "Range",
    "Recoil",
    "Reload_Speed",
    "Spread",
];
const CORE_PROPERTY_NAMES: [&str; 16] = [
    "Damage",
    "Dropoff_Studs",
    "Fire_Rate",
    "Hipfire_Spread",
    "ADS_Spread",
    "Time_To_Aim",
    "Detection_Radius",
    "Burst",
    "Movement_Speed_Modifier",
    "Suppression",
    "Health",
    "Equip_Time",
    "Recoil_Hip_Horizontal",
    "Recoil_Hip_Vertical",
    "Recoil_Aim_Horizontal",
    "Recoil_Aim_Vertical",
];

#[derive(Debug, Clone, PartialEq)]
pub enum JsonValue {
    Null,
    Int(i64),
    Float(f64),
    Str(String),
    Bool(bool),
    Array(Vec<JsonValue>),
}
impl JsonValue {
    fn as_str(&self) -> Option<&str> {
        if let Self::Str(v) = self {
            Some(v)
        } else {
            None
        }
    }
}

pub type ItemRow = HashMap<String, JsonValue>;

#[derive(Debug, Clone)]
pub struct ExportData {
    pub data: HashMap<String, Vec<ItemRow>>,
    pub penalties: Vec<Vec<f64>>,
    pub categories: HashMap<String, HashMap<String, i32>>,
}

pub struct Normalizer;
impl Normalizer {
    pub fn normalize_numeric_value(
        raw_value: &str,
        expect_range: bool,
    ) -> anyhow::Result<JsonValue> {
        let value = raw_value.trim();
        if value.is_empty() || value == "🎲" {
            return Ok(JsonValue::Null);
        }
        let cleaned = value
            .replace(['°', 's'], "")
            .replace("rpm", "")
            .replace(['%', ','], "")
            .replace('>', "-")
            .trim()
            .to_string();
        if expect_range {
            let parts: Vec<_> = cleaned.split(" - ").collect();
            if parts.len() != 2 {
                bail!("Expected numeric range but got: {raw_value:?}");
            }
            return Ok(JsonValue::Array(
                parts
                    .into_iter()
                    .map(|p| coerce_number(parse_single_or_multiplier(p)))
                    .collect(),
            ));
        }
        Ok(coerce_number(parse_single_or_multiplier(&cleaned)))
    }

    pub fn detect_price_type(price: &str) -> String {
        let normalized = price.trim();
        if normalized.is_empty() {
            return "Coin".into();
        }
        if VALID_PRICE_TYPES.contains(&normalized) {
            return normalized.to_string();
        }
        let mut chars = normalized.chars();
        let first = chars.next().unwrap_or_default();
        let capitalized = format!("{}{}", first.to_uppercase(), chars.as_str().to_lowercase());
        if VALID_PRICE_TYPES.contains(&capitalized.as_str()) {
            return capitalized;
        }
        if normalized.contains("WC") || normalized == "Weird Boxes" {
            return "WC".into();
        }
        if normalized == "Exclusive Weird Boxes" {
            return "Robux".into();
        }
        if normalized.replace(',', "").parse::<i64>().is_ok() {
            return "Coin".into();
        }
        "Unknown".into()
    }
}

fn parse_single_or_multiplier(value: &str) -> f64 {
    if let Some((l, r)) = value.split_once('x') {
        return l.trim().parse::<f64>().unwrap_or(0.0) * r.trim().parse::<f64>().unwrap_or(0.0);
    }
    value.trim().parse::<f64>().unwrap_or(0.0)
}
fn coerce_number(value: f64) -> JsonValue {
    if value.fract() == 0.0 {
        JsonValue::Int(value as i64)
    } else {
        JsonValue::Float(value)
    }
}

pub struct PartsParser {
    seen_parts: HashMap<(String, String), HashSet<String>>,
}
impl Default for PartsParser {
    fn default() -> Self {
        Self::new()
    }
}
impl PartsParser {
    pub fn new() -> Self {
        let mut seen_parts = HashMap::new();
        for c in VALID_PART_CATEGORIES {
            for p in VALID_PART_TYPES {
                seen_parts.insert((c.to_string(), p.to_string()), HashSet::new());
            }
        }
        Self { seen_parts }
    }
    pub fn parse_rows(
        &mut self,
        rows: &[Vec<String>],
    ) -> anyhow::Result<HashMap<String, Vec<ItemRow>>> {
        let mut output: HashMap<String, Vec<ItemRow>> = HashMap::from([
            (String::from("Barrels"), vec![]),
            (String::from("Magazines"), vec![]),
            (String::from("Grips"), vec![]),
            (String::from("Stocks"), vec![]),
        ]);
        let mut current_category = "AR".to_string();
        let mut current_type = String::new();

        for row in rows {
            if row.is_empty() {
                continue;
            }
            if row.len() != 16 {
                bail!("Invalid parts row length: expected 16, got {}", row.len());
            }
            let name = row[1].trim().to_string();
            if let Some((cat, ptype)) = parse_divider(&name) {
                current_category = cat;
                current_type = ptype;
                continue;
            }
            if current_type.is_empty() {
                bail!("Part encountered before section header");
            }

            let seen_key = (current_category.clone(), current_type.clone());
            let seen = self
                .seen_parts
                .get_mut(&seen_key)
                .ok_or_else(|| anyhow!("unknown section"))?;
            if !seen.insert(name.clone()) {
                bail!("Duplicate part name {name}");
            }

            let mut part = ItemRow::from([
                (
                    "Price_Type".into(),
                    JsonValue::Str(Normalizer::detect_price_type(&row[0])),
                ),
                ("Name".into(), JsonValue::Str(name)),
                ("Category".into(), JsonValue::Str(current_category.clone())),
            ]);

            for idx in 2..=15 {
                let cell = row[idx].trim();
                if cell.is_empty() {
                    continue;
                }
                let token = extract_leading_token(cell)?;
                part.insert(
                    PART_PROPERTY_NAMES[idx - 2].into(),
                    Normalizer::normalize_numeric_value(&token, false)?,
                );
            }

            output.get_mut(&current_type).unwrap().push(part);
        }
        Ok(output)
    }

    pub fn parse_file(&mut self, path: &Path) -> anyhow::Result<HashMap<String, Vec<ItemRow>>> {
        let rows = read_csv_rows(path, 2, true)?;
        let mut truncated = Vec::new();
        for row in rows {
            if row.get(1).is_some_and(|name| name.starts_with("Notable ")) {
                break;
            }
            truncated.push(row);
        }
        self.parse_rows(&truncated)
    }
}

fn parse_divider(name: &str) -> Option<(String, String)> {
    let parts: Vec<_> = name.split(' ').collect();
    if parts.len() != 2 {
        return None;
    }
    let (cat, ptype) = (parts[0], parts[1]);
    if VALID_PART_CATEGORIES.contains(&cat) && VALID_PART_TYPES.contains(&ptype) {
        Some((cat.into(), ptype.into()))
    } else {
        None
    }
}

pub struct CoresParser;
impl CoresParser {
    pub fn parse_file(&self, path: &Path) -> anyhow::Result<Vec<ItemRow>> {
        let rows = read_csv_rows(path, 2, true)?;
        self.parse_rows(&rows)
    }

    pub fn parse_rows(&self, rows: &[Vec<String>]) -> anyhow::Result<Vec<ItemRow>> {
        let mut output = vec![];
        let mut current_category = "AR".to_string();
        for row in rows {
            if row.is_empty() {
                continue;
            }
            if row.len() < 18 {
                bail!(
                    "Invalid cores row length: expected at least 18, got {}",
                    row.len()
                );
            }
            let trimmed = &row[0..18];
            let name = trimmed[1].trim();
            if is_category_divider(name) {
                current_category = name.trim_end_matches(" Cores").to_string();
                continue;
            }

            let mut core = ItemRow::from([
                (
                    "Price_Type".into(),
                    JsonValue::Str(Normalizer::detect_price_type(&trimmed[0])),
                ),
                ("Name".into(), JsonValue::Str(name.to_string())),
                ("Category".into(), JsonValue::Str(current_category.clone())),
            ]);
            for idx in 2..=17 {
                if idx == 2 {
                    if let Some(p) = extract_pellets(&trimmed[idx]) {
                        core.insert("Pellets".into(), JsonValue::Int(p as i64));
                    }
                }
                let val =
                    Normalizer::normalize_numeric_value(&trimmed[idx], idx <= 3 || idx >= 14)?;
                if val != JsonValue::Null {
                    core.insert(CORE_PROPERTY_NAMES[idx - 2].into(), val);
                }
            }
            output.push(core);
        }
        Ok(output)
    }
}
fn is_category_divider(name: &str) -> bool {
    name.ends_with(" Cores") && VALID_PART_CATEGORIES.contains(&name.trim_end_matches(" Cores"))
}
fn extract_pellets(cell: &str) -> Option<i32> {
    cell.split(" > ").next()?.split_once('x')?.1.parse().ok()
}

pub fn extract_leading_token(cell: &str) -> anyhow::Result<String> {
    cell.split_once(' ')
        .map(|(v, _)| v.to_string())
        .ok_or_else(|| anyhow!("Invalid property cell format: {cell:?}"))
}

pub fn read_csv_rows(
    path: &Path,
    skip_header_rows: usize,
    trim_first_column: bool,
) -> anyhow::Result<Vec<Vec<String>>> {
    let mut reader = ReaderBuilder::new()
        .has_headers(false)
        .flexible(true)
        .from_path(path)?;
    let mut rows = Vec::new();
    for record in reader.records() {
        rows.push(record?.iter().map(ToString::to_string).collect::<Vec<_>>());
    }
    let rows = rows.into_iter().skip(skip_header_rows);
    if trim_first_column {
        Ok(rows
            .map(|row| row.into_iter().skip(1).collect::<Vec<_>>())
            .collect())
    } else {
        Ok(rows.collect())
    }
}

pub struct SheetExport {
    pub gid: String,
    pub output_path: PathBuf,
    pub url_override: Option<String>,
}
impl SheetExport {
    pub fn export_url(&self, sheet_id: &str) -> String {
        self.url_override.clone().unwrap_or_else(|| format!("https://docs.google.com/spreadsheets/d/{sheet_id}/export?format=csv&id={sheet_id}&gid={}", self.gid))
    }
}

pub struct SheetDownloader {
    sheet_id: String,
    sheet_folder: PathBuf,
    client: Client,
}
impl SheetDownloader {
    pub fn new(sheet_id: String, sheet_folder: PathBuf) -> Self {
        Self {
            sheet_id,
            sheet_folder,
            client: Client::builder()
                .redirect(reqwest::redirect::Policy::none())
                .build()
                .unwrap(),
        }
    }
    pub fn download(&self, exports: &[SheetExport]) -> anyhow::Result<()> {
        clear_sheet_folder(&self.sheet_folder)?;
        for export in exports {
            self.download_file(&export.export_url(&self.sheet_id), &export.output_path)?;
        }
        Ok(())
    }

    fn download_file(&self, url: &str, output_path: &Path) -> anyhow::Result<()> {
        let body = self.get_with_redirects(url)?;
        if let Some(parent) = output_path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(output_path, body)?;
        Ok(())
    }

    fn get_with_redirects(&self, initial_url: &str) -> anyhow::Result<String> {
        let mut url = initial_url.to_string();
        for _ in 0..=5 {
            let resp = self.client.get(&url).send()?;
            if !resp.status().is_redirection() {
                return Ok(resp.error_for_status()?.text()?);
            }
            let location = resp
                .headers()
                .get("Location")
                .ok_or_else(|| anyhow!("Redirect response missing Location header"))?
                .to_str()?;
            url = if location.starts_with("http://") || location.starts_with("https://") {
                location.to_string()
            } else {
                let parsed = reqwest::Url::parse(&url)?;
                format!(
                    "{}://{}{}",
                    parsed.scheme(),
                    parsed.host_str().unwrap_or_default(),
                    if location.starts_with('/') {
                        location.to_string()
                    } else {
                        format!("/{location}")
                    }
                )
            };
        }
        bail!("Too many redirects while downloading {initial_url}")
    }
}

pub fn build_full_data(parts_file: &Path, cores_file: &Path) -> anyhow::Result<ExportData> {
    let mut parts_parser = PartsParser::new();
    let parts_data = parts_parser.parse_file(parts_file)?;
    let cores_parser = CoresParser;
    let cores_data = cores_parser.parse_file(cores_file)?;

    let mut combined = HashMap::new();
    combined.insert(
        "Barrels".to_string(),
        parts_data.get("Barrels").cloned().unwrap_or_default(),
    );
    combined.insert(
        "Magazines".to_string(),
        parts_data.get("Magazines").cloned().unwrap_or_default(),
    );
    combined.insert(
        "Grips".to_string(),
        parts_data.get("Grips").cloned().unwrap_or_default(),
    );
    combined.insert(
        "Stocks".to_string(),
        parts_data.get("Stocks").cloned().unwrap_or_default(),
    );
    combined.insert("Cores".to_string(), cores_data);

    let categories = HashMap::from([
        (
            "Primary".to_string(),
            HashMap::from([
                ("AR".to_string(), 0),
                ("Sniper".to_string(), 1),
                ("SMG".to_string(), 2),
                ("Shotgun".to_string(), 3),
                ("LMG".to_string(), 4),
                ("Weird".to_string(), 5),
                ("BR".to_string(), 6),
            ]),
        ),
        (
            "Secondary".to_string(),
            HashMap::from([("Sidearm".to_string(), 7)]),
        ),
    ]);
    let penalties = vec![
        vec![1.00, 0.70, 0.75, 0.70, 0.75, 1.00, 0.80, 0.65],
        vec![0.70, 1.00, 0.60, 0.60, 0.80, 1.00, 0.85, 0.50],
        vec![0.80, 0.60, 1.00, 0.65, 0.65, 1.00, 0.70, 0.70],
        vec![0.70, 0.50, 0.65, 1.00, 0.75, 1.00, 0.60, 0.65],
        vec![0.75, 0.80, 0.65, 0.75, 1.00, 1.00, 0.85, 0.50],
        vec![1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00],
        vec![0.80, 0.85, 0.70, 0.60, 0.85, 1.00, 1.00, 0.65],
        vec![0.65, 0.50, 0.75, 0.65, 0.50, 1.00, 0.65, 1.00],
    ];

    Ok(ExportData {
        data: combined,
        penalties,
        categories,
    })
}

pub fn download_sheets(sheet_id: &str, sheet_folder: &Path) -> anyhow::Result<()> {
    let downloader = SheetDownloader::new(sheet_id.to_string(), sheet_folder.to_path_buf());
    downloader.download(&[
        SheetExport {
            gid: CORES_SHEET_GID.to_string(),
            output_path: PathBuf::from(CORES_SHEET),
            url_override: None,
        },
        SheetExport {
            gid: PARTS_V2_SHEET_GID.to_string(),
            output_path: PathBuf::from(PARTS_V2_SHEET),
            url_override: None,
        },
    ])
}

fn clear_sheet_folder(path: &Path) -> anyhow::Result<()> {
    fs::create_dir_all(path)?;
    for entry in fs::read_dir(path)? {
        let path = entry?.path();
        if path.is_file() {
            fs::remove_file(path)?;
        } else {
            fs::remove_dir_all(path)?;
        }
    }
    Ok(())
}

pub fn save_sqlite(export_data: &ExportData, output_path: &Path) -> anyhow::Result<()> {
    if let Some(parent) = output_path.parent() {
        fs::create_dir_all(parent)?;
    }
    if output_path.exists() {
        fs::remove_file(output_path)?;
    }
    let conn = Connection::open(output_path)?;
    create_schema(&conn)?;
    insert_categories(&conn, &export_data.categories)?;
    insert_penalties(&conn, &export_data.penalties)?;
    let records = &export_data.data;
    insert_cores(
        &conn,
        records.get("Cores").map(Vec::as_slice).unwrap_or(&[]),
    )?;
    insert_magazines(
        &conn,
        records.get("Magazines").map(Vec::as_slice).unwrap_or(&[]),
    )?;
    insert_parts(
        &conn,
        "Barrels",
        records.get("Barrels").map(Vec::as_slice).unwrap_or(&[]),
    )?;
    insert_parts(
        &conn,
        "Grips",
        records.get("Grips").map(Vec::as_slice).unwrap_or(&[]),
    )?;
    insert_parts(
        &conn,
        "Stocks",
        records.get("Stocks").map(Vec::as_slice).unwrap_or(&[]),
    )?;
    Ok(())
}

fn create_schema(conn: &Connection) -> anyhow::Result<()> {
    conn.execute_batch(
        "CREATE TABLE categories (name TEXT PRIMARY KEY, idx INTEGER NOT NULL);
         CREATE TABLE penalties (core_idx INTEGER NOT NULL, part_idx INTEGER NOT NULL, value REAL NOT NULL, PRIMARY KEY (core_idx, part_idx));
         CREATE TABLE cores (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, category TEXT NOT NULL, damage REAL NOT NULL, damage_end REAL NOT NULL, fire_rate REAL NOT NULL);
         CREATE TABLE magazines (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, category TEXT NOT NULL, magazine_size REAL NOT NULL, reload_time REAL NOT NULL, damage_mod REAL NOT NULL, fire_rate_mod REAL NOT NULL);
         CREATE TABLE parts (id INTEGER PRIMARY KEY AUTOINCREMENT, part_type TEXT NOT NULL, name TEXT NOT NULL, category TEXT NOT NULL, damage_mod REAL NOT NULL, fire_rate_mod REAL NOT NULL);"
    )?;
    Ok(())
}

fn insert_categories(
    conn: &Connection,
    categories: &HashMap<String, HashMap<String, i32>>,
) -> anyhow::Result<()> {
    for group in categories.values() {
        for (name, idx) in group {
            conn.execute(
                "INSERT INTO categories (name, idx) VALUES (?, ?)",
                params![name, idx],
            )?;
        }
    }
    Ok(())
}
fn insert_penalties(conn: &Connection, penalties: &[Vec<f64>]) -> anyhow::Result<()> {
    for (core_idx, row) in penalties.iter().enumerate() {
        for (part_idx, value) in row.iter().enumerate() {
            conn.execute(
                "INSERT INTO penalties (core_idx, part_idx, value) VALUES (?, ?, ?)",
                params![core_idx as i64, part_idx as i64, value],
            )?;
        }
    }
    Ok(())
}
fn insert_cores(conn: &Connection, cores: &[ItemRow]) -> anyhow::Result<()> {
    for core in cores {
        let (damage, damage_end) = extract_damage_pair(core.get("Damage"));
        conn.execute("INSERT INTO cores (name, category, damage, damage_end, fire_rate) VALUES (?, ?, ?, ?, ?)", params![string_field(core, "Name"), string_field(core, "Category"), damage, damage_end, json_value_to_f(core.get("Fire_Rate"))])?;
    }
    Ok(())
}
fn insert_magazines(conn: &Connection, mags: &[ItemRow]) -> anyhow::Result<()> {
    for mag in mags {
        conn.execute("INSERT INTO magazines (name, category, magazine_size, reload_time, damage_mod, fire_rate_mod) VALUES (?, ?, ?, ?, ?, ?)", params![string_field(mag, "Name"), string_field(mag, "Category"), json_value_to_f(mag.get("Magazine_Size")), json_value_to_f(mag.get("Reload_Time")), json_value_to_f(mag.get("Damage")), json_value_to_f(mag.get("Fire_Rate"))])?;
    }
    Ok(())
}
fn insert_parts(conn: &Connection, part_type: &str, parts: &[ItemRow]) -> anyhow::Result<()> {
    for part in parts {
        conn.execute("INSERT INTO parts (part_type, name, category, damage_mod, fire_rate_mod) VALUES (?, ?, ?, ?, ?)", params![part_type, string_field(part, "Name"), string_field(part, "Category"), json_value_to_f(part.get("Damage")), json_value_to_f(part.get("Fire_Rate"))])?;
    }
    Ok(())
}
fn extract_damage_pair(value: Option<&JsonValue>) -> (f64, f64) {
    match value {
        Some(JsonValue::Array(arr)) if !arr.is_empty() => (
            json_value_to_f(arr.first()),
            json_value_to_f(arr.get(1).or(arr.first())),
        ),
        Some(v) => {
            let d = json_value_to_f(Some(v));
            (d, d)
        }
        _ => (0.0, 0.0),
    }
}
fn json_value_to_f(value: Option<&JsonValue>) -> f64 {
    match value {
        Some(JsonValue::Int(v)) => *v as f64,
        Some(JsonValue::Float(v)) => *v,
        _ => 0.0,
    }
}
fn string_field(row: &ItemRow, key: &str) -> String {
    row.get(key)
        .and_then(JsonValue::as_str)
        .unwrap_or_default()
        .to_string()
}
