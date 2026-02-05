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

## Run

No args (example harness mode):

```bash
packages/hxhx/out/_build/default/out.exe
```

Delegate to Stage 0 `haxe`:

```bash
HAXE_BIN=haxe packages/hxhx/out/_build/default/out.exe -- compile.hxml
```
