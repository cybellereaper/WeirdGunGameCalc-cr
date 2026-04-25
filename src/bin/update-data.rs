use std::path::Path;

use wggcalc::sheet_parser::{
    build_full_data, download_sheets, save_sqlite, CORES_SHEET, DATA_FOLDER, OUTPUT_FILE,
    PARTS_V2_SHEET, SHEET_FOLDER, SHEET_ID,
};

fn main() -> anyhow::Result<()> {
    std::fs::create_dir_all(DATA_FOLDER)?;
    download_sheets(SHEET_ID, Path::new(SHEET_FOLDER))?;
    let export_data = build_full_data(Path::new(PARTS_V2_SHEET), Path::new(CORES_SHEET))?;
    save_sqlite(&export_data, Path::new(OUTPUT_FILE))?;
    Ok(())
}
