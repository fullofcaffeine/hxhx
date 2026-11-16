# Stage3 Int values in Float destinations

Haxe promotes an `Int` value to `Float` when the value enters a `Float`
destination. `Main.hx` checks that the native Stage3 program does the same and
prints what upstream Haxe 4.3.7 prints. It covers:

- a generic interface instantiated with Float: `floats.put(2)` where
  `floats:Box<Float>`, and an Int result passed to it;
- a generic class instantiated with Float: the constructor argument, a method
  argument, an Int expression argument, and a write to a field of type `T`;
- a generic method whose type parameter is inferred as Float;
- Int results read where Float is expected: a Float local, a Float local
  assignment, a Float argument, and a Float return;
- a `Null<Float>` type argument, including null;
- `Array<Float>` writes from Int values: an array literal, an index write,
  `push`, and `insert`;
- Float field writes and Float returns whose value is an Int array read, an
  Int field read, or a negated Int call, and a field write by its bare name
  inside the class (`f = values.length`);
- a `Null<Int>` value (`Std.parseInt("7")`) stored in a Float local;
- `Cell<Int>` and `Cell<Dynamic>`, which must keep the Int value.

Before the fix, Stage3 promoted only Int literals and Int locals, and only
when the parameter was written as `Float`. A parameter written as `T` received
the OCaml int `2`, and code that reads a boxed float then read memory at
address 2: the program crashed with SIGSEGV (exit 139). `var f:Float =
ints.get()` kept an OCaml int in a float binding, so the program also crashed,
or `ocamlopt` rejected it with "This expression has type int but an expression
was expected of type float".

Now the emitter asks the checked types at each boundary. When the value is an
`Int` and the destination is a `Float`, it wraps the value in `float_of_int`.

The fixture prints every Float with a fractional part (for example `2.25`), so
its output does not depend on how whole-number Floats are formatted; that gap
has its own task. It also avoids arithmetic directly on a field of type `T`
(`cell.value / 8`), which has a separate typing gap.

`npm run test:m14:stage3-float-type-arguments` checks that upstream Haxe prints
`expected.stdout`, builds the program with Stage3, and requires the native
executable to print the same text. It also checks the generated OCaml:
`floats.put(2)` passes `float_of_int 2`, and the `Cell<Int>` calls pass the
plain Int.
