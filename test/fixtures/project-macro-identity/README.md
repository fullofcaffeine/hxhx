# Project identity macro

This fixture runs a real project expression macro through hxhx's native plugin path.

`src/Identity.hx` declares `Identity.preserve`, a macro that receives a function as authored
syntax, checks its written signature, nested brace group, explicit returns, and the statements
after the group, and then returns the argument unchanged. `src/Main.hx` calls it on a function
whose inner `return` must leave the whole function, so the program prints `ok` and an empty
event line (`expected.stdout`). Upstream Haxe 4.3.7 produces the same output:

```bash
cd test/fixtures/project-macro-identity && haxe oracle.hxml
```

A plain compile runs the macro; hxhx builds, caches, and loads its native plugin itself:

```bash
cd test/fixtures/project-macro-identity && hxhx --hxhx-stage3 -cp src -main Main
```

The hxhx check is `npm run test:macro-runtime:project-module`
(`scripts/hxhx/run-project-macro-module-smoke.sh`, which needs a native hxhx built from the
current sources). It checks that:

1. the first compile builds the plugin (`project_macro_plugin=built`), runs the macro, and the
   native program prints `expected.stdout`;
2. a second compile reuses the plugin (`project_macro_plugin=reused`);
3. `WrongSignature.hx` fails at the macro call with the macro's own message;
4. editing `Identity.hx` rebuilds the plugin;
5. without `dune` and `ocamlopt`, and in the external-host mode, the call fails with one clear
   reason;
6. a changed receipt (compiler identity, ABI version, declaration, artifact digest) is rejected
   and the plugin is rebuilt;
7. the plain command above, with the default cache directory, runs the macro.

The focused interpreter checks are `npm run test:m14:project-macro-plugin-cache` and
`npm run test:m14:macro-compilation-context`.

The macro calls no `haxe.macro.Context` API. Positions it receives are zero-width starts of the
syntax that owns one (see `docs/00-project/EXPRESSION_MACRO_ARGUMENT_PLAN.md`).
