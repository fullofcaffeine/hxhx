# Records in native enum payloads

An ordinary enum must retain the same anonymous object that its caller supplied.
This program checks mutation through both aliases, typed Int and Bool fields,
stored records with extra fields, argument and field initializer order, and
omitted, null, and present optional/nullable payloads.

Run `npm run test:m14:stage3-enum-patterns` from the repository root. The focused
record test uses the normal frontend and authored emitter, compiles native OCaml,
and compares upstream Haxe 4.3.7 and native output with `expected.stdout`.
It also rejects record calls missing their exact projected operand facts.

This contract does not admit Array payloads or establish project macro dispatch.
Generated OCaml remains an artifact; the test does not modify it.
