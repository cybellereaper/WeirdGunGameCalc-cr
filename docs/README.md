# Web build (GitHub Pages)

This folder contains a static browser app for the calculator.

## Local preview

Use any static file server, for example:

```bash
python3 -m http.server 8080
```

Then open `http://localhost:8080/docs/`.

## GitHub Pages

1. Push this repository.
2. In GitHub repository settings, go to **Pages**.
3. Set source to **Deploy from branch**, branch `main` (or your default), folder `/docs`.
4. Save and wait for deployment.

The app loads `../Data/FullData.json` by default.

## Unit tests

```bash
node --test docs/tests/engine.test.mjs
```
