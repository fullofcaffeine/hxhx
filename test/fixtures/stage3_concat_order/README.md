# Stage3 String concatenation order and numeric `+` in printed expressions

`Main.hx` concatenates the results of calls that print a marker such as
`[a]` when they run, so the output shows the order in which the operands
were evaluated. It also prints numeric `+` expressions directly
(`Sys.println(ratio + 0.25)`) and inside concatenations (`whole + 3 + "x"`).

Before the fix:

- `" calls " + step("a") + step("b") + step("c")` printed `[c][b][a]`.
  Stage3 renders String `+` as OCaml's `^`, and OCaml evaluates the
  arguments of `^` right to left. Haxe evaluates them left to right.
- `Sys.println(ratio + 0.25)` printed `0.50.25`, and `whole + 3 + "x"`
  printed `23x`. The path that renders printed expressions treated every `+`
  as concatenation instead of reading the typed result.

`npm run test:m14:stage3-concat-order` checks that upstream Haxe 4.3.7
prints `expected.stdout`. It then builds the program with Stage3 and
requires the native executable to print the same text.
