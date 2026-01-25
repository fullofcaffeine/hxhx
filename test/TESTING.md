# Testing strategy

This repo follows the same broad layering used in `haxe.elixir.codex`:

1. **Unit-ish tests (printer / lowering invariants)**  
   Fast checks that validate we print / lower OCaml syntax correctly (no runtime required).

2. **Milestone integration tests (compile + inspect + optional build)**  
   `test/M*IntegrationTest.hx` runs via `--interp`, invokes `haxe` to compile fixtures to OCaml, inspects emitted `.ml`,
   and (when `dune` + `ocamlc` are available) builds + runs the produced executable.

3. **Example apps (acceptance / QA)**  
   Real-ish programs under `examples/` that are compiled to OCaml, built via `dune`, and executed with expected stdout.

## Commands

- Full suite: `npm test`
- Example apps only: `npm run test:examples`
- Snapshots only: `npm run test:snapshot`

## Why examples?

Snapshot tests are great for *stability*, but examples are great for *truth*:

- They validate end-to-end behavior (codegen + runtime + dune wiring).
- They act as living documentation for users.
- They become the place we steadily grow “Haxe-in-Haxe enough” workloads.

## Snapshot tests

Snapshot tests live under `test/snapshot/` and follow the same “out vs intended” pattern used in `haxe.elixir.codex`:

- `out/`: last generated output (committed)
- `intended/`: golden output (committed)

Update golden outputs after an intentional change:

- Run once to regenerate `out/`
- Copy `out/` → `intended/`: `bash scripts/update-snapshots-intended.sh`
