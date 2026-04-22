require "file_utils"
require "csv"
require "json"
require "http/client"

module SheetParser
  SHEET_ID     = "1Kc9aME3xlUC_vV5dFRe457OchqUOrwuiX_pQykjCF68"
  SHEET_FOLDER = "SheetData"
  DATA_FOLDER  = "Data"

  PARTS_V2_SHEET_GID = "319672878"
  CORES_SHEET_GID    = "911413911"

  PARTS_V2_SHEET = "#{SHEET_FOLDER}/parts2.csv"
  CORES_SHEET    = "#{SHEET_FOLDER}/cores.csv"

  OUTPUT_FILE = "#{DATA_FOLDER}/FullData.json"

  VALID_PART_CATEGORIES = ["AR", "Sniper", "SMG", "LMG", "Shotgun", "BR", "Weird", "Sidearm"]
  VALID_PART_TYPES      = ["Barrels", "Magazines", "Grips", "Stocks"]
  VALID_PRICE_TYPES     = ["Coin", "WC", "Follow", "Robux", "Free", "Spin", "Limited", "Missions", "Verify discord", "Season Pass 1", "Unknown"]

  PART_PROPERTY_NAMES = [
    "Magazine_Size", "Reload_Time", "Damage", "Detection_Radius", "Equip_Time", "Fire_Rate", "Health", "Magazine_Cap", "Movement_Speed", "Pellets", "Range", "Recoil", "Reload_Speed", "Spread",
  ]

  CORE_PROPERTY_NAMES = [
    "Damage", "Dropoff_Studs", "Fire_Rate", "Hipfire_Spread", "ADS_Spread", "Time_To_Aim", "Detection_Radius", "Burst", "Movement_Speed_Modifier", "Suppression", "Health", "Equip_Time", "Recoil_Hip_Horizontal", "Recoil_Hip_Vertical", "Recoil_Aim_Horizontal", "Recoil_Aim_Vertical",
  ]

  CURRENT_CATEGORIES = {
    "Primary"   => {"AR" => 0, "Sniper" => 1, "SMG" => 2, "Shotgun" => 3, "LMG" => 4, "Weird" => 5, "BR" => 6},
    "Secondary" => {"Sidearm" => 7},
  }

  CURRENT_PENALTIES = [
    [1.00, 0.70, 0.75, 0.70, 0.75, 1.00, 0.80, 0.65],
    [0.70, 1.00, 0.60, 0.60, 0.80, 1.00, 0.85, 0.50],
    [0.80, 0.60, 1.00, 0.65, 0.65, 1.00, 0.70, 0.70],
    [0.70, 0.50, 0.65, 1.00, 0.75, 1.00, 0.60, 0.65],
    [0.75, 0.80, 0.65, 0.75, 1.00, 1.00, 0.85, 0.50],
    [1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00],
    [0.80, 0.85, 0.70, 0.60, 0.85, 1.00, 1.00, 0.65],
    [0.65, 0.50, 0.75, 0.65, 0.50, 1.00, 0.65, 1.00],
  ]

  alias Primitive = Int32 | Int64 | Float64 | String | Bool | Nil
  alias JsonValue = Primitive | Array(JsonValue) | Hash(String, JsonValue) | Array(Hash(String, JsonValue)) | Hash(String, Hash(String, Int32)) | Array(Array(Float64))

  class ParseError < Exception
  end

  struct SheetExport
    getter gid : String
    getter output_path : String

    def initialize(@gid : String, @output_path : String)
    end

    def export_url(sheet_id : String)
      "https://docs.google.com/spreadsheets/d/#{sheet_id}/export?format=csv&id=#{sheet_id}&gid=#{gid}"
    end
  end

  class SheetDownloader
    def initialize(@sheet_id : String, @sheet_folder : String)
    end

    def download(exports : Array(SheetExport))
      clear_sheet_folder
      exports.each { |export| download_file(export.export_url(@sheet_id), export.output_path) }
    end

    private def clear_sheet_folder
      Dir.mkdir_p(@sheet_folder)
      Dir.each_child(@sheet_folder) do |entry|
        path = File.join(@sheet_folder, entry)
        File.file?(path) ? File.delete(path) : FileUtils.rm_rf(path)
      end
    end

    private def download_file(url : String, output_path : String)
      response = HTTP::Client.get(url)
      raise "Failed to download #{output_path}. status=#{response.status_code}" unless response.success?

      Dir.mkdir_p(File.dirname(output_path))
      File.write(output_path, response.body)
    end
  end

  module Normalizer
    extend self

    def normalize_numeric_value(raw_value : String, expect_range : Bool = false) : JsonValue
      value = raw_value.strip
      return nil if value.empty? || value == "🎲"

      cleaned = value.gsub('°', "").gsub("s", "").gsub("rpm", "").gsub('%', "").gsub(',', "").gsub('>', '-').strip

      if expect_range
        pieces = cleaned.split(" - ")
        raise ParseError.new("Expected numeric range but got: #{raw_value.inspect}") unless pieces.size == 2
        return pieces.map { |piece| coerce_number(parse_single_or_multiplier(piece)) }.map { |v| v.as(JsonValue) }
      end

      coerce_number(parse_single_or_multiplier(cleaned))
    end

    def detect_price_type(price : String) : String
      normalized = price.strip
      return "Coin" if normalized.empty?
      return normalized if VALID_PRICE_TYPES.includes?(normalized)

      capitalized = normalized.capitalize
      return capitalized if VALID_PRICE_TYPES.includes?(capitalized)

      return "WC" if normalized.includes?("WC")
      return "WC" if normalized == "Weird Boxes"
      return "Robux" if normalized == "Exclusive Weird Boxes"

      numeric_candidate = normalized.gsub(',', "")
      return "Coin" if numeric_candidate.to_i?

      "Unknown"
    end

    private def parse_single_or_multiplier(value : String) : Float64
      if value.includes?('x')
        left, right = value.split('x', 2)
        return left.to_f * right.to_f
      end
      value.to_f
    end

    private def coerce_number(value : Float64) : JsonValue
      whole = value.to_i
      whole.to_f == value ? whole : value
    end
  end

  class PartsParser
    @seen_parts = {} of Tuple(String, String) => Set(String)

    def initialize
      VALID_PART_CATEGORIES.each do |category|
        VALID_PART_TYPES.each do |part_type|
          @seen_parts[{category, part_type}] = Set(String).new
        end
      end
    end

    def parse_file(path : String) : Hash(String, Array(Hash(String, JsonValue)))
      rows = SheetParser.read_csv_rows(path)
      truncated = [] of Array(String)
      rows.each do |row|
        break if row.size >= 2 && row[1].starts_with?("Notable ")
        truncated << row
      end
      parse_rows(truncated)
    end

    def parse_rows(rows : Array(Array(String))) : Hash(String, Array(Hash(String, JsonValue)))
      output = {"Barrels" => [] of Hash(String, JsonValue), "Magazines" => [] of Hash(String, JsonValue), "Grips" => [] of Hash(String, JsonValue), "Stocks" => [] of Hash(String, JsonValue)}

      current_category = "AR"
      current_type = ""

      rows.each do |row|
        next if row.empty?
        raise ParseError.new("Invalid parts row length: expected 16, got #{row.size}") unless row.size == 16

        name = row[1].strip
        if divider = parse_divider(name)
          current_category, current_type = divider
          next
        end

        raise ParseError.new("Part encountered before section header") if current_type.empty?

        seen_key = {current_category, current_type}
        raise ParseError.new("Duplicate part name #{name}") if @seen_parts[seen_key].includes?(name)
        @seen_parts[seen_key] << name

        part = {"Price_Type" => Normalizer.detect_price_type(row[0]), "Name" => name, "Category" => current_category} of String => JsonValue

        (2..15).each do |index|
          cell = row[index].strip
          next if cell.empty?
          part[PART_PROPERTY_NAMES[index - 2]] = Normalizer.normalize_numeric_value(SheetParser.extract_leading_token(cell))
        end

        output[current_type] << part
      end

      output
    end

    private def parse_divider(name : String) : Tuple(String, String)?
      parts = name.split(" ")
      return nil unless parts.size == 2
      category, part_type = parts
      return nil unless VALID_PART_CATEGORIES.includes?(category) && VALID_PART_TYPES.includes?(part_type)
      {category, part_type}
    end
  end

  class CoresParser
    def parse_file(path : String) : Array(Hash(String, JsonValue))
      parse_rows(SheetParser.read_csv_rows(path))
    end

    def parse_rows(rows : Array(Array(String))) : Array(Hash(String, JsonValue))
      output = [] of Hash(String, JsonValue)
      current_category = "AR"

      rows.each do |row|
        next if row.empty?
        raise ParseError.new("Invalid cores row length: expected 18, got #{row.size}") unless row.size == 18

        name = row[1].strip
        if category_divider?(name)
          current_category = name[0...-6]
          next
        end

        core = {"Price_Type" => Normalizer.detect_price_type(row[0]), "Name" => name, "Category" => current_category} of String => JsonValue

        (2..17).each do |index|
          cell = row[index]
          if index == 2
            pellets = extract_pellets(cell)
            core["Pellets"] = pellets if pellets
          end
          value = Normalizer.normalize_numeric_value(cell, expect_range: index <= 3 || index >= 14)
          core[CORE_PROPERTY_NAMES[index - 2]] = value unless value.nil?
        end

        output << core
      end

      output
    end

    private def category_divider?(name : String) : Bool
      name.ends_with?(" Cores") && VALID_PART_CATEGORIES.includes?(name[0...-6])
    end

    private def extract_pellets(cell : String) : Int32?
      first_segment = cell.split(" > ")[0]
      pieces = first_segment.split('x')
      return nil unless pieces.size == 2
      pieces[1].to_i?
    end
  end

  extend self

  def read_csv_rows(path : String, skip_header_rows : Int32 = 2, trim_first_column : Bool = true) : Array(Array(String))
    rows = CSV.parse(File.read(path)).map(&.to_a)
    data_rows = rows[skip_header_rows..] || [] of Array(String)
    return data_rows.map { |row| row[1..] || [] of String } if trim_first_column
    data_rows
  end

  def extract_leading_token(cell : String) : String
    pieces = cell.split(" ", 2)
    raise ParseError.new("Invalid property cell format: #{cell.inspect}") if pieces.size < 2
    pieces[0]
  end

  def save_json(data : JsonValue, output_path : String)
    Dir.mkdir_p(File.dirname(output_path))
    File.write(output_path, data.to_json)
  end

  def build_full_data(parts_file : String = PARTS_V2_SHEET, cores_file : String = CORES_SHEET)
    parts_data = PartsParser.new.parse_file(parts_file)
    cores_data = CoresParser.new.parse_file(cores_file)

    combined_data = {
      "Barrels"   => parts_data["Barrels"],
      "Magazines" => parts_data["Magazines"],
      "Grips"     => parts_data["Grips"],
      "Stocks"    => parts_data["Stocks"],
      "Cores"     => cores_data,
    }

    {"Data" => combined_data, "Penalties" => CURRENT_PENALTIES, "Categories" => CURRENT_CATEGORIES}
  end

  def download_sheets
    SheetDownloader.new(SHEET_ID, SHEET_FOLDER).download([
      SheetExport.new(CORES_SHEET_GID, CORES_SHEET),
      SheetExport.new(PARTS_V2_SHEET_GID, PARTS_V2_SHEET),
    ])
  end

  def run
    download_sheets
    full_data = build_full_data
    save_json(full_data, OUTPUT_FILE)
  end
end
