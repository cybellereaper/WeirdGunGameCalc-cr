# WeirdGunGameCalc (Zig Rewrite)

A full Zig rewrite of the original Weird Gun Game build calculator.

## What changed

- Replaced the legacy C++ implementation with a modular Zig codebase.
- Added typed JSON parsing for `Data/FullData.json`.
- Added a clean calculation engine with deterministic scoring and top-N selection.
- Added unit tests for core stat math and ranking behavior.

## Build

```bash
zig build
```

## Run

```bash
zig build run -- --data Data/FullData.json --output Results.txt --sort TTK --top 10 --max-health 100
```

## CLI Options

- `--data <path>`: Path to full JSON dataset. Default: `Data/FullData.json`
- `--output <path>`: Output text file path. Default: `Results.txt`
- `--sort <metric>`: `TTK`, `DAMAGE`, `DAMAGEEND`, `FIRERATE`, or `DPS`
- `--top <n>`: Number of results to output. Default: `10`
- `--max-health <n>`: Health used by TTK calculations. Default: `100`
- `--include <category>`: Include one category (repeat flag for multiple categories)

## Test

```bash
zig build test
```
