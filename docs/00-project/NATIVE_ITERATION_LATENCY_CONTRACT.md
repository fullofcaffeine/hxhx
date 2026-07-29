# Native Iteration Latency Contract

Last audited: 2026-07-22

This document defines the project-level latency north star for native
`hxhx + reflaxe.ocaml` work. It is a measurement contract, not a claim that the
current implementation is already fast enough.

The user-facing goal is simple: common compiler and target-development loops
should get materially faster as `hxhx` and Reflaxe target promotion become
stage0-free and native by default, while strict Haxe `4.3.7` oracle gates remain
available for release proof.

The deeper product goal is Haxe-authored compiler performance: compiler and
backend logic should be pleasant to write in Haxe, then promotable through
`reflaxe.ocaml` into OCaml-backed native plugin, builtin, or bootstrap artifacts
whose runtime profile is in the same class as direct OCaml compiler code.
`hxhx` itself is Haxe-authored, not Reflaxe-authored; the relevant bet is that
`reflaxe.ocaml` can compile and bootstrap those Haxe sources into practical
native artifacts. In other words, `hxhx` may be created with Reflaxe as a
native compilation route, but the compiler core should stay ordinary Haxe
unless a separate architecture bead deliberately changes that boundary. Over
time, `hxhx`/Reflaxe-specific optimization should make
those promoted artifacts candidates for better-than-straightforward
hand-written performance when the compiler pipeline can specialize generated
code safely.

The accepted Oracle boundary for this distinction lives in
`docs/00-project/ORACLE_CHECKPOINT_REFLAXE_HXHX_FRAMEWORK_BOUNDARY_2026_07_03.md`.
It treats Reflaxe as a native artifact and backend/plugin seam for `hxhx`, not
as the default owner of compiler-core semantics.

## Why Current Loops Are Slow

Small compiler fixes can currently pay several costs that are only loosely
related to the code being changed:

- stage0-driven Haxe compilation of the compiler or bootstrap snapshots,
- Reflaxe output generation before native OCaml can be built,
- Dune/native linking for generated OCaml artifacts,
- broad repo guardrails such as provenance, generated-snapshot, and format
  checks,
- upstream-derived oracle gates that intentionally run larger compatibility
  suites.

Native `hxhx + reflaxe.ocaml` should reduce the repeated stage0/delegated part
of this loop. It will not eliminate every cost. Target-language compilers,
OCaml native linking, full upstream oracle suites, and report-only performance
lanes can still be the dominant work.

## Measurement Buckets

Measure these buckets separately:

- focused local smoke: the smallest target/backend or compiler smoke that proves
  the current edit,
- bootstrap snapshot regeneration: generated OCaml snapshot refresh and
  verification,
- stage0-free hxhx rebuild: rebuilding the native compiler from committed
  snapshots or current source without runtime stage0 delegation,
- native Reflaxe artifact loop: build a Reflaxe target/compiler into an
  OCaml-backed plugin or builtin artifact, then run a focused smoke,
- Full1 evidence gates: strict upstream-suite, macro/eval, plugin, and
  performance gates used for release claims.

Do not compare a focused smoke directly to Full1. They answer different
questions.

## Targets

The initial target is evidence discipline first, then speed. A release or public
performance claim must use measured medians from the relevant runner class.

