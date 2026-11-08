# Stage3 Array.concat

`Main.hx` calls `Array.concat` on the native OCaml route and prints each
result next to its operands.

In Haxe, `a.concat(b)` returns a new array that holds the elements of `a`
followed by the elements of `b`. Neither operand changes, and later changes to
the result or to an operand do not affect the other arrays.

Native Stage3 output once called the OCaml standard `Array.concat` with two
arguments. That OCaml function takes one list of arrays, so the generated
program did not compile. Stage3 now lowers the call to the shared
`HxArray.concat` runtime operation.

The fixture covers:

- the original reproducer, `[null].concat(args)` on `Array<Dynamic>`;
- aliasing: writes to the result and to each operand stay separate, also for
  `a.concat(a)`;
- empty left, right, and both operands;
- `Int`, `Float`, `String`, class-instance, `Null<Int>`, and nested array
  elements (nested arrays share their inner arrays, as upstream does);
- operand order: the receiver is evaluated before the argument.

`npm run test:m14:stage3-array-methods` checks that upstream Haxe prints
`expected.stdout`. It then builds the program with Stage3 and requires the
native executable to print the same text.
