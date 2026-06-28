# Full1 Flake Policy

Last audited: 2026-06-27

This document defines how Full 1.0 release evidence may handle flakes without
weakening the strict Haxe 4.3.7-equivalence claim.

Success marker:

- `FULL1_FLAKE_POLICY:PASS`: the policy surface is present, the allowlist is
  parseable, and every quarantine entry has an owner, justification, linked
  bead, marker, workflow, retry bound, and future expiry.

`FULL1_FLAKE_POLICY:PASS` is a contract marker only. It does not mean any
Full1 runtime, suite, plugin, or performance evidence passed.

## Rules

- Full1 gates must never silently skip required evidence.
- A retry is allowed only when the workflow or runner explicitly reports the
  first attempt and preserves both attempts in artifacts/logs.
- A quarantine is allowed only through
  `docs/00-project/FULL1_FLAKE_ALLOWLIST.json`.
- Every quarantine entry must include:
  - `id`: stable identifier.
  - `owner`: accountable human or team.
  - `bead`: tracking issue for removal.
  - `workflow`: workflow or guard affected.
  - `marker`: marker temporarily blocked by the flake.
  - `justification`: release-evidence reason, not a vague note.
  - `retryLimit`: maximum automatic retries before the lane is failing.
  - `expiresAt`: ISO date after which the quarantine is invalid.
- Expired quarantine entries block `FULL1_FLAKE_POLICY:PASS`.
- Quarantines must not convert a required Full1 marker into success. They only
  document bounded retry/quarantine behavior while the owning bead remains open.

## Current Allowlist

The current allowlist is intentionally empty. Any future entry must be narrow,
owned, justified, and expiring.

Guard:

- `scripts/ci/full1-flake-policy-check.js`
