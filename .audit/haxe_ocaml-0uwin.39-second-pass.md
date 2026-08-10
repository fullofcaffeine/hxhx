# Second-pass review: sealed assignment Int addition authority

## Outcome

The slice is safe to close. Static-field, instance-field, and array `+=`, prefix update, and postfix update operations now obtain `HxInt.add` through the exact assignment plan that already owns their evaluation order. No target printer or emitter chooses the helper from generated text.

This closes only the six `place-assignment` inventory entries. It does not authorize the remaining array load/store names, complete requirements-only runtime selection, or change any 1.0 readiness claim.

## Ownership review

- The planner creates one occurrence after it has selected the exact Int mutation and its operator step.
- The occurrence points to the existing `haxe-int32-add` requirement, the exact plan identity, the source span, both supported profiles, and cardinality one.
- The expected operator order is explicit for all six shapes: static compound 2, static update 1, array compound 4, array update 3, instance compound 3, and instance update 2.
- The validator checks that contract before target syntax is constructed.
- The emitter receives a restricted runtime reference and returns the exact addition subtree separately from the full expression.
- The lowerer reconciles only that subtree. This matters because receiver, index, or right-hand-side expressions can contain other independently sealed operations whose permissions belong to their own lowerers.
- The public inspection path rejects a report whose runtime-use owner, requirement, symbol, order, source, profile, or cardinality disagrees with the sealed plan.

## Adversarial finding and fix

The first review found that the generic plain-private-name detector did not list `HxInt.add`. The expected authorized call would still reconcile, but a second ordinary `EField(EIdent("HxInt"), "add")` node could have been ignored. `HxInt.add` is now part of the detector, and the focused runtime-authority fixture proves that an unmarked call is rejected. The anonymous-object vertical fixture remains green, showing that its separately authorized additions still work.

## Behavior and oracle review

The real instance, static, and array programs compile generated OCaml, build it with Dune, run it, and compare stdout. The instance fixture also compares every mutation observation against upstream Haxe eval and Neko. Only the separately owned uninitialized primitive-field observation is excluded because those hosts print `null` while this target's exact-carrier policy prints zero or false.

The compared mutation evidence includes receiver/index/right-hand-side single evaluation, load-before-right-hand-side behavior, prefix/postfix old-versus-new results, and signed 32-bit overflow from `2147483647` to `-2147483648`.

## Snapshot review

Only the three assignment-family lowering goldens were refreshed. They also contained stale additive anonymous-object occurrence data from the immediately preceding migration. A targeted review confirmed:

- 7 instance-field mutation plans, all with one valid `HxInt.add` occurrence;
- 13 static-field mutation plans, all with one valid occurrence; and
- 5 array mutation plans, all with one valid occurrence.

The normal repository runner then reproduced the refreshed reports exactly and passed each executable and fixture-specific check.

## Verification

- Expected red: the instance fixture failed only because mutation plans had no exact occurrence.
- Three assignment portable fixtures: pass through the normal sequential runner.
- Anonymous-object portable fixture: pass after extending plain-name rejection.
- Runtime-use authority fixture: pass, including stale, duplicate, missing, reordered, wrong-symbol, wrong-profile, and plain-name failures.
- Runtime-requirement ledger: pass.
- Runtime-reference inventory fixture and current inventory: pass at 402 entries; `place-assignment` count is zero.
- Public inspection corruption: rejects a wrong plan owner with an actionable message.
- Haxe formatting, shell syntax, diff hygiene, path privacy, and mega-file guard: pass.

The package-wide `npm run test:reflaxe-ocaml:runtime-use-authority` wrapper was not repeated because its full-package `nullSafety("reflaxe.ocaml")` traversal has the separately tracked long-running defect `haxe_ocaml-850ii.23`. The same fixture was run directly and passed immediately; this limitation does not count as broader package-lane closure.

## Residual risk

There are 402 legacy private-runtime references left. Compiler observations therefore remain authoritative for source selection, and `haxe_ocaml-0uwin.31` stays open. README Goals do not move from this slice.
