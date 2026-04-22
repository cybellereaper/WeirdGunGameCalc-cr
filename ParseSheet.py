import csv
import json
import os
from pathlib import Path
from typing import Any

SHEETID = "1Kc9aME3xlUC_vV5dFRe457OchqUOrwuiX_pQykjCF68"
SHEETFOLDER = Path("SheetData")

PARTSHEET = SHEETFOLDER / "parts.csv"
PARTSHEETGID = "503295784"
PARTSHEET2 = SHEETFOLDER / "parts2.csv"
PARTSHEET2GID = "319672878"
CORESHEET = SHEETFOLDER / "cores.csv"
CORESHEETGID = "911413911"

OUTPUTFILE = Path("Data") / "FullData.json"

validPartCategories = ["AR", "Sniper", "SMG", "LMG", "Shotgun", "BR", "Weird", "Sidearm"]
validPartTypes = ["Barrels", "Magazines", "Grips", "Stocks"]
validPriceTypes = [
    "Coin",
    "WC",
    "Follow",
    "Robux",
    "Free",
    "Spin",
    "Limited",
    "Missions",
    "Verify discord",
    "Season Pass 1",
    "Unknown",
]  # The calculator will only detect "Coin" "WC" "Robux". Anything else will be turned into "Special"

PART_PROPERTIES = [
    "Magazine_Size",
    "Reload_Time",
    "Damage",
    "Detection_Radius",
    "Equip_Time",
    "Fire_Rate",
    "Health",
    "Magazine_Cap",
    "Movement_Speed",
    "Pellets",
    "Range",
    "Recoil",
    "Reload_Speed",
    "Spread",
]

CORE_PROPERTIES = [
    "Damage",
    "Dropoff_Studs",
    "Fire_Rate",
    "Hipfire_Spread",
    "ADS_Spread",
    "Time_To_Aim",
    "Detection_Radius",
    "Burst",
    "Movement_Speed_Modifier",
    "Suppression",
    "Health",
    "Equip_Time",
    "Recoil_Hip_Horizontal",
    "Recoil_Hip_Vertical",
    "Recoil_Aim_Horizontal",
    "Recoil_Aim_Vertical",
]


def FindSameName(obj, name):
    for value in obj:
        if value["Name"] == name:
            return value


def DeepCompare(obj1, obj2):
    for partType, partList in obj1.items():
        print(f"\n------------------------- {partType} -----------------------------\n")
        for part in partList:
            if part["Name"] == "Stat Randomizer":
                continue
            part2 = FindSameName(obj2[partType], part["Name"])
            if part2 is None:
                print(f"Part {part['Name']} not found in {partType}")
                continue
            for i, v in part.items():
                try:
                    if v != part2[i]:
                        print(part, "\n", part2)
                        print()
                        break
                except KeyError:
                    print(part, "\n", part2)
                    print()
                    break


def FormatNumber(value: str, doubleNum: bool = False):
    raw = value.strip()
    if raw in {"", "🎲"}:
        return None

    normalized = (
        raw.replace("°", "")
        .replace("s", "")
        .replace("rpm", "")
        .replace("%", "")
        .replace(",", "")
        .replace(">", "-")
        .strip()
    )

    if not doubleNum:
        number = float(normalized)
        return int(number) if int(number) == number else number

    if " - " not in normalized:
        raise RuntimeError(f"Couldn't find separator for {normalized}")

    values = [_parse_multiplier_or_number(v) for v in normalized.split(" - ")]
    if len(values) != 2:
        raise AssertionError(f"Expected two numbers, got {normalized}")

    return [int(v) if int(v) == v else v for v in values]


def _parse_multiplier_or_number(value: str) -> float:
    if "x" in value:
        lhs, rhs = value.split("x")
        return float(lhs) * float(rhs)
    return float(value)


def DetectPriceType(price, row) -> str:
    price = price.strip()

    if price == "":  # No data so we just return coin
        return "Coin"

    if price in validPriceTypes or price.capitalize() in validPriceTypes:
        return price

    price = price.replace(",", "")  # Remove commas from the values more than 1,000

    if "WC" in price:
        return "WC"
    try:
        int(price)
        return "Coin"
    except ValueError:  # Price must be either Robux or Limited or Free
        price = price.capitalize()
        if price not in validPriceTypes:
            print(f"WARNING: Invalid price type detected at row {row}")
            return "Unknown"
        return price


def DownloadSheet():
    SHEETFOLDER.mkdir(parents=True, exist_ok=True)
    os.system(f"rm -f {SHEETFOLDER}/*")
    # os.system(f'wget -O {PARTSHEET} "https://docs.google.com/spreadsheets/d/{SHEETID}/export?format=csv&id={SHEETID}&gid={PARTSHEETGID}"')
    os.system(f'wget -O {CORESHEET} "https://docs.google.com/spreadsheets/d/{SHEETID}/export?format=csv&id={SHEETID}&gid={CORESHEETGID}"')
    os.system(f'wget -O {PARTSHEET2} "https://docs.google.com/spreadsheets/d/{SHEETID}/export?format=csv&id={SHEETID}&gid={PARTSHEET2GID}"')


def _read_sheet_rows(path: Path) -> list[list[str]]:
    with open(path, "r") as file:
        return [row[1:] for row in list(csv.reader(file))[2:]]


