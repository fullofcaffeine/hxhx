# A nullable Bool call in a case body that Haxe emits twice

This fixture extends `duplicated_case_local_function`. A guarded `switch` case
makes Haxe emit the next case body twice, and each copy declares its own local
function `check(v:Int):Null<Bool>`. The body stores `check(op.length)` into a
`Null<Bool>` local.

While the OCaml syntax for that store is built, the builder asks the call plan
whether this exact call produces the nullable Bool carrier. That question
looks the call up by its source span. Both copies share the span, so the lookup
must also use the identity of the called local. Before the fix, this lookup
did not, and the build stopped with
`[ocaml-call:ambiguous-source-occurrence]: 2 sealed calls match one typed occurrence`.

The call plan now owns the local identities of its function body, so every
lookup, including these carrier questions, selects the plan of its own copy.

The fixture checks that the native program prints the same output as upstream
Haxe and the expected output, and that the lowering report keeps two plans
for the one source call.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=duplicated_case_nullable_bool_call bash scripts/test-portable.sh
```

This regression does not change README Goals status.
