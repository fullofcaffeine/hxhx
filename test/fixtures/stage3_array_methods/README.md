# Stage3 bodiless Array methods

`Main.hx` calls each standard Array method that has no Haxe body, on String
and Int arrays. Each line prints the method's return value and the array
afterwards.

Stage3 emits an OCaml `Array` module from the standard `Array` class, and
these methods are empty stubs in that module. A call that bound to a stub
compiled, then left the array unchanged and returned a placeholder, so the
native output differed from `expected.stdout` on every line.

`npm run test:m14:stage3-array-methods` checks that upstream Haxe prints
`expected.stdout`. It then builds the program with Stage3 and requires the
native executable to print the same text.
