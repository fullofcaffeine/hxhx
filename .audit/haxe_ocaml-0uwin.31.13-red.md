# Expected-red records: Array insertion and membership

## Missing typed-call operation

Command:

```text
npm run test:reflaxe-ocaml:call-plan
```

The focused fixture failed because `OcamlStandardArrayOperation` had no
`Insert` field. This was the intended first red state: the test named the
missing compiler-owned operation before the implementation existed.

## Object identity regression discovered by the vertical tracer

Command:

```text
npm run test:m6:array
```

The installed Haxe 4.3.7 oracle accepted the case, but the generated OCaml
executable threw `contains_object_identity`. Two different class instances had
the same field values; OCaml structural equality incorrectly treated them as
the same Array member.

The focused runtime owner was already available as
`HxRuntime.dynamic_equals`. Routing Array search/removal comparisons through
that helper made the same cross-compiler regression green without changing the
typed-call planner's authority.
