# WeirdGunGameCalc

## Build

```bash
shards build --release
```

Executable output:

```bash
./bin/wggcalc --help
```

## Run examples

```bash
./bin/wggcalc --top 10 --sort ttk --include AR,SMG
./bin/wggcalc --sort dps --priority highest --dps-min 100
./bin/wggcalc --ttk-max 0.25 --mh 100
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
- `--ttk-min`, `--ttk-max` (seconds)
- `--dps-min`, `--dps-max`
- `--metrics`

## Test

```bash
crystal spec
```

## Regenerating sheet data

```bash
crystal run ParseSheet.cr
```


## Web app (GitHub Pages)

A browser-hosted version is available under `docs/`.

- Entry point: `docs/index.html`
- Engine: `docs/src/engine.js`
- UI: `docs/src/app.js`
- Tests: `docs/tests/engine.test.mjs`

See `docs/README.md` for GitHub Pages deployment steps.
