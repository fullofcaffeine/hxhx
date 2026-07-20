# CI Gates and Workflows

This page maps GitHub Actions workflow names to plain-English purpose and trigger scope.

For gate terminology (`Gate 1`, `Gate 2`, etc.), see `docs/00-project/GLOSSARY.md`.
For lane/profile context, use the canonical beginner truth table:

- `docs/02-user-guide/concepts/execution_modes.md`
- `docs/02-user-guide/concepts/what_delegates_today.md`
- Scoped 1.0 parity contract map (current lanes):
  `docs/00-project/PARITY_MAP_HAXE_4_3_7.md`
- Full 1.0 parity contract map (strict closure track):
  `docs/00-project/PARITY_MAP_FULL_1_0.md`
- Plain-language Full1 target/generator decisions:
  `docs/02-user-guide/compat/FULL1_TARGET_SCOPE.md`
- Macro runtime parity blocker list (explicit gaps before inproc-default):
  `docs/00-project/MACRO_RUNTIME_PARITY_BLOCKERS.md`
- Weekly ops audit procedure (scheduled gates + triage):
  `docs/00-project/WEEKLY_CI_EVIDENCE.md`
- Machine-readable workflow/failure ownership ledger:
  `docs/00-project/CI_EVIDENCE_OWNERSHIP.json`
- Full vs scoped release contract:
  `docs/00-project/FULL_1_0_CONTRACT.md`
- Public `Scoped 1.0` vs `Full 1.0` claim checklist:
  `docs/00-project/PUBLIC_1_0_CHECKLIST.md`
- Full1 release go/no-go decision page:
  `docs/00-project/FULL1_RELEASE_GO_NO_GO.md`
- Plain-language temporary adapter boundaries and removal checks:
  `docs/00-project/BOOTSTRAP_BRIDGE_RETIREMENT.md`

## Gate purpose by lane (quick map)

| Gate | Primary purpose in lane terms |
| --- | --- |
| Gate 0 | Fast safety checks across delegated/native lanes before merge |
| Gate 1 | Upstream macro/unit compatibility baseline (oracle lane confidence) |
| Gate 2 | Wider upstream macro/workload compatibility checks |
| Gate 3 | Native target/workflow compatibility scope checks (`--ocaml`, `--js <file>`) |
| Gate 4 | Distribution, plugin, and performance readiness checks |

## Trigger classes

- **PR required**: fast lanes expected to stay green for normal merges.
- **Nightly/scheduled**: heavier oracle/perf lanes that are too expensive for every PR.
- **Release**: strict release-readiness lanes used for publish confidence.
- **Manual**: maintainer-triggered diagnostics or targeted reruns.

## Interpreting GitHub UI State

`PR required` is the repository merge-policy classification for this project. It is the set of workflows maintainers should treat as blocking for ordinary merges, even when a checkout, fork, or private repository instance does not currently enforce GitHub branch-protection rules.

When GitHub branch protection is enabled, it should require the PR-required fast lanes listed below. When branch protection is disabled, the docs remain the source of truth for the intended baseline, and maintainers must verify these workflows manually before merging release-relevant work.

Cancelled runs on older commits are not baseline failures when they were superseded by a newer push under the same concurrency group. Evaluate the latest run for the current head SHA. A skipped `Release / Semantic Publish` workflow-run after a non-successful or superseded `CI / Core PR Checks` run is also expected and does not count as a release-lane failure by itself.

## Evidence ownership audit

`CI / Evidence Ownership Audit`
(`.github/workflows/ci-evidence-ownership.yml`) is an operations guard, not a
compiler-parity gate. It answers a narrower question: does every important
red, cancelled-without-successor, stale, or missing run point to an active
P0/P1 bead with enough information to fix and close it?

The audit runs after the workflows listed in
`docs/00-project/CI_EVIDENCE_OWNERSHIP.json` and once per day. It emits
`CI_EVIDENCE_OWNERSHIP:PASS` and uploads a JSON report when every problem has
an owner. That marker means the failure queue is accountable; it does **not**
mean the owned compiler, target, macro, plugin, performance, or Full1 failures
have passed.

The live collector retries only safe GitHub API reads after a network failure,
rate limit, or temporary `502`/`503`/`504` response. It makes at most four
attempts, honors `Retry-After` up to an eight-second per-wait cap, and records
the endpoint, response class, attempt history, and elapsed retry time if GitHub
does not recover. Authentication, permission, missing-resource, malformed-data,
and evidence-policy failures are never retried or softened. The workflow's
ten-minute timeout and cancel-superseded concurrency rule remain the outer
bound. This transport retry keeps a brief GitHub outage from impersonating a
compiler failure; it is not permission to retry a semantic gate until it passes.

