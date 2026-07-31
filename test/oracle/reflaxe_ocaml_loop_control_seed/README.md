# Loop-control behavior oracle

This fixture records what upstream Haxe 4.3.7 does when `break` and `continue`
appear in nested `while` loops, `do ... while`, source `try/catch`, `Void` and
`Float` functions, and a nested function literal.

The practical contract is:

- each transfer affects the innermost loop in the same function;
- `continue` in `do ... while` still evaluates the loop condition;
- a source `catch` does not intercept compiler-private loop control;
- loop behavior does not depend on whether the function's return carrier is
  admitted by reflaxe.ocaml's separate early-return family; and
- a nested function owns its own loop stack.

Run `npm run test:reflaxe-ocaml:loop-control-oracle` to compare interpreter,
JavaScript, and Neko output with `expected.stdout`. The portable fixture uses
the same Haxe source so generated OCaml is checked against this behavior
without copying upstream compiler implementation.
