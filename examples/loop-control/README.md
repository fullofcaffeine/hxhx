# loop-control

Exercises `break` / `continue` lowering inside `while` loops (including nested loops).

This example is intended to catch regressions that would otherwise manifest as infinite loops
when Haxe lowers higher-level looping constructs to `while (true) { ... break; }`.

