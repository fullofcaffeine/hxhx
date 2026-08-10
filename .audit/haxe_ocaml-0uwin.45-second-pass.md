# Second-pass review: Boolean call-argument runtime ownership

## Outcome reviewed

A Haxe `Bool` passed to a `Dynamic` call parameter now receives one private
`HxRuntime.box_bool` permission tied to that exact call and argument slot. The
runtime helper is still needed for correct behavior: OCaml represents `Bool`
and `Int` similarly at the generic object boundary, while Haxe `Dynamic` must
keep them distinguishable.

## Architecture checks

- The ordinary call decision remains the semantic owner. A companion runtime-use
  plan is derived from its call ID, argument index, source span, profile, and
  function/body/pipeline revisions. No type-wide or builder-wide permission was
  introduced.
- The companion plan is derived data, so the public call-report schema did not
  need a new migration. Its detached copies are revalidated against the exact
  call before requirements or syntax can consume them.
- Syntax receives a checked target identifier. It reconciles only that helper
  identifier because the argument expression can contain runtime work owned by
  other plans. The request-wide final-output authority still verifies that the
  checked identifier reaches generated output exactly once.
- The function-value path previously rejected the same Bool-to-Dynamic crossing
  that its later call-value planner already supported. The admission check now
  agrees with the existing closed conversion matrix; it does not add a new
  conversion family.
- Runtime selection remains explicit-full and overall authority remains partial.
  The legacy inventory moved from 388 to 387 entries, exactly one call-argument
  constructor.

## Adversarial checks

The focused model fixture rejects a missing or duplicated occurrence, stale
plan revision, wrong call, wrong argument slot, wrong owner, wrong symbol,
wrong profile, and a plain private helper reference. An identity-only call owns
no companion permission.

The vertical fixture covers two direct static calls and one computed function
value. It also covers an omitted trailing optional argument and makes every
Boolean argument evaluation visible. The installed Haxe 4.3.7 interpreter is
the independent behavior oracle; the generated OCaml builds with Dune and the
native executable matches its output.

## Findings and disposition

1. The first tracer used an optional `Dynamic` parameter and exposed a separate
   representation bug: a supplied `true` arrived as an unsupported value. That
   problem is outside runtime-use authorization and is tracked by
   `haxe_ocaml-0uwin.46`.
2. The generated report does not expose companion runtime-use occurrences.
   That is intentional for this bounded slice: the stable runtime-requirement
   report records each exact call/slot dependency, focused corruption tests
   prove the companion data, and the final structured-output authority verifies
   cardinality. A public report-schema change would add migration cost without
   improving the current correctness boundary.
3. No Oracle review was needed. The existing call plan, runtime requirement
   ledger, and final-output authority provided a bounded reusable seam, and the
   focused plus vertical tests converged without an unresolved architecture
   choice.

## Closure judgment

The change is bounded to the selected call-argument family, fails closed before
printing, preserves source evaluation order, and does not broaden readiness.
The `thinking:xhigh` level was appropriate because an overly broad runtime
permission could have produced believable but incorrect generated code.
