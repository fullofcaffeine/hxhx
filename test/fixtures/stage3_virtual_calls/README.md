# Stage3 overridden methods and super calls

`Main.hx` calls overridden methods through values typed as a superclass and
compares the native Stage3 program with upstream Haxe 4.3.7. It covers:

- a four-level chain, `Person` -> `Teacher` -> `Assistant` -> `Professor`, where
  `Assistant` overrides nothing, and a `final` class `Visitor` that overrides
  nothing;
- receivers held in locals, a static field, an instance field, parameters,
  array elements, and `this` (`Person.describe` calls `name()`);
- method values (`final read = local.name`) and a call through an interface
  (`Ranked`) that a superclass implements;
- String, Int, Float, Bool, and Void results, optional arguments whose
  default value differs between the class and its override, and a method with
  its own type parameter;
- `super.method()` with and without arguments, in value and statement
  position, to the direct parent, to an ancestor reached through a class that
  does not override (`Professor` -> `Teacher` through `Assistant`), and to a
  method that no class overrides (`super.tag()`).

Before the fix, every call named the declaring class's function, so a value
typed `Person` that held a `Teacher` ran `Person`'s methods, and each
`super.name()` turned the whole expression around it into the placeholder
`(Obj.magic 0)`.

Now a method that a generated subclass overrides keeps its body in a direct
function (`name'direct`) and gets a dispatcher under its own name. The
dispatcher looks up the receiver's class in the `HxMethodDispatch` runtime.
`super` calls and calls whose static receiver type no override can reach
name the direct function.

The fixture avoids shapes that fail for reasons unrelated to dispatch: Float
results are not whole numbers (haxe_ocaml-iffj5), static fields are not
reassigned, and `Array<Person>` is built with `push`.

`npm run test:m14:stage3-virtual-calls` checks that upstream Haxe prints
`expected.stdout`, builds the program with Stage3, and requires the native
executable to print the same text. It also checks which calls in the generated
modules dispatch and which stay direct, that overridden `dynamic` and rest
methods and a `super` method value fail at emit time with a named error, and
that a `dynamic` override called on its most derived class still compiles.
