# Stage3 class type tests and downcasts

`Main.hx` asks whether a value belongs to a class or an interface, and narrows
a value to a subclass. It uses every standard spelling:

- `Std.isOfType(value, T)`, the deprecated `Std.is(value, T)`, and the
  operator `(value is T)` return a `Bool`.
- `Std.downcast(value, T)` and the deprecated `Std.instance(value, T)` return
  the same value when it belongs to `T`, and `null` otherwise.

The types are a class, its subclass, a two-level subclass, an interface, and
an interface that extends another one. Operands are typed as the class, a
superclass, an interface, `Dynamic`, and `Any`, and include `null`, numbers,
a string, a Bool, an anonymous object, and an array. Three operands come from
a function that logs its label, so the output also shows that every operand
runs exactly once.

Before the fix, the native program did not get this far. With a class name as
the type argument, `Std.is` and `Std.downcast` stopped the build with an
unrelated error ("first-class type values"). With any other type argument,
such as a `Dynamic` parameter, Stage3 replaced `Std.is(...)` with `true` and
`Std.downcast(...)` with `null` without evaluating the arguments, so every
type test passed and every downcast failed.

Now all five calls select the same runtime test that `Std.isOfType` already
used: the value must be a generated class instance, and its class or one of
its ancestors must be the requested class or implement the requested
interface. A type argument that Stage3 cannot test yet (a `Dynamic` value
holding a class, an enum, or the core types `Int`, `Float`, `Bool`, `String`
and `Dynamic`) stops the build with a named error.

The fixture reads a plain `label` field instead of the overridden `name()`
method, and prints Bools through `show`, so the output does not depend on
virtual dispatch or on Bool-to-String conversion, which are tracked
separately.

`npm run test:m14:ocaml-nominal-type-predicates` checks that upstream Haxe
4.3.7 prints `expected.stdout`. It then builds the program with Stage3 and
requires the native executable to print the same text. The same test checks
the named errors for unsupported type arguments.
