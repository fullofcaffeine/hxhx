Keep methods of one class in scope when they refer to each other.

The native OCaml emitter writes each method, or each group of methods that call
each other, as its own `let rec` binding. OCaml only sees a binding that is
defined earlier or in the same recursive group, so the emitter orders the
bindings by the references between them. The fixture checks references that
the ordering must count:

- a method captured as a value (`values.map(earlier)`) that is declared before
  the method that captures it, and one (`later`) that is declared after it.
  Inline lowering expands `Array.map` into a loop, so the capture is inside a
  generated declaration, not directly in the call,
- two instance methods that call each other (`isEven` and `isOdd`),
- a static method captured as a value (`values.map(shout)`) by an earlier
  static method.

Run `haxe test/m14_stage3_method_reference_order_test.hxml` (or
`npm run test:m14:stage3-method-reference-order`) to compare upstream Haxe with
the generated native OCaml executable.
