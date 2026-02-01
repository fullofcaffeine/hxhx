# reflaxe.ocaml

[![Version](https://img.shields.io/badge/version-0.8.0-blue)]

Haxe → OCaml target built on Reflaxe.

This repo is currently in early scaffolding (see `prd.md` for the roadmap).

## Environment setup

This repo has two “levels” of setup:

- **Emit-only** (generate `.ml` + dune scaffold): Node.js + Haxe (+ Lix).
- **Build/run** (produce a native executable): add OCaml + dune toolchain.

### Prerequisites

- **Node.js + npm** (used for Lix + dev tooling).
- **Haxe** (this repo targets Haxe **4.3.7** right now).
- **OCaml + dune** (required if you want to compile the emitted OCaml to a binary).

macOS (Homebrew):

```bash
brew install ocaml dune ocaml-findlib
```

Linux (example, Debian/Ubuntu):

```bash
sudo apt-get update
sudo apt-get install -y ocaml dune ocaml-findlib
```

## Usage (current scaffold)

This repo is set up for **Lix** (via `lix.client` / haxeshim-style `haxe_libraries`).

First-time setup:

```bash
npm install
npx lix download
```

Generate `.ml` files into an output directory:

```bash
npx haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output
```

`-D ocaml_output=<dir>` is required; it enables the compiler and selects the output folder.

By default, the target also emits a minimal `dune-project`, `dune`, and an executable entry module (`<exeName>.ml`) so the output directory is a runnable OCaml project.

### Build the emitted OCaml (native)

Option A (recommended): let the target invoke dune after emitting:

```bash
npx haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out -D ocaml_build=native --no-output
```

Option B: build manually with dune:

```bash
cd out
dune build ./*.exe
```

Optional flags:

- `-D ocaml_no_dune` to disable dune scaffolding emission.
- `-D ocaml_no_build` (or `-D ocaml_emit_only`) to skip post-emit build/run.
- `-D ocaml_build=native` (or `byte`) to force `dune build` after emitting (requires `dune` + `ocamlc` on PATH; fails hard if missing).
- `-D ocaml_run` to run the produced executable via `dune exec` after emitting (best-effort unless combined with `ocaml_build=...`).

## hxhx (Haxe-in-Haxe) bring-up

`hxhx` is the long-term “Haxe-in-Haxe” compiler. Right now it is a **stage0 shim** that delegates to a system `haxe`, but it already provides a place to hang acceptance tests and bootstrapping gates.

Build the `hxhx` example (requires `dune` + `ocamlc`):

```bash
bash scripts/hxhx/build-hxhx.sh
```

Run upstream Gate 1 (requires a local Haxe checkout; defaults to the author’s path):

```bash
HAXE_UPSTREAM_DIR=/path/to/haxe \
  npm run test:upstream:unit-macro
```

Run upstream Gate 2 (runci Macro target; heavier and more tool-dependent):

```bash
HAXE_UPSTREAM_DIR=/path/to/haxe \
  npm run test:upstream:runci-macro
```

Gate 2 requires additional tooling beyond Gate 1 (at least `git`, `haxelib`, `neko`/`nekotools`, `python3`, `javac`, and a C compiler like `cc`/`clang`), and it can download external deps (e.g. `tink_core`) during the run.

## Two surfaces (design)

- Portable (default): keep Haxe stdlib semantics and portability; the target provides `std/_std` overrides and runtime helpers so users can target OCaml without writing OCaml-specific code.
- OCaml-native (opt-in): import `ocaml.*` for APIs that map more directly to OCaml idioms (e.g. `'a list`, `option`, `result`) while still using Haxe typing and tooling.

## Docs

- [Imperative → OCaml Lowering](docs/02-user-guide/IMPERATIVE_TO_OCAML_LOWERING.md) — how mutation/loops/blocks are lowered in portable vs OCaml-native surfaces.

## Escape hatch

- `untyped __ocaml__("...")` injects raw OCaml snippets (intended for interop and early bring-up).
