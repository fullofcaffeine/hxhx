This fixture checks exact static-function and constructor signatures retained by the OCaml compiler.
The generated constructors must return their selected instance record type.
The macro also checks function-only module eligibility and dependency order before relying on recursive module emission.

Run `PORTABLE_FIXTURE_ALLOWLIST=module_function_signature npm run test:portable`.
The runner compiles the Haxe source, builds the OCaml program, and checks its output against `expected.stdout`.
The constructor assertion checks that its argument reaches the returned instance.
A two-argument constructor remains without a checked signature and must fail recursive-module eligibility while preserving ordinary runtime behavior.

This fixture does not emit recursive modules or prove safe initialization for arbitrary modules.
It does not change the README Goals percentages.