## Temporary bridge guard

`npm run guard:bridge-boundaries` protects four small native/bootstrap adapters
that are still needed today. In plain language, it checks that reflective
backend calls, backend input type recovery, one OCaml-only compiler-driver hint,
and the compiler-server socket helper have not quietly spread into new files.

The guard validates both current call sites and negative fixtures, then emits
`BRIDGE_RETIREMENT_INVENTORY:PASS`. That marker means the adapters are confined
and have named removal evidence. It does **not** mean they are removed or that
Full1 compatibility has passed.

## Release policy (Scoped 1.0)

- `Release / Semantic Publish` (`.github/workflows/release.yml`) is the automation lane for normal semantic releases.
- `Gate M7 / Replacement Bundle` (`.github/workflows/gate-m7.yml`) is the strict replacement-readiness lane.
- For current 0.x automation, M7 strict is **not** a hard precondition of semantic publish.
- For Scoped 1.0 release readiness/sign-off, M7 strict **is required** and must show:
  - `M7_STRICT_STAGE0:PASS`
  - `M7_REPLACEMENT_READY:PASS`

Every publishing run also downloads the `qa-risk-route-<commit>` artifact from
the exact successful `CI / Core PR Checks` run and attempt. The release job
recomputes the changed paths from the previous release tag, checks the policy
digest and required Q tier, and verifies the exact successful `Tests` aggregate
(the final CI job that checks every job required by that tier). It refuses
stale, skipped, cancelled, lower-tier, or different-commit evidence before
invoking semantic-release. A manual
publishing run must name `core_run_id` and `core_run_attempt`; a non-publishing
Full1 provenance dry run remains allowed without them.

For Full 1.0 claims, use the strict Full contract and markers in:

- `docs/00-project/FULL_1_0_CONTRACT.md`
- `docs/00-project/PUBLIC_1_0_CHECKLIST.md`

The semantic-release publication path blocks candidate versions `>=1.0.0`
through `scripts/release/full1-release-enforcement.js`. A Full1 release must
first run the manual prepublication RC workflow. The release job downloads the
exact RC run attempt, verifies its artifact digest, checks out the candidate
SHA named by the receipt, and recomputes the required evidence before it can
accept `FULL1_RELEASE_GO:PASS`.

For strict Full1 compatibility claims within the declared target/generator
scope, the primary proof is the relevant upstream Haxe 4.3.7 suite matrix
running under `hxhx`.
Repo-local focused regressions and bridge tests are supporting evidence for diagnosis and closure work; they do not replace upstream-suite proof.

## PR-required fast lanes

| Workflow | File | Purpose | Trigger class | Triggers |
| --- | --- | --- | --- |
| `CI / Core PR Checks` | `.github/workflows/ci.yml` | Core guardrails, tests, and scoped smokes for baseline safety. | **PR required** (+manual exact-commit proof) | `push`, `pull_request`, manual |
| `Security / CodeQL` | `.github/workflows/codeql.yml` | Static security analysis for JS/TS surfaces. | **PR required** (+scheduled) | `push`, `pull_request`, weekly schedule |
| `Gate 1 Lite / Upstream Macro Unit Smoke` | `.github/workflows/gate1-lite.yml` | Fast upstream unit macro compatibility smoke. | **PR required** | `push`, `pull_request` |
| `Gate 2 Lite / Workloads Smoke` | `.github/workflows/gate2-lite.yml` | Fast workload/macro compatibility smoke. | **PR required** | `push`, `pull_request` |
| `Gate 3 Builtin / Native Target Smoke` | `.github/workflows/gate3-builtin.yml` | Native builtin target smoke (`ocaml` and `js`) plus JS oracle smoke lane. | **PR required** (+scheduled/manual) | `push`, `pull_request`, weekly schedule, manual |
| `Oracle / JS Smoke (Upstream vs HXHX)` | `.github/workflows/js-oracle-smoke.yml` | Focused JS behavior comparison against upstream oracle. | **PR required** (+manual) | `push`, `pull_request`, manual |
| `Stdlib Portable / Tier1` | `.github/workflows/stdlib-portable-lite.yml` | Tier1 portable stdlib conformance checks. | **PR required** | `push`, `pull_request` |
| `Stdlib / Semantic Diff` | `.github/workflows/semantic-diff.yml` | Scoped semantic-diff-lite canary for stdlib/runtimegen-sensitive PRs, plus nightly expanded lane. | **PR required** (+scheduled/manual) | `push`, `pull_request`, weekly schedule, manual |

