# Stage3 `.length` on typed String and Array receivers

`Main.hx` reads `.length` from strings and arrays that come from different
places: an instance field (`box.text`), a static field (`Main.title`), an
index into an array (`parts[0]`, `grid[1]`), a chained split and index
(`text.split(";")[1].split("=")[1]`), a call that returns `Null<String>` or
`Null<Array<Int>>` (`maybe(true)`), and a string returned by an instance call
(`s.substr(1)`).

Before the fix, Stage3 printed `null` for most of these. It picks the native
`HxString.length` or `HxBootArray.length` read only when it knows the receiver
is a String or an Array. It did not read the typed type of a field, an index,
or a nullable call result, so it used a dynamic field lookup that finds
nothing on a native string or array.

The fixture also reads `.length` from a null `String`, a null `Array`, and a
null `String` field inside `try`/`catch`. Upstream Haxe throws a catchable
error there. The native program now raises the runtime's `Null Access`
exception, so the same `catch` runs instead of the process crashing.

`npm run test:m14:stage3-member-length` checks that upstream Haxe 4.3.7
prints `expected.stdout`. It then builds the program with Stage3 and requires
the native executable to print the same text.
