use crate::data::{Core, DataSet, Magazine, Part};
use rusqlite::Connection;
use serde_json::Value;
use std::collections::HashMap;
use std::path::Path;

pub fn load_data(path: &str) -> anyhow::Result<DataSet> {
    if is_sqlite_path(path) {
        load_sqlite_data(path)
    } else {
        load_json_data(path)
    }
}

fn is_sqlite_path(path: &str) -> bool {
    let lowered = path.to_ascii_lowercase();
    lowered.ends_with(".sqlite") || lowered.ends_with(".sqlite3") || lowered.ends_with(".db")
}

fn load_sqlite_data(path: &str) -> anyhow::Result<DataSet> {
    let conn = Connection::open(path)?;
    let categories = load_categories_from_sqlite(&conn)?;
    let penalties = load_penalties_from_sqlite(&conn)?;
    Ok(DataSet {
        cores: load_cores_from_sqlite(&conn)?,
        magazines: load_magazines_from_sqlite(&conn)?,
        barrels: load_parts_from_sqlite(&conn, "Barrels")?,
        grips: load_parts_from_sqlite(&conn, "Grips")?,
        stocks: load_parts_from_sqlite(&conn, "Stocks")?,
        penalties,
        categories,
    })
}

fn load_cores_from_sqlite(conn: &Connection) -> anyhow::Result<Vec<Core>> {
    let mut stmt = conn
        .prepare("SELECT name, category, damage, damage_end, fire_rate FROM cores ORDER BY id")?;
    let rows = stmt.query_map([], |row| {
        Ok(Core {
            name: row.get(0)?,
            category: row.get(1)?,
            damage: row.get(2)?,
            damage_end: row.get(3)?,
            fire_rate: row.get(4)?,
        })
    })?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

fn load_magazines_from_sqlite(conn: &Connection) -> anyhow::Result<Vec<Magazine>> {
    let mut stmt = conn.prepare("SELECT name, category, magazine_size, reload_time, damage_mod, fire_rate_mod FROM magazines ORDER BY id")?;
    let rows = stmt.query_map([], |row| {
        Ok(Magazine {
            name: row.get(0)?,
            category: row.get(1)?,
            magazine_size: row.get(2)?,
            reload_time: row.get(3)?,
            damage_mod: row.get(4)?,
            fire_rate_mod: row.get(5)?,
        })
    })?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

fn load_parts_from_sqlite(conn: &Connection, part_type: &str) -> anyhow::Result<Vec<Part>> {
    let mut stmt = conn.prepare("SELECT name, category, damage_mod, fire_rate_mod FROM parts WHERE part_type = ? ORDER BY id")?;
    let rows = stmt.query_map([part_type], |row| {
        Ok(Part {
            name: row.get(0)?,
            category: row.get(1)?,
            damage_mod: row.get(2)?,
            fire_rate_mod: row.get(3)?,
        })
    })?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

fn load_categories_from_sqlite(conn: &Connection) -> anyhow::Result<HashMap<String, usize>> {
    let mut stmt = conn.prepare("SELECT name, idx FROM categories")?;
    let rows = stmt.query_map([], |row| {
        let idx: i64 = row.get(1)?;
        Ok((row.get::<_, String>(0)?, idx as usize))
    })?;
    Ok(rows.collect::<Result<HashMap<_, _>, _>>()?)
}

fn load_penalties_from_sqlite(conn: &Connection) -> anyhow::Result<Vec<Vec<f64>>> {
    let mut stmt = conn.prepare("SELECT core_idx, part_idx, value FROM penalties")?;
    let rows = stmt.query_map([], |row| {
        Ok((
            row.get::<_, i64>(0)? as usize,
            row.get::<_, i64>(1)? as usize,
            row.get::<_, f64>(2)?,
        ))
    })?;
    let entries = rows.collect::<Result<Vec<_>, _>>()?;
    let max_row = entries.iter().map(|x| x.0).max();
    let max_col = entries.iter().map(|x| x.1).max();
    let (Some(max_row), Some(max_col)) = (max_row, max_col) else {
        return Ok(Vec::new());
    };
    let mut matrix = vec![vec![1.0; max_col + 1]; max_row + 1];
    for (r, c, v) in entries {
        matrix[r][c] = v;
    }
    Ok(matrix)
}

fn load_json_data(path: &str) -> anyhow::Result<DataSet> {
    let root: Value = serde_json::from_slice(&std::fs::read(Path::new(path))?)?;
    let categories = parse_category_map(&root["Categories"])?;
    let penalties = root["Penalties"]
        .as_array()
        .ok_or_else(|| anyhow::anyhow!("Penalties missing"))?
        .iter()
        .map(|row| {
            row.as_array()
                .unwrap_or(&Vec::new())
                .iter()
                .map(number_to_f)
                .collect()
        })
        .collect();
    let data = &root["Data"];
    Ok(DataSet {
        cores: parse_cores(&data["Cores"])?,
        magazines: parse_magazines(&data["Magazines"])?,
        barrels: parse_parts(&data["Barrels"])?,
        grips: parse_parts(&data["Grips"])?,
        stocks: parse_parts(&data["Stocks"])?,
        penalties,
        categories,
    })
}

fn parse_cores(v: &Value) -> anyhow::Result<Vec<Core>> {
    let nodes = v
        .as_array()
        .ok_or_else(|| anyhow::anyhow!("cores not array"))?;
    Ok(nodes
        .iter()
        .map(|node| {
            let obj = node.as_object().unwrap();
            let (damage, damage_end) = parse_damage_pair(obj.get("Damage"));
            Core {
                name: obj
                    .get("Name")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                category: obj
                    .get("Category")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                damage,
                damage_end,
                fire_rate: optional_number(obj.get("Fire_Rate")),
            }
        })
        .collect())
}

fn parse_magazines(v: &Value) -> anyhow::Result<Vec<Magazine>> {
    let nodes = v
        .as_array()
        .ok_or_else(|| anyhow::anyhow!("magazines not array"))?;
    Ok(nodes
        .iter()
        .map(|node| {
            let obj = node.as_object().unwrap();
            Magazine {
                name: obj
                    .get("Name")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                category: obj
                    .get("Category")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                magazine_size: optional_number(obj.get("Magazine_Size")),
                reload_time: optional_number(obj.get("Reload_Time")),
                damage_mod: optional_number(obj.get("Damage")),
                fire_rate_mod: optional_number(obj.get("Fire_Rate")),
            }
        })
        .collect())
}

fn parse_parts(v: &Value) -> anyhow::Result<Vec<Part>> {
    let nodes = v
        .as_array()
        .ok_or_else(|| anyhow::anyhow!("parts not array"))?;
    Ok(nodes
        .iter()
        .map(|node| {
            let obj = node.as_object().unwrap();
            Part {
                name: obj
                    .get("Name")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                category: obj
                    .get("Category")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                damage_mod: optional_number(obj.get("Damage")),
                fire_rate_mod: optional_number(obj.get("Fire_Rate")),
            }
        })
        .collect())
}

fn parse_category_map(v: &Value) -> anyhow::Result<HashMap<String, usize>> {
    let mut map = HashMap::new();
    for group in ["Primary", "Secondary"] {
        if let Some(obj) = v.get(group).and_then(Value::as_object) {
            for (name, idx) in obj {
                map.insert(name.clone(), number_to_i(idx) as usize);
            }
        }
    }
    Ok(map)
}

fn parse_damage_pair(value: Option<&Value>) -> (f64, f64) {
    let Some(value) = value else {
        return (0.0, 0.0);
    };
    if let Some(arr) = value.as_array() {
        (
            number_to_f(&arr[0]),
            number_to_f(arr.get(1).unwrap_or(&arr[0])),
        )
    } else {
        let d = number_to_f(value);
        (d, d)
    }
}

fn optional_number(value: Option<&Value>) -> f64 {
    value.map(number_to_f).unwrap_or(0.0)
}
fn number_to_f(value: &Value) -> f64 {
    value
        .as_f64()
        .or_else(|| value.as_i64().map(|x| x as f64))
        .unwrap_or(0.0)
}
fn number_to_i(value: &Value) -> i32 {
    value
        .as_i64()
        .map(|x| x as i32)
        .or_else(|| value.as_f64().map(|x| x as i32))
        .unwrap_or(0)
}
