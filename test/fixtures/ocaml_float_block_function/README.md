Run local functions that are declared to return `Float` and have a block body.

A block-bodied local function such as `function():Float { f += 1; return 0.25; }`
is written in native OCaml as a closure that leaves through a local exception.
The emitter picks the OCaml type of the returned value (the "result carrier")
from the function's typed `Float` result. Before this fixture existed, `Float`
had no carrier, and emission stopped with "OCaml block function requires a
supported concrete return carrier".

The fixture checks:

- a function expression that updates a captured outer `Float` local and returns
  a literal, and a local function declaration that assigns that local,
- results read from a local, computed from captured values, and chosen by
  several `return` statements,
- `Int` results (`return 1;`, `return count;`) widened to the declared `Float`
  result, in block and expression bodies.

Every printed value is a short binary fraction such as `3.375`. Whole-number
`Float` output (`4` in Haxe, `4.` natively) is a separate formatting bug.

Run `haxe test/m14_stage3_float_block_function_test.hxml` (or
`npm run test:m14:stage3-float-block-function`) to compare upstream Haxe with
the generated native OCaml executable.