PR-required baseline is: **guardrails + core tests + scoped smokes** (`ci.yml`, gate-lite workflows, builtin smoke, JS oracle, stdlib tier1, semantic diff smoke) when the changed surface can affect those contracts. Documentation and tracking-only changes use the cheap aggregate described below instead of starting compiler toolchains.

### Risk-routed PR cost

`scripts/ci/qa-risk-policy.json` is the machine-readable Q0-Q4 policy, and
`scripts/ci/qa-risk-classifier.js` classifies an immutable changed-path
inventory. Pull requests use their exact proposed diff. A default-branch push
uses every change since the latest reachable `vMAJOR.MINOR.PATCH` release tag,
so a documentation or snapshot follow-up cannot hide an earlier unreleased
compiler/runtime change whose expensive proof was cancelled. A version-looking
tag resets this range only when its commit has both the matching automated
release message and the matching package version. The result is
uploaded as `qa-risk-route-<commit>` and records the producer commit, release
base, inventory digest, policy digest, changed paths, selected tier, reasons,
and requested workloads. If the required Git history or release boundary is
unavailable, routing fails safe to Q3.

- **Q0:** documentation, repository guidance, and Beads-only changes run the
  Core route, cheap documentation guards, full-history secret scan, and stable
  `Tests` aggregate. They do not install an OCaml/Haxe toolchain or build
  `hxhx`.
- **Q1:** standalone `reflaxe.ocaml` examples, package consumers, and authoring
  tools add Guardrails and the installed-package compile/build/run proof. The
  hxhx-only Gate 1, Gate 3, JS-oracle, and KPI workflows stay asleep; standalone
  OCaml workload, stdlib, semantic-diff, performance, and security checks keep
  their own normal trigger contracts.
- **Q2:** target/compiler changes add the bounded Stage0-free, JS-native,
  plugin, and Core test-shard canaries.
- **Q3:** central representation/runtime, bootstrap, plugin ABI, workflow, and
  toolchain changes are marked for the large `hxhx` consumer and authentic
  compiler-promotion evidence at their owning workflow boundaries. Core
  already runs its full compiler canaries for this tier. The retained
  authentic compiler workload remains owned by `haxe_ocaml-bxwut`; until that
  Bead lands, its scheduled/manual pilot is precursor evidence rather than a
  per-change ABI proof.
- **Q4:** release evidence remains explicit and is never inferred from an
  ordinary documentation or source change.

Unknown code paths fail safe to Q2. A push or pull request whose immutable
change inventory cannot be established escalates to Q3. Schedules and ordinary
manual requests also require at least Q3; a manual Q4 request is explicit.

To validate an exact commit at the high-risk boundary, run `CI / Core PR Checks`
manually and select `Q3` (the default). Select `Q4` only when release evidence is
actually required. From the command line, the equivalent is
`gh workflow run ci.yml --ref <branch-or-commit> -f qa_tier=Q3`. The selected
tier is a minimum: a manual request cannot downgrade the policy, and its receipt
still records the exact commit and reason. This route is preferable to creating
a no-op source change merely to wake expensive checks.

Core CI is the cheap always-present aggregate. The other broad automatic
workflows ignore the exact Q0 documentation/tracking pattern set, which is
checked by `scripts/ci/qa-risk-workflow-contract-check.js`. If branch
protection is enabled, require the stable Core `Tests` aggregate; do not require
a conditional workflow name whose trigger is intentionally absent at Q0.
Scheduled, manual, and release gates are not weakened by Q0 path routing.
The same guard owns a narrower Q1 ignore list for workflows whose only purpose
is exercising `hxhx`; mixed changes and hxhx-specific examples still escalate
to Q2 and wake those consumers.

At Q2, the Core workflow runs 105 of the 106 canonical `npm test` commands as
three clean-runner shards after Guardrails: focused compiler regressions,
macro-host integration, and portable/snapshot/example coverage. Stage0-free,
JS-native, and strict plugin canaries remain required at that tier. Q3 adds the
single `test:hxhx-targets` shard, whose large application/bootstrap workload
measured about 24 runner minutes. Q4 inherits the complete Q3 set.

The macro-host integration shard compiles one request-local test host containing
the reviewed union of its three consumers' entrypoints. Every consumer checks
the candidate commit, plan digest, executable path, SHA-256 digest, byte count,
and its own required entrypoints before running; the shard records each outcome
and then removes the executable. Running any of those npm tests directly still
builds its own narrow host. This removes duplicate native compilation without
introducing a global cache or making standalone developer tests depend on CI.

