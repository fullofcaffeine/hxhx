# Mega-File Gravity Watch

This note owns `haxe_ocaml-zn07`; `haxe_ocaml-8b0o` keeps the watch wired into
CI. It is a lightweight review trigger for compiler/backend hotspots that are
already large or mixed-purpose. It is not a freeze on urgent Full 1.0 fixes, and
it is not a demand for a giant rewrite.

README and North Star progress bars stay unchanged by default. This policy
protects the hackable-compiler goal; it does not by itself change production
readiness.

MEGA_FILE_GRAVITY_WATCH:PASS

## Current Hotspots

Measured on July 26, 2026, in the active PHP render-session hard-cut candidate.
The guard allows small drift but asks for this table to be refreshed when a
watched file moves by more than 250 lines.

| File | Lines | Risk |
| --- | ---: | --- |
| `packages/hxhx-core/src/backend/source/SourceTargetCommon.hx` | 19,603 | Multiple source/native target families share one backend surface. Target-specific runtime/API shims can quietly become common-backend behavior. |
| `packages/hxhx-core/src/backend/cpp/CppTargetCore.hx` | 25,516 | Fixed prelude assembly lives in `CppProgramPrelude`, and known standard-library carrier signatures live in `CppKnownStdlibSignatures`; rendering, helper reachability, runtime support coordination, type-flow inference, and smoke support still make this a red hotspot. |
| `packages/hxhx-core/src/EmitterStage.hx` | 8,892 | Core stage orchestration plus target/runtime shims can blur frontend/backend ownership. |
| `packages/hxhx-core/src/HxParser.hx` | 5,456 | Parser behavior is central and easy to destabilize with local workarounds. |
| `packages/hxhx-core/src/ParserStage.hx` | 269 | The July 24 parser hard cut removed the duplicate native decoder and profiling copies. Keep this file as the narrow stage/cache adapter around `HxParser`; module-local recovery scanning remains isolated in `ParserStageScanHelpers`. |
| `packages/hxhx/src/hxhx/Stage3Compiler.hx` | 1,041 | Keep orchestration-only; do not let it become a target/runtime implementation surface. |

## Thresholds

Use these as review triggers, not hard CI limits:

- `red`: files over 10,000 lines, or files already owning multiple independent
  target/runtime responsibilities.
- `orange`: files over 5,000 lines, or files where a new change adds a second
  major responsibility to an existing module.
- `yellow`: files over 2,500 lines that are beginning to mix orchestration,
  target lowering, runtime helpers, parser workarounds, or test-only shims.

For `red` files, new substantial logic needs an extraction decision in the bead
before implementation. "Substantial" means any new behavior surface, target
runtime helper family, parser/typer workaround, caching subsystem, or more than a
small local repair.

## Bounded Fix Rule

A bounded Full 1.0 fix may still touch a mega-file when all of these are true:

- the failing gate or regression has a narrow local cause;
- the change does not add a new runtime/stdlib semantic family to the file;
- focused tests or oracle evidence cover the changed behavior;
- the bead records why the mega-file touch was acceptable;
- an extraction follow-up exists, or the bead records why none is needed.

If an inline `out.push` block starts looking like a runtime library, move it to
a target runtime module, template, extern/core declaration, intrinsic lowering,
or technical doc before expanding it.

## Review Triggers

Pause for an extraction note or follow-up bead when a change would:

- add another target family to `SourceTargetCommon.hx`;
- add broad Cpp runtime/stdlib behavior directly to `CppTargetCore.hx`;
- add render-time type inference, reachability, or cache machinery to
  `CppTargetCore.hx` without using an existing bounded seam;
- add bootstrap/stage orchestration and target behavior to the same module;
- add parser workaround logic to `HxParser.hx` or `ParserStage.hx` for one
  backend-specific failure;
- grow a `red` file by more than a small local repair without reducing a
  comparable amount of responsibility elsewhere.

## Existing Follow-Ups

- `haxe_ocaml-8b0o`: mega-file gravity watch wiring/guard.
- `haxe_ocaml-850ii.13`: extract known C++ signature tables for faster native rebuilds.
- `haxe_ocaml-36ec`: Cpp render/type-flow cache extraction.
- `haxe_ocaml-crsq`: Cpp imported stdlib static calls and helper reachability.
- `haxe_ocaml-ejja`: Cpp compact primitive helper oracle freeze.
- `haxe_ocaml-zo90`: Cpp sys/event-loop smoke scaffolding audit.
- `haxe_ocaml-cy8e`: SourceTargetCommon target-family extraction plan.
- `haxe_ocaml-e1kqo`: retired the handwritten OCaml parser and the full
  `ParserStage` comparison copies.

