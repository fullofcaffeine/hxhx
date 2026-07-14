# Weekly CI Evidence Runbook

Last audited: 2026-07-14

This runbook defines how maintainers audit scheduled CI health each week and what to do when a gate regresses.

## CI failure ownership rule

The user-facing outcome is simple: an important failed check must never leave
someone asking, “Who is handling this?” The repository now answers that with:

- `docs/00-project/CI_EVIDENCE_OWNERSHIP.json`: the watched checks and their
  current failure records;
- `scripts/ci/ci-evidence-ownership.js`: compares those records with GitHub
  runs and the tracked Beads export;
- `CI / Evidence Ownership Audit`: runs after watched workflows and once per
  day, then uploads a JSON report.

The audit rejects a current failure, uncaught cancellation, stale scheduled
success, or missing scheduled run unless it points to one active P0/P1 bead.
The bead and JSON record must include the commit, run and attempt, observed
problem, classification, and the remote evidence needed for closure. A local
pass is useful diagnosis, but it does not close a required remote failure.
A clean audit prints `CI_EVIDENCE_OWNERSHIP:PASS`; that means every problem is
owned, not that the owned checks themselves are green.

### Two labels, for two different questions

Keep the observed GitHub state separate from the likely cause:

| Evidence state | Plain meaning |
| --- | --- |
| `failure-current` | The newest relevant run completed unsuccessfully. |
| `cancelled-superseded` | A newer valid run replaced the cancellation. Only the newer run counts. |
| `cancelled-no-successor` | Nothing valid replaced the cancellation, so evidence is missing. |
| `stale-success` | A run passed, but it is too old for the declared freshness window. |
| `missing` | No qualifying run exists for the declared event/profile. |

Then classify the likely cause as `semantic`, `repository-policy`,
`toolchain`, `infrastructure`, `timeout-performance`, `expected-no-go`, or
`unknown`. `unknown` is an honest temporary classification; the owner still
has to inspect the first useful log or artifact.

### What to do when a check fails

1. Reuse an existing bead when the root cause is already owned; otherwise
   create one bounded P0/P1 bead.
2. Add or update one open incident in
   `CI_EVIDENCE_OWNERSHIP.json`. Record the exact SHA, run ID, attempt, URL,
   evidence state, cause class, and closure gate.
3. Put the incident ID and the same facts in the bead comment so a human can
   understand the record without reading the evaluator code.
4. If a newer run repeats the same root cause, keep the same bead, mark the old
   incident superseded, and record the newer run as the open incident.
5. Close the bead and mark the incident resolved only after a valid remote
   successor passes. A cancelled run is not a pass.

Scheduled runs remain the normal freshness signal. For M7, Full1 plugin, and
macro-runtime lanes, an explicit `workflow_dispatch` rerun may also resolve an
owned failure when it uses the same full workflow and produces the lane's
candidate-bound, artifact-verified receipt. For M7, that is the
`m7-shared-artifacts.v2` receipt plus both strict markers. For plugins, it is
`full1-plugin-parity-summary.v3`. For external macros, it is
`macro-runtime-host-evidence.v1`, accompanied by both mode artifacts and the
aggregate summary. This lets maintainers prove a fix without waiting for the
next calendar run; it does not remove the weekly schedule or turn a local pass
into release evidence.

Run the local contract check with:

```bash
npm run guard:ci-evidence-ownership
```

### Current reviewed ledger