<!-- NATIVE_ITERATION_LATENCY_POLICY_JSON_START -->
```json
{
  "schema": "native-iteration-latency-policy.v1",
  "contractMarker": "NATIVE_ITERATION_LATENCY_POLICY:PASS",
  "haxeCompatibilityBaseline": "4.3.7",
  "primaryOwnerBead": "haxe_ocaml-850ii",
  "completedFoundationBead": "haxe.ocaml-5rjl",
  "timingTool": "scripts/ci/full1-phase-timing.js",
  "policyGuard": "scripts/ci/native-iteration-latency-contract-check.js",
  "activeEvidenceLoop": {
    "full1PhaseTimingReportSchema": "full1-phase-timing-summary.v2",
    "full1PhaseTimingReportValidator": "scripts/ci/full1-phase-timing.js",
    "m7SharedArtifactReceiptSchema": "m7-shared-artifacts.v2",
    "m7SharedArtifactReceiptValidator": "scripts/ci/m7-shared-artifacts.js",
    "m7SharedArtifactRunner": "scripts/hxhx/run-replacement-ready.sh",
    "reportSchema": "hxhx.kpi.v2",
    "reportValidator": "scripts/ci/hxhx-kpi-report-validator.js",
    "reportWorkflow": ".github/workflows/hxhx-kpi-report.yml",
    "artifactComparisonSchema": "hxhx.kpi-artifact-comparison.v1",
    "artifactComparisonValidator": "scripts/ci/hxhx-kpi-artifact-comparison.js",
    "artifactComparisonRunner": "scripts/hxhx/bench-kpi-artifact-comparison.sh",
    "bootstrapReportSchema": "hxhx.bootstrap-regen-benchmark.v1",
    "bootstrapReportValidator": "scripts/ci/bootstrap-regen-benchmark-report.js",
    "bootstrapReportWorkflow": ".github/workflows/bootstrap-regen-bench.yml",
    "stage0FreeBuildReportSchema": "hxhx.stage0-free-build.v1",
    "stage0FreeBuildReportValidator": "scripts/ci/stage0-free-build-benchmark-report.js",
    "stage0FreeBuildReportRunner": "scripts/hxhx/bench-stage0-free-build.sh",
    "nativePluginLoopReportSchema": "hxhx.native-plugin-loop.v1",
    "nativePluginLoopReportValidator": "scripts/ci/native-plugin-loop-benchmark-report.js",
    "nativePluginLoopReportRunner": "scripts/hxhx/bench-native-plugin-loop.sh",
    "compilerScaleReflaxeServerReportSchema": "hxhx.compiler-scale-reflaxe-server.v1",
    "compilerScaleReflaxeServerEvidence": "scripts/ci/compiler-scale-reflaxe-server-evidence.js",
    "compilerScaleReflaxeServerFixture": "scripts/ci/compiler-scale-reflaxe-server-evidence-fixture-test.js",
    "compilerScaleReflaxeServerRunner": "scripts/hxhx/run-compiler-scale-reflaxe-server-proof.sh",
    "localCapacityPreflightSchema": "hxhx.local-capacity-preflight.v2",
    "localCapacityPreflight": "scripts/hxhx/check-local-capacity.js",
    "localCapacityPreflightFixture": "scripts/ci/local-capacity-preflight-fixture-test.js",
    "localCapacityQueue": "scripts/hxhx/local-capacity-queue.js",
    "localCapacityQueueFixture": "scripts/ci/local-capacity-queue-fixture-test.js",
    "localMemoryCapacity": "scripts/hxhx/local-memory-capacity.js",
    "localMemoryCapacityFixture": "scripts/ci/local-memory-capacity-fixture-test.js",
    "cooperativeHeavyRunLeaseSchema": "haxe-family.heavy-run-lease.v1",
    "cooperativeHeavyRunLease": "scripts/hxhx/local-heavy-run-lease.js",
    "cooperativeHeavyRunLeaseWrapper": "scripts/hxhx/with-heavy-run-lease.js",
    "cooperativeHeavyRunLeaseFixture": "scripts/ci/local-heavy-run-lease-fixture-test.js",
    "cooperativeHeavyRunLeaseCrossRepositoryFixture": "scripts/ci/cross-repository-heavy-run-lease-fixture-test.js",
    "developerCurrentSourceInputSchema": "hxhx.current-source-inputs.v1",
    "developerCurrentSourceInputFingerprint": "scripts/hxhx/current-source-input-fingerprint.js",
    "developerCurrentSourceCacheFixture": "scripts/ci/developer-current-source-cache-fixture-test.js"
  },
  "measurementBuckets": [
    {
      "id": "focused-local-smoke",
      "purpose": "Fast edit validation for a bounded compiler/backend change.",
      "target": "Median runtime should stay comfortably below the matching broad gate; warn if local p50 grows beyond 30s for a previously focused smoke.",
      "evidence": [
        "package.json",
        "scripts/ci/full1-phase-timing.js",
        "scripts/hxhx/current-source-input-fingerprint.js",
        "scripts/ci/developer-current-source-cache-fixture-test.js"
      ]
    },
    {
      "id": "bootstrap-snapshot-regeneration",
      "purpose": "Refresh committed OCaml bootstrap snapshots when repo-owned Haxe compiler sources change.",
      "target": "Native/stage0-free refresh should become materially faster than the stage0/delegated baseline before a 1.0 speed claim; until then, record medians and artifact footprint.",
      "evidence": [
        "scripts/hxhx/bench-bootstrap-regen.sh",
        "scripts/ci/bootstrap-regen-benchmark-report.js",
        ".github/workflows/bootstrap-regen-bench.yml",
        "scripts/hxhx/profile-stage0-regen.sh",
        "docs/00-project/STAGE0_POLICY.md"
      ]
    },
    {
      "id": "stage0-free-hxhx-rebuild",
      "purpose": "Rebuild usable native hxhx artifacts without relying on upstream Haxe at runtime.",
      "target": "Track wall time and peak RSS separately from correctness; Full1 performance parity remains governed by FULL1_PERF_PARITY:PASS.",
      "evidence": [
        "scripts/hxhx/bench-stage0-free-build.sh",
        "scripts/ci/stage0-free-build-benchmark-report.js",
        ".github/workflows/gate-perf-full1.yml",
        "docs/00-project/FULL1_PERF_PARITY_POLICY.md"
      ]
    },
    {
      "id": "native-reflaxe-artifact-loop",
      "purpose": "Build Haxe-authored compiler/backend code, such as a Reflaxe target or hxhx bootstrap artifact, as an OCaml-backed plugin or builtin artifact and run a focused smoke.",
      "target": "Native artifact iteration should beat the current delegated/stage0 promotion path for common compiler and target-development loops before it is recommended as the default path; where a direct OCaml compiler baseline exists, promoted Haxe-authored artifacts should be compared against that baseline and target the same performance class or better.",
      "evidence": [
        "scripts/hxhx/bench-native-plugin-loop.sh",
        "scripts/ci/native-plugin-loop-benchmark-report.js",
        "scripts/hxhx/bench-native-reflaxe.sh",
        "docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md"
      ]
    },
    {
      "id": "native-compilation-server",
      "purpose": "Reuse unchanged parsing and typing work across repeated native hxhx requests without reusing stale compiler state.",
      "target": "Warm unchanged and one-module-change requests should be materially faster than equivalent clean-process compilations, while diagnostics, generated output, and runtime behavior remain equivalent.",
      "evidence": [
        "packages/hxhx/src/hxhx/Stage3WaitServer.hx",
        "packages/hxhx/src/hxhx/NativeCompilerServer.hx",
        "scripts/hxhx/run-compiler-scale-reflaxe-server-proof.sh",
        "scripts/ci/compiler-scale-reflaxe-server-evidence.js",
        "scripts/test-hxhx-targets.sh",
        "docs/benchmarks/REFLAXE_COMPILER_SCALE_SERVER_CHECKPOINT_2026_07_29.md",
        "docs/00-project/BOOTSTRAP_BRIDGE_RETIREMENT.md",
        "docs/01-getting-started/COMPILATION_SERVER.md"
      ]
    },
    {
      "id": "full1-evidence-gates",
      "purpose": "Release proof for Haxe 4.3.7 compatibility, macro/eval parity, plugin parity, target parity, and performance parity.",
      "target": "Do not optimize by weakening coverage. Use phase timings to remove avoidable rebuild/setup duplication and to prevent hidden throughput regressions.",
      "evidence": [
        ".github/workflows/full1-suite-runners.yml",
        ".github/workflows/full1-eval-native.yml",
        ".github/workflows/gate3-full1-extended.yml",
        ".github/workflows/gate-perf-full1.yml",
        ".github/workflows/gate-m7.yml",
        "scripts/ci/m7-shared-artifacts.js",
        "scripts/hxhx/check-local-capacity.js",
        "scripts/ci/local-capacity-preflight-fixture-test.js",
        "scripts/hxhx/local-capacity-queue.js",
        "scripts/hxhx/local-memory-capacity.js",
        "scripts/hxhx/local-heavy-run-lease.js",
        "docs/00-project/CI_GATES.md"
      ]
    }
  ]
}
```
<!-- NATIVE_ITERATION_LATENCY_POLICY_JSON_END -->