Source/native target-family extraction should be filed before adding more broad
target-specific runtime/API support to `SourceTargetCommon.hx`.

2026-07-26 checkpoint: `haxe_ocaml-850ii.32.2.26` grew
`SourceTargetCommon.hx` from the July 22 count of 17,902 lines to 19,603 while
hard-cutting genuine typed PHP bodies away from process-wide function and
lexical state. The increase is accepted only for this vertical ownership cut:
the shared recursive kernel now requires a closed render frame, while
`PhpFunctionBodyRenderer`, `PhpFunctionLoweringPlan`, and
`PhpLexicalRenderScope` own the PHP request state. Twenty-one PHP
function/lexical statics and their reset entries were removed. No new PHP
runtime semantic family was added, and the finite pre-existing compatibility
body substitutions are now machine-guarded against expansion and separately
owned by `haxe.ocaml-f1cl.3.11.12`. Slice 4 of
`PHP_RENDER_SESSION_HARD_CUT_PLAN.md` must move program/support ownership out
of the shared file; `haxe_ocaml-cy8e` remains the broader target-family
extraction owner. Further substantial growth before one of those cuts is a
stop.

2026-07-25 checkpoint: `haxe_ocaml-850ii.32.2.13` reduced
`SourceTargetCommon.hx` by 282 lines while routing PHP functions through exact
typed records. The shared compiler now evaluates the affected compile-time
diagnostic probes before PHP rendering, so the obsolete PHP-local evaluator was
deleted instead of moved into another target helper. This is an ownership
reduction, but the file remains a red hotspot and the target-family extraction
plan remains active.

2026-07-24 checkpoint: `haxe_ocaml-e1kqo` reduced `ParserStage.hx` from the
July 22 count of 4,721 lines to 269 by making `HxParser` the only frontend,
deleting the native-protocol decoder, and removing profiling-only copies of the
old path. This is an ownership cut, not cosmetic splitting: Haxe source now has
one parser meaning before resolution and typing. The 2,747-line
`ParserStageScanHelpers` remains a yellow hotspot because it supplements
module-local declaration facts from the same source; future work should replace
those best-effort scans with richer `HxParser` output rather than growing a
second parser.

2026-07-18 checkpoint: `haxe_ocaml-850ii.13` moves the existing known
standard-library method argument and return carrier tables out of
`CppTargetCore` into the documented target-owned
`CppKnownStdlibSignatures`. The main emitter still selects declarations and
supplies its existing scope-aware type services; the extracted module only
answers the same already-classified C++ signature questions. This reduces the
red hotspot by 502 lines without adding runtime behavior or another semantic
owner. Focused behavior and before/after build telemetry remain the closure
gate for this in-progress checkpoint.

2026-07-18 checkpoint: `haxe_ocaml-850ii.8.1` moved the fixed 1,168-line C++
support prelude out of `CppTargetCore` into the documented target-owned
`CppProgramPrelude`. In plain language, the main emitter still decides when the
prelude is emitted and retains all class discovery and semantic work; the new
module only assembles the already-classified support lines in their established
order. This is a mechanical responsibility extraction, not new runtime
behavior. The moved source line sequence remained byte-identical, the full
focused C++ suite and verified bootstrap regeneration passed, and full-profile
telemetry reduced `CppTargetCore` generation from `106,535ms` to `78,886ms`;
the extracted module cost `58ms`. The broader render/type-flow extraction
remains open.

2026-07-13 checkpoint: `haxe_ocaml-qa5jq` added an exact render/type shortcut
for `typedXml.elementsNamed(...).next()`. In plain language, it stops the Cpp
renderer from repeatedly rediscovering the `Iterator<Xml>` result when the
receiver is already a known local Xml value. Computed receivers, Dynamic
values, unrelated classes, wrong methods or argument counts, and ordinary
typed iterators remain on the general path. This is a bounded expression and
type-flow repair, not a new Xml runtime surface. Its measurement and safety
coverage is isolated in a dedicated 311-line fixture; broader extraction
remains covered by `haxe_ocaml-36ec`.

2026-07-13 checkpoint: `haxe_ocaml-vhfsr` added an exact equality-rendering
shortcut for zero-argument `toString()` calls on core `Xml.create*` factories.
In plain language, this avoids proving and rendering the same factory chain
twice. Typed locals, a local that shadows the name `Xml`, Dynamic values,
unrelated factories, property getters, and wrong factory arities remain on the
general path. This is a bounded expression-render repair, not a new
runtime/stdlib semantic family; broader Cpp render/type-flow extraction remains
covered by `haxe_ocaml-36ec`.