The historical check name `Tests` is a fail-closed aggregate. Its versioned
manifest records the minimum tier for every prerequisite, so only a skip
authorized by the exact route is accepted. A failed route, secret scan,
required job, cancelled job, unexpected skip, or missing result fails the
aggregate. Local `npm test` remains the canonical complete serialized command
with all 106 entries. The measured baseline and shard rationale are recorded in
`docs/benchmarks/HXHX_CORE_TEST_CRITICAL_PATH_2026_07_18.md`.

Stable success markers used by required lanes:

- `STAGE0_FREE_SMOKE:PASS` (`ci.yml` job `stage0-free-smoke`)
- `JS_NATIVE_SMOKE:PASS` (`ci.yml` job `js-native-smoke`)
- `PLUGIN_MATRIX_STRICT:PASS` (`ci.yml` job `plugin-matrix`)
- `CORE_TESTS_AGGREGATE:PASS` (`ci.yml` job `Tests`)
- `GATE1_LITE:PASS` (`gate1-lite.yml`)
- `GATE2_LITE:PASS` (`gate2-lite.yml`)
- `SEMANTIC_DIFF_LITE_SCOPE:RUN` or `SEMANTIC_DIFF_LITE_SCOPE:SKIP_NO_RELEVANT_CHANGES` (`semantic-diff.yml` job `Semantic diff (PR smoke)`)
- `SEMANTIC_DIFF_LITE:PASS` (emitted when scoped semantic-diff lane executes)

Semantic-diff PR artifacts are uploaded as `semantic-diff-pr-artifacts` and include:

- `changed_files.txt` (revision file list)
- `matched_files.txt` (scoped trigger matches)
- `semantic_diff_lite.marker.txt` (scope + pass/skip markers)
- lane reports under `.artifacts/semantic-diff/pr/**` when the scoped lane runs

## Scheduled compatibility and release gates (slow lanes)

