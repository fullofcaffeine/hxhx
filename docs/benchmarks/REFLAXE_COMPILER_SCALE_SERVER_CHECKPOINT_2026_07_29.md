# Reflaxe compiler-scale server checkpoint — 2026-07-29

## Outcome

The upstream Haxe 4.3.7 compilation server now gives `reflaxe.ocaml` the
complete `hxhx` program on a warm request, and that warm request reproduces the
cold program exactly. It does **not** make this compiler-scale generation loop
faster yet.

On candidate `35aec28992e9a9b3afd9642e0302360f3222d96b`, the cold and warm
requests produced the same:

- 368-file, 27,792,458-byte generated tree;
- program and source-bundle revisions;
- generated-file receipt and artifact-manifest digests;
- native executable digest; and
- `--version` exit status, stdout, and stderr.

The warm full loop was approximately 25 seconds slower than cold. This reaches
the stop condition in `haxe_ocaml-850ii.33.6`: do not repeat the same expensive
proof or enable this route by default until target-generation work is reduced.

## Small mental model

The complete loop has two different kinds of work:

```text
Haxe reads and types the program
  -> Reflaxe reconstructs and renders the complete OCaml target
  -> Dune compiles the generated OCaml
  -> the native executable runs
```

The Haxe server reused the first step: typing fell from about 2 seconds to
effectively 0 seconds. The expensive part was the second step. Reflaxe still
spent more than 37 minutes reconstructing and rendering the complete target on
both requests. Dune reused its native build state effectively, but that
roughly 44-second saving could not offset the target-generation cost.

## Measured result

| Phase | Cold | Warm | Practical result |
| --- | ---: | ---: | --- |
| Haxe + Reflaxe generation | about 2,223.1 s | about 2,292.5 s | Warm was about 69.3 s slower. |
| Dune/native build | about 45.3 s | about 1.0 s | Warm saved about 44.2 s. |
| Complete loop | about 2,268.4 s | about 2,293.5 s | Warm was about 25.1 s slower (`0.989x` cold/warm speedup). |

The report gate required either a 120-second absolute saving or a warm/cold
ratio of at most `0.80`. Neither condition passed.

Reflaxe telemetry identifies the dominant boundary:

| Checkpoint | Cold | Warm |
| --- | ---: | ---: |
| Haxe typing completed | 2 s | 0 s |
| 50 target classes rendered | 335 s | 435 s |
| 150 target classes rendered | 542 s | 668 s |
| 200 target classes rendered | 2,046 s | 2,155 s |
| 300 target classes rendered | 2,185 s | 2,261 s |
| Output completion reached | 2,187 s | 2,263 s |

The large interval between classes 150 and 200 occurs in both runs. The next
performance task should identify the exact class or target operation inside
that interval before changing architecture or adding a cache.

## Memory and cleanup

The owned server process tree peaked at 6,288,480 KiB (about 6.0 GiB). Samples
immediately after cold and warm generation were approximately 1.54 GiB and
1.52 GiB respectively. The run stayed inside the capacity-qualified host
budget.

Shutdown left:

- zero owned server PIDs;
- zero PID-state files; and
- zero private output transactions or candidates.

This proves scoped cleanup for this sequence. It does not establish a
long-running memory plateau.

## Evidence precision

The compiler, generated output, native builds, behavior checks, captures, and
cleanup all completed. A runner bookkeeping defect then interrupted report
creation: the server ownership helper correctly returned a nonzero status for
an empty post-stop PID list, and shell `pipefail` treated that desired result
as fatal.

The exact output identities above come directly from the retained cold and
warm capture files. The phase intervals in this note were recovered from the
retained log creation and completion timestamps because the original
millisecond shell variables were lost when report creation stopped. They are
decisive for the negative performance result—the warm loop missed the gate by
far—but they are not a release-grade timing baseline.

The runner now:

- normalizes an empty post-stop PID list to a count of zero; and
- writes every completed phase duration immediately, before final report
  assembly.

A future qualifying run will therefore retain authoritative timing data even
if a later report or cleanup assertion fails.

## Decision

Keep the upstream-Haxe/Reflaxe server route explicit and optional. Do not
repeat this compiler-scale proof until a bounded profile identifies and reduces
the target-generation bottleneck. Do not infer that upstream Haxe's compilation
server is ineffective: it eliminated the measured typing work, but typing is
only a tiny fraction of this particular full loop.

README Goals progress bars remain unchanged. The checkpoint proves correctness
and exposes the next performance owner; it does not improve production
readiness.
