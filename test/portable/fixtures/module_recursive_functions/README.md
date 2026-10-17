Two Haxe classes call each other across compilation units. The generated OCaml program must print `3`, `4`, and `ready` through their original module paths.
The target stores the recursive group in the first module file and keeps the other file as an alias.
The entry module also declares and matches an enum. Its declaration must remain structured when the compiler assembles recursive modules elsewhere in the program.

Run `PORTABLE_FIXTURE_ALLOWLIST=module_recursive_functions npm run test:portable`.
The runner builds and executes the OCaml program. Then `test.sh` verifies that an eager initializer and a cycle without a function-only module fail before OCaml module publication.

One module exports literal Int, Bool, and String constants; its partner exports only functions.
OCaml can initialize this group because every cycle passes through that function-only partner.
If both modules export constants, their cycle is rejected. A safe member elsewhere in a larger group is insufficient: every cycle needs one.
Calls, mutable static initialization, and opaque declarations remain unsupported.
Two further classes refer to each other only through record fields. Their constants
remain available, and runtime field assignments preserve both object identities.
Type references keep declarations in one recursive group without imposing runtime
initialization order. This pair prints `left:right`.
The fixture provides focused evidence and does not change the README Goals percentages.
