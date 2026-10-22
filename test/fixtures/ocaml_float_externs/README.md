# Float values in native extern calls

Run `haxe test/m14_ocaml_native_externs_test.hxml`.

The observer calls real OCaml identity exports through typed Haxe externs.
It checks direct and saved calls, producer effects, and Float array identity
and mutation. Existing bit-conversion helpers provide zero, negative zero,
1.25, infinities, and a quiet NaN. The observer checks their known input patterns
before checking that native identity calls preserve them.

Upstream Haxe uses ordinary identity methods and its own FPHelper. Both routes
must match the fixed expected output. This tests native Float transport; it
does not establish complete FPHelper, formatting, or numeric parity.
No handwritten native implementation is added for this test.
