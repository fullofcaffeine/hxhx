# Float Numeric Review Gate

This checklist is the review gate for `haxe_ocaml-yjp8`. Use it before changes
that touch Float parsing, formatting, special values, comparison, JSON numeric
behavior, binary float encoding, or Serializer/Unserializer numeric tokens.

This is a process gate, not a readiness claim. Strict Cpp Gate3 remains red, and
README/North Star progress bars stay unchanged unless strict gates and public
usability evidence change.

## Process Hook

Any bead or patch touching the trigger surfaces below must cite this document in
the bead note before implementation. If the work changes behavior, the note must
also list the upstream Haxe `4.3.7` oracle cases and local target validation
that will prove the change.

If the behavior is broad, unclear, or cross-target, stop before implementation
and use the `thinking:xhigh` second-pass review path described in `AGENTS.md`.

Accepted checkpoint: the 2026-07-04 Cpp `TestJson` review
[`ORACLE_CHECKPOINT_CPP_TESTJSON_DYNAMIC_NUMERIC_2026_07_04.md`](ORACLE_CHECKPOINT_CPP_TESTJSON_DYNAMIC_NUMERIC_2026_07_04.md)
allows only a bounded JSON-surface numeric slice under `haxe_ocaml-ghy0.1`.
Positive Infinity, negative Infinity, and `NaN` may become JSON `null` there,
and the signed-zero / finite-formatting cases are scoped to the selected JSON
oracle. That acceptance does not expand `Std.string(Float)`, Math, comparison,
Serializer/Unserializer, binary Float, or generic `Dynamic` behavior.

## Trigger Surfaces

Use this gate when a change touches these files, helpers, or search tokens:

| Surface | Trigger |
| --- | --- |
| `packages/hxhx-core/src/backend/cpp/CppRuntimeSupport.hx` | `fpReinterpretLines`, `enumValueDynamicLines`, `compareLines`, `std::stod`, default double conversion, `__hxhx_any_double`, `__hxhx_compare` |
| `packages/hxhx-core/src/backend/cpp/CppTargetCore.hx` | `__hxhx_stringify`, `std::to_string`, `std::isnan`, `std::isfinite`, `std::numeric_limits`, `Reflect.compare`, Math intrinsic lowering, hxcpp byte-memory/reinterpret lowering |
| `packages/hxhx-core/src/backend/source/SourceTargetCommon.hx` | source-native Float, Math, JSON, Serializer, or binary encoding behavior |
| `packages/reflaxe.ocaml/std/_std/Math.hx` | `NaN`, positive/negative Infinity, `isNaN`, `isFinite`, rounding, or target-native Math mappings |
| Serializer/Unserializer support | numeric tokens, stringification of Float values, invalid numeric tokens, resolver behavior involving numeric enum args |
| JSON support | numeric parse/print behavior, `NaN`, Infinity, signed zero, integer-vs-float preservation |
| Tests and oracle runners | new expected output involving Float special values, binary float bytes, JSON numbers, or Serializer numeric tokens |

Search tokens that should trigger a review pass include `NaN`, `Infinity`,
`POSITIVE_INFINITY`, `NEGATIVE_INFINITY`, `signed zero`, `Std.parseFloat`,
`parseFloat`, `std::stod`, `std::to_string`, `isnan`, `isfinite`, `isinf`,
`__hxcpp_memory_get_double`, `__hxcpp_reinterpret`, `Reflect.compare`,
`haxe.Json`, `haxe.Serializer`, and `haxe.Unserializer`.

## Required Questions

Before implementation, answer these behavior questions in the bead:

- What exact upstream Haxe `4.3.7` behavior is being matched?
- Which oracle target is used, and is the observed behavior target-stable?
- Does the change affect `Std.string`, `Std.parseFloat`, Math predicates,
  comparisons, JSON numeric encoding/decoding, binary float read/write, or
  Serializer/Unserializer tokens?
- How are `NaN`, positive Infinity, negative Infinity, and signed zero handled?
- Are finite values formatted with the same precision and exponent rules where
  output is observable?
- Do invalid numeric strings throw, return `NaN`, return `null`, return `0`, or
  preserve the original string, and is that behavior oracle-backed?
- Does comparison treat `NaN`, signed zero, strings, enums, and Dynamic values
  the same as upstream Haxe for the supported scope?
- Does binary encoding preserve endianness, signed zero, Infinity, and `NaN`
  payload behavior where observable?
- Does the change introduce a silent default value for unsupported Dynamic or
  erased cases?
- Does the target support depend on compiler flags, platform libc formatting,
  locale, or C++ standard-library behavior?

## Required Evidence

Runtime behavior changes require:

- repo-owned oracle cases run against upstream Haxe `4.3.7`;
- exact serialized strings or printed output when stable;
- decoded value shape and predicate checks when exact strings are not stable;
- focused local tests for the target helper or lowering path;
- Cpp strict/native validation when the Cpp lane is affected;
- explicit `unsupported_diagnostic` or `known_divergence` labels for unsupported
  cases;
- README/North Star progress-bar review, normally recorded as unchanged.

Do not use local smoke tests alone as parity evidence.

## Current Cpp Audit

| Surface | Classification | Audit note |
| --- | --- | --- |
| `CppRuntimeSupport.fpReinterpretLines` | `review_required` | Binary float helpers use byte reinterpretation and must be checked for endianness, signed zero, Infinity, and `NaN` behavior before parity claims. |
| `CppRuntimeSupport.enumValueDynamicLines` / `__hxhx_any_double` | `review_required` | String conversion uses `std::stod` and catches failures by returning `0.0`. That is not oracle-backed Haxe behavior. |
| `CppRuntimeSupport.compareLines` | `review_required` | Arithmetic comparison uses raw `<`/`>` behavior. `NaN`, signed zero, Dynamic, enum, and string cases need oracle coverage before expansion. |
| `CppTargetCore.__hxhx_stringify` | `review_required` | `double`/`float` values currently flow through `std::to_string` in several paths, which may not match Haxe `Std.string` formatting. |
| `CppTargetCore` Math intrinsic lowering | `bounded_bringup_support` | `Math.NaN`, `isNaN`, `isFinite`, and common Math calls have shape coverage, but special-value runtime behavior is not Full1 parity evidence. |
| `CppTargetCore` hxcpp memory/reinterpret lowering | `bounded_bringup_support`, `review_required` | Smoke tests pin helper routing, not binary Float parity. |
| `CppTargetCore` Reflect compare lowering | `review_required` | The lowering avoids invalid generated helper calls, but semantic comparison still depends on `__hxhx_compare`. |
| Serializer/Unserializer numeric cases | `review_required` | Use `SERIALIZER_UNSERIALIZER_BEHAVIOR_MATRIX.md` plus this gate before numeric token implementation. |

## Exit Criteria

A numeric runtime/compiler change may proceed only when:

- the touched trigger surfaces are named in the bead;
- upstream Haxe `4.3.7` oracle cases are selected before code changes;
- local target tests are identified;
- unsupported or partial behavior is explicitly classified;
- the change is scoped to one behavior surface rather than a broad runtime
  rewrite;
- second-pass review is recorded for `thinking:xhigh` work.
