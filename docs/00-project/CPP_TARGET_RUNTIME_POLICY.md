# Cpp Target Runtime Policy

This note is the runtime-helper invariant and default-stub audit for
`haxe_ocaml-moz7`. It blocks new broad Cpp runtime or stdlib semantics from
being added to `CppTargetCore.hx` or `CppRuntimeSupport.hx` as ordinary helper
burn-down work.

Strict Cpp Gate3 remains red. Runtime helper work is internal blocker burn-down
unless upstream-derived strict gates and public usability evidence change.
README and North Star progress bars stay unchanged by default.

## Classifications

Every Cpp runtime/helper surface must be classified before it is expanded:

- `parity_support`: behavior-scoped support with upstream Haxe 4.3.7 oracle
  evidence for meaningful edge cases.
- `bounded_bringup_support`: target-owned support used to unblock a narrow smoke
  or strict-gate frontier. It is not parity evidence and must name its limits.
- `declaration_only_support`: type/signature support only. It must not imply the
  runtime behavior exists.
- `unsupported_diagnostic`: explicit refusal or diagnostic. Prefer this to fake
  generated classes, no-op behavior, or silent target defaults.
- `review_required`: too broad or cross-cutting to expand without a behavior
  spec, oracle plan, and second-pass architecture review.

## Invariants

All new or expanded Cpp runtime/helper support must satisfy these invariants:

- It is repo-owned and provenance-safe. Do not copy or translate upstream Haxe
  compiler/test code.
- It has an observable behavior scope pinned to Haxe 4.3.7 expectations, or it
  is explicitly labeled `bounded_bringup_support` or `unsupported_diagnostic`.
- It states the validation lane: focused local smoke, strict stage0-free Cpp
  diagnostic, upstream oracle matrix, or Full1 gate.
- It does not silently return default values for missing behavior unless that is
  the documented Haxe behavior for the supported scope.
- It does not move broad semantics from `CppTargetCore.hx` into
  `CppRuntimeSupport.hx` without classification.
- It uses declaration-only surfaces, target runtime modules, templates, or
  intrinsic lowering instead of fake generated classes when those are the real
  boundary.
- It records deterministic inclusion/order expectations when generated output is
  affected.
- It reviews null, exceptions, Dynamic/Reflect, metadata, comparisons,
  NaN/Infinity/signed zero, parsing/formatting, JSON, binary float encoding, and
  serialization impact whenever the surface can touch them.
- It records README/North Star status. The default is "progress bars unchanged"
  unless production readiness actually changes.

## CppRuntimeSupport Audit

