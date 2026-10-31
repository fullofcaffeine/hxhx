# Stage3 String methods on typed receivers

`Main.hx` calls every instance method of the standard `String` class
(`toUpperCase`, `toLowerCase`, `toString`, `charAt`, `charCodeAt`, `indexOf`,
`lastIndexOf`, `split`, `substr`, `substring`) on strings that come from
different places: a local, an instance field (`box.text`), a static field
(`Main.title`), an index into an array (`parts[1]`), a static call result
(`make()`), an instance call result (`box.get()`), a chained split and index,
a type check (`(value : String)`), an unchecked cast (`(cast value : String)`),
a `Null<String>` local, and a function parameter.

Before the fix, the native program printed `0` for every `toUpperCase`,
`toLowerCase`, and `toString` call. `String` is an `extern` class, so its
methods have no Haxe body. Stage3 still writes a `String` OCaml module, and
each method there is an empty stub that returns `0`. The emitter routed the
other String methods to the `HxString` runtime, but these three bound to the
stub. A hint-free `(cast value : String)` also kept its `Dynamic` OCaml value,
so a String method on it did not compile.

`npm run test:m14:stage3-string-methods` checks that upstream Haxe 4.3.7
prints `expected.stdout`. It then builds the program with Stage3 and requires
the native executable to print the same text. It also checks that every
instance method of the emitted `String` declaration has a native adapter.