| Workflow | File | Purpose | Trigger class | Triggers |
| --- | --- | --- | --- |
| `Gate 1 / Upstream Macro Unit Compatibility` | `.github/workflows/gate1.yml` | Full upstream unit macro compatibility baseline. | **Nightly/scheduled** | weekly schedule, manual |
| `Gate 2 / Upstream Macro Workloads` | `.github/workflows/gate2.yml` | Wider upstream `runci` macro workload checks. | **Nightly/scheduled** | weekly schedule, manual |
| `Macro Runtime Parity (Weekly)` | `.github/workflows/macro-runtime-parity-weekly.yml` | Runs upstream macro + display checks in both macro runtime modes (`external-host`, `inproc`). It also builds one real Haxe-authored project macro and runs it through both modes. The summary job opens all three uploaded proof packages and checks their commit, run, markers, and file hashes before it emits the macro pass markers. | **Nightly/scheduled + Release + Reusable** | weekly schedule, manual, `release`, `workflow_call` |
| `Full1 / Eval Native` | `.github/workflows/full1-eval-native.yml` | Runs the upstream-aligned native eval/interp baseline (`tests/unit/compile-macro.hxml`) in strict stage0-forbidden mode. Its v2 receipt names the exact candidate commit, run attempt, and Haxe 4.3.7 oracle checkout. | **Release + Manual + Reusable** | manual, `release`, `workflow_call` |
| `Full1 / Macro Eval Evidence` | `.github/workflows/full1-macro-eval.yml` | Runs the macro and native-eval proof workflows for one commit, downloads both verified summaries, and emits `FULL1_MACRO_EVAL_PARITY:PASS` only after their contents agree. In plain language, it reads the proof files instead of trusting two green job labels. | **Manual + Reusable** | manual, `workflow_call` |
| `Gate 3 / Upstream Target Matrix` | `.github/workflows/gate3.yml` | Upstream target/workflow compatibility matrix checks. | **Nightly/scheduled** | weekly schedule, manual |
| `Gate 3 Full1 / Extended Targets Strict` | `.github/workflows/gate3-full1-extended.yml` | Full1 strict extended target matrix (`Macro,Js,Neko,Hl,Python,Java,Cs,Cpp,Lua,Php`) with no-skip enforcement, bounded target-level parallelism, controlled inner timeout, JSON summary, and phase-timing artifacts. `Cpp` includes upstream Cppia checks; `Hl` includes its required bytecode and C-output checks. JVM, Flash, XML, and JSON decisions are explicit in the target-scope doc rather than silently skipped. | **Nightly/scheduled** | weekly schedule, manual |
| `Full1 / Suite Runners Strict` | `.github/workflows/full1-suite-runners.yml` | Full1 strict suite runners for `misc`, `server`, `threads`, `optimization`, `display` with per-suite log, summary, and phase-timing artifacts. Inproc suites (`misc`, `threads`, `display`) do not download or export a macro host; current external-host suites (`server`, `optimization`) consume the shared macro-host artifact until inproc parity catches up. | **Nightly/scheduled** | weekly schedule, manual |
| `Full1 / Source-Build Probe` | `.github/workflows/full1-source-probe.yml` | Non-blocking diagnostic lane: force source build (`HXHX_FORCE_STAGE0=1`) and run narrowed strict suites (`server`, `optimization`) to detect bootstrap-lagged fixes without destabilizing the primary matrix. Summary JSON stays compact; child processes are hard-timeboxed and full logs are separate artifacts. | **Nightly/scheduled diagnostic** | weekly schedule, manual |
| `Full1 / Bootstrap-Source Reconciliation` | `.github/workflows/full1-bootstrap-source-reconcile.yml` | Diagnostic evidence lane that runs `server` + `optimization` in both bootstrap-built and source-built lanes on the same commit, then classifies each blocker as bootstrap lag vs source-build instability vs real parity bug. | **Nightly/scheduled diagnostic** | weekly schedule, manual |
| `Gate Perf Full1 / HXHX vs Haxe` | `.github/workflows/gate-perf-full1.yml` | Release-blocking Full1 performance parity lane. Uploads raw KPI evidence, phase timings, and evaluated Full1 perf summary, then emits `FULL1_PERF_PARITY:PASS` only through the evaluator after the policy passes. | **Nightly/scheduled + Release + Reusable** | weekly schedule, `release`, manual, `workflow_call` |
| `Full1 / Plugin Parity` | `.github/workflows/full1-plugin-parity.yml` | Runs the three required `reflaxe.ocaml` plugin proof rows, uploads each receipt plus the plugin file it loaded, and emits `FULL1_PLUGIN_PARITY:PASS` only after the aggregate verifies the exact same-run artifacts, candidate commit, stage0 rules, checksums, load result, and runtime output. | **Nightly/scheduled + Release + Reusable** | weekly schedule, `release`, manual, `workflow_call` |
| `Gate Full1 / Strict Matrix + Macro Eval + Plugin Parity` | `.github/workflows/gate-full1.yml` | Full1 aggregate gate that composes strict suite runners, strict extended Gate3, artifact-verified macro/eval evidence, and plugin parity. Before repeating `FULL1_MACRO_EVAL_PARITY:PASS`, the gate downloads and validates the focused workflow's combined receipt. | **Nightly/scheduled + Release + Reusable** | weekly schedule, `release`, manual, `workflow_call` |
| `Gate Full1 RC / Release Go-No-Go` | `.github/workflows/gate-full1-rc.yml` | Prepublication Full1 decision gate. It downloads and verifies same-run child artifacts, writes a candidate-bound `full1-rc-summary.v2` receipt, and emits `FULL1_RELEASE_GO:PASS` only when every required artifact and marker is valid. Its `provenance_only` mode safely proves a no-go handoff without running the expensive matrix. | **Prepublication manual** | manual |
| `Gate M7 / Replacement Bundle` | `.github/workflows/gate-m7.yml` | Strict replacement-readiness lane (scheduled/manual + release-event verification). | **Nightly/scheduled + Release** | weekly schedule, `release`, manual |
| `Reflaxe OCaml / Package Artifact Matrix` | `.github/workflows/reflaxe-ocaml-package-matrix.yml` | Builds one deterministic source ZIP and gives that exact artifact to Ubuntu and macOS. Each host performs the isolated install/native-run proof, then measures six clean target-performance scenarios plus report-only cold-output, unchanged-warm, and one-file-change samples outside the checkout. Separate aggregate jobs open the receipts before emitting `RO_PACKAGE_ARTIFACT_MATRIX:PASS` and `RO_TARGET_PERF_PLATFORM_MATRIX:PASS`; absolute timings remain per host. | **Nightly/scheduled product evidence** | relevant pushes/PRs, weekly schedule, manual |
| `Stdlib Portable / Full` | `.github/workflows/stdlib-portable-full.yml` | Full portable stdlib conformance lane. | **Nightly/scheduled** | weekly schedule, manual |
| `Smoke / Stage0 Source Build` | `.github/workflows/stage0-source-smoke.yml` | Source-only stage0 smoke plus a fail-closed regeneration profile. The profile must finish successfully and include timing evidence for the main C++ backend and its extracted signature table before hotspot comparison runs. | **Nightly/scheduled** | daily schedule, manual |

Heavy Full1 workflows use event+ref scoped concurrency and cancel stale in-progress reruns so manual retries and scheduled evidence runs do not pile up behind obsolete work.

