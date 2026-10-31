# Stage3 interface calls

`Main.hx` calls methods through interface-typed values and compares the native
Stage3 program with upstream Haxe 4.3.7. It covers:

- receivers held in a local, a static field, instance fields, array elements,
  a parameter, and `this` passed to a function that takes the interface;
- a generic interface (`Box<T>`) implemented with `Int` and `Float`, and a
  generic class implementing an interface that extends it (`Store<T>`);
- a method inherited from a parent interface (`Greeter extends Named`);
- a class that implements an interface only through a superclass method,
  subclasses that do and do not override the implementation, and a packaged
  interface (`shapes.Shape`) whose runtime class name includes its package;
- interface method values (`final read = p.name`);
- String, Int, Float, and Bool results and arguments, including a String
  method called on an interface result;
- `StringBuf.toString` on a local, an instance field, and a call result.

Before the fix, the interface module held an empty stub for each method that
returned the placeholder `0`. `p.name()` printed `raw 0`, and
`p.name().toUpperCase()` crashed with SIGSEGV (exit 139). `g.name()` on a
`Greeter` value was not resolved to `Named.name` at all, so typing this fixture
stopped with `selected call conversion does not satisfy its retained parameter:
unknown -> dynamic`.

Now each generated class registers its interface method table with the
`HxMethodDispatch` runtime, and each interface method looks up the receiver's
class and calls the implementing function.

The fixture avoids shapes that fail for reasons unrelated to interfaces, so
that a failure here points at interface dispatch: Float values are printed
with `Std.string`, implementations do not call `super.method()`, static
fields are not reassigned, and `Array<Named>` is built with `push` instead of
an array literal. Those gaps have their own Beads.

`npm run test:m14:stage3-interface-calls` checks that upstream Haxe prints
`expected.stdout`, builds the program with Stage3, and requires the native
executable to print the same text. It also checks that every interface module
of the fixture holds dispatchers rather than stubs, that interface calls with
an optional argument or a `dynamic` implementation fail at emit time with a
named error, and that an `IMap` call on an extern `StringMap` stops with a
named runtime error.
