# Generic type-parameter equality

Generic functions compare two values of the same type parameter with `==` and `!=`. Callers use Float, String, Int, Bool, `Null<Int>`, class, and anonymous-record values.

Native output must match upstream Haxe eval. Numbers and equal strings in separate allocations compare by value. A null compares equal only to null. Class instances and records compare by identity, not by their contents.

Run `PORTABLE_FIXTURE_ALLOWLIST=generic_type_parameter_equality bash scripts/test-portable.sh` from the repository root.
