# Quickstart: Compat Lane (Delegated)

Use this path when you want compatibility-first behavior immediately.

In compat lane, `hxhx` delegates compile work to upstream `haxe` (`stage0`).

Canonical definition:

- `docs/02-user-guide/concepts/what_delegates_today.md`

## Prerequisites

- Node.js + npm
- Haxe `4.3.7`

## 1) Build `hxhx`

```bash
npm install
npx lix download
HXHX_BIN="$(bash scripts/hxhx/build-hxhx.sh | tail -n 1)"
echo "$HXHX_BIN"
```

## 2) Run a compat compile

OCaml delegated macro lane:

```bash
"$HXHX_BIN" --ocaml-eval -cp src -main Main --no-output -D ocaml_no_build
```

JS passthrough compat lane:

```bash
"$HXHX_BIN" --compat --js out/main.js -cp src -main Main
```

## 3) Verify lane behavior

Add trace output to confirm selection:

```bash
HXHX_TRACE_BACKEND_SELECTION=1 "$HXHX_BIN" --ocaml-eval -cp src -main Main --no-output -D ocaml_no_build
```

This lane is expected to rely on stage0 runtime delegation.

## Troubleshooting

- `hxhx: --target removed`
  - use direct flags: `--ocaml`, `--ocaml-eval`, `--js <file>`, and `--compat`.
- `No such file or directory` for upstream `haxe`
  - ensure `haxe -version` works on `PATH` (or set `HAXE_BIN` explicitly).
- you want non-delegating behavior
  - switch to `docs/01-getting-started/QUICKSTART_NATIVE.md`.
