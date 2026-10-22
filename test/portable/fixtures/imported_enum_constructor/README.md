# Imported enum constructor names

`Type.enumConstructor` must return the Haxe constructor name for an enum declared
in another module. This fixture checks a constant constructor and a constructor
with two payload fields. The generated OCaml must compile with the owning module
on each pattern, while the returned strings remain `Empty` and `Pair`.
It also checks a same-module enum and a producer counter. The counter proves
that reflection evaluates its argument once. Null-input parity is a separate
known gap; this fixture covers valid enum values.

Run `PORTABLE_FIXTURE_ALLOWLIST=imported_enum_constructor npm run test:portable`.
The runner builds and executes native output. `test.sh` compares the independent
expected output with upstream Haxe eval.
