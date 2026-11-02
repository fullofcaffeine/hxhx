# Stage3 locals named `_`

In Haxe, `_` is an ordinary local name, and it can be read:

```haxe
try throw "read" catch (_:String) Sys.println("caught value: " + _);
```

Upstream Haxe 4.3.7 prints `caught value: read`. In OCaml, `_` is a wildcard
pattern that cannot be read, so Stage3 refused to emit every such binding
with `cannot render exact binding ... :_`. That stopped native builds of
programs using `catch (_:String)`, `for (_ in 0...3)`, `(_) -> 1`,
`function(_:Int)`, a method parameter named `_`, or `var _`.

`Main.hx` uses `_` in each of those positions, including two `_` parameters
in one lambda, nested `_` loops, `_` in two catches of one try, and a pattern
wildcard `case [_, second]` (which was already supported).

`npm run test:m14:stage3-underscore-bindings` checks that upstream Haxe prints
`expected.stdout`, then builds the program with Stage3 and requires the
native executable to print the same text.
