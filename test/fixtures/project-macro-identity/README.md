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

The hxhx check is `npm run test:macro-runtime:project-module`
(`scripts/hxhx/run-project-macro-module-smoke.sh`). It:

1. builds a plugin from `Identity.hx` with hxhx's own Stage3 OCaml emitter
   (`-main hxhxmacrohost.MacroDeclarationPlugin -D ocaml_plugin_macro_declarations=Identity.preserve`),
2. writes and validates a receipt for that plugin,
3. compiles `Main.hx` in-process with the plugin loaded, runs the native program, and compares
   its output with `expected.stdout`,
4. checks that `WrongSignature.hx` fails at the macro call with the macro's own message, that a
   compile without a plugin reports the call as unexecuted, that the external macro host loads
   the plugin but reports the declaration as unexecuted, and that changed receipts are rejected.

The macro calls no `haxe.macro.Context` API. Positions it receives are zero-width starts of the
syntax that owns one (see `docs/00-project/EXPRESSION_MACRO_ARGUMENT_PLAN.md`).
