Two Haxe classes call each other across compilation units. The generated OCaml program must print `3` and `4` through their original module paths.
The target stores the recursive group in the first module file and keeps the other file as an alias.

Run `PORTABLE_FIXTURE_ALLOWLIST=module_recursive_functions npm run test:portable`.
The runner builds and executes the OCaml program. Then `test.sh` verifies that an eager initializer in a recursive group fails before OCaml module publication.

This covers function-only recursion. Static initialization, opaque declarations, and signatures requiring new private runtime type identities remain unsupported.
The fixture provides focused evidence and does not change the README Goals percentages.