The original 2026-07-12 Core local-path and Portable Tier1 Rest failures are
resolved by exact-head required runs and retained as machine-readable history.
The plugin failure is resolved by artifact-backed run `29281925684`. Manual
KPI run `29283471461` supersedes the original missing-run record. Its incomplete
v1 report led to `haxe_ocaml-850ii.1`; exact-commit run `29285154286` then
produced the independently validated, self-describing v2 report and completed
that follow-up. Full1 phase receipts received the same treatment under
`haxe_ocaml-850ii.6`; exact-commit plugin run `29303951143` produced three
independently validated v2 timing reports. These are report-quality results,
not proof that the compiler is fast enough. The M7 timeout is now resolved by
exact-commit strict/full run `29321576340`, which finished in about 102 minutes,
uploaded artifact `8309183633`, and emitted both required M7 markers. The
macro-runtime incident is resolved by exact-commit run `29334023225`. That run
reused one candidate-bound, stage0-forbidden external host and passed both
runtime modes. It closes the host lifecycle failure, not the separate
project-defined macro obligation. That next obligation is now resolved by
exact-commit run `29349360051` at `3806c611`: one repo-owned Haxe macro was
generated, authenticated, loaded, and run in both native modes, while both
established runtime jobs and the aggregate marker also passed. Project evidence
artifact `8317497905` has digest
`sha256:aa3c83f4b56e9cba8c1dd661e0319928447ccbd56620f298b778cc1a42248766`;
summary artifact `8317500638` has digest
`sha256:b294cbc5c7b9383cf9d4fb1494cc0ae0ecd4570253f0bc601e7165573b78d839`.
The broader macro/eval outcome is now also green for one exact candidate.
Focused run `29353274632` at `243f9801` opened the three macro proof packages,
the candidate-bound native-eval receipt, and then both verified summaries
before emitting `FULL1_MACRO_EVAL_PARITY:PASS`. Combined artifact `8319351564`
has digest
`sha256:e0be361dffa7c246875196c5ca7da8ac22e31f8302c62a74e35388a12c6467a5`.
The native eval runner took 482.6 seconds, so this is correctness evidence; it
does not close the separate performance goal. Gate Full1 remains scheduled and
is the ongoing freshness route for this child evidence.
The current open incident record is the expected broader Full1 aggregate no-go.
Its owner is recorded in the JSON ledger, and the open record does not count as
passing product or Full1 evidence.

## Audit window

- Primary review window: **Wednesday after 08:00 UTC**.
- Why this window:
  - Gate M7 scheduled run has already executed (Sunday 09:00 UTC).
  - Gate 1 and Gate 2 scheduled runs have already executed (Monday 07:00/09:00 UTC).
  - Semantic-diff nightly expanded run has just executed (Wednesday 07:00 UTC).
- KPI report workflow is not currently scheduled; trigger it manually during this window.

## Required weekly evidence set

| Workflow | File | Cadence | Expected pass signal | Evidence artifact/log |
| --- | --- | --- | --- | --- |
| Gate 1 / Upstream Macro Unit Compatibility | `.github/workflows/gate1.yml` | Weekly schedule | `GATE1_MACRO:PASS` | Workflow run logs (marker in log output) |
| Gate 2 / Upstream Macro Workloads | `.github/workflows/gate2.yml` | Weekly schedule | `GATE2_MACRO:PASS` | Workflow run logs (marker in log output) |
| Macro Runtime Parity (Weekly) | `.github/workflows/macro-runtime-parity-weekly.yml` | Weekly schedule | `MACRO_RUNTIME_PARITY_WEEKLY:PASS`, `FULL1_MACRO_PARITY:PASS`, plus mode markers (`..._EXTERNAL_HOST:PASS`, `..._INPROC:PASS`). The summary opens the two mode packages and the Haxe-authored project-macro package before it can pass. | Artifacts `macro-runtime-parity-external-host-<run_id>-<attempt>`, `macro-runtime-parity-inproc-<run_id>-<attempt>`, `project-macro-module-<run_id>-<attempt>`, and verified `macro-runtime-parity-summary-<run_id>-<attempt>` |
| Gate M7 / Replacement Bundle | `.github/workflows/gate-m7.yml` | Weekly schedule | `M7_SHARED_ARTIFACTS:PASS`, `M7_STRICT_STAGE0:PASS`, and `M7_REPLACEMENT_READY:PASS` | Artifact `gate-m7-logs-<run_id>` with the run log and `m7-shared-artifacts.v2` receipt + run logs |
| Full1 / Plugin Parity | `.github/workflows/full1-plugin-parity.yml` | Weekly schedule | `FULL1_PLUGIN_PARITY:PASS` | Per-proof artifacts `full1-plugin-upstream-to-hxhx-<run_id>-<attempt>`, `full1-plugin-hxhx-to-hxhx-<run_id>-<attempt>`, `full1-plugin-upstream-host-adapter-<run_id>-<attempt>` each contain the receipt and loaded plugin file; aggregate artifact `full1-plugin-parity-summary-<run_id>-<attempt>` records same-candidate verification and checksums. |
| Gate Full1 / Strict Matrix + Macro Eval + Plugin Parity | `.github/workflows/gate-full1.yml` | Weekly schedule | `FULL1_SUITE_MATRIX:PASS`, `FULL1_MACRO_EVAL_PARITY:PASS`, and `FULL1_PLUGIN_PARITY:PASS` | Artifacts `full1-macro-eval-summary-<run_id>-<attempt>` and `full1-summary-<run_id>-<attempt>` + child proof logs. Gate Full1 opens the combined macro/eval receipt before repeating its marker. |
| Stdlib / Semantic Diff (nightly expanded job) | `.github/workflows/semantic-diff.yml` | Weekly schedule | `SEMANTIC_DIFF_NIGHTLY:PASS` | Artifact `semantic-diff-nightly-artifacts` |
| Perf / HXHX KPI (Report Only) | `.github/workflows/hxhx-kpi-report.yml` | Manual weekly dispatch | job completes and emits `report.json` | Artifact `hxhx-kpi-report-<run_id>` (contains `report.json`) |