Heavy Full1 OCaml/dune worker and cache policy:
- Full1 workflows that build `hxhx`, macro host artifacts, or plugin/eval proof binaries keep `HXHX_DUNE_JOBS=auto` explicit.
- Fixed worker caps such as `HXHX_DUNE_JOBS=2` or `HXHX_DUNE_JOBS=4` are allowed only for a workflow-specific memory/throughput experiment with fresh evidence.
- Current benchmark source: `docs/benchmarks/STAGE0_BOOTSTRAP_THROUGHPUT_2026_03_05.md`.
  In that bounded matrix, fixed worker settings increased peak RSS compared with `auto`, so `auto` remains the default.
- Workflows that already require `ocaml/setup-ocaml` for opam-backed proof setup keep `dune-cache: true`; apt-based Full1 lanes should not be converted to opam/setup-ocaml without comparable timing/RSS evidence.

All mandatory Full1 phase-timing summaries use
`full1-phase-timing-summary.v2`. Each downloaded summary identifies the exact
commit, GitHub run and attempt, workflow/job, machine, tool versions, tracked
source state at summary time, and the raw phase rows. Missing tools are written
as `unavailable`, and paths stay repository-safe. The validator recomputes the
phase total and rejects mixed-commit, mixed-run, malformed, or absolute-path
evidence. The displayed total means only the phases that were timed; it is not
necessarily the complete GitHub job wall time. The evidence is report-only and
does not emit a Full1 release or performance-pass marker.

Full1 suite runner timing artifacts:
- build jobs emit `build_hxhx.timings.*` and `build_macro_host.timings.*`
- suite jobs emit `<suite>.timings.jsonl`, `<suite>.timings.summary.json`, and `<suite>.timings.md`
- timing Markdown is appended to `GITHUB_STEP_SUMMARY` for quick before/after review

Full1 perf timing artifacts:
- raw artifacts include `full1-perf.timings.jsonl`
- evaluated artifacts include `full1-perf.timings.summary.json` and `full1-perf.timings.md`
- measured phases are `build_hxhx_binary`, `build_macro_host_binary`, `kpi_benchmark`, `eval_evidence`, `suite_evidence`, and `perf_evaluator`

Full1 native eval timing artifacts:
- raw artifacts include `full1-eval-native.timings.jsonl`
- evaluated artifacts include `full1-eval-native.timings.summary.json` and `full1-eval-native.timings.md`
- measured phases include host/toolchain setup, npm/Haxe dependency prep, upstream checkout fetch, `build_hxhx_binary`, and `native_eval_runner`

Full1 plugin parity timing artifacts:
- proof artifacts include `<proof-id>.timings.jsonl`, `<proof-id>.timings.summary.json`, and `<proof-id>.timings.md`
- measured phases include OCaml package prep, npm/Haxe dependency prep, optional upstream eval-host preparation, and `plugin_proof`
- timing Markdown is appended to `GITHUB_STEP_SUMMARY` for each proof row

Macro runtime parity timing artifacts:
- mode-tagged artifacts include `<mode>.timings.jsonl`, `<mode>.timings.summary.json`, and `<mode>.timings.md`
- the external-host artifact includes `macro-runtime-host-receipt.json`, the exact host executable, its build logs, and `MACRO_RUNTIME_EXTERNAL_HOST_ARTIFACT:PASS`
- the receipt binds the host to the candidate commit and committed macro-host snapshot tree, records its SHA-256 digest, and verifies the real RPC handshake; later workload steps revalidate it
- release evidence sets `HXHX_FORBID_STAGE0=1`, disables `HXHX_MACRO_HOST_AUTO_BUILD`, and treats a recursive host build as a hard error
- measured phases include host/toolchain setup, npm/Haxe dependency prep, upstream checkout fetch, `build_hxhx_binary`, `prepare_external_macro_host`, unit macro, runci macro, and display/protocol checks
- timing Markdown is appended to `GITHUB_STEP_SUMMARY` for each runtime mode

Full1 Gate3 extended timing artifacts:
- raw artifacts include `gate3-full1-extended.timings.jsonl`
- evaluated artifacts include `gate3-full1-extended.timings.summary.json` and `gate3-full1-extended.timings.md`
- measured phases include host/toolchain setup, npm/Haxe dependency prep, upstream checkout fetch, and `strict_extended_gate3_matrix`
- `strict_extended_gate3_matrix` runs targets through `scripts/ci/run-gate3-targets-parallel.js`, which builds one shared `hxhx`, creates isolated upstream worktrees per target, and runs a bounded number of target jobs at once.
- `strict_extended_gate3_matrix` is wrapped in an inner timeout below the job timeout so overruns fail with uploaded artifacts instead of GitHub job cancellation being mistaken for a successful matrix phase.

