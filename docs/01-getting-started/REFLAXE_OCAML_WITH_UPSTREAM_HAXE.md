# Using `reflaxe.ocaml` with upstream Haxe

This guide is for users who want to keep using upstream Haxe while targeting OCaml through `reflaxe.ocaml`.

## What this gives you

- Upstream Haxe CLI/workflow.
- `reflaxe.ocaml` code generation/runtime.
- Native OCaml build path via dune.

## Prerequisites

- Haxe `4.3.7`
- Node.js + npm (for local repo tooling/lix workflows)
- OCaml + dune + ocaml-findlib (if you want to build/run emitted OCaml)

macOS:

```bash
brew install ocaml dune ocaml-findlib
```

Linux (Debian/Ubuntu):

```bash
sudo apt-get update
sudo apt-get install -y ocaml dune ocaml-findlib
```

## Option A: use local monorepo checkout (`haxelib dev`)

From your project (or globally), point `reflaxe.ocaml` to this repo:

```bash
haxelib dev reflaxe.ocaml /absolute/path/to/haxe.ocaml
```

Then compile with:

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output
```

Build emitted OCaml natively:

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out -D ocaml_build=native --no-output
```

## Option B: use repo-local `haxe_libraries` wiring in this monorepo

Inside this repo, `haxe_libraries/reflaxe.ocaml.hxml` already points to:

- `packages/reflaxe.ocaml/src/`
- `packages/reflaxe.ocaml/std/`
- `reflaxe.ocaml.CompilerInit.Start()`

So local tests/examples can use:

```bash
-lib reflaxe.ocaml
```

without publishing/reinstalling on each change.

## Common required define

`reflaxe.ocaml` expects:

```bash
-D ocaml_output=<output-dir>
```

Without it, target output is not selected.

## Relationship to `hxhx`

- `hxhx` is the primary compiler product in this repo.
- `reflaxe.ocaml` remains independently useful with upstream Haxe.
- We keep both in one repo right now because active development is still tightly coupled.
