# Weekly CI Evidence Runbook

Last audited: 2026-07-12

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

Run the local contract check with:

```bash
npm run guard:ci-evidence-ownership
```

### Current reviewed ledger

The original 2026-07-12 Core local-path and Portable Tier1 Rest failures are
resolved by exact-head required runs and retained as machine-readable history.
The current open scheduled records are macro-runtime failure, M7 timeout with
no successor, plugin-parity failure, the expected Full1 aggregate no-go, and
the missing manual weekly KPI run. Their owners are recorded in the JSON
ledger; none of those records counts as passing product or Full1 evidence.

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
| Macro Runtime Parity (Weekly) | `.github/workflows/macro-runtime-parity-weekly.yml` | Weekly schedule | `MACRO_RUNTIME_PARITY_WEEKLY:PASS`, `FULL1_MACRO_PARITY:PASS`, plus mode markers (`..._EXTERNAL_HOST:PASS`, `..._INPROC:PASS`) | Artifacts `macro-runtime-parity-external-host-<run_id>`, `macro-runtime-parity-inproc-<run_id>`, and `macro-runtime-parity-summary-<run_id>` |
| Gate M7 / Replacement Bundle | `.github/workflows/gate-m7.yml` | Weekly schedule | `M7_STRICT_STAGE0:PASS` and `M7_REPLACEMENT_READY:PASS` | Artifact `gate-m7-logs-<run_id>` + run logs |
| Full1 / Plugin Parity | `.github/workflows/full1-plugin-parity.yml` | Weekly schedule | `FULL1_PLUGIN_PARITY:PASS` | Per-proof artifacts `full1-plugin-upstream-to-hxhx-<run_id>-<attempt>`, `full1-plugin-hxhx-to-hxhx-<run_id>-<attempt>`, `full1-plugin-upstream-host-adapter-<run_id>-<attempt>` each contain the receipt and loaded plugin file; aggregate artifact `full1-plugin-parity-summary-<run_id>-<attempt>` records same-candidate verification and checksums. |
| Gate Full1 / Strict Matrix + Macro Eval + Plugin Parity | `.github/workflows/gate-full1.yml` | Weekly schedule | `FULL1_SUITE_MATRIX:PASS`, `FULL1_MACRO_EVAL_PARITY:PASS`, and `FULL1_PLUGIN_PARITY:PASS` | Artifact `full1-summary-<run_id>` + logs from called Full1 workflows (`gate3-full1-extended`, `full1-suite-runners`, `macro-runtime-parity-weekly`, `full1-eval-native`, `full1-plugin-parity`) |
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
5. For Macro Runtime Parity, download both mode-tagged artifacts and inspect:
   - `markers.txt`
   - `macro-runtime-parity-blockers.md`
   - suite logs (`unit`, `runci`, `display/protocol`)
6. For Gate M7, Gate Full1, and semantic-diff, download artifacts and confirm expected files are present.
7. For Gate Full1, confirm both aggregate markers appear:
   - `FULL1_SUITE_MATRIX:PASS`
   - `FULL1_MACRO_EVAL_PARITY:PASS`
8. Check `Full1 / Source-Build Probe`:
   - `PASS`: source-build probe agrees with current strict matrix behavior.
   - `WARN`: do not block release by this alone; open/update a bead with artifact links and classify as bootstrap-lag, source-build instability, or parity bug.
9. Manually dispatch `Perf / HXHX KPI (Report Only)`.
10. Download KPI artifact and compare `report.json` against:
   - `docs/benchmarks/kpi/hxhx-kpi-thresholds.v1.json`
   - `docs/benchmarks/HXHX_KPI_THRESHOLDS.md`
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
