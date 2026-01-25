# Snapshot tests

Snapshot tests validate **generated OCaml output** stays stable and idiomatic.

Structure:

```
test/snapshot/<category>/<case>/
  compile.hxml         # compiles Main.hx to OCaml (emit-only)
  *.hx                 # small fixture program(s)
  out/                 # last generated output (committed)
  intended/            # golden output (committed)
```

## Commands

- Run snapshots: `npm run test:snapshot`
- Update golden output after an intentional change:
  1. Run snapshots once to regenerate `out/`
  2. Copy `out/` → `intended/`: `bash scripts/update-snapshots-intended.sh`

## Conventions

- Snapshot tests should compile with `-D ocaml_no_build` so we only snapshot emitted sources,
  not dune build artifacts.
- Keep fixtures minimal and focused: one language feature per case where possible.

