# reflaxe.ocaml

[![Version](https://img.shields.io/badge/version-0.6.0-blue)]

Haxe → OCaml target built on Reflaxe.

This repo is currently in early scaffolding (see `prd.md` for the roadmap).

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

Optional flags:

- `-D ocaml_no_dune` to disable dune scaffolding emission.
- `-D ocaml_no_build` (or `-D ocaml_emit_only`) to skip post-emit build/run.
- `-D ocaml_build=native` (or `byte`) to force `dune build` after emitting (requires `dune` + `ocamlc` on PATH; fails hard if missing).
- `-D ocaml_run` to run the produced executable via `dune exec` after emitting (best-effort unless combined with `ocaml_build=...`).

## Two surfaces (design)

- Portable (default): keep Haxe stdlib semantics and portability; the target provides `std/_std` overrides and runtime helpers so users can target OCaml without writing OCaml-specific code.
- OCaml-native (opt-in): import `ocaml.*` for APIs that map more directly to OCaml idioms (e.g. `'a list`, `option`, `result`) while still using Haxe typing and tooling.

## Docs

- [Imperative → OCaml Lowering](docs/02-user-guide/IMPERATIVE_TO_OCAML_LOWERING.md) — how mutation/loops/blocks are lowered in portable vs OCaml-native surfaces.

## Escape hatch

- `untyped __ocaml__("...")` injects raw OCaml snippets (intended for interop and early bring-up).
