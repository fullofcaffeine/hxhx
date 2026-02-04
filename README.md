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
- `-D ocaml_dune_layout=exe|lib` to choose between an executable scaffold (default) or a library-only dune project.
- `-D ocaml_dune_exes=name:MainModuleId[,name2:MainModuleId...]` to emit a multi-executable dune stanza (`(executables ...)`) with one entry module per name.
- `-D ocaml_no_build` (or `-D ocaml_emit_only`) to skip post-emit build/run.
- `-D ocaml_build=native` (or `byte`) to force `dune build` after emitting (requires `dune` + `ocamlc` on PATH; fails hard if missing).
- `-D ocaml_run` to run the produced executable via `dune exec` after emitting (best-effort unless combined with `ocaml_build=...`).
- `-D ocaml_mli` (or `-D ocaml_mli=infer|all`) to generate inferred `*.mli` via `ocamlc -i` and rebuild with dune (requires `ocamlfind`).
- `-D ocaml_no_line_directives` to disable `# 1 "File.ml"` prefixes (default is enabled to improve dune error locations).

## hxhx (Haxe-in-Haxe) bring-up

`hxhx` is the long-term “Haxe-in-Haxe” compiler. Right now it is a **stage0 shim** that delegates to a system `haxe`, but it already provides a place to hang acceptance tests and bootstrapping gates.

Terminology note: in this repo, “compile Haxe” might mean compiling this backend, building the upstream compiler binary, or compiling Haxe projects. See `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1` for precise definitions and the Stage0→Stage2 bootstrapping model.

Build the `hxhx` example (requires `dune` + `ocamlc`):

```bash
bash scripts/hxhx/build-hxhx.sh
```

Run upstream Gate 1 (requires a local Haxe checkout; defaults to the author’s path):

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:unit-macro
```

Run upstream Gate 2 (runci Macro target; heavier and more tool-dependent):

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:runci-macro
```

Gate 2 requires additional tooling beyond Gate 1 (at least `git`, `haxelib`, `neko`/`nekotools`, `python3`, `javac`, and a C compiler like `cc`/`clang`), and it can download external deps (e.g. `tink_core`) during the run.
You can override the upstream checkout via `HAXE_UPSTREAM_DIR=/path/to/haxe`.

## Two surfaces (design)

- Portable (default): keep Haxe stdlib semantics and portability; the target provides `std/_std` overrides and runtime helpers so users can target OCaml without writing OCaml-specific code.
- OCaml-native (opt-in): import `ocaml.*` for APIs that map more directly to OCaml idioms (e.g. `'a list`, `option`, `result`) while still using Haxe typing and tooling.

## Docs

- [Imperative → OCaml Lowering](docs/02-user-guide/IMPERATIVE_TO_OCAML_LOWERING.md) — how mutation/loops/blocks are lowered in portable vs OCaml-native surfaces.
- [Compatibility Matrix](docs/02-user-guide/COMPATIBILITY_MATRIX.md) — what works today (portable vs `ocaml.*`) and known limitations.
- [HXHX Builtin Backends](docs/02-user-guide/HXHX_BUILTIN_BACKENDS.md) — design for bundling/linking targets and the proposed `--target` registry.
- [OCaml Interop: Labelled Args](docs/02-user-guide/OCAML_INTEROP_LABELLED_ARGS.md) — how to express `~label:` / `?label:` extern callsites from Haxe.
- [OCaml-native Mode](docs/02-user-guide/OCAML_NATIVE_MODE.md) — when/why to use `ocaml.*` and how the surface maps to `Stdlib`.
- [Optional `.mli` Generation](docs/02-user-guide/OCAML_TOOLING_MLI.md) — `.mli` inference via `ocamlc -i` for better OCaml tooling UX.
- [Error Mapping](docs/02-user-guide/OCAML_TOOLING_ERROR_MAPPING.md) — line directives to keep OCaml error locations stable under dune.

## Escape hatch

- `untyped __ocaml__("...")` injects raw OCaml snippets (intended for interop and early bring-up).
