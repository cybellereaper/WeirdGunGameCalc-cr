# WeirdGunGameCalc (Zig)

A full Zig rewrite of the Weird Gun Game calculator.

## What changed

- Replaced the previous C++ codebase with a Zig CLI application.
- Kept the same data source (`Data/FullData.json`).
- Reimplemented a production-friendly brute-force engine with filtering and sorting.
- Added unit tests for core logic (`zig build test`).

## Build

```bash
zig build -Doptimize=ReleaseFast
```

Executable output:

```bash
./zig-out/bin/wggcalc --help
```

## Run examples

```bash
./zig-out/bin/wggcalc --top 10 --sort ttk --include AR,SMG
./zig-out/bin/wggcalc --sort dps --priority highest --dps-min 100
./zig-out/bin/wggcalc --ttk-max 0.25 --mh 100
```

## Supported flags

- `--data <path>` path to `FullData.json`
- `--top <n>` number of returned builds
- `--mh <health>` max player health
- `--sort <ttk|dps|damage|damageend|firerate|magazine>`
- `--priority <highest|lowest|auto>`
- `--include <cat1,cat2,...>` include weapon categories
- `--damage-min`, `--damage-max`
- `--damage-end-min`, `--damage-end-max`
- `--ttk-min`, `--ttk-max` (seconds)
- `--dps-min`, `--dps-max`

## Test

```bash
zig build test
```
