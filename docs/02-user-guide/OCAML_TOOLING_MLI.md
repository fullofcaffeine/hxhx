# Optional `.mli` Generation (OCaml-inferred)

OCaml does **not** require `.mli` interface files. A directory of `.ml` files will compile
fine without them, and the compiler will infer module interfaces automatically.

However, `.mli` files are still useful when:

- you want faster, clearer type errors at module boundaries,
- you want to **stabilize** a public API surface (by hiding internal values/types),
- or you want editor tooling (Merlin) to show a clean, “intended” interface.

## Strategy in this repo

This target implements optional `.mli` generation via **OCaml inference**:

- we run `ocamlc -i` (via `ocamlfind`) on the emitted `.ml` modules,
- write the inferred interface to `*.mli`,
- and then rebuild with dune to ensure the generated interfaces compile.

This approach is intentionally chosen over “derive `.mli` from Haxe types” because:

- the OCaml compiler is the source of truth for generalization/value restriction,
  module path resolution, hidden type equalities, etc.
- a Haxe-derived signature generator would be large, correctness-sensitive,
  and easy to drift from the real emitted OCaml semantics.

In the future, we *may* add an additional mode that emits a **curated** `.mli` for a
deliberately-stable public API surface (e.g. portable vs `ocaml.*` “native” surfaces),
but that is explicitly **not** required for bootstrapping `hxhx`.

## How to enable

Pass:

```bash
-D ocaml_mli
```

or explicitly:

```bash
-D ocaml_mli=infer
```

Notes:

- This requires an OCaml toolchain on `PATH` (`dune`, `ocamlc`, and `ocamlfind`).
- The generated `.mli` is **inferred**, not hand-curated. Expect it to be verbose and
  not particularly stable across backend changes.
- `.mli` generation implies a dune build (because inference needs typechecking).
  If you want a non-fatal best-effort mode (e.g. for CI where OCaml might be missing),
  add `-D ocaml_mli_best_effort`.

## What gets an `.mli` today

For robustness and speed, we infer `.mli` only for modules that dune actually compiled
for the requested build target (i.e. modules that have a corresponding `*.cmi` in
`_build/`).

This avoids needing a “compile every emitted module” pass (which would be much slower),
and it also avoids failures when an emitted-but-unused module references other modules
that dune never had to compile for the chosen target.
