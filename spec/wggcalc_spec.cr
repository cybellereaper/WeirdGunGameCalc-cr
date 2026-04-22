require "./spec_helper"

def fixture_data : WGGCalc::DataSet
  WGGCalc::DataSet.new(
    cores: [WGGCalc::Core.new("Core-1", "AR", 50.0, 40.0, 120.0)],
    magazines: [WGGCalc::Magazine.new("Mag-1", "AR", 20.0, 1.0, 0.0, 0.0)],
    barrels: [WGGCalc::Part.new("Barrel-1", "AR", 0.0, 0.0)],
    grips: [WGGCalc::Part.new("Grip-1", "AR", 0.0, 0.0)],
    stocks: [WGGCalc::Part.new("Stock-1", "AR", 0.0, 0.0)],
    penalties: [[1.0]],
    categories: {"AR" => 0}
  )
end

describe WGGCalc::Range do
  it "supports open-ended ranges" do
    WGGCalc::Range.new(2.0, 4.0).contains?(3.0).should be_true
    WGGCalc::Range.new(2.0, 4.0).contains?(5.0).should be_false
    WGGCalc::Range.new(2.0, nil).contains?(500.0).should be_true
    WGGCalc::Range.new(nil, 10.0).contains?(-1.0).should be_true
  end
end

describe WGGCalc::Engine do
  it "tracks evaluated combinations" do
    engine = WGGCalc::Engine.new(fixture_data)
    results, stats = engine.calculate_top(WGGCalc::Config.new)

    stats.cores_considered.should eq(1)
    stats.combinations_evaluated.should eq(1)
    stats.combinations_filtered.should eq(0)
    stats.results_kept.should eq(1)
    results.size.should eq(1)
  end

  it "tracks filtered combinations" do
    config = WGGCalc::Config.new
    config.damage_range = WGGCalc::Range.new(9999.0, nil)

    engine = WGGCalc::Engine.new(fixture_data)
    results, stats = engine.calculate_top(config)

    stats.combinations_evaluated.should eq(1)
    stats.combinations_filtered.should eq(1)
    stats.results_kept.should eq(0)
    results.size.should eq(0)
  end
end
