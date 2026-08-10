# Second-pass review: catch runtime-tag authority

## Outcome

The change is ready for the task's broad guard run. It removes only the five
direct `HxRuntime.tags_has` constructors used by sealed catch generation. It
does not enable requirements-only runtime selection or change a public
readiness claim.

## What was checked

- **Owner identity:** every tag test ID contains the exact catch-chain and
  clause IDs. The occurrence also keeps the catch function revision, clause
  source span, target profile, and the shared catch runtime requirement.
- **Order and count:** the signal pattern is first, tag tests follow source
  clause order and expression order, and unmatched rethrow is last. Every
  occurrence has cardinality one. Focused tests reject missing, reordered,
  wrong-clause, wrong-role, wrong-owner, wrong-symbol, wrong-domain,
  wrong-profile, and wrong-cardinality plans.
- **No blanket permission:** syntax asks for one closed tag-test role at a
  time. `HxRuntime.tags_has` is now a reserved private name, so a plain target
  identifier fails the focused check.
- **Copied native channel:** a source catch handles both the compiler's Haxe
  exception signal and an OCaml exception. The native branch repeats the catch
  bodies. The first vertical run exposed that copying only tag identities also
  repeated an existing `HxBytes.read` identity. The final implementation
  constructs each tag permission once, rebuilds the native branch from those
  checked names, and copies the complete branch through the existing final-
  output authority. This gives every repeated checked name a fresh output ID.
- **Requirement scope:** all new occurrences use the existing catch-signal
  requirement whose only direct runtime root is `HxRuntime`. No new module or
  broader runtime capability was added.
- **Independent behavior:** expected catch behavior comes from pinned Haxe
  4.3.7 on three routes and twelve cases. The native portable fixture then
  compiles, builds, and runs the same catch families through the OCaml target.
- **Inventory boundary:** the reviewed source inventory fell from 362 to 357.
  The `builder-runtime-tags` family is empty, while 357 unrelated legacy
  references remain visible and still block complete runtime authority.

## Deliberate limits

The catch planner still owns the same match policies, tag values, payload
conversions, and clause order. The syntax builder only turns those saved facts
into checked OCaml identifiers. This task does not migrate private return or
loop signals, nullable carriers, arrays, integers, strings, reflection, or
other runtime families.

Oracle review was deliberately skipped. The accepted per-occurrence authority
model and the existing sealed catch plan provided one bounded implementation
seam. Focused corruption tests plus the real Haxe-to-OCaml build decided the
remaining questions, including the copied-branch issue found during this task.

## Broad-guard repair

The first broad guard run exposed a separate command-line defect in two
planner fixtures: their source imports Reflaxe lifecycle types, but the npm
commands did not load the `reflaxe` library. Both commands passed immediately
when run with the missing `-lib reflaxe` flag. The package scripts now declare
that dependency explicitly, matching the neighboring planner fixtures. This
changes test wiring only; it does not change compiler behavior or catch
authority.
