# WeirdGunGameCalc (Rust)

## Build

```bash
cargo build --release
```

Executable output:

```bash
./target/release/wggcalc --help
```

## Run examples

```bash
./target/release/wggcalc --top 10 --sort ttk --include AR,SMG
./target/release/wggcalc --sort dps --priority highest --dps-min 100
./target/release/wggcalc --ttk-max 0.25 --mh 100
```

## Supported flags

- `--data <path>` path to `FullData.sqlite3` (JSON still supported for backward compatibility)
- `--top <n>` number of returned builds
- `--mh <health>` max player health
- `--sort <ttk|dps|damage|damageend|firerate|magazine>`
- `--priority <highest|lowest|auto>`
- `--include <cat1,cat2,...>` include weapon categories
- `--part-pool <n>` candidate parts per type per core
- `--damage-min`, `--damage-max`
- `--damage-end-min`, `--damage-end-max`
- `--damage`, `--damageStart`, `--damage-end`
- `--magazine`, `--spreadHip`, `--spreadAim`, `--recoilHip`, `--recoilAim`
- `--speed`, `--fireRate`, `--health`, `--pellet`, `--timeToAim`
- `--reload`, `--detectionRadius`, `--range`, `--rangeEnd`, `--burst`
- each metric also supports `--<metric>-min` and `--<metric>-max`
- `--ttk-min`, `--ttk-max` (seconds)
- `--dps-min`, `--dps-max`
- `--TTK`, `--DPS`
- force parts / cores: `--fb|--forceBarrel`, `--fm|--forceMagazine`, `--fg|--forceGrip`, `--fs|--forceStock`, `--fc|--forceCore`
- ban parts / cores: `--bb|--banBarrel`, `--bm|--banMagazine`, `--bg|--banGrip`, `--bs|--banStock`, `--bc|--banCore`
- `--banPriceType <COIN|WC|ROBUX|LIMITED|SPECIAL>`
- `--metrics`

## Test

```bash
cargo test
```

## Regenerating sheet data

```bash
cargo run --bin update-data
```