## Advisory weekly evidence (non-blocking)

| Workflow | File | Cadence | Expected signal | Evidence artifact/log |
| --- | --- | --- | --- | --- |
| Full1 / Source-Build Probe | `.github/workflows/full1-source-probe.yml` | Weekly schedule | `FULL1_SOURCE_BUILD_PROBE:PASS` (ideal) or `FULL1_SOURCE_BUILD_PROBE:WARN` (diagnostic follow-up required) | Artifact `full1-source-probe-<run_id>` with compact summary JSON plus separate build/suite logs |
| Full1 / Bootstrap-Source Reconciliation | `.github/workflows/full1-bootstrap-source-reconcile.yml` | Weekly schedule | `FULL1_BOOTSTRAP_SOURCE_RECONCILIATION:PASS` (classification complete) or `...:WARN` (artifact pair/classification incomplete) | Artifact `full1-bootstrap-source-reconcile-<run_id>` |

## Weekly procedure

1. Open the latest `CI / Evidence Ownership Audit` report. Fix any unowned,
   stale, or missing row before treating the weekly set as reviewed.
2. Open GitHub Actions and filter to the weekly evidence workflows above.
3. Verify latest scheduled runs for Gate 1, Gate 2, Macro Runtime Parity, Gate M7, Gate Full1, and semantic-diff are green.
4. Open each run and confirm expected markers appear in logs.
5. For Macro Runtime Parity, download both mode-tagged artifacts, the project
   macro artifact, and the verified summary. Inspect:
   - `markers.txt`
   - `macro-runtime-parity-blockers.md`
   - `macro-runtime-host-receipt.json` and its referenced executable digest in
     the external-host artifact
   - suite logs (`unit`, `runci`, `display/protocol`)
   - `summary.json`, whose schema must be `macro-runtime-parity-summary.v4`
     and whose three proof records must belong to the same commit/run attempt
6. For Gate M7, Gate Full1, and semantic-diff, download artifacts and confirm expected files are present.
7. For Gate Full1, inspect `full1-macro-eval.summary.json` and confirm all three
   aggregate markers appear:
   - `FULL1_SUITE_MATRIX:PASS`
   - `FULL1_MACRO_EVAL_PARITY:PASS`
   - `FULL1_PLUGIN_PARITY:PASS`
8. Check `Full1 / Source-Build Probe`:
   - `PASS`: source-build probe agrees with current strict matrix behavior.
   - `WARN`: do not block release by this alone; open/update a bead with artifact links and classify as bootstrap-lag, source-build instability, or parity bug.
9. Manually dispatch `Perf / HXHX KPI (Report Only)`.
10. Download the KPI artifact, require a valid self-describing `hxhx.kpi.v2`
    report, and compare it against:
   - `docs/benchmarks/kpi/hxhx-kpi-thresholds.v1.json`
   - `docs/benchmarks/HXHX_KPI_THRESHOLDS.md`

Validate the downloaded report with:

```bash
node scripts/ci/hxhx-kpi-report-validator.js --report <artifact>/report.json
```
11. Check GitHub branch protection for `main` and compare it with the `PR required` table in `docs/00-project/CI_GATES.md`.
12. Record evidence links and outcomes in the weekly ops note/bead comment.

