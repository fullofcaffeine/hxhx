# Full 1.0 Contract (vs Scoped 1.0)

Last audited: 2026-07-23

This page is the canonical definition boundary for release claims:

- **Scoped 1.0**: the currently declared replacement-ready scope.
- **Full 1.0**: strict Haxe 4.3.7 compatibility for the declared target and
  generator scope, with explicit parity/performance/release gates.

Public-claim checklist:

- `docs/00-project/PUBLIC_1_0_CHECKLIST.md`

Full1 release go/no-go decision:

- `docs/00-project/FULL1_RELEASE_GO_NO_GO.md`

Machine-readable scope source of truth:

- `docs/02-user-guide/compat/full-1.0-scope.json`
- `docs/02-user-guide/compat/FULL1_TARGET_SCOPE.md`
- `docs/00-project/PARITY_MAP_FULL_1_0.json`

## Baseline

- Upstream compatibility baseline is pinned to `Haxe 4.3.7`.
- No copied upstream compiler/test sources are allowed in this repo.
- Upstream suites are exercised from ephemeral/local checkouts only.

## Scoped 1.0 (current release scope)

Scoped 1.0 is the practical ship scope for current lanes and guardrails:

- Native lanes: `--ocaml`, `--js <file>`
- Delegated lanes: `--ocaml-eval`, `--compat`
- Required scoped markers are listed in `full-1.0-scope.json` under `scoped.requiredMarkers`.

Scoped 1.0 sign-off uses M7 strict markers:

- `M7_STRICT_STAGE0:PASS`
- `M7_REPLACEMENT_READY:PASS`

## Full 1.0 (strict declared-scope compatibility claim)

Full 1.0 is a stricter claim than Scoped 1.0. It requires:

- relevant upstream Haxe 4.3.7 suites to pass under `hxhx` as the primary
  proof of compatibility for the declared scope,
- strict non-delegating parity coverage against the contract matrix,
- macro/eval closure markers,
- plugin parity markers,
- upstream-relative performance parity gate,
- release RC aggregation marker.

For any code path offered as evidence for a declared Full1 behavior, it also
requires authentic compiler behavior rather than a target-output repair that
merely lets the next tool run. In particular:

- a backend may consume the source-shaped projection built from sealed typed
  bodies during migration, but it must not recover semantics from the original
  parser body;
- Stage3 placeholder modules, generated-file semantic rewrites, or unexplained
  fallback values cannot by themselves satisfy a Full1 row;
- an unsafe native implementation cast may remain only when its typed
  representation boundary, reason, permitted profile, validation, and behavior
  tests are explicit; and
- three consecutive source-shaped patches in one failure family trigger a
  review of the shared parser, resolver, typer, lowered-model, runtime, or
  toolchain owner before another leaf fix proceeds.

`haxe.ocaml-f1cl.3.11` owns that root-family classification. The accepted
six-month disposition is
`docs/00-project/ORACLE_CHECKPOINT_SIX_MONTH_ARCHITECTURE_2026_07_23.md`.

The native `hxhx + reflaxe.ocaml` hard cut is separately owned by
`haxe_ocaml-38gsp.1`. It is required for that combined product and later M22
work, but it is not a target or generator in the declared Full1 scope and is
not a prerequisite for closing `haxe.ocaml-f1cl`.

### Exactly which targets and generators are included?

In plain language, the first Full1 release requires JavaScript, Lua, Neko,
PHP, C++ plus Cppia, C#, Java source output, Python, both HashLink output
forms, and native interpreter/run-module behavior. C++/hxcpp is mandatory.

It deliberately does not claim every Haxe 4.3.7 output:

- Flash SWF/SWC is intentionally incompatible with the `hxhx` product scope.
- Direct JVM bytecode is deferred; Java source output is still required.
- XML and JSON type-description generation are deferred.

