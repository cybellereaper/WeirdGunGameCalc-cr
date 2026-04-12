# WeirdGunGameCalc (Go Rewrite)

This repository now includes a Go implementation of the Weird Gun Game calculator focused on:

- clean architecture,
- testable core logic,
- concurrent search,
- deterministic top-N sorting,
- JSON output for downstream tooling.

## Build

```bash
go build -o wggcalc ./cmd/calculator
```

## Run

```bash
./calculator -data Data/FullData.json -number 10 -sort TTK -priority AUTO -output Results.json
```

## Important notes

- The Go rewrite preserves core stat-composition behavior and filtering/sorting shape.
- The previous C++ project had multiple historical algorithms (Bruteforce/Prune/DynamicPrune). This rewrite currently uses a concurrent exhaustive search with modular pipeline logic.
- The web/WASM frontend is not yet ported to Go in this iteration.

## Test

```bash
go test ./...
```
