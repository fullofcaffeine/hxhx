# Changed Haxe Formatter Measurement

The changed-file wrapper now starts the official formatter once, streams its
output, preserves its exit code, and stops its process group on POSIX cancellation.
It does not make the formatter's large-file parser faster.

Task `haxe_ocaml-850ii.31` owns the wrapper. Task `haxe_ocaml-vz0h6` owns the
remaining large-file cost and the upstream parser optimization.

## Workload and method

The measurement uses the 21 Haxe files changed by commit
`c2169a52ed483741d4756842102d87c2fe285886`, with that commit's `hxformat.json`.
Each source file was extracted from Git into a separate temporary repository.
The formatter reports 76,771 input lines. The original issue reported 76,765
lines before that commit; these are the same paths, with a six-line difference.

The candidate wrapper is based on main commit
`7cfd95d1f47eeb596bd53c1067f85465673225f8`. It uses one formatter process for
the complete selected set, with no result cache or automatic retry.

Measurements ran on 2026-09-14 UTC, on an Apple M2 Pro with 12 CPUs and 32 GiB RAM.
The toolchain was Darwin 24.4.0, Node 23.9.0, and Haxe Formatter 1.18.0.
The process root retained normal priority for timing. Browser, system indexing, and another background Haxe build were
active. These are local observations, not an isolated benchmark or a release
performance claim.

Each sample starts a fresh process. The first and repeat samples use unchanged
files; the filesystem cache was not purged. The repeat is a warm-filesystem
measurement, not a compiler-server cache hit. The sequence checks small files,
then the complete set in wrapper/direct/direct/wrapper order, then the largest
file twice. Small process-fixture checks also ran during the first complete-set
sample. Checks on the representative files were serial to avoid competing
formatter processes on those files.

The measurement set `HX_FORMAT_TIMEOUT_SECONDS=280`, with a separate 300-second
outer deadline. Every check finished within the wrapper's normal 240-second
deadline. The original attached session was retained across tool yields until
the complete sequence exited. All observed formatter processes were gone afterward.

The installed haxelib contains prebuilt `run.n` and `run.js` programs. Its
`formatter.Cli` launcher chooses Node when available. An observed process tree
contained haxelib, Neko, and `node run.js`; it contained no Haxe compiler.
Compilation cost is therefore absent from this installed invocation. There is
no Haxe compiler server to identify or reuse on this path.

The installed artifacts had these SHA-256 hashes:

| Artifact | SHA-256 |
| --- | --- |
| `run.n` | `c2649baa95866cc774a9a8dd4f4c4e5b4a6df2f8093e3191771bc86583fa0725` |
| `run.js` | `5b7513ad80a2c8729210472638555ff1837b1457b518c4bf13920be5d8f40b19` |

## Results and budget

All checks returned zero. Wall times include process startup and the macOS
`time` command. The formatter also reports time spent processing the selected
files, after its argument handling and startup.

| Workload | First wall time | Repeat wall time | Formatter processing, first / repeat |
| --- | ---: | ---: | ---: |
| Startup only: `--help` | 0.152 s | 0.145 s | No files |
| Four small files, direct | 0.223 s | 0.228 s | 0.069 / 0.075 s |
| Four small files, wrapper | 0.255 s | 0.282 s | 0.063 / 0.058 s |
| All 21 files, direct | 116.707 s | 116.304 s | 116.517 / 116.091 s |
| All 21 files, wrapper | 115.589 s | 115.227 s | 115.367 / 114.991 s |
| Largest file, direct | 65.468 s | 66.275 s | 65.305 / 66.091 s |

A final alternating before/after comparison used the same four small files.
The old wrapper took 0.435 and 0.421 seconds; the new wrapper took 0.255 and
0.282 seconds. Removing the help invocation saved 0.139–0.180 seconds in those
paired samples. The complete-set difference from the direct command is too
small to claim a file-processing speedup.

The macOS `time -l` output recorded these larger samples:

| Sample | User CPU seconds | System CPU seconds | Maximum resident bytes |
| --- | ---: | ---: | ---: |
| All files, wrapper first | 113.71 | 2.57 | 545701888 |
| All files, direct first | 114.56 | 2.73 | 550092800 |
| All files, direct repeat | 114.68 | 2.70 | 565706752 |
| All files, wrapper repeat | 113.76 | 2.38 | 539377664 |
| Largest file, first | 64.28 | 1.51 | 346013696 |
| Largest file, repeat | 64.48 | 1.68 | 319520768 |

Use these **report-only investigation budgets** on this workload and machine class:

- One second for the four small files.
- 150 seconds for the complete set.
- One second for total wrapper time outside the formatter's reported file processing.

The complete-set budget gives approximately 28% headroom over the
slowest sample. All observed samples meet these budgets.

These budgets detect a reason to investigate; they are not CI admission rules.
Two samples on a shared host do not establish a stable noise policy. The
150-second budget also does not make a two-minute edit loop satisfactory.
The 65–66-second single-file cost remains owned by `haxe_ocaml-vz0h6` and must
be measured again after the upstream parser optimization is available.

## Reproduce and compare

Use a clean checkout of the workload revision above. Obtain its file list with:

```bash
git diff --name-only HEAD^ HEAD -- '*.hx'
```

Run the candidate wrapper from that checkout, using its path in your candidate
worktree:

```bash
node /path/to/candidate/scripts/lint/hx-format-changed.js --check --base HEAD^
```

For the direct baseline, pass each listed path to `haxelib run formatter` with
its own `-s` argument, then append `--check`. On macOS, prefix each command with
`/usr/bin/time -l` to record wall time, CPU time, and maximum resident memory.
Measure `haxelib run formatter --help` separately for startup. Repeat each
unchanged workload with a fresh process and retain the formatter's statistics.

The small set is `TypedBodyInvariant.hx`, `TypedBodySource.hx`, `TypedExpr.hx`,
and `M14JsNativeUnsupportedDiagnosticsIntegrationTest.hx`. The largest file is
`packages/hxhx-core/src/backend/cpp/CppTargetCore.hx`, with 25,255 physical lines.

Run `npm run test:hxhx:hx-format-guard` in the candidate checkout for process
and real-formatter parity checks. The test compares written files byte for
byte. It also compares successful and failed check output, normalizing only
the formatter's elapsed-time statistic and excluding wrapper progress lines.
