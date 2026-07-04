# hxhx Haxe-Family Variation Workflow

Last prepared: 2026-07-04
Status: planning workflow for `haxe.ocaml-vary.6`; no supported user platform claim

Related docs:

- [`HXHX_CUSTOMIZATION_AND_VARIATION_ARCHITECTURE.md`](HXHX_CUSTOMIZATION_AND_VARIATION_ARCHITECTURE.md)
- [`ORACLE_CHECKPOINT_REFLAXE_HXHX_FRAMEWORK_BOUNDARY_2026_07_03.md`](ORACLE_CHECKPOINT_REFLAXE_HXHX_FRAMEWORK_BOUNDARY_2026_07_03.md)
- [`FULL1_RELEASE_GO_NO_GO.md`](FULL1_RELEASE_GO_NO_GO.md)
- [`PROVENANCE_POLICY.md`](PROVENANCE_POLICY.md)
- [`STAGE0_POLICY.md`](STAGE0_POLICY.md)

## Purpose

This page describes how a project should plan a deliberate Haxe-family compiler
variation when ordinary plugins are not enough.

The default answer remains: do not fork the compiler if a macro, target plugin,
backend plugin, or diagnostic customization can express the change. A variation
is for a named compiler product or profile with intentional behavior differences,
separate claims, separate tests, and explicit activation.

The baseline rule stays intact:

> The stock `hxhx` release remains Haxe `4.3.7`-compatible by default. A
> Haxe-family variation must be selected deliberately and must not contribute to
> baseline Full 1.0 evidence.

## Choose The Smallest Surface

Use this order before deciding to create a variation:

| Need | Preferred surface | Variation needed? |
| --- | --- | --- |
| Add codegen for a target | Backend or target plugin | No |
| Package a Reflaxe target as native | Reflaxe promotion / target-core seam | No |
| Add upstream-compatible macro behavior | Stage4 macro/hook surface | No |
| Add a report or project policy after typing | Explicit hxhx customization | Usually no |
| Bundle target/runtime defaults for one product | Named profile or customization bundle | Maybe |
| Change accepted syntax | Variation |
| Change name lookup, typing, unification, or macro lifecycle ordering | Variation |
| Ship a compiler with different compatibility promises | Variation |
| Explore Reflaxe-shaped compiler-core ownership | Research first, then possibly variation |

If the behavior can be removed and the baseline compiler still behaves exactly
the same, start with a plugin or customization. If the behavior changes what the
language accepts, how it types, or what compatibility means, use a named
variation.

## Variation Charter

Every proposed variation starts with a short charter in its bead or design doc.
The charter must include:

- variation ID, for example `acme-policy-haxe`;
- owner and intended users;
- compatibility statement, such as "Haxe `4.3.7` except these named rules";
- explicit non-goals;
- activation mechanism;
- affected compiler phases;
- baseline impact;
- provenance plan;
- validation plan;
- release-claim wording.

The compatibility statement is the important part. A variation may be
Haxe-family, but it is not the baseline Haxe `4.3.7` replacement unless it passes
the baseline gates under the stock profile.

## Explicit Selection

A variation must be selected deliberately. Classpath presence, package name,
ambient project files, or an accidental environment variable must not change the
compiler product.

Until a stable variation API exists, use this as the intended model:

```text
hxhx baseline profile
  -> no variation selected
  -> Full 1.0 baseline evidence may run here

hxhx variation profile
  -> one named variation selected
  -> separate evidence and release claim
```

Future activation may be a flag, manifest, distribution wrapper, or named
profile. Whatever form it takes, it must be:

- explicit: the selected variation ID is visible in command output or evidence;
- deterministic: duplicate or unknown IDs fail before compilation;
- removable: deleting the selection returns to baseline behavior;
- auditable: CI can report the active variation;
- strict-mode-safe: baseline strict lanes reject hxhx-only variation controls.

Use environment variables only as local developer conveniences. They are not a
release-grade selection mechanism unless they are surfaced in the activation
report and forbidden in baseline evidence lanes.

## Code Ownership

Variation code should live behind named boundaries. Avoid hidden `if` branches
scattered through parser, resolver, typer, macro lifecycle, or backend code.

Preferred patterns:

