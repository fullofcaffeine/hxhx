# Arrays in native enum payloads

An ordinary enum must retain the same typed array object that its caller supplied.
The fixture checks shared mutation, distinct equal-content arrays, nested objects,
Boolean and numeric storage, argument order, and omitted, null, and present payloads.
Transparent whole-array, element, applied, and nullable aliases preserve that contract.
An explicitly heterogeneous `Array<Dynamic>` checks that Bool and Int keep their
existing runtime values without converting a differently typed input array.

Run `npm run test:m14:stage3-enum-patterns` from the repository root.
The focused array test loads ordinary Haxe source through the frontend and authored
emitter, compiles native OCaml, and compares its output with `expected.stdout`.
Upstream Haxe 4.3.7 independently checks the same expected output.
The test also rejects missing, copied, and differently typed constructor operand facts.

This change supports exact element storage types, including transparent aliases.
It does not add different-element conversions, generic enum declarations, or macro dispatch.
The focused test emits the fixture module rather than rebuilding the compiler or its SDK closure.
Generated OCaml remains an artifact; the test does not modify it.
