# Cpp Helper Rendering Policy

This note records the strict Cpp Gate3 helper-rendering checkpoint for
`haxe_ocaml-bhzg`. It is an execution policy for reducing helper body rendering
pressure without weakening upstream Haxe 4.3.7 behavior evidence.

Strict Cpp Gate3 remains red. Local helper, render, and cache improvements are
blocker burn-down evidence only; they do not move README or North Star
production-readiness bars unless strict gates and public usability evidence
change.

## Buckets

Reachable helper classes are classified into four coarse buckets before helper
rendering:

- `full_body`: render parsed helper fields, constructors, and method bodies.
  This is the current default and the expensive path.
- `declaration_only`: emit no body or only a signature/interface surface. This
  is appropriate when C++ only needs the type boundary, not the helper's parsed
  implementation body.
- `runtime_module`: emit target-owned runtime support, a source template, or an
  intrinsic/module body instead of rendering the parsed helper implementation.
  This requires behavior scope and provenance review when the surface is
  semantic rather than mechanical.
- `unsupported_diagnostic`: refuse or diagnose unsupported helper semantics
  explicitly. This bucket exists so missing behavior does not become fake parity
  through default/no-op support.

The initial implementation reports class-level counts through the existing Cpp
trace channel:

```text
cpp_target_phase=render_helper_classes_classification total=<n> full_body=<n> declaration_only=<n> runtime_module=<n> unsupported_diagnostic=<n>
```

For architecture/debug runs that need the actual inventory, enable
`HXHX_TRACE_STAGE3_CPP_HELPER_CLASSIFICATION_DETAILS=1`. It emits one opt-in
line per ordered helper:

```text
cpp_target_phase=render_helper_classes_classification_detail index=<n> kind=<bucket> name=<rendered-helper> [raw=<source-name>] [package=<package>]
```

Use the same strict Cpp Gate3 command and timeout when comparing counts across
slices. Timing/frontier changes are meaningful only when paired with helper
counts, generated size, and the failure mode.

## Movement Rules

A helper may move from `full_body` to `declaration_only` only when the current
program needs a type/signature boundary and not inline body semantics.

A helper may move from `full_body` to `runtime_module` only when the support is
target-owned, provenance-safe, deterministic, and behavior-scoped. Broad
runtime/stdlib semantics also need
[`CPP_TARGET_RUNTIME_POLICY.md`](CPP_TARGET_RUNTIME_POLICY.md) and upstream Haxe
4.3.7 oracle evidence where applicable.

Current bounded examples include stdlib `List` / `haxe.ds.List`, which is
package/source-gated to the real stdlib class and emitted from target-owned C++
runtime support to avoid re-rendering the parsed List body in strict-gate
diagnostics. This does not generalize to user-defined classes named `List`.

`utest.Assert` is also target-owned for Cpp strict-gate diagnostics, but only in
two narrow ways:

- semantic helpers that Cpp call sites actually need, such as polymorphic
  `q`, `same`, and `sameAs`, must stay on explicit Cpp support paths with focused
  smoke coverage. Common upstream signatures should render through direct
  target-owned helpers rather than generic parsed-body/signature prep; unusual
  signatures fall back to the normal helper renderer;
- public non-generic assertion helpers whose bodies are only diagnostic/reporting
  machinery may render direct neutral no-op signatures. This avoids building a
  full render scope for each assertion stub, but it must not be generalized to
  arbitrary default-return helper methods or to user-defined `Assert` classes.

Macro-time assertion helpers must not accidentally become runtime semantics.
For example, upstream unit `HelperMacros.typedAs(actual, expected)` is a
macro-time type probe; Cpp lowering may use it for local type-inference evidence
and then emit a neutral helper call rather than evaluating `actual` or
`expected` as runtime C++ values. Do not generalize this to ordinary helper
functions: only helpers with macro-time probe behavior and focused evidence may
use this treatment.

