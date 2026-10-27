This fixture checks exact static-function and constructor signatures retained by the OCaml compiler.
The generated constructors must return their selected instance record type.
The macro also checks function-only module eligibility and dependency order before relying on recursive module emission.

Run `PORTABLE_FIXTURE_ALLOWLIST=module_function_signature npm run test:portable`.
The runner compiles the Haxe source, builds the OCaml program, and checks its output against `expected.stdout`.
The constructor assertion checks that two integer arguments reach the returned instance.
An array constructor parameter also has a checked signature. Its unused interface
metadata must not activate extra runtime references in this non-recursive module.
A constructor with an Int-to-Int callback retains that checked function signature
and passes recursive-module eligibility. Its runtime assertion checks the callback result.
Unsupported callback representations remain covered by `module_callback_signature`.

Standard `haxe.Int32` parameters and results retain their existing OCaml `int`
carrier, including a transparent typedef alias. The fixture checks the exact
internal Int64 constructor's `high` and `low` parameter types. It also checks an
ordinary Int32 constructor and a returned alias through generated OCaml and runtime.
The signature selector must reject a same-spelled user abstract, nullable Int32,
a nonempty Int32 type application, and a conflicting target carrier.
These checks do not grant optimized core Int call or storage permissions.
They do not prove Int64 mutation or alias/copy behavior.

This fixture does not emit recursive modules or prove safe initialization for arbitrary modules.
It does not change the README Goals percentages.
