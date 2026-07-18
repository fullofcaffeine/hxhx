# hxhx Fresh-Build Hotspots (2026-07-18)

This record explains where a fresh current-source `hxhx` build spends its
time. It is developer-loop evidence, not Haxe 4.3.7 parity or release evidence.

## Practical result

Upstream Haxe typing is not the current multi-minute bottleneck. In the
instrumented run, Haxe typed 473 module types in about 2 seconds. Reflaxe then
spent 106.535 seconds generating OCaml for `backend.cpp.CppTargetCore` alone.
That one 26,920-line class produced a 12.2 MB OCaml module and consumed just
over half of the complete 211-second emit.

This changes the optimization order:

1. split the mixed-purpose C++ generator into reviewable target-owned modules;
2. let unchanged compiler-core and target-plugin artifacts rebuild separately;
3. keep exact full-compiler builds as the decisive proof;
4. do not enable persistent Haxe-server reuse or Dune caching as a default
   based on the current evidence.

The extraction work is tracked by `haxe_ocaml-850ii.8.1`. The shared native
plugin product contract remains owned by `haxe_ocaml-c4czv`: one plugin ABI and
payload for stock Haxe and `hxhx`, with different thin loader shells allowed
only for a measured OCaml/runtime/linker incompatibility.

## Candidate and host

- Candidate: `15d5368649af1924a28e0b8d75087e96d203065d`
- Host: Apple M2 Pro, Darwin arm64, 12 logical CPUs
- Upstream Haxe: `4.3.7`, direct executable
  - executable SHA-256: `273229125b5606cd1379fb5369cdf83fb769d1e177a3f64e6e6bdaf5208e8e7f`
- OCaml: `5.4.0`
- Dune: `3.21.0`
- Capacity preflight: pass
  - load averages: `10.700`, `17.439`
  - sustained normalized load: `0.892`
  - active compiler competitors: `1`

The emit used a new isolated artifact directory. It did not overwrite the
cached current-source compiler or any committed bootstrap snapshot.

## Full emit command shape

From the repository root:

```bash
cd packages/hxhx
REFLAXE_OCAML_PROGRESS_FILE=<artifact-dir>/reflaxe-progress.log \
  "$HAXE_NATIVE" \
  build.hxml \
  -D ocaml_emit_only \
  -D ocaml_output=<artifact-dir>/out \
  -D reflaxe_ocaml_progress \
  -D reflaxe_ocaml_telemetry \
  --times
```

The machine-local executable and artifact paths above are reproduction inputs,
not source configuration. The tracked current-source fingerprint resolves and
hashes the active toolchain rather than assuming this path on another host.

## Results

- Wall time: `211s`
- Haxe module types after typing: `473`
- Typing checkpoint: about `2s`
- Generated OCaml modules: `294`
- Generated OCaml source: about `24 MB`

Largest per-class generation costs:

| Haxe class | Generation time | Generated OCaml bytes |
| --- | ---: | ---: |
| `backend.cpp.CppTargetCore` | `106,535ms` | `12,198,594` |
| `backend.source.SourceTargetCommon` | `8,758ms` | `2,446,186` |
| `EmitterStage` | `7,111ms` | `1,602,627` |
| `HxParser` | `2,412ms` | `2,045,319` |
| `backend.vm.NekoTargetCore` | `1,596ms` | `590,463` |
| `backend.cpp.CppLocalTypeInference` | `868ms` | `163,152` |
| `backend.js.JsExprEmitter` | `547ms` | `227,783` |
| `TypedBodyBuilder` | `538ms` | `106,344` |

The Haxe `--times` table reports only about 4.7 seconds inside its normal
compiler timers. Reflaxe's progress log is the source of truth for the
post-typing generation wall time.

Raw artifact hashes, retained here so cleanup does not erase identity:

| Artifact | SHA-256 |
| --- | --- |
| `stage0.log` | `4b7f39fe8414fd51ed29fc9d6cf6ba12f702a5f7165b4b0e61a415bf095f319f` |
| `reflaxe-progress.log` | `681a8a12b76397da27efea76e3598ad840d528fd8a95c7db9b2ba8c2a8d6482d` |
| `progress-summary.json` | `99792dceed7406aaacfff2b49e682b0b100064eaf22e1fada63e0f486d1fc2b7` |

## Rejected Dune-cache shortcut

A separate native, stage0-free A/B used a private Dune cache, one unrecorded
prime, one alternating sample per lane, and two Dune jobs. Its capacity
preflight passed at normalized load `1.297` with four active compiler
competitors.

| Clean native build | Time | Child peak RSS |
| --- | ---: | ---: |
| shared cache disabled | `38,397ms` | `1,957,712 KiB` |
| private cache primed | `37,704ms` | `1,897,040 KiB` |

The `0.982x` ratio is too small to justify adding shared-cache state to the
ordinary workflow. The report SHA-256 is
`1b947767ed1bd5e2f425fade6b822246932b2bbf0250c01a7c611a4de6b7e1d5`.

## Remaining bounded experiment

`reflaxe_ocaml_disable_expression_preprocessors` remains an explicit
developer-only A/B candidate because earlier probes reduced memory. It is not a
default and does not count as exact evidence. Before promotion it must complete
the same isolated emit, build the result, pass focused target behavior, and
show a meaningful improvement. The first attempted A/B was correctly stopped
by the capacity preflight at sustained normalized load `1.704` with eight
active competitors.

No-opt and no-inline modes remain troubleshooting knobs. Existing evidence says
they can make completed builds slower, so they are not current speed defaults.