`HelperMacros.typeError(expr)` and `HelperMacros.typeErrorText(expr)` are also
macro-time assertion probes when their argument is a non-literal expression
being tested for a type error. Cpp may fold those probes to neutral values
before rendering the argument, so invalid anonymous records, duplicate fields,
and invalid call shapes do not become runtime C++ expressions. This must remain
scoped to the helper probe seam and must not become a generic anonymous-record,
Dynamic, or stringification fallback.

Reachability and ordering should scan parsed field initializers and method
bodies only for `full_body` helpers. `declaration_only` and `runtime_module`
helpers keep signature/type dependencies, but their parsed bodies must not pull
body-only helpers into the render set.

Anonymous-struct discovery follows the same rule. Structural field, argument,
and return type hints remain visible for every reachable helper because they are
part of the signature boundary. Parsed field initializers and method bodies are
scanned only for `full_body` helpers; target-owned runtime modules and
declaration-only helpers must not add body-only anonymous carriers or spend
collection time on bodies that will not be emitted. Cache helper render-kind
classification on the per-program class lookup before reusing it in anonymous
collection; recomputing classification inside the collector can erase the
intended timing win.

`haxe.io.Bytes` and `haxe.io.BytesBuffer` follow this rule as target-owned
runtime modules. The C++ backend already owns `BytesData` as vector storage and
already lowers byte copying, byte/string conversion, hex output, and float
memory access through `__hxhx_*` prelude helpers. Rendering the parsed stdlib
`Bytes` body therefore duplicates target-owned byte lowering and was a
strict-probe hotspot. `BytesBuffer` is the same byte-storage family: it appends
to `BytesData`, converts strings through `Bytes.ofString`, writes binary
numbers through the byte-memory helpers, and returns `Bytes`. The bounded
runtime modules keep the public C++ shapes and move the bodies into
`CppRuntimeSupport.bytesSupportLines` and
`CppRuntimeSupport.bytesBufferSupportLines`, with smoke coverage asserting
vector storage, byte helper calls, UTF8 enum-carrier shape, `Int64` projections,
buffer reset behavior, and runtime-module classification.

`Input` and `Output` are deliberately not folded into the same change. They are
abstract stream override surfaces with EOF, blocked I/O, buffering, and
exception contracts, so they need separate oracle/smoke work before becoming
C++ runtime modules. Until then, they remain parsed helpers even if their bodies
are also visible in strict timing logs.

The 2026-07-09 strict source-only Cpp probe after this rule still timed out, but
moved the 360s frontier from `ListNode` helper rendering to
`TestBasetypes.testMath`. The anonymous collector summary changed from
`count=92 walked_bodies=102 skipped_bodies=1602` to
`count=85 walked_bodies=97 skipped_bodies=1290 omitted_bodies=592
skipped_field_inits=191`, which is useful burn-down evidence but not a green
gate.

Sensitive surfaces require separate behavior review before implementation:
Serializer/Unserializer, Float/NaN/Infinity/Math, JSON, binary float encoding,
Reflect/Dynamic, comparisons, and default/no-op runtime support. For the
accepted 2026-07-04 Cpp `TestJson` checkpoint
[`ORACLE_CHECKPOINT_CPP_TESTJSON_DYNAMIC_NUMERIC_2026_07_04.md`](ORACLE_CHECKPOINT_CPP_TESTJSON_DYNAMIC_NUMERIC_2026_07_04.md),
JSON support must enter through a behavior-scoped JSON runtime/helper seam, not
through broad `__hxhx_stringify`, generic `std::any`, or fake generated helper
classes.

If a helper cannot be rendered faithfully yet, prefer an explicit unsupported
diagnostic over fake generated classes or silent default returns.

## Checkpoint Exit

This architecture checkpoint can exit when:

- helper rendering is classified in strict Cpp logs;
- declaration-only versus body-needed decisions have focused evidence;
- runtime-helper invariants and default-stub audit exist for semantic support;
- strict Cpp timing can be interpreted as reduced body pressure, not only as a
  moved timeout frontier;
- README/North Star progress bars remain unchanged unless production readiness
  actually changes.
