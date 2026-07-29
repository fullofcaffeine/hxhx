# Reflaxe compiler-scale server checkpoint — 2026-07-29

## Outcome

The upstream Haxe 4.3.7 compilation server gives `reflaxe.ocaml` the complete
`hxhx` program on a warm request, and that warm request reproduces the cold
program exactly. Removing one duplicate typed-body observation made both cold
and warm target generation about four minutes faster than the preparation-aware
profile, but it did **not** make warm generation materially faster than cold.

The practical result is therefore split:

- ordinary `reflaxe.ocaml` generation is measurably faster without weakening
  exact-body validation; and
- compiler-scale incremental target generation remains unfinished because the
  warm request still reconstructs and renders the complete target.

On candidate `35aec28992e9a9b3afd9642e0302360f3222d96b`, the cold and warm
requests produced the same:

- 368-file, 27,792,458-byte generated tree;
- program and source-bundle revisions;
- generated-file receipt and artifact-manifest digests;
- native executable digest; and
- `--version` exit status, stdout, and stderr.

The first full proof's warm loop was approximately 25 seconds slower than cold.
After the bounded optimization, warm saved 54.164 seconds, but the required
material threshold was 120 seconds or a warm/cold ratio of at most `0.80`.
The optimized ratio was `0.9725`, so the route remains explicit and optional.

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

## One-observation cut and optimized full proof

Candidate `097803880838ff640b3753196a26977d0ac78eac` implemented the
bounded seam identified above. Immediately before constructing OCaml syntax,
the target now observes the final typed body once and receives these three
facts together:

1. the sealed target plan;
2. the request-local map from Haxe variables to stable lexical identities; and
3. the optional constructor boundary.

Previously, ordinary methods requested the first two facts separately and
constructors requested all three separately. Each request re-rendered and
hashed the same typed body. The new handoff is not a cache: it is created and
consumed inside one request, and a body replacement after sealing still fails
with `[reflaxe:planned-body-revision-mismatch]` before syntax is built.

A focused lifecycle counter proves that one syntax handoff performs exactly one
body digest. The same test replaces the body after sealing and proves that the
remaining observation rejects the old plan. The complete clean/warm application
matrix and the late-mutation lifecycle fixture also remain green.

The exact profile-only comparison shows a material general speedup:

| Measurement | Before | After | Change |
| --- | ---: | ---: | ---: |
| Complete generation | 2,193.437 s | 1,947.640 s | **245.797 s faster (11.2%)** |
| `CppTargetCore` combined | 1,219.271 s | 1,041.214 s | **178.057 s faster (14.6%)** |
| `CppTargetCore` preparation | 826.964 s | 807.756 s | 19.208 s faster |
| `CppTargetCore` rendering/syntax | 392.307 s | 233.458 s | 158.849 s faster |
| `SourceTargetCommon` combined | 183.007 s | 162.386 s | 20.621 s faster |
| `EmitterStage` combined | 101.686 s | 84.599 s | 17.087 s faster |
| Peak owned RSS | 5,271,088 KiB | 5,193,744 KiB | 77,344 KiB lower |

The exact cold/warm proof then passed every output and behavior comparison:

- generated tree:
  `sha256:f6856d7d1b3da4e4e3eaea64912b29877cc4613521bfa98ec7d50d3bb7a7d3a2`;
- program revision:
  `sha256:4c305e2918b107d4a8d62e4090173fd197dee875f57ef8d186d3e80628c7c9f3`;
- source-bundle revision:
  `sha256:a5583a581585f5868fdeed63996f1fd4534c9e54b8c7ef904fc69f624de8f254`;
- artifact-manifest and generated-file receipt digests;
- native executable:
  `sha256:3b39627e4d44beaa57ee6ee2aa41f85228af88f69a60d3a2183bb00099aba875`;
  and
- `--version` exit status, stdout, and stderr.

Its performance result did not pass:

| Phase | Cold | Warm | Warm saving |
| --- | ---: | ---: | ---: |
| Haxe + Reflaxe generation | 1,936.617 s | 1,915.754 s | 20.863 s |
| Dune/native build | 34.336 s | 1.035 s | 33.301 s |
| Complete loop | 1,970.953 s | 1,916.789 s | **54.164 s** |

The warm/cold full-loop ratio was `0.9725`. Haxe frontend reuse is visible—the
warm request reported effectively zero typing time—but complete target
reconstruction still dominates both requests. The optimization therefore
improves all generation; it does not create incremental target generation.

This result crosses the task's stop threshold for the next change. A material
warm-only gain now requires deciding which immutable, revision-keyed target
facts may survive a request and how deletions, configuration changes, failed
requests, and final output ownership invalidate them. That is an architecture
decision and needs a focused review before implementation. It must not be
approximated by retaining mutable Haxe compiler objects or skipping complete
program reconstruction.

## Memory and cleanup

The original full proof's owned server process tree peaked at 6,288,480 KiB
(about 6.0 GiB). The optimized full proof recorded 196 samples, peaked at
6,538,464 KiB, and ended at 1,163,168 KiB. The optimized profile-only run peaked
at 5,193,744 KiB and ended at 1,144,160 KiB. All runs stayed inside their
capacity-qualified host budget.

Shutdown left:

- zero owned server PIDs;
- zero PID-state files; and
- zero private output transactions or candidates.

This proves scoped cleanup for these sequences. It does not establish a
long-running memory plateau or make target artifacts cacheable.

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
only a tiny fraction of this particular full loop.

Retain the one-observation handoff: it is a measured four-minute general
generation improvement, keeps one exact validation immediately before syntax,
and passed the clean/warm correctness matrix. It does not close
`haxe_ocaml-850ii.33.7`, because the same candidate's warm loop saved only
54.164 seconds.

The next engineering step is a focused architecture review of incremental
target work—not a broad cache or mega-file rewrite. The review must decide the
smallest immutable artifact boundary that can avoid reprocessing unchanged
functions or modules while still reconstructing complete program membership
and atomically replacing the generated source tree. Source-class concentration
remains a measured architecture and performance concern, but the evidence still
does not justify splitting a 25,301-line file merely for appearance.

Do not retain mutable `ClassFuncData`, typed-expression graphs, macro state, or
target builders across requests. Do not treat a body digest as a complete cache
identity. Do not skip lifecycle validation, generated-file deletion, runtime
requirements, manifests, or failure rollback to manufacture a warm speedup.

README Goals progress bars remain unchanged. The checkpoint proves correctness
and improves general generation time, but it does not make the compiler-scale
warm workflow materially incremental or improve production readiness.
