require "./spec_helper"
require "../src/sheet_parser"
require "http/server"

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

describe SheetParser::CoresParser do
  it "accepts rows with extra trailing columns" do
    parser = SheetParser::CoresParser.new
    rows = [
      [
        "Coin", "Test Core", "10 - 8", "100 - 80", "", "", "", "", "", "", "", "", "", "", "1 - 1", "1 - 1", "1 - 1", "1 - 1", "ignored extra",
      ],
    ]

    output = parser.parse_rows(rows)
    output.size.should eq(1)
    output[0]["Name"].should eq("Test Core")
    output[0]["Category"].should eq("AR")
    output[0]["Damage"].should eq([10, 8])
  end
end

describe SheetParser::SheetDownloader do
  it "follows HTTP redirects when downloading exports" do
    server = HTTP::Server.new do |context|
      case context.request.path
      when "/redirect"
        context.response.status_code = 307
        context.response.headers["Location"] = "/final"
      when "/final"
        context.response.print("name,stat\nx,y\n")
      else
        context.response.status_code = 404
      end
    end

    address = server.bind_tcp("127.0.0.1", 0)
    port = address.port
    spawn { server.listen }
    sleep 20.milliseconds

    tmp_dir = File.join(Dir.tempdir, "sheet_parser_spec_#{Random.rand(1_000_000)}")
    Dir.mkdir_p(tmp_dir)

    begin
      export = SheetParser::SheetExport.new("unused", File.join(tmp_dir, "cores.csv"), "http://127.0.0.1:#{port}/redirect")
      downloader = SheetParser::SheetDownloader.new("unused", tmp_dir)
      downloader.download([export])

      File.read(File.join(tmp_dir, "cores.csv")).should contain("name,stat")
    ensure
      FileUtils.rm_rf(tmp_dir)
      server.close
    end
  end
end