2026-07-13 checkpoint: `haxe_ocaml-48f9i` reuses the existing proven plain
String field result for the exact `Xml.parse(...).firstChild().nodeValue`
equality shape before general type inference. In plain language, it stops the
renderer from answering the same field/type question twice. Wrong arities,
name shadowing, properties, Dynamic values, other fields, unrelated classes,
and general expressions keep the old path. This is a bounded equality/type-flow
repair, not a new Xml runtime surface; broader extraction remains covered by
`haxe_ocaml-36ec`.

2026-07-11 checkpoint: `haxe_ocaml-jdmr9` added a bounded diagnostic buffer at
the existing Cpp timing-output seam. It removes synchronous timing-line output
from enclosing statement, method, and class measurements without changing
generated Cpp or adding runtime semantics. Broader Cpp render/type-flow
extraction remains covered by `haxe_ocaml-36ec`.

2026-07-09 checkpoint: `haxe_ocaml-nheiw` added a bounded target-owned
`utest.Assert` neutral-support fast path inside the existing Cpp helper support
seam. This is not a new runtime semantic family; broader Cpp render/type-flow
extraction remains covered by `haxe_ocaml-36ec`.

2026-07-09 checkpoint: `haxe_ocaml-lartj` moved the reusable base
`haxe.io.Input`/`haxe.io.Output` stream control flow into `CppRuntimeSupport`.
`CppTargetCore` grew only the runtime-module recognition, signature metadata,
and dependency wiring needed to route the stdlib bases there; concrete stream
subclasses remain parsed. Broader Cpp render/type-flow extraction remains
covered by `haxe_ocaml-36ec`.

2026-07-10 checkpoint: `haxe_ocaml-jfn2q` added bounded typed-local EReg split
dispatch and reused the existing String call-argument contract inside the Cpp
renderer. This adds no runtime/stdlib semantic family and keeps the change in
existing expression/type-flow seams. Broader extraction remains covered by
`haxe_ocaml-36ec`.

2026-07-10 checkpoint: `haxe_ocaml-vzxtn` added an equality-render shortcut
only for proven String-concat trees around the existing typed-local EReg
split/join lowering. Literal and typed String leaves are explicit, while the
join keeps the established String conversion path for its separator. This is
a bounded expression-render repair, not a new runtime/stdlib semantic family;
broader extraction remains covered by `haxe_ocaml-36ec`.

2026-07-10 checkpoint: `haxe_ocaml-f2ne1` added an exact render/type/equality
shortcut for the target-owned `pos` and `len` fields of a zero-argument
typed-local EReg `matchedPos()` call. It reuses the existing typed-local EReg
receiver seam and changes no runtime support or structural carrier behavior.
This is a bounded expression-render repair, not a new runtime/stdlib semantic
family; broader extraction remains covered by `haxe_ocaml-36ec`.

2026-07-10 checkpoint: `haxe_ocaml-z5oql` added an exact render/type path for
the fixed String/callback contract of a two-argument typed-local EReg `map`
call. It reuses the existing EReg String conversion and direct typed-lambda
seams, while non-matching callback values retain general adaptation. This is a
bounded expression-render repair, not a new runtime/stdlib semantic family;
broader extraction remains covered by `haxe_ocaml-36ec`.

2026-07-10 checkpoint: `haxe_ocaml-81ifg` added an exact render/type path for
the fixed two- or three-argument contract of a typed-local EReg `matchSub`
call. It reuses the existing EReg String conversion, renders proven Int and
optional Int carriers directly, and delegates uncommon numeric shapes to the
general parameter adapter. This is a bounded expression-render repair, not a
new runtime/stdlib semantic family; broader extraction remains covered by
`haxe_ocaml-36ec`.

2026-07-10 checkpoint: `haxe_ocaml-xhtte` reused the existing target-owned
String and callback adapters only for exact two-argument `map` and `replace`
calls on a syntactically fresh EReg receiver. The existing fresh `match`
dispatch deliberately retains general argument adaptation. This is a bounded
expression-render repair, not a new runtime/stdlib semantic family; broader
extraction remains covered by `haxe_ocaml-36ec`.

