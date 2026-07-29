# {{PROJECT_NAME}}

This application is written in Haxe and compiled to a native OCaml executable
with `reflaxe.ocaml`.

Check the required tools:

```bash
haxelib run reflaxe.ocaml doctor --require native
```

Build and run:

```bash
haxelib run reflaxe.ocaml build --run .out.reflaxe-ocaml-dune-build/default/out.exe
```

Rebuild and run after each stable source edit:

```bash
haxelib run reflaxe.ocaml watch --run .out.reflaxe-ocaml-dune-build/default/out.exe
```

Inspect the active profile, runtime selection, and typed place operations:

```bash
haxelib run reflaxe.ocaml inspect --require-lowering
```

The watcher starts a fresh Haxe process for each edit batch. Reflaxe publishes
the complete generated `out/` tree only after source generation succeeds.
Dune then builds that public tree and keeps reusable native state in
`.out.reflaxe-ocaml-dune-build/`, so replacing generated source does not make
every native build cold.

Build output separates total Haxe-child time from the target-owned Dune phase.
Dune typechecking, compilation, and linking are one measured phase; cache hits,
program loading, startup, and workload runtime are not guessed.
