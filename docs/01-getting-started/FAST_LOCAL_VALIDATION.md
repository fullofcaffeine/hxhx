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

Fast reuse path:

```bash
npm run hxhx:current-source-bin
```

This validates the existing `packages/hxhx/out/hxhx-current-source.env` metadata
and reuses the previous current-source binary when both are true:

- `HEAD` is unchanged since the build.
- The tracked worktree content hash is unchanged since the build, even if the
  same files were already dirty.

Fresh rebuild path:

```bash
npm run hxhx:build-current-source
```

Use the fresh rebuild path when you intentionally need to rebuild even if a
valid current-source binary already exists.

For diagnosis-only reuse after a harmless tracked-content change:

```bash
HXHX_CURRENT_SOURCE_ALLOW_STALE=1 npm run hxhx:current-source-bin
```

Do not use stale reuse as final proof for a code change. Rebuild before closing a
bead that depends on current-source compiler behavior.

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
| C++ syntax-only compile for `cpp-numeric-only` | one generated translation unit | about 1.1s |
| C++ full compile/link for `cpp-numeric-only` | one generated translation unit | about 1.3s |

On July 18, 2026, an exact current-source strict C++ run reached its 5,400-second
timeout while the host load was roughly 48. That run is retained as contention
evidence, not compiler-semantic or performance evidence. The capacity preflight
now rejects that situation before expensive setup instead of normalizing it as
an acceptable development-loop duration.

If a local step is much slower than these baselines, treat it as a problem to
diagnose. Check whether the run rebuilt from scratch, serialized work that could
be sharded, waited on network/tool setup, wrote to a shared artifact directory,
or got stuck without a heartbeat.
