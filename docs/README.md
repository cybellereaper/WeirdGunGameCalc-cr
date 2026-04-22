# WebAssembly Calculator (GitHub Pages)

This folder contains a static calculator app that runs on GitHub Pages.

## Local build

1. Install `wasm-pack`.
2. From this folder (`docs/`), build the wasm package:

```bash
wasm-pack build --target web --out-dir pkg
```

3. Serve the `docs` directory with any static server:

```bash
python3 -m http.server 8000
```

Then open `http://localhost:8000`.

## Deploy on GitHub Pages

- Enable GitHub Pages to serve from the `docs/` directory on your default branch.
- Commit both source files and generated `docs/pkg/*` files.
- Re-run the build when `src/lib.rs` changes.
