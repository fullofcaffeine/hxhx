# HXHX Gate 2 Workflow (CI + Local Usage)

Gate 2 is our first “toolchain-level” acceptance bar for Haxe-in-Haxe:

- it goes beyond “can we compile code?” and includes compiler tooling behaviors
- it maps to upstream Haxe’s `tests/runci/targets/Macro.hx`

See the definition of Gate 2 in:

- `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1`

## What CI runs (and why it’s split)

We keep Gate 2 split into two layers to avoid slowing down normal PR CI:

1) **Acceptance-only examples** (fast-ish, deterministic)
2) **Upstream runci Macro stage** (slow, depends on host tools)

This is implemented in:

- `.github/workflows/gate2.yml:1`

### Job: Acceptance-only examples

Runs:

- `npm run test:acceptance`

Why:

- validates the repo’s heavy “compiler-shaped” examples (`examples/`)
- catches regressions in codegen/runtime integration (compile → dune build → run)

Host requirements (Ubuntu):

- `ocaml`, `dune`, `ocaml-findlib`
- `libextlib-ocaml-dev` (needed by some examples that depend on ExtLib)

### Job: Upstream runci Macro (optional)

Runs:

- `bash scripts/vendor/fetch-haxe-upstream.sh`
- `npm run test:upstream:runci-macro`

This job is:

- **manual-only** (via `workflow_dispatch` input in GitHub Actions)
- not scheduled by default, because it is slower and toolchain-heavy

Host requirements (Ubuntu):

- OCaml toolchain: `ocaml`, `dune`, `ocaml-findlib`
- `neko` (upstream `RunCi` uses an echo server)
- `python3`, a C compiler toolchain (`build-essential`), and a JDK (`default-jdk`)

## How to trigger the workflow on GitHub

In GitHub Actions:

- Run workflow: **Gate 2 (HXHX)**
- By default it runs only **Acceptance-only examples**
- To also run upstream `runci` Macro:
  - set the input `run_upstream_macro=true`

## How to run Gate 2 locally

Acceptance-only examples:

```bash
npm run test:acceptance
```

Upstream runci Macro:

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:runci-macro
```

Notes:

- The upstream suite expects additional host tools depending on the stages it exercises.
- See `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1` for OS caveats (e.g. sys-stage behavior on macOS).
- Useful env flags for the runner (`scripts/hxhx/run-upstream-runci-macro.sh`):
  - `HXHX_GATE2_SKIP_PARTY=0`: enable `tests/party` (network-heavy; skipped by default for stability).
  - `HXHX_GATE2_MISC_FILTER=<pattern>`: run only a subset of `tests/misc` fixtures.
  - `HXHX_GATE2_SKIP_PARTY=1`: skip `tests/party` entirely (default).
  - `HXHX_GATE2_SEED_UTEST_FROM_GLOBAL=1`, `HXHX_GATE2_SEED_HAXESERVER_FROM_GLOBAL=1`, `HXHX_GATE2_SEED_SOURCEMAP_FROM_GLOBAL=1`:
    if those libs are installed globally, seed a local `.haxelib` via `haxelib dev` to avoid installs.
