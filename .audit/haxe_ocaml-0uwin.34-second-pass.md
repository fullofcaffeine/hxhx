# Second-pass review: Bytes mutation runtime uses

Bead: `haxe_ocaml-0uwin.34`

Review date: 2026-08-09

Reason: `thinking:xhigh` changes require an independent second look before closure.

## Practical result

`haxe.io.Bytes.fill` and `haxe.io.Bytes.blit` can no longer introduce their
private OCaml helpers merely because syntax knows the helper names. The
completed compiler decision now lists each permitted helper call. Syntax must
consume that list exactly, in evaluation order, and the final structured OCaml
expression is checked before printing.

For a nullable fill value, the order is:

1. call `HxRuntime.nullable_int_unwrap` for the nullable argument;
2. call `HxBytes.fill` after receiver and arguments have been evaluated.

An absent helper, duplicate helper, wrong name, reversed order, stale plan, or
unmarked direct call fails compilation.

## Identity and ownership review

- The Bytes mutation decision owns the function, program, typed-body, and
  target-pipeline revisions used to derive the runtime-use plan revision.
- Each helper occurrence names one exact requirement, target symbol, role,
  source span, profile set, order, and cardinality.
- The runtime requirement ledger owns why `HxBytes` is needed and, when a
  nullable integer crosses the boundary, why `HxRuntime` is needed.
- `OcamlBytesMutationSyntax` receives an authority object instead of creating
  ordinary `EIdent`/`EField` calls. It returns the exact identifier values it
  inserted so the caller can check only this decision's calls; nested receiver
  or argument expressions remain owned by their own decisions.
- `OcamlRuntimeUseAuthority` verifies requirement roots, identities, ordering,
  and cardinality before the printer can publish OCaml text.

No Haxe compiler expressions, mutable compiler contexts, builders, or output
writers were added to persistent state. The new values remain request-local
plain decision data.

## Adversarial checks

- Removing the use list fails.
- Replacing `HxBytes.blit` with `HxBytes.get` fails.
- Reversing nullable unwrap and mutation calls fails.
- Constructing plain `HxBytes.fill`, `HxBytes.blit`, or
  `HxRuntime.nullable_int_unwrap` expressions fails.
- The real Bytes integration path compiles generated OCaml, builds it with
  Dune, runs it, and retains expected Haxe 4.3.7 behavior.
- The public-inspection negative test now recomputes the report's outer
  checksum after deliberate corruption. This makes it reach the intended
  Int64/Float carrier validation instead of passing for the unrelated reason
  that the checksum was stale.

## Scope and disposition

The private-runtime migration inventory fell from 424 to 422 entries, exactly
removing the two source constructors owned by Bytes mutation syntax. Other
Bytes helpers and the remaining 422 inventory entries are intentionally
unchanged. README readiness and source-selection claims do not move.

Disposition: the design is fail-closed and the selected `thinking:xhigh` level
was sufficient. No Oracle escalation is needed because the existing sealed
decision and runtime-use authority provided a bounded, already-reviewed seam.