2026-07-11 checkpoint: `haxe_ocaml-i8ymm` added exact render and String-return
discovery only for typed-local EReg `matched(Int)`, `matchedLeft()`, and
`matchedRight()` calls. Indexed conversion reuses the existing target-owned
Int adapter, and unknown receivers or wrong arities remain generic. This is a
bounded expression-render repair, not a new runtime/stdlib semantic family;
broader extraction remains covered by `haxe_ocaml-36ec`.

2026-07-11 checkpoint: `haxe_ocaml-qpmn4` added exact render and Bool-return
discovery only for one-argument `match` calls on a typed-local or syntactically
fresh EReg. Both forms reuse the existing target-owned String adapter, while
unknown receivers, wrong arities, and unrelated methods remain generic. This
is a bounded expression-render repair, not a new runtime/stdlib semantic
family; broader extraction remains covered by `haxe_ocaml-36ec`.

2026-07-11 checkpoint: `haxe_ocaml-ao6dj` reused the existing exact typed-local
EReg split/join concat grammar in a non-rendering mode so explicit and inferred
types can return String without general abstract, Dynamic, or field-call
discovery. Unknown receivers, non-String outer leaves, wrong arity, and bare
joins remain generic. This is a bounded expression-render refinement, not a
new runtime/stdlib semantic family; broader extraction remains covered by
`haxe_ocaml-36ec`.

2026-07-11 checkpoint: `haxe_ocaml-gpp6y` extended the existing primitive
literal argument path only to unary minus over exact Int or Float literals and
skips abstract metadata scans only for canonical primitive type hints. User
abstracts, arbitrary unary expressions, and mismatched expected types remain
generic. This is a bounded shared argument-render refinement, not a new
runtime/stdlib semantic family; broader extraction remains covered by
`haxe_ocaml-36ec`.

2026-07-11 checkpoint: `haxe_ocaml-vywzf` corrected the existing target-owned
EReg runtime contract so indexed captures use a nullable String carrier and
failed last-match reads throw, matching black-box upstream behavior. The
runtime implementation stays in `CppRuntimeSupport`; `CppTargetCore` only
revises its existing exact EReg render/type seams for presence checks, String
adaptation, and present-capture String method access. This is a bounded parity
repair, not a new runtime/stdlib semantic family; broader extraction remains
covered by `haxe_ocaml-36ec`.

2026-07-11 checkpoint: `haxe_ocaml-cjah7` extended the existing exact
EReg-to-String callback grammar so literal/callback-owned concatenations can be
rendered before lambda scope maps are copied or mutated. Captured values,
unsupported leaves, other function signatures, and general lambdas decline to
the canonical scoped path. This is a bounded EReg callback-render refinement,
not a new runtime/stdlib semantic family; broader extraction remains covered
by `haxe_ocaml-36ec`.

2026-07-14 checkpoint: `haxe_ocaml-djqur` moved the new generic
class-backed-abstract representation and `@:to` selection policy into the
dedicated 170-line `CppAbstractProjection` module. `CppTargetCore` receives
only the lookup, dispatch, and carrier-rendering glue at existing seams. In
plain language, the emitter now stores eligible static-only abstracts in their
real underlying class instead of inventing a second wrapper object. Stateful,
instance, primitive-backed, array-backed, nongeneric, and ambiguous shapes
decline to the existing model. This is a bounded target type-flow repair, not a
new runtime or stdlib family; broader extraction remains covered by
`haxe_ocaml-36ec`.

2026-07-15 checkpoint: `haxe_ocaml-idem2` added 25 net lines to `HxParser` to
distinguish an anonymous-object value from a statement block when braces begin
an `if` branch. Exact-source recovery for expression-bodied `return { ... }`
functions lives in the already extracted `ParserStageScanHelpers` module,
which grew 37 lines. In practical terms, upstream macro helpers now remain
structural instead of becoming opaque parser text, while the strict typed-body
invariant stays enabled. This is shared Haxe grammar behavior, not a
backend-specific workaround, and moving the brace decision away from the
parser would split ownership of its token state. Original focused parser and
scanner regressions plus the 163-module upstream macro Gate1 cover the change;
no additional extraction bead is needed.

## Upstream Reference Boundary

Upstream Haxe is useful as an ownership reference point: target generators are
owned by target-specific generator modules with shared support around them. Use
that idea at the architecture level only. Do not copy, translate, or mirror
upstream compiler implementation code.

## Guard

Run:

```bash
npm run guard:mega-file-gravity-watch
```

The guard checks that this policy remains linked from the project docs, that
the threshold language and follow-up owners are present, and that watched file
line counts have not drifted by more than 250 lines from the table above. It is
a review prompt, not a hard file-size budget.
