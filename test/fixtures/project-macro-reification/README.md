# Project macro with reification

`Main.hx` calls `Macros.tally(["alpha", "beta"])`, an expression macro whose body builds its
result with `macro { ... }` and the splices `$b{}`, `$v{}`, `$e{}`, `$a{}`, a field splice
(`seen.$field`), and `@:pos`. The macro calls no `haxe.macro.Context` API.

Files:

- `oracle.hxml` runs the program with upstream Haxe 4.3.7; `expected.stdout` is its output.
- `probe-oracle.hxml` runs `Probe.main()` in upstream's macro context; it prints the structure
  of the expression `Macros.build` returns, as `probe-expected.stdout`.
- `Shadowing.hx` quotes where locals, parameters, and static fields are named `haxe`, `Std`, and
  `hxhxmacrohost`; `Probe` prints those results too, so a user name that captured the lowered
  syntax would change the probe output.

Checks:

- `npm run test:m14:project-macro-reification` (interpreter): builds the macro plugin through
  hxhx's plugin cache driver (child compiler run by the interpreter, `dune` build), then compiles
  `Probe` natively with the Stage3 emitter and compares its output with `probe-expected.stdout`.
- `npm run test:macro-runtime:project-module` (needs a source-built hxhx): compiles `Main`
  end to end, running the macro from the loaded plugin, and compares with `expected.stdout`.