The complete per-surface table and user consequences are in
`docs/02-user-guide/compat/FULL1_TARGET_SCOPE.md`. The machine-readable list is
`full.targetAndGeneratorScope` in the scope manifest. The
`FULL1_TARGET_SCOPE_CONTRACT:PASS` policy marker proves that this list, the
strict target matrix, and the public docs still agree. It does **not** prove
that any runtime target has passed.

For Full 1.0, repo-local focused regressions and bridge-specific tests are supporting evidence only.
They are valuable for fast diagnosis and iteration, but they do not replace upstream-suite proof.

Planned Full 1.0 markers are listed in `full-1.0-scope.json` under `full.requiredMarkersPlanned`.

Macro/eval closure has its own explicit sub-contract:

- `docs/00-project/MACRO_EVAL_PARITY_CONTRACT.md`

That sub-contract distinguishes the contract-definition marker
`FULL1_MACRO_EVAL_CONTRACT:PASS` from the runtime evidence markers
`FULL1_MACRO_PARITY:PASS`, `FULL1_EVAL_NATIVE:PASS`, and
`FULL1_MACRO_EVAL_PARITY:PASS`.

The aggregate macro/eval marker must be built from uploaded proof files for
one exact commit and run attempt. Two green job labels are not enough. The
plain-language trust-flow decision is documented in
`docs/00-project/FULL1_MACRO_EVAL_EVIDENCE_DECISION.md`.

Performance parity has its own explicit sub-contract:

- `docs/00-project/FULL1_PERF_PARITY_POLICY.md`

That sub-contract distinguishes the contract-definition marker
`FULL1_PERF_POLICY:PASS` from the measured runtime evidence marker
`FULL1_PERF_PARITY:PASS`. Stage0 bootstrap regeneration memory is maintenance
evidence only; Full 1.0 performance evidence must compare stage0-free `hxhx`
runtime lanes against upstream Haxe 4.3.7.

Plugin parity has its own explicit sub-contract:

- `docs/00-project/PLUGIN_PARITY_FULL_1_0.md`

That sub-contract distinguishes the contract-definition marker
`FULL1_PLUGIN_PARITY_CONTRACT:PASS` from the runtime evidence marker
`FULL1_PLUGIN_PARITY:PASS`. Scoped 1.0 plugin smoke evidence
(`PLUGIN_MATRIX_STRICT:PASS`) does not replace the Full 1.0
`reflaxe.ocaml` plugin proof matrix.

Full1 suite flake handling has its own explicit sub-contract:

- `docs/00-project/FULL1_FLAKE_POLICY.md`

That sub-contract defines `FULL1_FLAKE_POLICY:PASS`, bounded retries, and the
expiry-based quarantine allowlist required before the Full1 RC gate may emit
`FULL1_RELEASE_GO:PASS`.

Full1 release go/no-go has its own explicit decision page:

- `docs/00-project/FULL1_RELEASE_GO_NO_GO.md`

That page defines the public `Full 1.0` go/no-go boundary and its
`full1-rc-summary.v2` receipt. The receipt must be created before publication,
must identify one exact candidate SHA/version and run attempt, and must point
to verified child artifact digests. Missing, stale, skipped, synthetic, or
cross-candidate evidence is no-go. It does not redefine `Scoped 1.0`.

## Non-goals policy

Anything not explicitly declared in the scope manifest is out-of-scope for the claim.
This prevents "scope drift by implication." Public wording must say
"Haxe 4.3.7-compatible for the declared Full1 target and generator scope," not
an unqualified all-target drop-in replacement.

## Documentation disambiguation rule

For release-policy docs, Scoped 1.0 or Full 1.0 claims must be explicit as either:

- `Scoped 1.0`, or
- `Full 1.0`.

Ambiguous wording is guard-checked by:

- `scripts/ci/full1-scope-contract-check.js`

Success marker:

- `FULL1_SCOPE_CONTRACT:PASS`

## Public claim rule

Before making a public `Scoped 1.0` or `Full 1.0` claim, use the explicit checklist:

- `docs/00-project/PUBLIC_1_0_CHECKLIST.md`

Do not use an unlabeled public version claim by itself.