- variation-specific module with a small baseline dispatch point;
- explicit profile object passed to the phase that needs it;
- target/plugin/provider registration for target-only behavior;
- separate distribution wrapper when the product is mostly packaging policy;
- research module outside baseline lanes for experimental compiler-core work.

Avoid:

- changing baseline defaults to make the variation easier;
- using target activation to change typing or name lookup;
- letting a backend reach backward into parser or typer internals;
- importing Reflaxe framework APIs into compiler-core ownership files unless a
  research bead explicitly allows it;
- copying, translating, or mechanically rewriting upstream Haxe compiler code.

`hxhx` can be compiled through `reflaxe.ocaml`, and Reflaxe-style APIs can power
target/backend/plugin seams. That does not mean a variation should build the
compiler core around Reflaxe by default.

## Testing

A variation needs two kinds of evidence:

1. Baseline protection evidence.
2. Variation behavior evidence.

Baseline protection evidence proves the stock compiler still behaves as Haxe
`4.3.7` when the variation is disabled:

- run a disabled/baseline fixture and compare it to the prior baseline result;
- run strict CLI or strict profile checks that reject variation-only controls;
- ensure Full 1.0 gates do not enable the variation by default;
- record that README progress bars remain unchanged unless public readiness
  actually changed.

Variation behavior evidence proves the selected product:

- focused repo-owned fixtures for each intentional behavior difference;
- black-box upstream Haxe runs only as behavior oracle, not source material;
- stage0-forbidden runs when the variation claims native/non-delegating support;
- macro-host tests when macro lifecycle behavior is part of the claim;
- plugin/builtin activation equivalence tests when target packaging is part of
  the claim;
- performance measurements when speed is part of the claim.

Do not use upstream Haxe compiler tests as checked-in fixtures. Keep fixtures
repo-owned and behavior-level.

## CI And Audit

Before a variation can move beyond research, it needs CI or a local gate that
answers these questions:

- Which variation ID was active?
- Was baseline mode also run with no variation?
- Did strict baseline lanes reject variation-only controls?
- Did the run use stage0 delegation, and is that allowed for the claim?
- Are generated artifacts labeled with the variation ID when relevant?
- Do provenance guards still pass?
- Does the release note avoid borrowing baseline Full 1.0 wording?

Useful existing checks and contracts:

- `npm run ci:guards`
- `npm run guard:hx-format:changed` for touched Haxe files
- `scripts/ci/reflaxe-hxhx-core-boundary-check.js`
- [`FULL1_RELEASE_GO_NO_GO.md`](FULL1_RELEASE_GO_NO_GO.md)
- [`PROVENANCE_POLICY.md`](PROVENANCE_POLICY.md)
- [`NATIVE_ITERATION_LATENCY_CONTRACT.md`](NATIVE_ITERATION_LATENCY_CONTRACT.md)

Add a dedicated guard only after the variation activation surface exists. Until
then, record the intended guard in the bead and keep the work research-only.

## Release Claims

Use plain wording:

- "A Haxe-family variation of `hxhx` for `<purpose>`."
- "Compatible with Haxe `4.3.7` except `<named differences>`."
- "Validated by `<variation gates>`."

Avoid misleading wording:

- "Drop-in Haxe replacement" unless the stock baseline gates pass.
- "Full 1.0 compatible" for variation-only evidence.
- "Native parity" when stage0 fallback was required.
- "Reflaxe-authored compiler core" unless a separate architecture decision
  proves that boundary.

A variation can be valuable without pretending to be baseline Haxe. The whole
point is to make intentional differences visible and testable.

## Minimal Workflow

1. Classify the requested behavior with the smallest-surface table.
2. If a plugin/customization is enough, do that instead.
3. If a variation is needed, write the charter.
4. Pick an explicit, removable selection mechanism.
5. Isolate implementation behind a named variation boundary.
6. Add baseline protection evidence.
7. Add variation behavior evidence.
8. Record provenance, stage0, release-claim, and README/North Star decisions.
9. Add CI tripwires once the activation surface is stable.
10. Keep the stock `hxhx` default unchanged.

## Current Status

This is a planning workflow. The repo has an architecture direction and a
diagnostic customization proof, but it does not yet provide a stable public API
for shipping Haxe-family compiler variations.

Use this page to design beads and review future work. Do not treat it as a
promise that external projects can publish supported `hxhx` dialects today.
