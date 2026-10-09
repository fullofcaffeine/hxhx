# Generated entrypoint calls

A generated dispatcher can call a Void function without knowing its return type.
The fixture stores that result as Dynamic in both a method and a static field.
Each call must execute once and produce Haxe null. The static call runs before
`main`; both values remain null when observed later.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=generated_entrypoint_call_plan npm run test:portable
```

The runner compiles and executes the native output against `expected.stdout`.
The fixture script compares the same source under upstream Haxe/eval. It also
checks that the two calls have distinct method and initializer owners, with the
required null runtime support.

The initializer used to be a negative test because it had no call plan. That
expectation became obsolete when field initializers gained their own plans.
Genuine missing and stale plans remain covered by `StandaloneCallPlanChecks`.
`CallPlanFixture` also rejects corrupted Void-result rules and missing callee
boundaries, including rejection before a sentinel output file is written.
Run those contracts with `npm run test:reflaxe-ocaml:call-plan`.

This fixture does not establish complete macro-host promotion or change README
Goals percentages.
