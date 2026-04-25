use crate::data::ResultRow;

pub fn write_results(
    results: &[ResultRow],
    mut writer: impl std::io::Write,
) -> std::io::Result<()> {
    for (idx, r) in results.iter().enumerate() {
        writeln!(writer, "#{}", idx + 1)?;
        writeln!(writer, " Core: {}", r.core)?;
        writeln!(writer, " Magazine: {}", r.magazine)?;
        writeln!(writer, " Barrel: {}", r.barrel)?;
        writeln!(writer, " Stock: {}", r.stock)?;
        writeln!(writer, " Grip: {}", r.grip)?;
        writeln!(writer, " Damage: {:.3}", r.damage)?;
        writeln!(writer, " Damage End: {:.3}", r.damage_end)?;
        writeln!(writer, " Fire Rate: {:.3}", r.fire_rate)?;
        writeln!(writer, " TTK: {:.3}s", r.ttk_seconds)?;
        writeln!(writer, " DPS: {:.3}\n", r.dps)?;
    }
    Ok(())
}
