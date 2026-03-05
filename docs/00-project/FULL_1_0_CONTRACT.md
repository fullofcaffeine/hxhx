# Full 1.0 Contract (vs Scoped 1.0)

Last audited: 2026-03-05

This page is the canonical definition boundary for release claims:

- **Scoped 1.0**: the currently declared replacement-ready scope.
- **Full 1.0**: strict Haxe 4.3.7-equivalent claim with explicit parity/perf/release gates.

Machine-readable scope source of truth:

- `docs/02-user-guide/compat/full-1.0-scope.json`

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

## Full 1.0 (strict equivalence claim)

Full 1.0 is a stricter claim than Scoped 1.0. It requires:

- strict non-delegating parity coverage against the contract matrix,
- macro/eval closure markers,
- plugin parity markers,
- upstream-relative performance parity gate,
- release RC aggregation marker.

Planned Full 1.0 markers are listed in `full-1.0-scope.json` under `full.requiredMarkersPlanned`.

## Non-goals policy

Anything not explicitly declared in the scope manifest is out-of-scope for the claim.
This prevents "scope drift by implication."

## Documentation disambiguation rule

For release-policy docs, Scoped 1.0 or Full 1.0 claims must be explicit as either:

- `Scoped 1.0`, or
- `Full 1.0`.

Ambiguous wording is guard-checked by:

- `scripts/ci/full1-scope-contract-check.js`

Success marker:

- `FULL1_SCOPE_CONTRACT:PASS`
