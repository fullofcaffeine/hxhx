# {{PROJECT_NAME}}

This starter is a Haxe library that also emits a library-only native Dune
project through `reflaxe.ocaml`.

Check the required tools and build the library:

```bash
haxelib run reflaxe.ocaml doctor --require native
haxelib run reflaxe.ocaml build
```

For the edit loop:

```bash
haxelib run reflaxe.ocaml watch
```

The generated Dune project lives in `out/` and builds as a library, not an
executable. `haxelib.json` describes the Haxe-facing package. Select and document
your project license before publishing it.

Important: inferred `.mli` files in the current target are inspection aids, not
a curated stable OCaml export ABI. Keep the generated OCaml library private to
your build until the explicit export-ABI workflow is available.
