# Fast Local Validation

Use this page when you are changing code and need a quick, trustworthy check
before running the broader gates.

The rule is simple: run the narrowest check that proves your change, then run
the broader guard before committing or closing the bead.

## Haxe Formatting

Yes, this repo uses the official Haxe formatter from haxelib.

Fast path for files changed in your worktree:

```bash
npm run format:hx:changed
npm run guard:hx-format:changed
```

What this does:

- `format:hx:changed` formats only changed `.hx` files.
- `guard:hx-format:changed` checks only changed `.hx` files.
- Both commands still call `haxelib run formatter`; they do not define a repo-specific style.

Full guard:

```bash
npm run guard:hx-format
```

`guard:hx-format` runs `scripts/lint/hx_format_guard.sh`. That shell script is
only a stable npm/CI entrypoint. It moves to the repo root and calls
`scripts/lint/hx-format-guard.js`.

`hx-format-guard.js` still delegates to `haxelib run formatter --check`. It is
faster than one huge formatter process because it splits tracked `.hx` files into
deterministic, line-balanced chunks and checks those chunks in parallel.

Useful knobs:

```bash
HX_FORMAT_JOBS=1 npm run guard:hx-format   # serial, easier to debug
HX_FORMAT_JOBS=8 npm run guard:hx-format   # explicit parallel chunk count
```

## Current-Source hxhx Builds

Some diagnostics need an `hxhx` binary built from the current checkout.

For ordinary edit-build-test work, use the isolated fast compiler:

```bash
npm run hxhx:current-source-bin:fast
```

This builds once with Reflaxe's expression preprocessors disabled, then reuses
the result while the complete compiler-input fingerprint remains unchanged. A
comparable isolated emit fell from 211 seconds to 150 seconds. The resulting
compiler passed focused native OCaml, JavaScript, C++ source, plugin-runtime,
and macro-host checks.

Its receipt and generated files live under
`packages/hxhx/out_tmp_current_source_fast`, separate from the full compiler.
The receipt says `HXHX_BIN_BUILD_PROFILE=no-prepass-dev`; strict validation
rejects that profile. Use this compiler to iterate, then recheck the behavior
with the full profile before treating the result as parity, release, or closure
evidence.

Force a fresh fast-profile rebuild with:

```bash
npm run hxhx:build-current-source:fast
```

Full-profile reuse path:

```bash
npm run hxhx:current-source-bin
```

This first validates the exact commit and tracked worktree recorded in
`packages/hxhx/out/hxhx-current-source.env`. If that exact check fails, the
developer-only fallback can still reuse the binary when the complete compiler
input fingerprint is unchanged. In practical terms, documentation, test, and
Beads-only commits no longer force a multi-minute compiler rebuild.

Developer reuse prints:

```text
HXHX_DEVELOPER_CURRENT_SOURCE_CACHE:REUSE
```

The fingerprint invalidates when any consumed input changes, including:

- `hxhx` compiler/backend source;
- Reflaxe compiler source, OCaml runtime, shims, or target templates;
- HXML and library configuration;
- the resolved upstream Haxe standard library or external Reflaxe source;
- the resolved Haxe, Dune, or OCaml compiler executable;
- build-affecting Stage0, OCaml, Dune, or C/C++ environment configuration.

A fresh build hashes these inputs before and after compilation. If they differ,
the build refuses to record a reusable cache entry. The component report lives
next to the local metadata as
`packages/hxhx/out/hxhx-current-source.inputs.json`.
Committed bootstrap snapshots are not inputs to this cache because this command
forces a Stage0 source build. Snapshot-driven, stage0-forbidden builds keep
their separate snapshot and exact-candidate receipts.

This fast fallback is intentionally not release evidence. Gate 2, Gate 3, and
same-candidate proof runners call
`scripts/hxhx/validate-current-source-hxhx-bin.sh` directly; that strict
validator still requires both:

- `HEAD` is unchanged since the build.
- The tracked worktree content hash is unchanged since the build, even if the
  same files were already dirty.

Fresh full-profile rebuild path:

```bash
npm run hxhx:build-current-source
```

Use the fresh rebuild path when you intentionally need to rebuild even if a
valid full current-source binary already exists. The full receipt says
`HXHX_BIN_BUILD_PROFILE=full`; Gate 2, Gate 3, parity, and release workflows
continue to require that profile directly.

