require "./spec_helper"
require "../src/sheet_parser"

describe SheetParser::Normalizer do
  it "normalizes numeric and multiplier values" do
    SheetParser::Normalizer.normalize_numeric_value("10").should eq(10)
    SheetParser::Normalizer.normalize_numeric_value("2x3").should eq(6)
    SheetParser::Normalizer.normalize_numeric_value("  12.5% ").should eq(12.5)
    SheetParser::Normalizer.normalize_numeric_value("🎲").should be_nil
  end

  it "normalizes ranges" do
    value = SheetParser::Normalizer.normalize_numeric_value("5 - 10", expect_range: true)
    value.should eq([5, 10])
  end

  it "detects price types with aliases" do
    SheetParser::Normalizer.detect_price_type("").should eq("Coin")
    SheetParser::Normalizer.detect_price_type("Weird Boxes").should eq("WC")
    SheetParser::Normalizer.detect_price_type("Exclusive Weird Boxes").should eq("Robux")
    SheetParser::Normalizer.detect_price_type("12345").should eq("Coin")
    SheetParser::Normalizer.detect_price_type("mystery").should eq("Unknown")
  end
end

describe SheetParser::PartsParser do
  it "parses rows into categorized parts" do
    parser = SheetParser::PartsParser.new
    rows = [
      ["Coin", "AR Barrels", "", "", "", "", "", "", "", "", "", "", "", "", "", ""],
      ["WC", "Test Barrel", "10 stat", "", "", "", "", "", "", "", "", "", "", "", "", ""],
    ]

    output = parser.parse_rows(rows)
    output["Barrels"].size.should eq(1)
    output["Barrels"][0]["Name"].should eq("Test Barrel")
    output["Barrels"][0]["Magazine_Size"].should eq(10)
  end

  it "raises on duplicate names in same category/type" do
    parser = SheetParser::PartsParser.new
    rows = [
      ["Coin", "AR Barrels", "", "", "", "", "", "", "", "", "", "", "", "", "", ""],
      ["Coin", "Dup", "10 stat", "", "", "", "", "", "", "", "", "", "", "", "", ""],
      ["Coin", "Dup", "10 stat", "", "", "", "", "", "", "", "", "", "", "", "", ""],
    ]

    expect_raises(SheetParser::ParseError) { parser.parse_rows(rows) }
  end
end
