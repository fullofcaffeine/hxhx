# {{PROJECT_NAME}}

This application is written in Haxe and compiled to a native OCaml executable
with `reflaxe.ocaml`.

Check the required tools:

```bash
haxelib run reflaxe.ocaml doctor --require native
```

Build and run:

```bash
haxelib run reflaxe.ocaml build --run out/_build/default/out.exe
```

Rebuild and run after each stable source edit:

```bash
haxelib run reflaxe.ocaml watch --run out/_build/default/out.exe
```

Inspect the active profile, runtime selection, and typed place operations:

```bash
haxelib run reflaxe.ocaml inspect --require-lowering
```

The watcher starts a fresh Haxe process for each edit batch. Reflaxe leaves
unchanged generated OCaml files untouched, so Dune can reuse its native build
cache safely.
