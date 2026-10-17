This fixture calls existing OCaml exports through Haxe extern declarations.
For example, `HostString.count("abc")` selects `HxString.length` and returns `3`.
The same binding works through a type alias, a saved function, and a field initializer.

Run `npm run test:m14:ocaml-native-externs` from the repository root.
The test compares native execution with the independent Haxe operations in
`Oracle.hx`. Both must match `expected.stdout`, including argument effects in order.
It also tests declaration ownership, metadata revisions, rejection before output,
and an intentionally incorrect host signature that OCaml must reject.

This contract covers fixed static functions with Int, Bool, String, arrays of
those values, and Void results. The OCaml export must implement that exact signature.
Optional arguments, generics, Dynamic, callbacks, Float, native object instances,
and production standard-library provider selection have separate contracts.
