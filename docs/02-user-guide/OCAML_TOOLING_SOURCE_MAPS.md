# OCaml Tooling: Source Maps (OCaml errors → Haxe positions)

`reflaxe.ocaml` can optionally emit a **best-effort source map layer** so that OCaml
compiler errors can point back to **`.hx` file/line locations**, not only generated
`.ml` locations.

## Enabling

Enable the source map directives with:

```bash
-D ocaml_sourcemap=directives
```

This is intended to be used together with `-D ocaml_build=native|byte` (so dune/ocamlc
is actually invoked after emission).

## How it works

When `ocaml_sourcemap=directives` is enabled, the backend wraps many generated OCaml
expressions with OCaml **line directives** of the form:

```ocaml
# 42 "path/to/File.hx"
```

OCaml treats the following lines as originating from that file/line, which makes
type errors and syntax errors far more actionable when developing against Haxe code.

This is complementary to the default module-level directive described in
`OCAML_TOOLING_ERROR_MAPPING.md`, which improves the stability of `.ml` filenames
under dune.

## Limitations / tradeoffs

- **Best-effort**: the backend does not (yet) produce an exact 1:1 mapping between
  Haxe and OCaml columns or spanning ranges. The goal is to land you in the right
  Haxe *file and approximate line* quickly.
- **Formatting impact**: directives must start at OCaml column 0, so enabling this
  feature can introduce extra newlines and affect the readability of generated `.ml`.
- **Compile-time overhead**: line/column computation requires reading source files.
  This is cached, but still adds some overhead compared to the default mode.

## When to use it

- You’re iterating on backend semantics and hitting OCaml type errors.
- You’re working on portable stdlib behavior and want errors to lead you back to
  the originating `.hx` code quickly.

For stable emitted `.ml` filenames (without mapping back to Haxe), keep the default
behavior from `OCAML_TOOLING_ERROR_MAPPING.md`.

