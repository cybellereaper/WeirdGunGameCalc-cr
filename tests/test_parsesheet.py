from pathlib import Path
import importlib.util

MODULE_PATH = Path(__file__).resolve().parents[1] / "ParseSheet.py"
spec = importlib.util.spec_from_file_location("ParseSheet", MODULE_PATH)
ParseSheet = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(ParseSheet)


def test_format_number_single_numeric_variants():
    assert ParseSheet.FormatNumber("1,250") == 1250
    assert ParseSheet.FormatNumber("1.5s") == 1.5
    assert ParseSheet.FormatNumber("🎲") is None


def test_format_number_double_range_and_multiplier():
    assert ParseSheet.FormatNumber("20 > 30", doubleNum=True) == [20, 30]
    assert ParseSheet.FormatNumber("10x2 > 4x5", doubleNum=True) == [20, 20]


def test_detect_price_type_paths():
    assert ParseSheet.DetectPriceType("", 1) == "Coin"
    assert ParseSheet.DetectPriceType("2,000", 1) == "Coin"
    assert ParseSheet.DetectPriceType("500 WC", 1) == "WC"
    assert ParseSheet.DetectPriceType("limited", 1) == "limited"
    assert ParseSheet.DetectPriceType("????", 1) == "Unknown"


def test_parse_partsv2_parses_section_and_values(tmp_path: Path, monkeypatch):
    parts_csv = tmp_path / "parts2.csv"
    parts_csv.write_text(
        "h1,h2\n"
        "h3,h4\n"
        ",,AR Barrels,,,,,,,,,,,,,,\n"
        ",100,Test Barrel,1 Magazine_Size,2 Reload_Time,3 Damage,4 Detection_Radius,5 Equip_Time,6 Fire_Rate,7 Health,8 Magazine_Cap,9 Movement_Speed,10 Pellets,11 Range,12 Recoil,13 Reload_Speed,14 Spread\n"
    )

    monkeypatch.setattr(ParseSheet, "PARTSHEET2", parts_csv)

    output = {"Barrels": [], "Magazines": [], "Grips": [], "Stocks": [], "Cores": []}
    ParseSheet.ParsePartsv2(output)

    assert len(output["Barrels"]) == 1
    barrel = output["Barrels"][0]
    assert barrel["Name"] == "Test Barrel"
    assert barrel["Category"] == "AR"
    assert barrel["Price_Type"] == "Coin"
    assert barrel["Damage"] == 3
    assert barrel["Spread"] == 14


def test_parse_cores_parses_category_pellets_and_ranges(tmp_path: Path, monkeypatch):
    cores_csv = tmp_path / "cores.csv"
    cores_csv.write_text(
        "h1,h2\n"
        "h3,h4\n"
        ",,AR Cores,,,,,,,,,,,,,,,,\n"
        ",100,Test Core,10x2 > 20,30 > 40,5,6,7,8,9,10,11,12,13,14,15 > 16,17 > 18,19 > 20,21 > 22\n"
    )

    monkeypatch.setattr(ParseSheet, "CORESHEET", cores_csv)

    output = {"Barrels": [], "Magazines": [], "Grips": [], "Stocks": [], "Cores": []}
    ParseSheet.ParseCores(output)

    assert len(output["Cores"]) == 1
    core = output["Cores"][0]
    assert core["Name"] == "Test Core"
    assert core["Category"] == "AR"
    assert core["Price_Type"] == "Coin"
    assert core["Pellets"] == 2
    assert core["Damage"] == [20, 20]
    assert core["Dropoff_Studs"] == [30, 40]
    assert core["Recoil_Aim_Vertical"] == [21, 22]