| Surface | Current classification | Audit note |
| --- | --- | --- |
| `borrowedSharedPtrLines` | `bounded_bringup_support` | Target-internal ownership bridge. Mechanical support, not a user-facing runtime claim. |
| `resourceLines` | `bounded_bringup_support` | Target-owned resource table. Needs oracle cases for missing names, byte/string conversion, and list ordering before parity. |
| `sha1Lines` | `bounded_bringup_support` | Compact primitive helper. Must be frozen behind edge-case oracle coverage before parity claims. |
| `missingDeclarationLines` | `declaration_only_support` plus partial bring-up | `IMap` is signature-only; `StringMap` includes a small implementation; `Date.toString` currently returns an empty string and is not parity. |
| `missingMethodReturnType` | `declaration_only_support` | Signature helper only. It must not imply behavior exists. |
| `anySupportLines` | `bounded_bringup_support`, `review_required` before expansion | `Any.__promote` returns `T{}` for unsupported conversions. That is smoke scaffolding, not Dynamic parity. |
| `listSupportLines` | `bounded_bringup_support` | Package/source-gated stdlib `List<T>` / `haxe.ds.List<T>` support used to reduce strict Cpp helper-render pressure. It preserves common List API shape and existing iterator helper return types, but broader collection parity still needs oracle coverage. |
| `fpReinterpretLines` | `review_required` | Binary float support touches NaN, Infinity, signed zero, and platform representation. Use [`FLOAT_NUMERIC_REVIEW_GATE.md`](FLOAT_NUMERIC_REVIEW_GATE.md) before expansion. |
| `dateIntrinsicLines` | `bounded_bringup_support` | UTC construction helper. Date/timezone behavior needs oracle coverage before parity. |
| `stdIntrinsicLines` | `bounded_bringup_support` | `parseInt`, integer literal, and Int64 narrowing helpers. Numeric parsing changes must use oracle evidence. |
| `baseCodeLines` | `bounded_bringup_support` | Compact BaseCode support. Needs invalid input, empty input, byte, and non-ASCII oracle coverage before parity. |
| `vectorSupportLines` | `bounded_bringup_support` | Vector/array helpers use target defaults for some invalid access/empty cases. Not broad Array parity. |
| `sysEventLoopLines` | `bounded_bringup_support`, not parity | Lock/Mutex have bounded primitive support, while Timer/Http/MainLoop/EntryPoint remain simplified/no-op in several places. They unblock compile/smoke surfaces only; see [`CPP_SYS_EVENT_LOOP_SMOKE_AUDIT.md`](CPP_SYS_EVENT_LOOP_SMOKE_AUDIT.md). |
| `rttiMetaLines` | `bounded_bringup_support`, `review_required` | Metadata and Reflect helpers mostly return empty/default values or no-op mutation. This is false-parity risk; see [`CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md`](CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md). |
| `enumValueTypeLines` | `bounded_bringup_support`, `review_required` before expansion | Lightweight enum carrier. See the enum carrier behavior matrix below; current support is not enum parity. |
| `anyIsTypeLines` | `bounded_bringup_support`, `review_required` | Partial `Std.isOfType`/Dynamic-style checks for a small set of C++ carriers. |
| `enumValueDynamicLines` | `bounded_bringup_support`, `review_required` | Dynamic enum helpers and `std::any` conversions return defaults for unsupported values; Float conversion catches parse errors and returns `0.0`. |
| `compareLines` | `review_required` | Comparison touches Dynamic, enums, strings, numbers, NaN, and signed zero. Use [`FLOAT_NUMERIC_REVIEW_GATE.md`](FLOAT_NUMERIC_REVIEW_GATE.md) before expansion. |

## CppTargetCore Runtime Helper Audit

| Surface | Current classification | Audit note |
| --- | --- | --- |
| Cpp prelude/string/vector/base64/basecode/hash/resource lowering | `bounded_bringup_support` | Compact target-owned primitives are acceptable when edge-case oracle coverage exists. Do not broaden them without behavior specs. |
| `renderMissingInterfaceDeclaration` and missing declarations | `declaration_only_support` | Signature/declaration boundary only. Avoid fake generated classes for runtime behavior. |
| `renderRttiMetaHelper` and `rttiMetaLines` callers | `bounded_bringup_support`, `review_required` | Empty/default metadata results must not count as strict Reflect/RTTI parity. |
| `renderDceReflectionHelperStringOverload` | `bounded_bringup_support` | Narrow string overload support for current DCE/reflection helper shapes. Expansion needs behavior cases. |
| `dceReflectionHelperCallExpr`, `Reflect.field`, `Reflect.callMethod`, `Reflect.isFunction` | `bounded_bringup_support`, `review_required` | Reflect field/call/mutation is partial and may return `std::any()` or `false`. Unsafe as parity evidence. |
| `Reflect.compare` / `Reflect.compareMethods` lowering | `review_required` | Must use [`FLOAT_NUMERIC_REVIEW_GATE.md`](FLOAT_NUMERIC_REVIEW_GATE.md) before expansion. |
| Serializer/Unserializer object and enum helper lowering | `review_required` | Broad serialization behavior needs the Serializer/Unserializer spec and oracle matrix before more implementation. |
| Sys/event-loop and Http helper lowering | `bounded_bringup_support`, not parity | Simplified/no-op behavior is smoke support only; see [`CPP_SYS_EVENT_LOOP_SMOKE_AUDIT.md`](CPP_SYS_EVENT_LOOP_SMOKE_AUDIT.md). |
| Raw try/catch and dynamic fallback lowering | `bounded_bringup_support` | Catch-all fallbacks that return defaults are scaffolding unless explicitly oracle-backed. |

