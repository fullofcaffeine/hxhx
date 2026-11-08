# A local function in a case body that Haxe emits twice

Haxe compiles a `switch` into a decision tree. When a guarded case such as
`case EBinop(op, EThis, value) if (allowThis)` comes before a broader case
such as `case EBinop(op, left, right)`, the broader body is reachable on two
paths: when the guard fails and when the pattern does not match. Haxe emits
that body once per path. Each copy gets fresh locals, so each copy declares its
own `wrap` function, but both calls to `wrap(...)` keep the same source span.

The OCaml call planner used to identify such a call by its function body,
source span, and callee form only. Both copies got the same call identity with
two different plans, one per `wrap` local, and the build stopped with
`[ocaml-call:conflicting-source-occurrence]`. The `hxhx` compiler build hit
this in `EmitterStage.exprToOcamlRaw`, where a guarded `this` assignment case
precedes the general binary-operator case that declares `intArithmetic`.

The planner now includes the stable identity of the called local in the call
identity, and the syntax builder uses that identity to select the plan for
each copy.

This fixture checks that:

- the native program prints the same output as upstream Haxe and the expected output;
- the lowering report keeps two plans for the one source call, with distinct
  call and callee identities.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=duplicated_case_local_function bash scripts/test-portable.sh
```

This regression does not change README Goals status.