For diagnosis-only reuse that deliberately bypasses both safeguards:

```bash
HXHX_CURRENT_SOURCE_ALLOW_STALE=1 npm run hxhx:current-source-bin
```

Prefer the input-fingerprinted selector. `HXHX_CURRENT_SOURCE_ALLOW_STALE=1`
exists only for manual diagnosis and can accept a real compiler-source change;
never use it as final proof. Rebuild before closing a bead that depends on
current-source compiler behavior.

## Focused Native-Backend Smoke Groups

The complete C++ and source-target smoke tests are still the final local check:

```bash
npm run test:m14:cpp-native-backend-smoke
npm run test:m14:source-native-backend-smoke
```

While fixing one area, use a smaller group first. These commands run real checks
from the complete smoke; they are not replacement or reduced-coverage fixtures.

For C++:

```bash
# Individual Haxe-to-C++ rendering rules; no native build is required.
npm run test:m14:cpp-native-backend-smoke:render

# Generated C++ files plus available compiler/build/run checks.
npm run test:m14:cpp-native-backend-smoke:generated
```

For Python, Java, C#, PHP, and Lua source generation:

```bash
npm run test:m14:source-native-backend-smoke:targets
npm run test:m14:source-native-backend-smoke:language
npm run test:m14:source-native-backend-smoke:runtime
npm run test:m14:source-native-backend-smoke:objects
npm run test:m14:source-native-backend-smoke:platforms
```

The group names describe the kind of behavior being checked:

- `targets`: output files, packaging, and target setup;
- `language`: common statements and expressions;
- `runtime`: standard-library, macro, and runtime helpers;
- `objects`: classes, inheritance, collections, and related expressions;
- `platforms`: platform-specific process, filesystem, and switch behavior.

Run the complete command before closing a backend change. A focused group helps
you get a quick answer during development; the aggregate proves that none of its
sibling groups regressed.

## Timeouts And Heartbeats

Prefer repo gate runners that already have timeout and heartbeat knobs. For
one-off local diagnostics, use the timeout helper instead of shell alarm wrappers:

```bash
node scripts/dev/run-with-timeout-heartbeat.js \
  --timeout 420 \
  --heartbeat 30 \
  --log .tmp/my-diagnostic.log \
  -- \
  npm run test:m14:cpp-native-backend-smoke
```

The helper:

- writes command stdout/stderr to the log,
- prints heartbeat lines with elapsed time and log size,
- exits `124` on timeout,
- and terminates the child process group on timeout.

## Heavy-Run Capacity Preflight

Gate 3 checks whether the machine is already saturated before it resolves
packages, rebuilds `hxhx`, or creates a temporary upstream worktree. This keeps
an overloaded laptop from spending an entire target timeout producing timing
that cannot be compared with a normal run.

Run the same check directly:

```bash
node scripts/hxhx/check-local-capacity.js --label local-diagnostic
```

The default `auto` policy stops a saturated local run with exit code `75` and
only warns in CI. The marker is
`HXHX_LOCAL_CAPACITY:<PASS|WARNING|BLOCKED|OFF>`. Useful overrides are:

```bash
# Observe saturation without stopping.
HXHX_HEAVY_RUN_CAPACITY_POLICY=warn npm run test:upstream:runci-targets

# Accept the slowdown deliberately. Correctness rules remain unchanged.
HXHX_HEAVY_RUN_CAPACITY_POLICY=off npm run test:upstream:runci-targets

# Keep a redacted machine-state report for a timing comparison.
HXHX_HEAVY_RUN_CAPACITY_REPORT=.artifacts/capacity.json \
  npm run test:upstream:runci-targets
```

The report includes load averages and short process facts such as compiler
kind, PID, CPU use, and elapsed time. Only compiler processes actively
consuming CPU count as competitors; idle warm compiler servers remain outside
that count. The report deliberately discards full command lines so flags,
paths, and credentials cannot leak into evidence. Turning the capacity
decision off changes only whether the expensive command starts; it does not
relax target selection, retries, timeouts, stage0 restrictions, or pass
criteria.

## Parallelism Policy

Parallelize independent checks when they do not write the same output directory
or hide failure output. Examples:

```bash
npm run test:m14:cpp-native-backend-smoke
git diff --check
```

