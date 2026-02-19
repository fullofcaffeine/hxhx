# reflaxe.ocaml

MIT-licensed [Reflaxe](https://github.com/SomeRanDev/reflaxe) target that compiles Haxe to OCaml, with runtime/dune scaffolding for native builds.

This package is developed in the `hxhx` monorepo and is also usable with mainstream upstream Haxe workflows.

## What it provides

- Haxe → OCaml code generation (`.ml` files).
- Runtime support files under `std/runtime/`.
- Optional dune project emission (`dune`, `dune-project`).
- Optional post-emit native build/run helpers.
- Optional OCaml-native surface (`ocaml.*` types like `Option`, `Result`, `List`, `Hashtbl`, `Seq`, `Bytes`, `Buffer`).

## Requirements

- Haxe `4.3.7`
- Reflaxe `4.x`
- OCaml + dune + ocaml-findlib (for native build/run)

## Quickstart (inside this monorepo)

From repo root:

```bash
npm install
npx lix download
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output
```

Build emitted OCaml natively:

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out -D ocaml_build=native --no-output
```

## Using with mainstream upstream Haxe

If you want upstream Haxe CLI + `reflaxe.ocaml` (outside `hxhx` workflows), point `haxelib` to this repo checkout:

```bash
haxelib dev reflaxe.ocaml /path/to/hxhx
```

Then compile as usual:

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output
```

For a focused guide, see:
- [`docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md`](../../docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md)

## Required define

`reflaxe.ocaml` requires:

```bash
-D ocaml_output=<output-dir>
```

Without `ocaml_output`, OCaml target output is not selected.

## Common defines

- `-D ocaml_build=native|byte`: run dune build after emit.
- `-D ocaml_run`: run emitted executable via dune after emit.
- `-D ocaml_no_dune`: disable dune scaffolding emission.
- `-D ocaml_dune_layout=exe|lib`: choose dune layout.
- `-D ocaml_dune_exes=name:MainModule[,name2:Main2]`: multi-executable dune stanza.
- `-D ocaml_mli` or `-D ocaml_mli=infer|all`: generate `.mli` via `ocamlc -i`.
- `-D ocaml_sourcemap=directives`: add line directives for error mapping.

## Relationship to hxhx

- `hxhx` is the main compiler product in this repo.
- `reflaxe.ocaml` is both:
  - a standalone backend/runtime package for upstream Haxe users, and
  - a core implementation dependency used by `hxhx` bootstrap/native lanes.

## Related docs

- [`README.md` (repo root)](../../README.md)
- [`docs/01-getting-started/TESTING.md`](../../docs/01-getting-started/TESTING.md)
- [`docs/02-user-guide/HXHX_BACKEND_LAYERING.md`](../../docs/02-user-guide/HXHX_BACKEND_LAYERING.md)

## License

MIT. See [`LICENSE`](../../LICENSE).
