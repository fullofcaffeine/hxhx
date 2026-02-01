# ExtLib interop example: `PMap`

This example demonstrates **extern interop** with an external OCaml library (`extlib`), via:

- `ocaml.extlib.PMap` (Haxe typed surface)
- dune dependency injection via `-D ocaml_dune_libraries=...`

It is marked `ACCEPTANCE_ONLY` because it depends on a host-installed OCaml library.

## Prerequisites (macOS / Homebrew + opam)

```bash
brew install ocaml dune ocaml-findlib opam
opam init -y
eval "$(opam env)"
opam install -y extlib
```

## Run

From the repo root:

```bash
RUN_ACCEPTANCE_EXAMPLES=1 npm run test:examples
```