## Enum Carrier Behavior Matrix

This matrix exists because a Cpp strict timing checkpoint found repeated
`Assertation` enum-constructor helper cost. A direct shortcut that renders those
constructors as tag-returning methods would preserve today's generated Cpp shape
for some helpers, but it would also harden the current partial enum model.

The runnable Haxe 4.3.7 oracle seed for this matrix is repo-owned and should be
kept as the behavior source of truth before changing the Cpp enum carrier model:

```bash
npm run test:cpp-enum-carrier-oracle-seed
```

The runner enforces an upstream `haxe` version of `4.3.7`, executes
`test/oracle/cpp_enum_carrier_seed/src/Main.hx` with `--interp`, diffs against
`test/oracle/cpp_enum_carrier_seed/expected.stdout`, and writes
`.tmp/cpp-enum-carrier-oracle-seed/report.json`. On 2026-07-09 it reported:

```text
CPP_ENUM_CARRIER_ORACLE_SEED:PASS zero=2 payload=2 enumEq=3 switch=1 typeFactory=4 reflection=3 dynamic=2 serializer=4
```

The seed uses this enum:

```haxe
enum Color {
  Red;
  Green;
  Pair(i:Int, s:String);
}
```

The expected stdout pins zero-argument and payload `Std.string`, constructor
summary via `Type.enumConstructor` / `Type.enumIndex` /
`Type.enumParameters`, `Type.enumEq`, switch payload binders,
`Type.createEnum`, `Type.createEnumIndex`, `Type.allEnums`,
`Type.getEnumConstructs`, `Type.getEnumName`, Dynamic stringification, and
Serializer/Unserializer round-trip prerequisites. The current Cpp backend is
not expected to pass all of those behaviors yet; the seed defines the target
contract for follow-up implementation seams.

| Surface | Haxe 4.3.7 expectation | Current Cpp state | Decision |
| --- | --- | --- | --- |
| Zero-argument enum constructors | Values preserve constructor identity; `Std.string(Red)` is `Red`; `Type.enumEq(Red, Red)` is true. | Parser-scanned zero-arg constructors become enum metadata fields. Typed enum value contexts now create carriers with constructor tag/index metadata, and typed `Std.string` / `Type.enumEq` can read that metadata. Raw helper output may still use tag-shaped methods in non-carrier contexts. | Keep bounded support. A shortcut is only eligible after it proves it does not widen or confuse payload behavior. |
| Payload enum constructors | Constructor payloads are observable through `Std.string`, switch binders, equality, Dynamic, and reflection APIs. | Typed enum value contexts now preserve payloads as string metadata on `std::shared_ptr<Enum>` carriers and erase those carriers to `EnumValue` for `std::any` arguments. Raw constructor helper methods, non-string payload identity, and full runtime factory/switch parity are still incomplete. | Continue behind `haxe_ocaml-puquq`. Do not optimize payload constructors as pure tag methods. |
| Switch payload binders | `case Pair(i, s)` binds the actual payload values. | Typed enum carrier switches can match constructor metadata and bind stringified payload metadata for focused cases. Non-string payload identity and broader erased/non-carrier extraction are still incomplete. | Not full parity. Any switch/payload expansion needs focused oracle cases and cannot be justified by render timing alone. |
| `Type.enumEq` | Equality compares constructor identity and payload values; differing payloads are not equal. | Same-carrier typed enum cases compare preserved tag/index/payload metadata, including known static factory-created carriers. Generic erased flows and dynamic factory-created values still depend on bounded helpers and are not full parity. | Expansion is `review_required`; a shortcut must not bypass payload equality requirements. |
| `Type.createEnum` / `Type.createEnumIndex` | Runtime factory calls create real enum values, including payload values for named constructors. | Static enum class plus literal constructor-name/index factory calls now lower directly to typed metadata carriers. Dynamic factory calls and erased factory parity still depend on bounded helpers. | Treat as bounded bring-up. Serializer/Unserializer enum support must wait for oracle-backed factories. |
| `Type.getEnumConstructs` / `Type.allEnums` | Construct names are complete and stable; `allEnums` returns zero-argument enum values. | Cpp has string-vector metadata support for current smoke shapes. It does not prove enum value construction parity. | Keep metadata-only support separate from enum value parity. |
| Dynamic / `EnumValue` flows | Enum values keep constructor and payload identity when stored as `Dynamic` / `EnumValue`. | Typed enum carriers are converted to `std::shared_ptr<EnumValue>` when passed to `std::any` parameters, and `EnumValue` stringification includes payload metadata. Unsupported `std::any` values still default or return null. | Remains `review_required`; update `CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md` when expanding. |
| Serializer / Unserializer enum flows | Round trips preserve constructor name, constructor index mode, payload order, and payload values. | Current Cpp serializer docs mark enum support as shape-only and dependent on enum carriers plus Reflect/Dynamic behavior. | Blocked on this carrier matrix plus serializer oracle cases. |

