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

This fixture does not emit recursive modules or prove safe initialization for arbitrary modules.
It does not change the README Goals percentages.
