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
| `enumValueTypeLines` | `bounded_bringup_support` | Lightweight enum carrier. Needs enum behavior matrix before parity. |
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

## Required Follow-Ups

- Convert unsafe Reflect/Dynamic/default-return scaffolding into explicit
  `unsupported_diagnostic` behavior or oracle-backed support. The current
  inventory lives in
  [`CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md`](CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md).
- Put Serializer/Unserializer expansion behind
  [`SERIALIZER_UNSERIALIZER_BEHAVIOR_MATRIX.md`](SERIALIZER_UNSERIALIZER_BEHAVIOR_MATRIX.md).
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