Decision for the `Assertation` timing seam:

- Do not add an `Assertation`-specific renderer shortcut.
- Do not add a general payload-constructor shortcut that returns only tags.
- A future zero-arg-only shortcut may be considered only after the helper can
  prove it never applies to payload constructors and generated output/runtime
  behavior remains equivalent for the supported scope.
- The first `haxe_ocaml-puquq` implementation seam is typed enum carrier
  metadata: generated enum carriers store constructor tag, index, and
  stringified payloads; typed `Std.string`, same-carrier `Type.enumEq`, and
  `std::any` erasure can consume that metadata. This is intentionally smaller
  than parity. Switch payload extraction, runtime factories, complete
  `EnumValue`/Dynamic behavior, and Serializer/Unserializer remain follow-ups.

## Required Follow-Ups

- Convert unsafe Reflect/Dynamic/default-return scaffolding into explicit
  `unsupported_diagnostic` behavior or oracle-backed support. The current
  inventory lives in
  [`CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md`](CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md).
- Put Serializer/Unserializer expansion behind
  [`SERIALIZER_UNSERIALIZER_BEHAVIOR_MATRIX.md`](SERIALIZER_UNSERIALIZER_BEHAVIOR_MATRIX.md).
- Keep Cpp enum carrier expansion behind `haxe_ocaml-puquq` and the enum
  carrier behavior matrix above; do not treat tag-only or shell-carrier output
  as enum parity.
- Put Float/NaN/Infinity/Math/JSON/binary serialization and comparison changes
  behind [`FLOAT_NUMERIC_REVIEW_GATE.md`](FLOAT_NUMERIC_REVIEW_GATE.md).
- Freeze compact primitive helpers with black-box oracle edge cases before they
  are treated as parity support. The current inventory and runner plan live in
  [`CPP_COMPACT_PRIMITIVE_ORACLE_FREEZE.md`](CPP_COMPACT_PRIMITIVE_ORACLE_FREEZE.md).
- Keep declaration-only support separate from runtime behavior in code, tests,
  bead notes, and README/North Star status.

## Closure Rule

This policy is sufficient to resume bounded non-semantic Cpp work and small
classified helper work. It is not sufficient to resume broad runtime semantics
for Reflect/Dynamic, Serializer/Unserializer, Float/Math/JSON/binary encoding,
or comparison. Those need their owning P1 beads and second-pass review before
implementation.