## GitHub UI Interpretation

- Use the current head SHA when deciding whether the push/PR baseline is green.
- Treat cancelled runs on older commits as superseded when a newer push reused the same workflow concurrency group.
- Treat `Release / Semantic Publish` skipped runs as expected when the triggering `CI / Core PR Checks` run was cancelled, superseded, or otherwise did not meet the release workflow condition.
- Treat report-only performance workflows as advisory even though they run on push/PR for visibility.

## Triage matrix

| Signal | Owner | First action (same day) | Escalation |
| --- | --- | --- | --- |
| Gate 1 or Gate 2 scheduled failure | On-duty CI maintainer | Re-run once to rule out transient infrastructure failure; if reproducible, open regression bead with run URL + failing step | Escalate to compiler owners if not green within 24h |
| Macro runtime parity weekly failure (either mode) | On-duty macro/runtime maintainer | Inspect mode-tagged artifacts, identify whether failure is `external-host` only, `inproc` only, or both; file/update blocker bead with mode marker lines | Escalate to compiler owners if parity remains red for two consecutive weekly runs |
| Gate M7 scheduled failure or missing strict marker | On-duty release maintainer | Re-run Gate M7 with strict defaults; attach `gate-m7-logs-<run_id>` and marker lines to regression bead | Treat as release blocker until resolved |
| Semantic-diff nightly failure or missing artifact | On-duty stdlib maintainer | Re-run workflow, inspect comparator/lane logs, and attach `semantic-diff-nightly-artifacts` to bead | Escalate to stdlib/runtime owners if unresolved in 24h |
| KPI workflow emits no report or exceeds threshold budget | On-duty performance maintainer | Re-run KPI once; compare `report.json` with threshold file and classify expected vs regression | Escalate to release maintainer when regression exceeds thresholds on two consecutive weekly runs |
| Full1 source-build probe emits `FULL1_SOURCE_BUILD_PROBE:WARN` | On-duty Full1 maintainer | Download `full1-source-probe-*` artifact, identify whether failure is build path, macro-host path, or suite parity, and update/open a blocker bead with run URL + summary JSON | Escalate to compiler owners if WARN repeats for two consecutive weekly runs on the same suite |
| Full1 bootstrap-source reconciliation emits `FULL1_BOOTSTRAP_SOURCE_RECONCILIATION:WARN` | On-duty Full1 maintainer | Download `full1-bootstrap-source-reconcile-*` artifact, verify both lane summaries exist for `server` + `optimization`, and rerun if classification is incomplete | Escalate if WARN repeats for two consecutive weekly runs or blocker classification remains unknown |
| Scheduled workflow did not run | On-duty CI maintainer | Trigger manual dispatch immediately and capture run URL | Escalate to infra/CI owners if scheduler miss repeats next week |

## Local reproduction commands

```bash
# Gate 1
npm run test:upstream:unit-macro

# Gate 2
npm run test:upstream:runci-macro

# Gate M7 strict
npm run test:upstream:replacement-ready:strict

# Semantic diff (nightly profile)
SEMANTIC_DIFF_PROFILE=nightly \
SEMANTIC_DIFF_SEED=7331 \
SEMANTIC_DIFF_MAX_PROGRAMS=1000 \
SEMANTIC_DIFF_TIMEOUT_MS=15000 \
SEMANTIC_DIFF_COMPARATOR_REPEATS=2 \
SEMANTIC_DIFF_ARTIFACT_DIR=.artifacts/semantic-diff/nightly \
bash scripts/test-stdlib-semantic-diff-lane.sh

# KPI report generation
HXHX_KPI_REPS=2 HXHX_KPI_RUN_MACRO_LANE=1 npm run hxhx:bench:kpi

# Full1 source-build probe (non-blocking diagnostic lane)
npm run -s test:full1:source-probe

# Full1 bootstrap-source reconciliation (diagnostic classification lane)
npm run -s test:full1:bootstrap-source-reconcile
```

## Related docs

- `docs/00-project/CI_GATES.md`
- `docs/00-project/CI_EVIDENCE_OWNERSHIP.json`
- `docs/00-project/PARITY_MAP_HAXE_4_3_7.md`
- `docs/benchmarks/HXHX_KPI_THRESHOLDS.md`