def _build_base_item(row: list[str], name: str, category: str) -> dict[str, Any]:
    return {
        "Price_Type": DetectPriceType(row[0], row),
        "Name": name,
        "Category": category,
    }


def _parse_part_properties(row: list[str]) -> dict[str, Any]:
    parsed: dict[str, Any] = {}
    for index, property_name in enumerate(PART_PROPERTIES, start=2):
        column_value = row[index].strip()
        if not column_value:
            continue
        value_token = column_value.split(" ", 1)[0]
        parsed[property_name] = FormatNumber(value_token)
    return parsed


def ParsePartsv2(outputData):
    data = _read_sheet_rows(PARTSHEET2)

    currentCategory = "AR"
    currentType = ""
    seenParts = {x: set() for x in validPartCategories}

    for row in data:
        try:
            if len(row) == 0:
                continue
            assert len(row) == 16, f"invalid row length {row} expected 16"

            name = row[1].strip()
            categoryType = name.split(" ")

            if len(categoryType) == 2:
                if categoryType[0] == "Notable":
                    break
                if categoryType[0] in validPartCategories and categoryType[1] in validPartTypes:
                    currentCategory = categoryType[0]
                    currentType = categoryType[1]
                    continue

            if name in seenParts[currentCategory]:
                raise ValueError(f"Duplicate part name '{name}' in category '{currentCategory}'")
            seenParts[currentCategory].add(name)

            part = _build_base_item(row, name, currentCategory)
            part.update(_parse_part_properties(row))
            outputData[currentType].append(part)
        except Exception as error:
            print(f"Error parsing row {row}", flush=True)
            raise error


def _extract_pellets(damage_cell: str):
    pellet = damage_cell.split(" > ")[0].split("x")
    if len(pellet) == 2:
        return int(pellet[1])
    return None


def _parse_core_properties(row: list[str]) -> dict[str, Any]:
    parsed: dict[str, Any] = {}

    pellets = _extract_pellets(row[2])
    if pellets is not None:
        parsed["Pellets"] = pellets

    for index, property_name in enumerate(CORE_PROPERTIES, start=2):
        formatted_val = FormatNumber(row[index], doubleNum=(index <= 3 or index >= 14))
        if formatted_val is not None:
            parsed[property_name] = formatted_val
    return parsed


def ParseCores(outputData):
    data = _read_sheet_rows(CORESHEET)

    currentCategory = "AR"
    for row in data:
        try:
            if len(row) == 0:
                continue
            assert len(row) == 18, f"invalid row length {len(row)} expected 18"

            name = row[1].strip()
            if name[:-6] in validPartCategories:  # remove the word Cores from the back
                currentCategory = name[:-6]
                continue

            core = _build_base_item(row, name, currentCategory)
            core.update(_parse_core_properties(row))
            outputData["Cores"].append(core)

        except Exception as error:
            print(f"Error parsing row {row}", flush=True)
            raise error


def SaveData(outputData):
    with open(OUTPUTFILE, "w") as file:
        json.dump(outputData, file, indent=2)


def Compare():
    with open(OUTPUTFILE, "r") as file:
        SheetData = json.load(file)
    with open("Data/FullData.json", "r") as file:
        MyData = json.load(file)

    DeepCompare(SheetData, MyData)


# Anything with current_ is part of the Data used for calculations. Not part of the FileFormatter.py which is why there are two category variables
# The number is the index for current_penalties
current_categories = {
    "Primary": {
        "AR": 0,
        "Sniper": 1,
        "SMG": 2,
        "Shotgun": 3,
        "LMG": 4,
        "Weird": 5,
        "BR": 6,
    },
    "Secondary": {"Sidearm": 7},
}

current_penalties = [
    [1.00, 0.70, 0.75, 0.70, 0.75, 1.00, 0.80, 0.65],
    [0.70, 1.00, 0.60, 0.60, 0.80, 1.00, 0.85, 0.50],
    [0.80, 0.60, 1.00, 0.65, 0.65, 1.00, 0.70, 0.70],
    [0.70, 0.50, 0.65, 1.00, 0.75, 1.00, 0.60, 0.65],
    [0.75, 0.80, 0.65, 0.75, 1.00, 1.00, 0.85, 0.50],
    [1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00],
    [0.80, 0.85, 0.70, 0.60, 0.85, 1.00, 1.00, 0.65],
    [0.65, 0.50, 0.75, 0.65, 0.50, 1.00, 0.65, 1.00],
]


def Penalties():
    """
    It doesn't really look that good when dumping from a script but you can look at the current penalties in this python script instead haha
    The penalties will get accessed based on this string to index conversion table.
    """

    print("Running Penalties")

    with open("Data/Categories.json", "w") as file:
        json.dump(current_categories, file, indent=2)

    with open("Data/Penalties.json", "w") as file:
        json.dump(current_penalties, file)


def main():
    DownloadSheet()
    outputData = {"Barrels": [], "Magazines": [], "Grips": [], "Stocks": [], "Cores": []}
    # ParseParts(outputData)
    ParsePartsv2(outputData)
    ParseCores(outputData)
    # Penalties()
    fullData = {"Data": outputData, "Penalties": current_penalties, "Categories": current_categories}
    SaveData(fullData)
    # Compare()


if __name__ == "__main__":
    main()
