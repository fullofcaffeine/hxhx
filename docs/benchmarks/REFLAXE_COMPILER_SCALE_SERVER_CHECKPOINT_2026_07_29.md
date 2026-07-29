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

The safe diagnostic route for that next measurement is:

```bash
HAXE_BIN=/path/to/native/haxe-4.3.7 \
  HXHX_COMPILER_SCALE_SERVER_REPORT_DIR=/new/disposable/report-directory \
  bash scripts/hxhx/run-compiler-scale-reflaxe-server-proof.sh --profile-only
```

Profile-only mode runs one cold generation request with detailed per-class
telemetry, separates preparation from target rendering, summarizes the 20 most
expensive class pipelines, verifies scoped server and output cleanup, and stops
before Dune or a warm request. It cannot satisfy the cold/warm performance
report.

## Bounded profile result

The next bounded profile completed on candidate
`819022e55e76ddb055363387f23b75a33247d693`. One cold source-generation request
took 2,238.382 seconds and peaked at 5,638,624 KiB of owned server RSS.
It confirmed that the long class-150-to-class-200 interval is concentrated in
the largest compiler source modules, but it also exposed a blind spot in the
original telemetry.

There are two relevant costs for each class:

1. **Preparation** transfers and preprocesses the class's typed field bodies
   before the target compiler receives them.
2. **Rendering** lowers those prepared fields and produces OCaml source text.

The original timer began only at step 2. Between the class-150 and class-200
checkpoints, approximately 1,538 seconds elapsed. The measured render calls in
that interval accounted for 483.941 seconds, leaving 1,054.059 seconds—about
68.5% of the interval—outside the old timer.

The render measurements still identify important concrete owners:

| Source class | Render time | Generated OCaml text | Practical reading |
| --- | ---: | ---: | --- |
| `backend.cpp.CppTargetCore` | 409.975 s | 12,513,111 characters | One 25,301-line Haxe class generated about 45% of the complete target tree and dominated measured rendering. |
| `backend.source.SourceTargetCommon` | 49.318 s | 2,655,813 characters | The second large shared target module was the next substantial render cost. |
| `EmitterStage` | 26.159 s | not separately used for this decision | The legacy OCaml bring-up emitter remains expensive, but it was not the main cost in this profile. |
| `HxParser` | 17.096 s | not separately used for this decision | Parser source size also creates meaningful target-generation work. |

Three bounded native samples support the same diagnosis. During the unmeasured
preparation interval, the Haxe evaluator spent substantial time concatenating
large strings, growing buffers, allocating strings, and performing garbage
collection. During `CppTargetCore` rendering, samples showed both evaluator/JIT
work and the same large-string/garbage-collection pressure. The raw native
samples contain machine-local paths, so they remain local; this checkpoint
records only their sanitized mechanism-level finding.

This result does **not** prove that splitting `CppTargetCore` alone will fix the
loop, or that body-revision hashing may be skipped. It proves two narrower
claims:

- compiler source concentration has a measured target-generation cost, not
  merely a readability cost; and
- the next profile must attribute framework-side field/body preparation as
  well as target rendering before selecting an optimization.

The profiling implementation now starts the per-module timer before Reflaxe
extracts and preprocesses class fields. Its report ranks the combined
preparation-plus-render pipeline while retaining the separate values. A focused
fixture proves that a class with fast rendering but slow preparation ranks
above a render-only hotspot when its complete pipeline is more expensive.

## Preparation-aware profile result

Candidate `7aec7f674534bae4b69b405c1ec1487cd9973d0f` then ran the same
profile-only workload with the complete timer boundary. Generation completed in
2,193.437 seconds and peaked at 5,271,088 KiB of owned server RSS. All 310
rendered classes also produced preparation samples.

The result is decisive:

| Source class | Preparation | Rendering | Combined pipeline | Preparation share |
| --- | ---: | ---: | ---: | ---: |
| `backend.cpp.CppTargetCore` | 826.964 s | 392.307 s | 1,219.271 s | 67.8% |
| `backend.source.SourceTargetCommon` | 134.989 s | 48.018 s | 183.007 s | 73.8% |
| `EmitterStage` | 75.250 s | 26.436 s | 101.686 s | 74.0% |
| `HxParser` | 37.077 s | 17.235 s | 54.312 s | 68.3% |
| `backend.vm.NekoTargetCore` | 35.831 s | 12.967 s | 48.798 s | 73.4% |

`CppTargetCore` alone consumed about 20.3 minutes, or 55.6% of the complete
profile-only generation request. Its preparation phase was more than twice as
expensive as rendering. The same preparation-heavy ratio appears in the next
largest modules, so a printer-only optimization cannot solve the measured
problem.

Here, **preparation** includes Reflaxe extracting each function, applying the
configured typed-expression preprocessors, validating the semantic lifecycle,
and sealing target plans. It is not one operation and the aggregate does not
yet prove which substep should be removed. Source inspection does identify a
bounded first review seam: final typed bodies are rendered and hashed at
multiple exact-revision boundaries, and target syntax currently asks for the
same sealed function plan and request-local identities through two separately
validating lookups. Combining those two syntax inputs could remove one duplicate
observation without weakening the single validation immediately before syntax.
That claim needs focused counters, mutation tests, and an `xhigh` second pass
before implementation is accepted.

The preparation profile also retained one native sample from inside
`CppTargetCore`. It showed Haxe evaluator/JIT work on deeply nested functions
while the process footprint reached approximately 5.2 GiB. The sample contains
machine-local paths and remains outside version control; its sanitized finding
supports the aggregate timing but does not by itself select an optimization.

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
repeat the full cold/warm proof until a bounded change reduces the measured
target-generation bottleneck. Do not infer that upstream Haxe's compilation
server is ineffective: it eliminated the measured typing work, but typing is
only a tiny fraction of this particular full loop.

The next engineering decision is deliberately narrower than a general cache or
mega-file rewrite: measure and remove one demonstrably duplicate body
observation at the sealed-plan/syntax boundary while preserving one exact
validation immediately before syntax consumes the plan. Source-class
concentration remains a measured architecture and performance concern, but the
profile does not justify a 25,301-line extraction as the first performance fix.
Any broader proposal to cache a body digest, reuse a semantic plan across
requests, or skip lifecycle validation must pass the repository's higher
reasoning and second-pass review threshold first.

README Goals progress bars remain unchanged. The checkpoint proves correctness
and exposes the next performance owner; it does not improve production
readiness.
