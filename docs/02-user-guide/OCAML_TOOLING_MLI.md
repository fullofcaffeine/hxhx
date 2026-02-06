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

## Does this choice affect `hxhx` portability?

No — this is an **OCaml-target tooling feature**, not a `hxhx` architectural dependency.

- `ocamlc -i` is only used when **you are already targeting OCaml** and you ask the backend to emit `.mli` files.
- A non-OCaml build of `hxhx` (e.g. a hypothetical Haxe→Rust compiler build) would not emit OCaml modules at all,
  so `.mli` inference is irrelevant in that scenario.

If/when we add additional “curated interface” modes, that work is about **OCaml user ergonomics** (stable interfaces
and nicer editor/diagnostics), not about making the compiler core more or less portable.

## Not to be confused with “native shim” interfaces

This document is specifically about generating `.mli` files for **emitted user projects**.

`hxhx` also has a separate concept of “native shims” (small `std/runtime/*.ml` helpers behind Haxe `extern` APIs).
For those, we treat the **Haxe extern** as the interface/IDL and keep the shim replaceable per target; OCaml inference
is at most a sanity check for the OCaml implementation.

See:

- `docs/02-user-guide/HXHX_STAGE4_MACROS_AND_PLUGIN_ABI.md:1` (ABI strategy for native shims)

## How to enable

Pass:

```bash
-D ocaml_mli
```

or explicitly:

```bash
-D ocaml_mli=infer
```

To infer interfaces for **all emitted modules** (not just the modules dune compiled for the
requested build target), use:

```bash
-D ocaml_mli=all
```

Notes:

- This requires an OCaml toolchain on `PATH` (`dune`, `ocamlc`, and `ocamlfind`).
- The generated `.mli` is **inferred**, not hand-curated. Expect it to be verbose and
  not particularly stable across backend changes.
- `.mli` generation implies a dune build (because inference needs typechecking).
  If you want a non-fatal best-effort mode (e.g. for CI where OCaml might be missing),
  add `-D ocaml_mli_best_effort`.

## What gets an `.mli` today

For robustness and speed, `ocaml_mli=infer` infers `.mli` only for modules that dune actually
compiled for the requested build target (i.e. modules that have a corresponding `*.cmi` in
`_build/`).

This avoids needing a “compile every emitted module” pass (which would be much slower),
and it also avoids failures when an emitted-but-unused module references other modules
that dune never had to compile for the chosen target.

`ocaml_mli=all` opts into that slower “compile everything” pass by asking dune to build
`*.cmi` for every emitted non-runtime module before running `ocamlc -i`.
