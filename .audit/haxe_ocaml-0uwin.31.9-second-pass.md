# Second-pass review: sealed return-signal raises

## Outcome

The change stays inside the two intended expression-construction sites. Each
planned early return now owns one exact permission to construct either
`HxRuntime.Hx_return` or `HxRuntime.Hx_return_void`. The existing catch patterns
and function-boundary recovery remain outside this slice and remain visible in
the migration inventory.

## Checks performed

- The root-function control planner deliberately stops at nested function
  expressions. Nested functions are sealed separately, so their return
  requirements are recorded once rather than being duplicated by the parent.
- Requirement and occurrence identities include the exact control-decision ID.
  The runtime-use authority also checks the function-plan revision, symbol,
  expression domain, active profile, and one-use limit.
- The local syntax check observes only the newly introduced signal node. It does
  not claim ownership of private helpers inside the return value. The final
  program-wide authority still observes the complete generated expression
  before output publication.
- The generated signal reference is hidden behind the checked runtime-use AST
  node. Plain private identifiers, missing uses, duplicate uses, stale plans,
  wrong owners, wrong symbols, wrong domains, and wrong profiles are rejected by
  the focused fixture.
- The remaining `Hx_return` and `Hx_return_void` references in `OcamlBuilder`
  belong to catch propagation and function-boundary recovery. They were not
  silently folded into this narrower authorization.
- No readiness wording or README goal moved. The inventory decreased by exactly
  two expression references, from 357 to 355.

## Finding and correction

The first vertical run revealed that local reconciliation walked the whole
return value and therefore rejected an independently owned `HxInt.add` helper.
The implementation was narrowed to reconcile a signal-only proof expression.
This preserves ownership separation: the return plan authorizes the signal,
while the existing final authority remains responsible for every private helper
in the completed output.

The review also replaced a reflection-based test mutation with a typed invalid
mechanism input. No remaining second-pass blocker was found.

## Deferred finding

The `early_return` executable built and produced the expected output, but its
fixture script still expects an `Eof` throw to be rejected. Nominal class
exceptions were authorized later, so this is stale test policy rather than a
return-signal failure. Bead `haxe_ocaml-m9vvm` owns that separate correction.