Native iteration latency contract:
- `docs/00-project/NATIVE_ITERATION_LATENCY_CONTRACT.md` defines the project-level buckets for focused local smokes, bootstrap regeneration, stage0-free `hxhx` rebuilds, native Reflaxe artifact loops, and Full1 gates.
- `scripts/ci/native-iteration-latency-contract-check.js` validates that the contract stays connected to existing timing/reporting surfaces.
- The contract marker is `NATIVE_ITERATION_LATENCY_POLICY:PASS`; it is a policy/coverage marker only, not measured speed evidence.

Diagnostic Full1 timing scope:
- `.github/workflows/full1-source-probe.yml` and `.github/workflows/full1-bootstrap-source-reconcile.yml` are intentionally outside the mandatory per-phase timing-artifact contract while they remain non-blocking diagnostic lanes.
- Their purpose is source-vs-bootstrap failure classification, not release throughput regression detection. They already publish compact JSON summaries with run duration, build/suite timeout status, and pass/warn classification data.
- Do not treat missing `*.timings.jsonl`, `*.timings.summary.json`, or `*.timings.md` artifacts from these diagnostic workflows as a coverage gap.
- If either diagnostic workflow is promoted to a release-blocking or reusable Full1 gate, add the same phase-timing artifact contract used by the heavy Full1 lanes before making it blocking.

`Gate M7` release/scheduled runs force strict settings:
- `HXHX_M7_PROFILE=full`
- `HXHX_M7_STRICT=1`
- `HXHX_FORBID_STAGE0=1`

Before those checks start, strict M7 builds one native `hxhx` executable and
one native macro host from the committed stage0-free snapshots. Later checks
reuse those exact files instead of rebuilding the compiler for every row. The
`m7-shared-artifacts.v2` receipt binds both executable hashes and the macro
host's companion interface-folder hash to the current commit, clean tracked
tree, and committed snapshot trees. Native macro plugins need those interfaces
in the same way C/C++ code needs matching headers. The receipt is validated
before and after every check. In plain language: M7 shares the oven, not the
test results; each compatibility test still runs independently.

Expected strict markers in logs:
- `M7_SHARED_ARTIFACTS:PASS`
- `M7_STRICT_STAGE0:PASS`
- `M7_REPLACEMENT_READY:PASS`

Macro runtime mode policy (native lanes):
- default mode is `inproc`
- fallback/debug mode is `external-host`
- rollback knobs:
  - env: `HXHX_MACRO_RUNTIME_MODE=external-host`
  - flag: `--hxhx-macro-runtime external-host`
- audit marker: `hxhx_macro_runtime_mode=<mode>`

Macro runtime parity weekly markers:
- `MACRO_RUNTIME_PARITY_UNIT_EXTERNAL_HOST:PASS`
- `MACRO_RUNTIME_PARITY_UNIT_INPROC:PASS`
- `MACRO_RUNTIME_PARITY_RUNCI_EXTERNAL_HOST:PASS`
- `MACRO_RUNTIME_PARITY_RUNCI_INPROC:PASS`
- `MACRO_RUNTIME_PARITY_DISPLAY_PROTOCOL_EXTERNAL_HOST:PASS`
- `MACRO_RUNTIME_PARITY_DISPLAY_PROTOCOL_INPROC:PASS`
- `MACRO_RUNTIME_PARITY_EXTERNAL_HOST:PASS`
- `MACRO_RUNTIME_PARITY_INPROC:PASS`
- `MACRO_RUNTIME_PARITY_WEEKLY:PASS`
- `FULL1_MACRO_PARITY:PASS`

Full1 extended Gate3 marker:

- `FULL1_GATE3_EXTENDED_TARGETS:PASS` (`.github/workflows/gate3-full1-extended.yml`)

Full1 target-scope contract marker:

- `FULL1_TARGET_SCOPE_CONTRACT:PASS`
  (`scripts/ci/full1-target-scope-check.js`; policy source:
  `docs/02-user-guide/compat/FULL1_TARGET_SCOPE.md`)

This policy marker means the inventory, matrix, and docs agree. It does not
mean the targets themselves passed; that requires the Gate3 marker above.

Full1 strict suite runner markers:

- `FULL1_SUITE_MISC:PASS`
- `FULL1_SUITE_SERVER:PASS`
- `FULL1_SUITE_THREADS:PASS`
- `FULL1_SUITE_OPTIMIZATION:PASS`
- `FULL1_SUITE_DISPLAY:PASS`

Full1 aggregate matrix marker:

- `FULL1_SUITE_MATRIX:PASS` (`.github/workflows/gate-full1.yml`)

Full1 native eval marker:

