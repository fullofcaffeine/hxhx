# Native enum constants

`Type.allEnums` returns constructors without arguments in declaration order.
This fixture mixes constants with payload constructors so native tag order cannot hide incorrect Haxe indexes.

Run `haxe test/m14_stage3_all_enums_test.hxml` from the repository root with the repository Haxe toolchain.
The test compares a fixed expectation with upstream Haxe and the compiled native executable.
It checks repeated queries, fresh arrays, singleton equality, separate enum names, enums without constants, and one-time descriptor evaluation.

The runtime observer in `test/nominal_carrier_runtime/Observer.ml` also checks physical box identity.
These checks cover runtime enum descriptors; they do not establish full reflection or provider readiness.
