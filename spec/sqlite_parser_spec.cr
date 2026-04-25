require "./spec_helper"
require "../src/sheet_parser"

describe "SQLite data pipeline" do
  it "writes and reads dataset using sqlite3" do
    tmp_dir = File.join(Dir.tempdir, "wggcalc_sqlite_spec_#{Random.rand(1_000_000)}")
    Dir.mkdir_p(tmp_dir)
    db_path = File.join(tmp_dir, "full_data.sqlite3")

    data_section = {} of String => SheetParser::ItemRows

    core = {
      "Name"      => "Core-A".as(SheetParser::JsonValue),
      "Category"  => "AR".as(SheetParser::JsonValue),
      "Damage"    => [30.0.as(SheetParser::JsonValue), 20.0.as(SheetParser::JsonValue)].as(SheetParser::JsonValue),
      "Fire_Rate" => 120.0.as(SheetParser::JsonValue),
    } of String => SheetParser::JsonValue

    mag = {
      "Name"          => "Mag-A".as(SheetParser::JsonValue),
      "Category"      => "AR".as(SheetParser::JsonValue),
      "Magazine_Size" => 20.0.as(SheetParser::JsonValue),
      "Reload_Time"   => 1.0.as(SheetParser::JsonValue),
      "Damage"        => 5.0.as(SheetParser::JsonValue),
      "Fire_Rate"     => 10.0.as(SheetParser::JsonValue),
    } of String => SheetParser::JsonValue

    part = {
      "Name"      => "Part-A".as(SheetParser::JsonValue),
      "Category"  => "AR".as(SheetParser::JsonValue),
      "Damage"    => 0.0.as(SheetParser::JsonValue),
      "Fire_Rate" => 0.0.as(SheetParser::JsonValue),
    } of String => SheetParser::JsonValue

    data_section["Cores"] = [core]
    data_section["Magazines"] = [mag]
    data_section["Barrels"] = [part]
    data_section["Grips"] = [part]
    data_section["Stocks"] = [part]

    categories = {
      "Primary"   => {"AR" => 0},
      "Secondary" => {} of String => Int32,
    } of String => Hash(String, Int32)

    export_data = SheetParser::ExportData.new(data_section, [[1.0]], categories)

    begin
      SheetParser.save_sqlite(export_data, db_path)
      loaded = WGGCalc::Parser.load_data(db_path)

      loaded.cores.size.should eq(1)
      loaded.magazines.size.should eq(1)
      loaded.barrels.size.should eq(1)
      loaded.grips.size.should eq(1)
      loaded.stocks.size.should eq(1)
      loaded.categories["AR"].should eq(0)
      loaded.penalties[0][0].should eq(1.0)
      loaded.cores[0].damage_end.should eq(20.0)
      loaded.magazines[0].damage_mod.should eq(5.0)
    ensure
      FileUtils.rm_rf(tmp_dir)
    end
  end
end
