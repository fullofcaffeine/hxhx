# OCaml Tooling: Error Mapping (Line Directives)

When compiling generated OCaml with dune, the OCaml compiler often reports errors
against dune’s `_build/` paths (e.g. `_build/default/Foo.ml`). This is correct,
but it’s inconvenient: the file you want to open/edit is the one in your output
directory (the emitted `Foo.ml`), not the build artifact.

## What the target does

By default, `reflaxe.ocaml` prefixes each generated OCaml module with an OCaml
**line directive**:

```ocaml
# 1 "Foo.ml"
```

This causes OCaml error messages to use the stable, user-facing emitted filename,
even when dune compiles from `_build/`.

This keeps:

- **line numbers** accurate for the emitted `.ml` file
- **filenames** stable and actionable (open `out/Foo.ml`, not `_build/...`)

## Disabling

If you need “raw dune locations” for debugging, disable directives with:

```bash
-D ocaml_no_line_directives
```

## Scope / limitations

- This improves **OCaml → emitted `.ml`** traceability.
- For **OCaml → Haxe** mapping, see `OCAML_TOOLING_SOURCE_MAPS.md` and
  `-D ocaml_sourcemap=directives` (best-effort).