## Compilation Server And Incremental Reuse

`hxhx` must support the Haxe compilation-server workflow used by editors and
repeated builds. In plain language, a long-lived compiler should remember work
from the previous request and redo only the work made unsafe by changed inputs.

The word *incremental* has a precise limit here. Upstream Haxe 4.3.7 reuses
unchanged parsed files and typed modules. It checks source timestamps,
class-path and define signatures, module dependencies, and module check
policies before reusing a module, and it can attempt to retype a module whose
dependency changed. This is module-level reuse; it does not mean every later
compiler phase or target generator automatically updates one expression at a
time. The primary implementation references are Haxe 4.3.7's
[`server.ml`](https://github.com/HaxeFoundation/haxe/blob/4.3.7/src/compiler/server.ml)
and
[`compilationCache.ml`](https://github.com/HaxeFoundation/haxe/blob/4.3.7/src/compiler/compilationCache.ml).

The current native `hxhx` implementation has only the first transport rung:

- `--wait stdio` can keep the process alive and run the ordinary Stage3
  compilation routine for each request;
- `--wait <host:port>` and `--connect <host:port>` have a socket round-trip,
  but the server currently returns placeholder display responses and rejects
  ordinary compilation requests; and
- no native Stage3 parser or typed-module cache is shared across requests yet.

Therefore, the existence of `--wait` and `--connect` must not be described as
completed incremental compilation. The durable implementation needs separate,
reviewable ownership for transport, request state, cached immutable compiler
facts, dependency invalidation, macro/plugin lifecycle, and memory cleanup.

The correctness contract is:

1. A clean process and a warm server produce equivalent diagnostics, generated
   target source, executable behavior, and deterministic reports for the same
   complete input identity.
2. Editing, deleting, moving, or shadowing a source module invalidates that
   module and every cached result that depends on it.
3. Changing class paths, defines, target/profile options, libraries, standard
   library identity, compiler build, plugin set, macro implementation, or
   target-lowering schema cannot reuse an incompatible cached result.
4. Request-local mutable state never leaks into the next request. In
   particular, macro callbacks, feature/DCE state, typed-body revisions,
   diagnostics, target plans, and plugin state must be reset or reused only
   through an explicit revision-safe contract.
5. Cache hits, misses, invalidations, retyped modules, elapsed time, memory, and
   reset reasons are inspectable without changing compiler output.
6. Server shutdown, failed requests, interrupted clients, and cache reset leave
   no owned child process or stale lock behind.

Measure at least clean-process cold, server cold, warm unchanged, one-leaf-file
change, one-shared-dependency change, define/target change, macro/plugin change,
and explicit reset. Use the server automatically only on workloads where these
measurements show a practical speed improvement.

Haxe 4.3.7 remains the Full1 behavior and command-protocol oracle. Current
upstream Haxe is also a useful architecture reference because its HXB work can
serialize typed module information for later reuse, but HXB is not a Full1
requirement and must not be copied mechanically into `hxhx`. The native hxhx
cache boundary needs its own architecture review because it crosses parsing,
typing, macros, plugins, targets, and long-lived process state. The upstream
[HXB design discussion](https://github.com/HaxeFoundation/haxe/pull/11504)
is retained as research evidence, including its explicit warning that this is
one of the compiler's most deeply integrated and complex subsystems.

## What Should Get Faster

Expected improvement from native `hxhx + reflaxe.ocaml`:

- less stage0 handoff during compiler rebuild and snapshot refresh loops,
- less delegated Reflaxe setup when building stable Reflaxe targets as native
  plugin or builtin artifacts,
- faster focused target-development loops once target cores can be reused across
  plugin and builtin packaging,
- promoted compiler artifacts that can compete with direct OCaml compiler
  implementations on steady-state compiler workloads,
- less artifact churn from repeated bootstrap regeneration.

Expected to remain intentionally heavier:

- strict upstream Full1 suite gates,
- release-blocking performance parity evidence,
- target-language native builds and link steps,
- broad repo guardrails that protect provenance, generated artifacts, and
  release claims.

## Reporting Rule

Before an expensive local Gate 3 run prepares dependencies, rebuilds the
compiler, or creates an upstream worktree, its capacity preflight records the
host CPU/load state and a redacted summary of compiler processes actively
consuming CPU. Idle compiler servers do not count as competing work.
The default `auto` policy stops a saturated local run with retryable exit code
`75`; the same policy only warns in CI because CI capacity is controlled by the
runner platform. An explicit `off` accepts the expected slowdown but does not
change target selection, retries, timeouts, stage0 rules, or any correctness
claim. Optional JSON reports use `hxhx.local-capacity-preflight.v2` and never
retain full process command lines.

Local maintainers may set `HXHX_HEAVY_RUN_WAIT_SECONDS` to replace manual
retry polling with one bounded, attached queue. Participating repositories then
share the `haxe-family.heavy-run-lease.v1` user-scoped lease. Admission requires
both the existing host decision and lease ownership. The lease identifies its
owning shell by PID plus process start time, has a heartbeat and stale-owner
recovery, supports nested handoff, and never sends signals to competing work.
The final capacity report records admission or timeout and total queue time.
CI remains under runner scheduling and never acquires the local lease.

Participating Reflaxe repositories may keep a small local adapter while the
protocol has only a few consumers. Compatibility is defined by the shared
schema, default user-scoped path, PID-plus-start-time owner identity, heartbeat,
fail-closed schema handling, stale recovery without signaling another process,
and inherited owner handoff. A local entry point must remain opt-in and bounded;
it must wrap the repository's existing command without changing test selection,
timeouts, retries, or release claims.

Before adopting or upgrading an adapter, run the executable two-way proof
against a peer checkout:

```bash
npm run test:hxhx:cross-repository-heavy-run-lease -- \
  --peer-root ../haxe.ruby
```

The peer must expose `scripts/ci/with-heavy-run-lease.js`. The fixture proves
that each independent implementation blocks the other and that nested work
reuses, but does not release, its outer owner's lease. A wire-format change gets
a new schema name and coordinated repository updates; an unknown schema remains
an error rather than a candidate for stale deletion. Reconsider a shared
package when a third implementation would otherwise copy the complete protocol
core or when coordinated upgrades become the dominant maintenance cost.

### Shared-Package Decision (2026-07-19)

The third peer adapter triggered that review. The current Reflaxe.Elixir,
Reflaxe.Ruby, and Reflaxe.Rust review branches have a byte-identical 287-line
protocol core. Their wrappers and fixtures differ only where the owning
repository supplies its command, label, and documentation. The integrated
`hxhx` implementation has the same wire behavior, and all four fixture suites
also pass on Node 20.8.1. A shared implementation is therefore technically
feasible and would reduce coordinated bug-fix work.

| Consumer | Current constraint | Package consequence |
| --- | --- | --- |
| `hxhx` | Private npm root; lease participates in a larger capacity/reporting flow | Keep capacity policy local and import only the protocol/CLI boundary. |
| Reflaxe.Elixir | Node 22 npm project; local adapter is under owner review | Exact package version may replace the core after publication. |
| Reflaxe.Ruby | Node 22/npm 10 project; local adapter is under owner review | Exact package version must preserve its pinned-toolchain install. |
| Reflaxe.Rust | Node 22 npm project; local adapter is under owner review | Exact package version must not change the canonical full harness. |
| Reflaxe.C | Node 20 npm project; no adapter yet | Node 20 support is a package gate; do not add a fifth core copy. |
| Genes | Yarn 1 MIT project; no adapter yet | The package needs a locked Yarn installation proof before adoption. |

The decision is to retain the local `v1` adapters for the current rollout, but
not to copy the complete core into another repository. Distribution ownership,
not protocol design, is the remaining blocker:

- this repository is still private and its root npm package is intentionally
  non-publishable;
- the current public adapter-owning target repositories are copyleft-licensed target
  owners, not a neutral MIT home for Haxe-family developer tooling;
- no immutable public package, release key, provenance workflow, or long-term
  maintainer currently owns this cross-target protocol; and
- the zero-dependency local adapter works with Node before `npm install`, while
  a registry package would add a new cache/network failure to the command that
  is supposed to recover an overloaded development machine.

Relative workspace dependencies, a moving sibling checkout, a private Git URL,
and an unpublished tarball are rejected substitutes. They would make an
apparently shared implementation less reproducible than the reviewed local
files. The two-way fixture remains the compatibility authority for existing
adapters.

Package extraction becomes mandatory before the next repository (for example
Reflaxe.C or Genes) copies the complete core, before a `v2` wire schema is
introduced, or after another protocol-core repair has to be coordinated across
the existing adapters, whichever happens first. Bead
`haxe_ocaml-850ii.20.6` owns that extraction and its required human product
decisions. The package must then provide:

- a neutral public MIT-licensed repository with named maintainers;
- source provenance traced to the repo-owned `hxhx` implementation, without
  silently relicensing changes made only in a copyleft target repository;
- an exact, lockfile-pinned package version with provenance and immutable
  release artifacts;
- a dependency-free CommonJS API and CLI that pass on Node 20 and the declared
  Node 22 consumer floors, without requiring `hxhx` or another source checkout;
- deterministic clean-install, cached-offline-install, missing-package, and
  checksum/tamper tests for npm and the supported Yarn consumer;
- the same local fixture plus two-way tests against one still-local `v1`
  adapter before any consumer cuts over; and
- one hard-cut implementation per consumer, with the repository-specific
  command and labels remaining in a thin local wrapper.

Schema upgrades remain coordinated and fail closed. An older client must never
delete an unknown newer lease. Rollback pins the previous package version; if a
new-schema lease file remains, a maintainer must first prove that its recorded
owner is no longer active before removing it explicitly. No automatic cleanup
may guess across schema versions.

Capacity reports also distinguish raw free pages from a reviewed available-
memory signal. macOS uses `memory_pressure -Q`, Linux uses `MemAvailable`, and
Windows uses available physical memory. An unreviewed fallback is reported as
unavailable and does not fabricate a block. Local admission reserves the larger
of 4 GiB and 10% of total memory: native compiler evidence is roughly 1.6–3.5
GiB, while the 7.2 GiB historical wrapper peak remains visible context rather
than a universal requirement. Threshold overrides are evidence controls, not
compiler-correctness controls.

The fast current-source selector first asks the strict validator for an exact
commit/worktree match. If that fails, its developer-only fallback may reuse the
same compiler across documentation, test, or Beads changes only when the
`hxhx.current-source-inputs.v1` digest still matches. That digest covers the
compiler and backend sources, runtime/templates, build configuration, external
Reflaxe source, upstream Haxe standard library, resolved Haxe/OCaml/Dune tools,
and build-affecting environment. A fresh build fingerprints before and after
compilation and refuses reusable metadata if they differ. Release, Gate 2, and
Gate 3 proof paths continue to call the exact-commit validator directly and
cannot accept the developer shortcut.

Heavy Full1 jobs write `full1-phase-timing-summary.v2`. In plain language, a
downloaded timing file must say which commit, workflow run, machine, and tool
versions produced it before anyone compares its numbers. It embeds every raw
phase row, uses repository-safe paths, and can be reopened with
`full1-phase-timing.js validate`. A tool that was unavailable is written as
`unavailable` instead of silently disappearing. Its total is only the sum of
the commands that were actually timed; it is not automatically the whole
GitHub job runtime. These artifacts remain diagnostic and report-only.

The strict M7 replacement bundle also avoids paying for the same compiler build
before every independent check. It prepares one native `hxhx` and one macro
host from the committed stage0-free snapshots, then writes
`m7-shared-artifacts.v2`. The receipt records the commit, clean tracked-tree
fingerprints, committed snapshot trees, repository-safe artifact paths, both
executable hashes, and the hash of the macro host's companion interface
folder. The bundle revalidates it around every check. This only shares the
compiler tools; Gate1, Gate2, Gate3, plugin, policy, and builtin behavior checks
still run separately and keep their existing pass markers.

The report workflow has an opt-in bytecode/native comparison. It runs both
compiler forms sequentially in one GitHub job and accepts the comparison only
when the commit, runner, CPU, toolchains, commands, repetition rules, and raw
metric rows match. A requested native build that falls back to bytecode is
reported as missing native evidence, not renamed to make the comparison pass.
The comparison remains diagnostic until repeated observations justify a
separate threshold decision.

The bootstrap-regeneration benchmark also writes one self-describing,
report-only summary. In plain language, that summary tells a reader which
commit and machine ran, which tool versions and benchmark settings were used,
what `cold`, `skip`, and `select` mean, and which raw run reports back each
median. It deliberately does not own a warm scenario because it replaces the
tracked bootstrap snapshot. The separate compiler-scale server runner keeps
generated source disposable and Dune state external, then compares cold and
warm target trees, binaries, behavior, memory, and cleanup. A quick `select`
wiring check is not evidence that either full snapshot regeneration or a warm
compiler-scale loop is fast.

The first exact compiler-scale server checkpoint reproduced the cold generated
tree, manifests, native binary, and version behavior on the warm request, but
did not improve the complete loop: both source-generation requests took more
than 37 minutes, and warm was approximately 25 seconds slower after Dune reuse.
The practical result and timing-provenance limitation are recorded in
`docs/benchmarks/REFLAXE_COMPILER_SCALE_SERVER_CHECKPOINT_2026_07_29.md`.
This negative result blocks default enablement and routes the next measurement
to Reflaxe target generation rather than another identical server run.
The runner's `--profile-only` mode is the bounded diagnostic route: it records
one cold request with per-class Reflaxe telemetry and stops before Dune or a
warm request, so it cannot be mistaken for performance admission evidence.

The stage0-free build benchmark answers a smaller everyday question: how long
does it take to turn the already-committed OCaml bootstrap snapshot into a new
native `hxhx` executable without running upstream Haxe? It measures fresh build
workspaces twice: once with Dune's shared cache disabled, and once after priming
a private benchmark-only cache. Each timing must produce a native `.exe`, pass
a target-list smoke, and retain the executable and resource-record digests.
The reported memory value is the operating system's maximum for the completed
build child hierarchy; it is not simultaneous whole-machine or exact process-
tree-sum memory. Both lanes remain report-only until repeated evidence is
stable enough for a separate threshold decision.

The two similarly named Reflaxe benchmarks answer different questions:

- `hxhx:bench:native-reflaxe` compiles and runs a normal Haxe application. It
  measures generated-application compile/runtime behavior; it does not measure
  how long a target author waits to build and load a plugin.
- `hxhx:bench:native-plugin-loop` uses the real Full1 plugin proof paths. It
  prepares one native `hxhx` executable separately, then measures fresh plugin
  emission, Dune plugin build, plugin load, sample compilation, and sample
  runtime for the upstream-Haxe and stage0-forbidden `hxhx` routes on the same
  machine. Each numeric sample must carry a passing proof summary and artifact
  digest. Its comparison is report-only until repeated observations support a
  stable threshold.

When a bead materially changes compiler iteration speed, plugin/native artifact
loops, bootstrap regeneration, or Full1 throughput:

- record the measured command and runner context in the bead,
- update this contract or the referenced perf policy if the measurement bucket
  changes,
- update the README `Goals status` table only if production usability changes,
- otherwise record "README Goals progress bars unchanged" in the checkpoint.