Do not parallelize two commands that compile the same large C++ translation unit
or mutate the same artifact directory. Run those in dependency order so the
machine does useful work instead of competing with itself.

## Timing Evidence

Recent local evidence from July 3, 2026:

| Check | Scope | Time |
| --- | --- | --- |
| `haxelib run formatter -s <two files>` | touched files | about 28.6s |
| `npm run guard:hx-format` | 597 tracked Haxe files, 4 jobs | about 44.6s |
| `npm run hxhx:build-current-source` | fresh current-source build after cleanup | about 111s |
| `npm run hxhx:current-source-bin` | valid current-source cache reuse | about 0.4s |
| current-source complete-input fingerprint | 5,000+ repo/toolchain input entries, including OCaml libraries | about 1.6s |
| C++ syntax-only compile for `cpp-numeric-only` | one generated translation unit | about 1.1s |
| C++ full compile/link for `cpp-numeric-only` | one generated translation unit | about 1.3s |

Current cache evidence from July 18, 2026:

| Check | Scope | Time |
| --- | --- | --- |
| fresh input-fingerprinted current-source build | capacity preflight passed; Stage0 generation reached Dune at about 211s | 254.5s |
| exact same-worktree selector reuse | strict commit/tree validator | 0.34s |
| documentation-only edit selector reuse | strict validator rejected; complete-input developer fallback passed | 1.95s |
| isolated full Stage0 emit | 473 typed modules; all expression preprocessors enabled | 211s |
| isolated no-prepass developer emit | same 473 typed modules; focused cross-target validation | 150s |
| `hxhx:build-current-source:fast` | input fingerprint + isolated emit + Dune bytecode build | 185s |
| `hxhx:current-source-bin:fast` | valid no-prepass developer cache reuse | 2.18s |

Git/Beads workflow evidence from the same day:

| Check | Scope | Time |
| --- | --- | ---: |
| canonical Beads post-checkout | identical 40-character old/new commit IDs, branch flag `1`, 1,907 exported issues (`7,481,949` bytes) | 122.95s |
| repository identical-branch-and-commit guard | same hook arguments and recorded branch, three samples | 0.06s median |

The slow command spent its time in `bd import --quiet .beads/issues.jsonl`, used
about 2.0 GB maximum resident memory, and re-imported an older staged snapshot
over a newer local bead claim. The argument-level guard avoids both costs only
when Git proves the checked-out branch and commit did not change. Disposable
fixtures still delegate equal-commit branch switches, changed commits, file
checkouts, malformed calls, and custom hooks; an opt-in real-`bd` fixture proves
a changed branch imports its new issue data. See the hook setup in
[`TESTING.md`](TESTING.md). A companion post-commit hook advances the state after
local commits, while Git's rebase `head-name` keeps the original branch identity
visible during the temporary detached-HEAD step of a no-op pull.

The documentation-only reuse row avoids roughly 130 times the wait of that
fresh build, but only for changes outside the compiler input set. A compiler,
runtime, template,
configuration, or toolchain change still rebuilds. This is a developer-loop
improvement, not evidence that fresh compiler generation itself is fast enough.

A follow-up isolated profile explains the remaining fresh-build cost. Upstream
Haxe typed 473 module types in about 2 seconds, while Reflaxe spent 106.535
seconds generating the 12.2 MB OCaml module for the 26,920-line
`CppTargetCore`. The complete emit took 211 seconds. A private Dune-cache A/B
changed a clean native build from 38.397 seconds to 37.704 seconds, which is too
small to justify shared-cache workflow state. See
[`HXHX_FRESH_BUILD_HOTSPOTS_2026_07_18.md`](../benchmarks/HXHX_FRESH_BUILD_HOTSPOTS_2026_07_18.md)
for the exact candidate, capacity facts, artifact hashes, and optimization
decision.

On July 18, 2026, an exact current-source strict C++ run reached its 5,400-second
timeout while the host load was roughly 48. That run is retained as contention
evidence, not compiler-semantic or performance evidence. The capacity preflight
now rejects that situation before expensive setup instead of normalizing it as
an acceptable development-loop duration.

If a local step is much slower than these baselines, treat it as a problem to
diagnose. Check whether the run rebuilt from scratch, serialized work that could
be sharded, waited on network/tool setup, wrote to a shared artifact directory,
or got stuck without a heartbeat.
