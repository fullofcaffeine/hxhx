# reflaxe.ocaml

Haxe → OCaml target built on Reflaxe.

This repo is currently in early scaffolding (see `prd.md` for the roadmap).

## Usage (current scaffold)

Generate `.ml` files into an output directory:

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output
```

`-D ocaml_output=<dir>` is required; it enables the compiler and selects the output folder.

## Two surfaces (design)

- Portable (default): keep Haxe stdlib semantics and portability; the target provides `std/_std` overrides and runtime helpers so users can target OCaml without writing OCaml-specific code.
- OCaml-native (opt-in): import `ocaml.*` for APIs that map more directly to OCaml idioms (e.g. `'a list`, `option`, `result`) while still using Haxe typing and tooling.

## Escape hatch

- `untyped __ocaml__("...")` injects raw OCaml snippets (intended for interop and early bring-up).
