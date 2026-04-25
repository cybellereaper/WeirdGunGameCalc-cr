require "option_parser"
require "./wggcalc"

config = WGGCalc::Config.new
show_metrics = false

OptionParser.parse do |parser|
  parser.banner = "Usage: wggcalc [arguments]"

  parser.on("--data PATH", "Path to FullData.sqlite3") { |value| config.data_path = value }
  parser.on("--top N", "Number of results") { |value| config.top_n = value.to_i }
  parser.on("--mh VALUE", "Max player health") { |value| config.player_max_health = value.to_f }
  parser.on("--sort KEY", "ttk|dps|damage|damageend|firerate|magazine") do |value|
    config.sort_key = case value.downcase
                      when "ttk"       then WGGCalc::SortKey::TTK
                      when "dps"       then WGGCalc::SortKey::DPS
                      when "damage"    then WGGCalc::SortKey::DAMAGE
                      when "damageend" then WGGCalc::SortKey::DAMAGE_END
                      when "firerate"  then WGGCalc::SortKey::FIRE_RATE
                      when "magazine"  then WGGCalc::SortKey::MAGAZINE
                      else                  raise "Invalid sort key: #{value}"
                      end
  end
  parser.on("--priority MODE", "highest|lowest|auto") do |value|
    config.priority = case value.downcase
                      when "highest" then WGGCalc::SortPriority::HIGHEST
                      when "lowest"  then WGGCalc::SortPriority::LOWEST
                      when "auto"    then WGGCalc::SortPriority::AUTO
                      else                raise "Invalid priority: #{value}"
                      end
  end
  parser.on("--include LIST", "Comma-separated categories") { |v| config.include_categories = v.split(',').reject(&.empty?) }
  parser.on("--part-pool N", "Candidate parts per type per core") { |v| config.part_pool_per_type = v.to_i }

  parser.on("--damage-min VALUE", "Minimum damage") { |v| config.damage_range = WGGCalc::Range.new(v.to_f, config.damage_range.max) }
  parser.on("--damage-max VALUE", "Maximum damage") { |v| config.damage_range = WGGCalc::Range.new(config.damage_range.min, v.to_f) }
  parser.on("--damage-end-min VALUE", "Minimum end damage") { |v| config.damage_end_range = WGGCalc::Range.new(v.to_f, config.damage_end_range.max) }
  parser.on("--damage-end-max VALUE", "Maximum end damage") { |v| config.damage_end_range = WGGCalc::Range.new(config.damage_end_range.min, v.to_f) }
  parser.on("--ttk-min VALUE", "Minimum ttk") { |v| config.ttk_seconds_range = WGGCalc::Range.new(v.to_f, config.ttk_seconds_range.max) }
  parser.on("--ttk-max VALUE", "Maximum ttk") { |v| config.ttk_seconds_range = WGGCalc::Range.new(config.ttk_seconds_range.min, v.to_f) }
  parser.on("--dps-min VALUE", "Minimum dps") { |v| config.dps_range = WGGCalc::Range.new(v.to_f, config.dps_range.max) }
  parser.on("--dps-max VALUE", "Maximum dps") { |v| config.dps_range = WGGCalc::Range.new(config.dps_range.min, v.to_f) }

  parser.on("--metrics", "Print runtime metrics") { show_metrics = true }
  parser.on("-h", "--help", "Show help") { puts parser; exit }
end

total_start = Time.instant
load_start = Time.instant
data = WGGCalc::Parser.load_data(config.data_path)
load_ms = (Time.instant - load_start).total_milliseconds

calc_start = Time.instant
engine = WGGCalc::Engine.new(data)
results, stats = engine.calculate_top(config)
calc_ms = (Time.instant - calc_start).total_milliseconds
total_ms = (Time.instant - total_start).total_milliseconds

puts "Loaded #{data.cores.size} cores, #{data.magazines.size} magazines, #{data.barrels.size} barrels, #{data.stocks.size} stocks, #{data.grips.size} grips\n\n"
WGGCalc::Presenter.write_results(results, STDOUT)

if show_metrics
  puts "Performance metrics:"
  puts "  Data load: #{load_ms.round(3)} ms"
  puts "  Calculation: #{calc_ms.round(3)} ms"
  puts "  Total runtime: #{total_ms.round(3)} ms"
  puts "  Cores considered: #{stats.cores_considered}"
  puts "  Cores skipped by category: #{stats.cores_skipped_by_category}"
  puts "  Combinations evaluated: #{stats.combinations_evaluated}"
  puts "  Combinations filtered: #{stats.combinations_filtered}"
  puts "  Results kept: #{stats.results_kept}"
end
