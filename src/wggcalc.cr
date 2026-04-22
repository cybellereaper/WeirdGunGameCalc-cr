require "json"

module WGGCalc
  struct Range
    getter min : Float64?
    getter max : Float64?

    def initialize(@min : Float64? = nil, @max : Float64? = nil)
    end

    def contains?(value : Float64) : Bool
      return false if min && value < min.not_nil!
      return false if max && value > max.not_nil!
      true
    end
  end

  enum SortKey
    TTK
    DPS
    DAMAGE
    DAMAGE_END
    FIRE_RATE
    MAGAZINE
  end

  enum SortPriority
    HIGHEST
    LOWEST
    AUTO
  end

  struct Config
    property data_path : String = "Data/FullData.json"
    property top_n : Int32 = 10
    property player_max_health : Float64 = 100.0
    property sort_key : SortKey = SortKey::TTK
    property priority : SortPriority = SortPriority::AUTO
    property include_categories : Array(String) = [] of String
    property damage_range : Range = Range.new
    property damage_end_range : Range = Range.new
    property ttk_seconds_range : Range = Range.new
    property dps_range : Range = Range.new
    property part_pool_per_type : Int32 = 20
  end

  struct CalculationStats
    property cores_considered : Int32 = 0
    property cores_skipped_by_category : Int32 = 0
    property combinations_evaluated : Int64 = 0
    property combinations_filtered : Int64 = 0
    property results_kept : Int32 = 0
  end

  record Core, name : String, category : String, damage : Float64, damage_end : Float64, fire_rate : Float64
  record Magazine, name : String, category : String, magazine_size : Float64, reload_time : Float64, damage_mod : Float64, fire_rate_mod : Float64
  record Part, name : String, category : String, damage_mod : Float64, fire_rate_mod : Float64
  record Result, core : String, magazine : String, barrel : String, stock : String, grip : String,
    damage : Float64, damage_end : Float64, fire_rate : Float64, magazine_size : Float64, ttk_seconds : Float64, dps : Float64

  class DataSet
    getter cores : Array(Core)
    getter magazines : Array(Magazine)
    getter barrels : Array(Part)
    getter grips : Array(Part)
    getter stocks : Array(Part)
    getter penalties : Array(Array(Float64))
    getter categories : Hash(String, Int32)

    def initialize(
      @cores : Array(Core),
      @magazines : Array(Magazine),
      @barrels : Array(Part),
      @grips : Array(Part),
      @stocks : Array(Part),
      @penalties : Array(Array(Float64)),
      @categories : Hash(String, Int32),
    )
    end
  end

  module Parser
    extend self

    def load_data(path : String) : DataSet
      root = JSON.parse(File.read(path)).as_h
      categories = parse_category_map(root)
      penalties = root["Penalties"].as_a.map { |row| row.as_a.map { |cell| number_to_f(cell) } }
      data = root["Data"].as_h

      DataSet.new(
        cores: parse_cores(data["Cores"].as_a),
        magazines: parse_magazines(data["Magazines"].as_a),
        barrels: parse_parts(data["Barrels"].as_a),
        grips: parse_parts(data["Grips"].as_a),
        stocks: parse_parts(data["Stocks"].as_a),
        penalties: penalties,
        categories: categories
      )
    end

    private def parse_cores(nodes : Array(JSON::Any)) : Array(Core)
      nodes.map do |node|
        obj = node.as_h
        damage_start, damage_end = parse_damage_pair(obj)
        Core.new(
          name: obj["Name"].as_s,
          category: obj["Category"].as_s,
          damage: damage_start,
          damage_end: damage_end,
          fire_rate: optional_number(obj, "Fire_Rate")
        )
      end
    end

    private def parse_magazines(nodes : Array(JSON::Any)) : Array(Magazine)
      nodes.map do |node|
        obj = node.as_h
        Magazine.new(
          name: obj["Name"].as_s,
          category: obj["Category"].as_s,
          magazine_size: optional_number(obj, "Magazine_Size"),
          reload_time: optional_number(obj, "Reload_Time"),
          damage_mod: optional_number(obj, "Damage"),
          fire_rate_mod: optional_number(obj, "Fire_Rate")
        )
      end
    end

    private def parse_parts(nodes : Array(JSON::Any)) : Array(Part)
      nodes.map do |node|
        obj = node.as_h
        Part.new(
          name: obj["Name"].as_s,
          category: obj["Category"].as_s,
          damage_mod: optional_number(obj, "Damage"),
          fire_rate_mod: optional_number(obj, "Fire_Rate")
        )
      end
    end

    private def parse_damage_pair(obj : Hash(String, JSON::Any)) : Tuple(Float64, Float64)
      return {0.0, 0.0} unless obj.has_key?("Damage")

      value = obj["Damage"]
      if value.raw.is_a?(Array)
        arr = value.as_a
        {number_to_f(arr[0]), number_to_f(arr[1])}
      else
        dmg = number_to_f(value)
        {dmg, dmg}
      end
    end

    private def optional_number(obj : Hash(String, JSON::Any), key : String) : Float64
      obj[key]?.try { |v| number_to_f(v) } || 0.0
    end

    private def parse_category_map(root : Hash(String, JSON::Any)) : Hash(String, Int32)
      categories = root["Categories"].as_h
      map = {} of String => Int32
      ["Primary", "Secondary"].each do |group|
        categories[group].as_h.each do |name, idx|
          map[name] = number_to_i(idx)
        end
      end
      map
    end

    private def number_to_f(value : JSON::Any) : Float64
      raw = value.raw
      case raw
      when Int64
        raw.to_f
      when Float64
        raw
      else
        raise "Expected numeric value"
      end
    end

    private def number_to_i(value : JSON::Any) : Int32
      raw = value.raw
      case raw
      when Int64
        raw.to_i
      when Float64
        raw.to_i
      else
        raise "Expected numeric category index"
      end
    end
  end

  class Engine
    def initialize(@data : DataSet)
    end

    def calculate_top(config : Config, stats : CalculationStats = CalculationStats.new) : {Array(Result), CalculationStats}
      results = [] of Result
      stats.cores_considered = 0
      stats.cores_skipped_by_category = 0
      stats.combinations_evaluated = 0
      stats.combinations_filtered = 0

      @data.cores.each do |core|
        stats.cores_considered += 1
        unless include_category?(config.include_categories, core.category)
          stats.cores_skipped_by_category += 1
          next
        end

        core_idx = @data.categories[core.category]?
        next unless core_idx

        mags = top_magazines(core, core_idx, config.part_pool_per_type)
        barrels = top_parts(@data.barrels, core, core_idx, config.part_pool_per_type)
        stocks = top_parts(@data.stocks, core, core_idx, config.part_pool_per_type)
        grips = top_parts(@data.grips, core, core_idx, config.part_pool_per_type)

        mags.each do |mag|
          barrels.each do |barrel|
            stocks.each do |stock|
              grips.each do |grip|
                stats.combinations_evaluated += 1
                res = build_result(config, core, core_idx, mag, barrel, stock, grip)
                next unless res

                unless passes_filters?(config, res)
                  stats.combinations_filtered += 1
                  next
                end

                push_top(results, res, config)
              end
            end
          end
        end
      end

      stats.results_kept = results.size
      {results, stats}
    end

    private def push_top(results : Array(Result), candidate : Result, config : Config)
      return if config.top_n <= 0

      if results.size < config.top_n
        results << candidate
      elsif better?(candidate, results.last, config)
        results[-1] = candidate
      else
        return
      end

      results.sort! { |a, b| better?(a, b, config) ? -1 : 1 }
    end

    private def build_result(config : Config, core : Core, core_idx : Int32, mag : Magazine, barrel : Part, stock : Part, grip : Part) : Result?
      dmg_mult = percent_multiplier(core, core_idx, {
        {mag.name, mag.category, mag.damage_mod},
        {barrel.name, barrel.category, barrel.damage_mod},
        {stock.name, stock.category, stock.damage_mod},
        {grip.name, grip.category, grip.damage_mod},
      })
      fr_mult = percent_multiplier(core, core_idx, {
        {mag.name, mag.category, mag.fire_rate_mod},
        {barrel.name, barrel.category, barrel.fire_rate_mod},
        {stock.name, stock.category, stock.fire_rate_mod},
        {grip.name, grip.category, grip.fire_rate_mod},
      })

      damage = core.damage * dmg_mult
      fire_rate = core.fire_rate * fr_mult
      return nil if damage <= 0 || fire_rate <= 0

      shots = (config.player_max_health / damage).ceil
      ttk_seconds = ((shots - 1) / fire_rate) * 60.0

      Result.new(
        core: core.name,
        magazine: mag.name,
        barrel: barrel.name,
        stock: stock.name,
        grip: grip.name,
        damage: damage,
        damage_end: core.damage_end * dmg_mult,
        fire_rate: fire_rate,
        magazine_size: mag.magazine_size,
        ttk_seconds: ttk_seconds,
        dps: (damage * fire_rate) / 60.0
      )
    end

    private def percent_multiplier(core : Core, core_idx : Int32, parts : Tuple)
      mult = 1.0
      parts.each do |name, category, raw_mod|
        penalty = penalty_for(core_idx, category)
        mult *= 1.0 + adjusted_mod(raw_mod, core.name, name, penalty) / 100.0
      end
      mult
    end

    private def top_parts(pool : Array(Part), core : Core, core_idx : Int32, max_count : Int32)
      pool.sort_by { |part| -part_score(core, core_idx, part.name, part.category, part.damage_mod, part.fire_rate_mod) }
        .first(max_count)
    end

    private def top_magazines(core : Core, core_idx : Int32, max_count : Int32)
      @data.magazines.sort_by do |mag|
        -(part_score(core, core_idx, mag.name, mag.category, mag.damage_mod, mag.fire_rate_mod) + (mag.magazine_size * 0.05))
      end.first(max_count)
    end

    private def part_score(core : Core, core_idx : Int32, part_name : String, category : String, dmg_mod : Float64, fr_mod : Float64)
      penalty = penalty_for(core_idx, category)
      adjusted_mod(dmg_mod, core.name, part_name, penalty) + (adjusted_mod(fr_mod, core.name, part_name, penalty) * 0.6)
    end

    private def penalty_for(core_idx : Int32, category : String) : Float64
      part_idx = @data.categories[category]? || return 1.0
      @data.penalties[core_idx][part_idx]
    end

    private def adjusted_mod(raw : Float64, core_name : String, part_name : String, penalty : Float64) : Float64
      return 0.0 if core_name == part_name
      raw * penalty
    end

    private def passes_filters?(config : Config, result : Result) : Bool
      config.damage_range.contains?(result.damage) &&
        config.damage_end_range.contains?(result.damage_end) &&
        config.ttk_seconds_range.contains?(result.ttk_seconds) &&
        config.dps_range.contains?(result.dps)
    end

    private def include_category?(allowed : Array(String), category : String) : Bool
      return true if allowed.empty?
      allowed.any? { |candidate| candidate.compare(category, case_insensitive: true) == 0 }
    end

    private def better?(a : Result, b : Result, config : Config) : Bool
      left = metric(a, config.sort_key)
      right = metric(b, config.sort_key)

      priority = if config.priority.auto?
                   config.sort_key.ttk? ? SortPriority::LOWEST : SortPriority::HIGHEST
                 else
                   config.priority
                 end

      priority.highest? ? left > right : left < right
    end

    private def metric(result : Result, key : SortKey) : Float64
      case key
      in .ttk?        then result.ttk_seconds
      in .dps?        then result.dps
      in .damage?     then result.damage
      in .damage_end? then result.damage_end
      in .fire_rate?  then result.fire_rate
      in .magazine?   then result.magazine_size
      end
    end
  end

  module Presenter
    extend self

    def write_results(results : Array(Result), io : IO)
      results.each_with_index do |r, idx|
        io << "##{idx + 1}\n"
        io << " Core: #{r.core}\n"
        io << " Magazine: #{r.magazine}\n"
        io << " Barrel: #{r.barrel}\n"
        io << " Stock: #{r.stock}\n"
        io << " Grip: #{r.grip}\n"
        io << " Damage: #{format_float(r.damage)}\n"
        io << " Damage End: #{format_float(r.damage_end)}\n"
        io << " Fire Rate: #{format_float(r.fire_rate)}\n"
        io << " TTK: #{format_float(r.ttk_seconds)}s\n"
        io << " DPS: #{format_float(r.dps)}\n\n"
      end
    end

    private def format_float(value : Float64)
      "%.3f" % value
    end
  end
end
