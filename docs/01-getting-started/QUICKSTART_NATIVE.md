# Quickstart: Native Lane (Non-Delegating Runtime)

Use this path when you want `hxhx` native runtime compile behavior.

In native lane, `hxhx` uses linked backends (`--ocaml` / `--js <file>`) and should not delegate runtime compile work to stage0.

Canonical definitions:

- `docs/02-user-guide/concepts/execution_modes.md`
- `docs/02-user-guide/concepts/what_delegates_today.md`
- `docs/00-project/STAGE0_POLICY.md`

## Prerequisites

- Node.js + npm
- OCaml + dune + ocaml-findlib
- Haxe `4.3.7` (still used for bootstrap workflows)

## 1) Build `hxhx`

```bash
npm install
npx lix download
HXHX_BIN="$(bash scripts/hxhx/build-hxhx.sh | tail -n 1)"
echo "$HXHX_BIN"
```

If you run heavy stage0/source workflows and `which haxe` points to `.../lix/bin/haxeshim.js`, prefer a native binary explicitly:

```bash
HAXE_BIN="$HOME/haxe/versions/4.3.7/haxe" bash scripts/hxhx/regenerate-hxhx-bootstrap.sh --fast
```

## 2) Run native lane with stage0 forbidden

Native OCaml lane:

```bash
HXHX_FORBID_STAGE0=1 "$HXHX_BIN" --ocaml -cp src -main Main --hxhx-no-emit
```

Native JS lane:

```bash
HXHX_FORBID_STAGE0=1 "$HXHX_BIN" --js out/main.js -cp src -main Main --hxhx-no-run
```

Macro runtime mode (native lane):

- default is now in-process macros (`inproc`)
- fallback/debug mode is external host (`external-host`)

```bash
# Emergency fallback if you hit an inproc macro regression:
HXHX_MACRO_RUNTIME_MODE=external-host HXHX_FORBID_STAGE0=1 "$HXHX_BIN" --ocaml -cp src -main Main --hxhx-no-emit
```

## 3) Run core native checks

```bash
npm run ci:guards
HXHX_FORCE_STAGE0=0 npm run test:hxhx-targets
npm run test:upstream:replacement-ready:strict
```

Expected high-signal outputs include:

- `OK: stage0 policy (release)`
- `M7_STRICT_STAGE0:PASS`
- `M7_REPLACEMENT_READY:PASS`

(Marker docs: `docs/00-project/CI_GATES.md`)

## Troubleshooting

- `stage0 delegation blocked` / `HXHX_FORBID_STAGE0` failures
  - this is expected when a path still tries to delegate; use compat lane for that workflow or fix the native path.
- OCaml build toolchain not found
  - install `dune`, `ocamlopt`, `ocamlfind`.
- native JS smoke fails with unsupported expression
  - check current scoped support: `docs/02-user-guide/HXHX_JS_NATIVE_SCOPE_1_0.md`.
- macro behavior regression in native lane
  - use rollback knob: `HXHX_MACRO_RUNTIME_MODE=external-host`
  - capture emitted marker `hxhx_macro_runtime_mode=<mode>` in logs when filing the issue.
