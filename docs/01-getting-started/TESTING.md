# Testing Strategy

This repo’s tests are intentionally split into **fast compiler checks** and **behavioral checks** that require an OCaml toolchain.

The goal is to:

- keep `npm test` fast enough for tight iteration
- still have realistic “this actually builds and runs under dune” coverage
- provide at least one **compiler-shaped acceptance workload** (not just unit tests / golden output)

## Quick start

From the repo root:

```bash
npm test
```

If you have `ocamlc` + `dune` installed, this also runs:

- portable conformance fixtures (`test/portable/**`)
- example apps (`examples/**`, except acceptance-only examples)

To run the heavier acceptance examples:

```bash
npm run test:acceptance
```

## Upstream Haxe acceptance gates (Haxe-in-Haxe path)

These are **not** part of `npm test` because they depend on:

- a local checkout of the upstream Haxe compiler repo
- extra toolchains / deps (`haxelib`, network for pinned libs, etc.)

Gate 1 (unit macro suite) uses the upstream file:

- `tests/unit/compile-macro.hxml`

Run it via the `hxhx` harness:

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:unit-macro
```

Notes:

- Today `npm run test:upstream:unit-macro` is a **native/non-delegating bring-up rung**:
  it routes the upstream `compile-macro.hxml` through `hxhx --hxhx-stage3 --hxhx-no-emit` to exercise
  resolver + typer + macro-host plumbing without invoking a stage0 `haxe` binary.
  - The historical stage0-shim baseline remains available as:
    `npm run test:upstream:unit-macro-stage0`
- By default, upstream gate runners look for `vendor/haxe`; override with `HAXE_UPSTREAM_DIR=/path/to/haxe`.
- “Replacement-ready” acceptance is defined in `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1`.
  That document also clarifies what we mean by “compile Haxe” and how Stage0→Stage2 bootstrapping works.

Gate 2 (runci Macro target) runs the upstream `tests/runci/targets/Macro.hx` suite:

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:runci-macro
```

Notes:

- This is **not** run in GitHub Actions CI by default (it is network-heavy and relies on external toolchains).
- Host toolchain requirements and macOS sys-stage caveats are documented in `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1`.
- Debugging: set `HXHX_GATE2_MISC_FILTER=<pattern>` to run only a subset of `tests/misc` fixtures.
- By default this uses a **non-delegating** Gate 2 mode (`HXHX_GATE2_MODE=stage3_no_emit_direct`): it runs the same stage
  sequence as upstream runci Macro, but routes every `haxe` invocation through `hxhx --hxhx-stage3 --hxhx-no-emit`.
  - To run the historical “stage0 shim” harness instead, set `HXHX_GATE2_MODE=stage0_shim`.
  - `HXHX_GATE2_MODE=stage3_emit_runner` is an experimental rung: it tries to compile+run the upstream RunCi runner under the
    Stage3 bootstrap emitter (intended to run upstream `tests/RunCi.hx` unmodified once Stage3 is ready).
  - `HXHX_GATE2_MODE=stage3_emit_runner_minimal` is a bring-up rung that patches `tests/RunCi.hx` *in the temporary worktree*
    to a minimal harness so we can at least prove sub-invocation spawning.

Dedicated display smoke rung (non-delegating Stage3 no-emit):

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:display-stage3-no-emit
```

Notes:

- This validates `--display <file@mode>` request handling directly through `hxhx --hxhx-stage3 --hxhx-no-emit`.
- It intentionally does **not** require full upstream `--wait` display server parity yet.

### Stage 2 reproducibility rung (Stage1 builds Stage2)

This is a local bootstrap sanity check:

- Build stage1 `hxhx` (native OCaml binary).
- Use that stage1 binary to build stage2.
- Compare behavior and (best-effort) emitted `.ml` output hashes.

Run:

```bash
npm run test:upstream:stage2
```

### Gate 3 (runci matrix for selected targets)

Gate 3 runs additional upstream `tests/runci` targets beyond `Macro`.

Select targets via `HXHX_GATE3_TARGETS` (comma-separated) or pass them as args:

```bash
HXHX_GATE3_TARGETS="Macro,Js" npm run test:upstream:runci-targets
```

Notes:

- This is **not** run in CI by default (very toolchain/network dependent).
- By default, missing target toolchains fail the run; set `HXHX_GATE3_ALLOW_SKIP=1` to skip missing deps.
- For the `Macro` target, the runner applies the same stability knobs as Gate 2:
  - `HXHX_GATE2_SKIP_PARTY=1` (default) skips `tests/party` (network-heavy).
  - `HXHX_GATE2_SEED_UTEST_FROM_GLOBAL=1`, `HXHX_GATE2_SEED_HAXESERVER_FROM_GLOBAL=1`, `HXHX_GATE2_SEED_SOURCEMAP_FROM_GLOBAL=1`
    seed the local `.haxelib` repo from globally installed libs to avoid network installs when possible.

## Layers

### 1) “Build the backend” checks (fast, no dune required)

These checks run `haxe` compilations and/or compare emitted `.ml` text:

- **Printer tests**: ensure OCaml AST printing stays stable/valid.
- **Integration compile tests**: ensure the backend can compile representative Haxe code.
- **Snapshot tests** (`test/snapshot/**`): golden `.ml` output comparisons (compile-to-OCaml only; no dune build).

These catch regressions in:

- TypedExpr lowering (`OcamlBuilder`)
- printing/formatting (`OcamlASTPrinter`)
- module scheduling/ordering (`OcamlCompiler`)

### 2) “Runs under dune” checks (requires OCaml toolchain)

If `dune` and `ocamlc` are available, we additionally run:

- **Portable fixtures** (`test/portable/fixtures/**`): compile → dune build → run → diff stdout.
- **Examples** (`examples/**`): compile → dune build → run → diff stdout.

These catch regressions that pure snapshot tests can’t, like:

- OCaml type errors caused by ordering/dependencies
- missing runtime shims or incorrect OCaml stdlib usage
- runtime-level behavioral differences (null semantics, string handling, sys APIs)

### 3) Acceptance workloads (explicitly heavier)

Some example apps are marked with an `ACCEPTANCE_ONLY` file and are skipped by default.

Run them with:

```bash
npm run test:acceptance
```

Today, the primary acceptance workload is:

- `examples/hih-workload` — a multi-file “project compiler” that exercises parsing, type checking, and incremental rebuilds (Stage 1 toward Haxe-in-Haxe enough).
