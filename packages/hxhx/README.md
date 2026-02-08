# hxhx (Haxe-in-Haxe compiler driver, Stage 0 shim)

This example produces the `hxhx` binary.

Today it is intentionally a **Stage 0 shim**:

- It is compiled to native OCaml via `reflaxe.ocaml`.
- It delegates actual compilation to an existing `haxe` binary (Stage 0), so we can:
  - validate the end-to-end harness (build → run → invoke upstream suites),
  - stabilize the intended CLI surface,
  - and then replace internals incrementally with real Haxe-in-Haxe compiler subsystems.

Long-term, `hxhx` becomes the real Haxe-in-Haxe compiler, and the delegation path is removed.

## Build

From repo root (requires `dune` + `ocamlc`):

```bash
haxe -C packages/hxhx build.hxml -D ocaml_build=native
```

Binary will be at:

`packages/hxhx/out/_build/default/out.exe`

## Bootstrap snapshot (maintainers)

By default, `scripts/hxhx/build-hxhx.sh` builds from the committed OCaml snapshot under
`packages/hxhx/bootstrap_out/` so CI can build `hxhx` without requiring a stage0 `haxe`
binary on PATH.

To regenerate the snapshot (requires stage0 `haxe`):

```bash
HAXE_BIN="$HOME/haxe/versions/4.3.7/haxe" bash scripts/hxhx/regenerate-hxhx-bootstrap.sh
```

Notes:

- This can take several minutes because it runs stage0 Haxe macros for codegen.
- For progress logs from `reflaxe.ocaml`, set `HXHX_STAGE0_PROGRESS=1` (emits periodic `Context.warning(...)` markers during the stage0 build).
- For profiling, set `HXHX_BOOTSTRAP_DEBUG=1` to print `--times` output.
- For very verbose stage0 compiler logs (including typing/module loading), set `HXHX_STAGE0_VERBOSE=1` (passes `-v` to stage0 `haxe`).
- If you run a compilation server, you can pass `HAXE_CONNECT=<port>` to reuse it.

If you need to rebuild `hxhx` from stage0 source (instead of the committed `bootstrap_out`), use:

```bash
HAXE_BIN="$HOME/haxe/versions/4.3.7/haxe" HXHX_FORCE_STAGE0=1 HXHX_STAGE0_PROGRESS=1 HXHX_STAGE0_TIMES=1 HXHX_STAGE0_VERBOSE=1 bash scripts/hxhx/build-hxhx.sh
```

## Run

No args (example harness mode):

```bash
packages/hxhx/out/_build/default/out.exe
```

Delegate to Stage 0 `haxe`:

```bash
HAXE_BIN=haxe packages/hxhx/out/_build/default/out.exe -- compile.hxml
```
