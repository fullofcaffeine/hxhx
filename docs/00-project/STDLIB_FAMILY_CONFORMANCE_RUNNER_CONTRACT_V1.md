# Family Portable Stdlib Conformance Runner Contract (v1)

This document defines the shared compile-run contract for portable stdlib conformance across Reflaxe-family targets.

## Goal

- One deterministic runner interface for portable stdlib conformance.
- First implemented adapter: OCaml (this repository).
- Future adapters: Rust and Go (tracked as placeholders in beads).

## Non-goals

- This contract does not define target-native APIs (`ocaml.*`, `rust.*`, `go.*`).
- This contract does not replace target-specific performance suites.

## Runner interface (normative)

Each target adapter must expose a runner command that accepts equivalent inputs:

- `targetId` (for example `ocaml`, `rust`, `go`)
- `tier` (`tier1`, `tier2`)
- `allowlistPath` (path to target allowlist manifest)
- `fixtureRoot` (path containing portable fixtures)
- `reportPath` (json output path)
- `strictNativeSurface` (`true|false`)
- `corpusManifestPath` (path to semantic-diff corpus manifest)
- `sliceId` (corpus slice id, for example `core_seed_v1`)

The adapter may map these as CLI args or env vars, but behavior must be equivalent.

## Exit + marker contract (normative)

Runner exit codes:

- `0`: pass (or deterministic skip)
- `1`: conformance failure
- `2`: invalid runner configuration/inputs

Runner markers (stdout):

- `PORTABLE_CONFORMANCE_RUNNER_START target=<id> tier=<tier>`
- `PORTABLE_CONFORMANCE_RUNNER_PASS target=<id> tier=<tier>`
- `PORTABLE_CONFORMANCE_RUNNER_FAIL target=<id> tier=<tier> failed=<n>`
- `PORTABLE_CONFORMANCE_RUNNER_SKIP target=<id> tier=<tier> reason=<reason>`

## Comparator normalization rules (v1)

When adapter reports are compared, normalization must apply before field equality checks:

- normalize line endings to `\n`
- trim trailing whitespace per line
- trim trailing blank lines

Compared fields:

- `status`
- `compileExitCode`
- `runExitCode`
- normalized `stdout`
- normalized `stderr`

Comparator output contract id:

- `reflaxe.family.std.semantic_diff_divergence_report`

## Report contract (normative)

The runner writes a deterministic JSON report to `reportPath`:

```json
{
  "schemaVersion": 1,
  "contractId": "reflaxe.family.std.portable_conformance_runner",
  "contractVersion": "1.0.0",
  "targetId": "ocaml",
  "tier": "tier1",
  "strictNativeSurface": true,
  "status": "pass",
  "summary": {
    "total": 0,
    "passed": 0,
    "failed": 0,
    "skipped": 0
  },
  "fixtures": []
}
```

Required `status` values:

- `pass`
- `fail`
- `skip`

## OCaml adapter requirements (v1 baseline)

Current OCaml runner pieces:

- tier1 lane: `scripts/test-stdlib-portable-tier1.sh`
- full lane: `scripts/test-stdlib-portable-full.sh`
- fixture compile-run lane: `scripts/test-portable.sh`

Adapter requirements for OCaml under this contract:

1. Keep tier allowlist validation in front of fixture execution.
2. Keep strict portable-native-surface enforcement (`ocaml_portable_native_surface=error`) in tier1 lane.
3. Keep compile-run behavior based on fixture `expected.stdout` / optional `expected.stderr`.
4. Emit contract markers and JSON report in deterministic order.
5. Report skip as deterministic status (missing toolchain), not as hidden silent success.
6. Support corpus slicing by reading `test/portable/semantic_diff/corpus_v1.json` and selecting fixtures from `core_seed_v1`.

## First wired corpus slice (v1)

- Corpus manifest: `test/portable/semantic_diff/corpus_v1.json`
- Seed slice id: `core_seed_v1`
- Seed runner command:

```bash
npm run test:stdlib:semantic-diff:seed
```

## Placeholder adapters (tracked work)

Rust and Go adapters are tracked as explicit placeholder tasks. They must implement the same contract fields, markers, and report shape as OCaml.

- Rust placeholder: `haxe.ocaml-z7f.3.1`
- Go placeholder: `haxe.ocaml-z7f.3.2`

## Contract evolution policy

- Patch: wording/non-breaking clarifications.
- Minor: additive report fields or new optional markers.
- Major: breaking schema/marker/exit changes (requires `..._V2` contract doc).