- `FULL1_EVAL_NATIVE:PASS` (`.github/workflows/full1-eval-native.yml`)

Full1 macro/eval aggregate marker:

- `FULL1_MACRO_EVAL_PARITY:PASS` (`.github/workflows/gate-full1.yml`)

Full1 plugin parity marker:

- `FULL1_PLUGIN_PARITY:PASS` (`.github/workflows/full1-plugin-parity.yml` and `.github/workflows/gate-full1.yml`)

Full1 flake policy marker:

- `FULL1_FLAKE_POLICY:PASS` (`scripts/ci/full1-flake-policy-check.js`;
  policy source: `docs/00-project/FULL1_FLAKE_POLICY.md`; allowlist source:
  `docs/00-project/FULL1_FLAKE_ALLOWLIST.json`)

Full1 performance policy marker:

- `FULL1_PERF_POLICY:PASS` (`scripts/ci/full1-perf-policy-check.js`)

Full1 measured performance parity marker:

- `FULL1_PERF_PARITY:PASS` (`.github/workflows/gate-perf-full1.yml`;
  evaluator: `scripts/ci/full1-perf-evaluator.js`; policy source:
  `docs/00-project/FULL1_PERF_PARITY_POLICY.md`)

Full1 release go/no-go marker:

- `FULL1_RELEASE_GO:PASS` (`.github/workflows/gate-full1-rc.yml`;
  collector: `scripts/ci/full1-rc-artifact-collector.js`; evaluator:
  `scripts/ci/full1-rc-gate.js`; release downloader:
  `scripts/release/download-full1-rc-artifact.js`; scope source:
  `docs/02-user-guide/compat/full-1.0-scope.json`; decision page:
  `docs/00-project/FULL1_RELEASE_GO_NO_GO.md`)

Full1 semantic-release enforcement marker:

- `FULL1_RELEASE_ENFORCEMENT:PASS` (`scripts/release/full1-release-enforcement.js`;
  fixture coverage: `scripts/release/full1-release-enforcement-fixture-test.js`
  and `scripts/release/download-full1-rc-artifact-fixture-test.js`)

Gate Full1 also requires green reusable jobs from:

- `.github/workflows/macro-runtime-parity-weekly.yml`
- `.github/workflows/full1-eval-native.yml`

Full1 source-build probe marker (non-blocking diagnostic lane):

- `FULL1_SOURCE_BUILD_PROBE:PASS` or `FULL1_SOURCE_BUILD_PROBE:WARN` (`.github/workflows/full1-source-probe.yml`)

Full1 bootstrap-source reconciliation marker (diagnostic classification lane):

- `FULL1_BOOTSTRAP_SOURCE_RECONCILIATION:PASS` or `FULL1_BOOTSTRAP_SOURCE_RECONCILIATION:WARN` (`.github/workflows/full1-bootstrap-source-reconcile.yml`)

Local suite runner guide for Full1 suite scaffolding (`misc/server/threads/optimization/display`):

- `docs/01-getting-started/RUN_FULL1_SUITES_LOCALLY.md`

## Report-only / utility workflows

| Workflow | File | Purpose | Trigger class | Triggers |
| --- | --- | --- | --- |
| `Perf / HXHX KPI (Report Only)` | `.github/workflows/hxhx-kpi-report.yml` | KPI telemetry/report lane (non-blocking). Its `hxhx.kpi.v2` report identifies the commit, clean-source state, runner/CPU, toolchains, compiler artifact kind, measurement method, and raw samples. A manual opt-in measures bytecode and native executables sequentially in the same job and emits a checked diagnostic comparison; native fallback to bytecode is rejected as missing native evidence. | **Manual + PR visibility** | `push`, `pull_request`, manual |
| `Perf / M14 Portable vs Metal (Report Only)` | `.github/workflows/m14-perf-report.yml` | Portable vs metal benchmark reports (non-blocking). | **Manual + PR visibility** | `push`, `pull_request`, manual |
| `Pilot / Reflaxe.Elixir Todo Promotion` | `.github/workflows/reflaxe-elixir-pilot.yml` | Scheduled/manual promotion pilot against pinned external todo-app source checkout, uploading promotion/load evidence. | **Manual + scheduled diagnostic** | weekly + manual |
| `Utility / Bootstrap Regen Benchmark` | `.github/workflows/bootstrap-regen-bench.yml` | Report-only bootstrap regeneration timings with commit, machine, toolchain, configuration, raw-run, and median evidence. | **Manual utility** | manual |
| `Release / Semantic Publish` | `.github/workflows/release.yml` | Automated semantic release publication after CI success. | **Release automation** | workflow-run from CI, manual |
