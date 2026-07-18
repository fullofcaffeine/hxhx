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

1. use the isolated no-prepass compiler for ordinary focused iteration;
2. split the mixed-purpose C++ generator into reviewable target-owned modules;
3. let unchanged compiler-core and target-plugin artifacts rebuild separately;
4. keep exact full-compiler builds as the decisive proof;
5. do not enable persistent Haxe-server reuse or Dune caching as a default
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

## Accepted developer-only no-prepass profile

A second isolated emit added
`-D reflaxe_ocaml_disable_expression_preprocessors`. Compiler source inputs
were unchanged from the full baseline; intervening commits affected workflow
documentation and cache tooling. Its capacity preflight passed with 12 logical
CPUs, load averages `10.731` and `17.609`, sustained normalized load `0.894`,
and one active compiler competitor.

| Comparable emit | Full | No-prepass developer | Change |
| --- | ---: | ---: | ---: |
| Wall time | `211s` | `150s` | `-29%` |
| Typed module types | `473` | `473` | unchanged |
| Generated OCaml modules | `294` | `294` | unchanged |
| `CppTargetCore` generation | `106,535ms` | `73,470ms` | `-31%` |
| `CppTargetCore` generated bytes | `12,198,594` | `7,513,378` | `-38%` |
| Total generated source | about `24.27 MB` | about `17.34 MB` | `-29%` |

The isolated no-prepass output then built `out.bc` in roughly 11 seconds. The
resulting bytecode compiler has SHA-256
`e8994e9691c9918874d9201d3c191be7c00078f6c7b0c6c809923f9263ec7eda`.

Focused validation established the intended development boundary:

- native OCaml no-emit and JavaScript emit/run passed;
- stage0-forbidden native C++ source emission passed;
- the focused C++ translation unit was byte-for-byte identical between the
  full and no-prepass compilers (SHA-256
  `aaf26522b79632a59a131435c5d5a91161aab89464f3ff42981f0557acb2d16d`);
- both profiles reached the same pre-existing C++ `Class` definition-order
  compile failure, so that failure is not a no-prepass regression;
- native backend plugin relative/absolute loading, execution, missing-artifact
  rejection, and ABI-mismatch rejection passed; and
- the stage0-free external macro-host RPC self-test passed.

Raw no-prepass artifact hashes:

| Artifact | SHA-256 |
| --- | --- |
| `stage0.log` | `6d42ec0b6d668d24f8ec228166a5bb22a0bbeb068d4bb2bbf621256b5db9c804` |
| `reflaxe-progress.log` | `7dcde35ac5eda1b48b4775457cd072ddcfa86489f1e2e044f588a6967d9ab965` |
| `progress-summary.json` | `547575261e733a0a5e37df2fdcd259a8e462305ea6f008816b2bb12d35f79720` |
| native plugin runtime smoke log | `d2be1f2461a347d29afd48dc559df859026e266cda003438bd978241e3811041` |
| macro-host RPC smoke log | `b698a26738d0b623af314fbc0c400e488867b0e5a0fd9549321e582a56ca4393` |

This evidence justifies an explicitly named local compiler profile, not a
release default. `npm run hxhx:current-source-bin:fast` uses a separate output
directory and a `no-prepass-dev` receipt. Exact parity, Gate 2, Gate 3, and
release paths require the `full` receipt and deterministically reject the fast
profile.

The integrated workflow was then exercised through its public commands:

- `hxhx:build-current-source:fast` completed fingerprinting, isolated Stage0
  emission, and the Dune bytecode build in `185s`;
- the resulting isolated compiler SHA-256 was
  `06d49241e24944d85e9b1ecdbc8fb13b8eb5ba258ccb88935a68e18db6d4c0d4`;
- `hxhx:current-source-bin:fast` reused it in `2,184ms`;
- the full-profile validator rejected its `no-prepass-dev` receipt;
- the public artifact passed native OCaml and JavaScript smoke, native plugin
  loading/negative cases, and the external macro-host RPC self-test; and
- its stage0-forbidden focused C++ output remained byte-for-byte identical to
  the full-profile output.

The integrated build log SHA-256 is
`298e389a4a6780fe4438ff888d3dc9284b5525f5daaddef8a13b2c3ef482a4c2`;
the public-artifact plugin smoke log SHA-256 is
`b6789e5d80fcadc2fe41fb4a875dd9b17622970c4c3973d9aa479c603ab7bd96`.

No-opt and no-inline modes remain troubleshooting knobs. Existing evidence says
they can make completed builds slower, so they are not current speed defaults.
