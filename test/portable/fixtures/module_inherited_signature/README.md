# Inherited objects in recursive modules

Pass a derived object through functions that accept and return its base class.
The two modules depend on each other, so OCaml requires explicit export types.
The same object must retain overridden methods, mutable state, and identity.
The fixture also observes a nullable base-class argument.
The classes call back into the module group, so their constructor bodies and
instance methods also require export signatures. A root class exercises a
zero-argument super-constructor; derived classes pass a constructor argument.

Run with `PORTABLE_FIXTURE_ALLOWLIST=module_inherited_signature bash scripts/test-portable.sh`.
Native execution and Haxe/eval must match the independent expected output.
