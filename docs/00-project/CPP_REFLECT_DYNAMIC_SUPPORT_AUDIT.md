# Cpp Reflect/Dynamic Support Audit

This audit owns the `haxe_ocaml-1uw3` checkpoint for Cpp
Reflect/Dynamic/default-return scaffolding. Strict Cpp Gate3 remains red, so
these classifications are internal blocker burn-down evidence only. README and
North Star progress bars stay unchanged.

## Current Decision

The current Cpp Reflect/Dynamic helpers remain `bounded_bringup_support` for
the specific M14/strict-Gate3 compile-shape paths that depend on them. They are
not Haxe 4.3.7 parity evidence.

The accepted 2026-07-04 Cpp `TestJson` review
[`ORACLE_CHECKPOINT_CPP_TESTJSON_DYNAMIC_NUMERIC_2026_07_04.md`](ORACLE_CHECKPOINT_CPP_TESTJSON_DYNAMIC_NUMERIC_2026_07_04.md)
does not promote these erased helpers. Its JSON carrier may use `std::any` only
as a box around known JSON carrier states; unsupported erased values must stay
explicit and must not become generic `Dynamic`, `Reflect`, or stringification
parity.

This slice does not turn the broad erased helpers into throwing diagnostics
because current Cpp burn-down still needs them to keep Serializer,
Unserializer, metadata, and DCE-reflection helper rendering compile-safe while
the behavior matrix is being built. Instead, the generated support now carries
explicit `hxhx-cpp-bounded-bringup` markers, and the smoke test asserts those
markers survive generation.

Future broad behavior must choose one of these paths before implementation:

- `unsupported_diagnostic`: fail explicitly for unsupported runtime behavior;
- `parity_support`: behavior-scoped support with upstream Haxe 4.3.7 oracle
  cases; or
- `bounded_bringup_support`: only for a named smoke/strict-gate compile shape,
  with no public parity claim.

## Inventory

| Surface | Classification | Current scope | Before expansion |
| --- | --- | --- | --- |
| `__hxhx_meta_get_as` | `bounded_bringup_support` | Keeps `haxe.rtti.Meta.getMeta`-style Cpp helper rendering compile-safe with empty defaults. | Oracle cases for metadata on classes, fields, methods, absence, and typed casts. |
| `__hxhx_meta_section_as` | `bounded_bringup_support` | Keeps `Meta.getType`/`Meta.getFields` erased-section access compile-safe with empty defaults. | Oracle cases for section names, missing sections, field metadata, and stable empty behavior. |
| `__hxhx_reflect_get_property_any` | `bounded_bringup_support`, `review_required` | Erased metadata map probe shape only; currently returns empty `std::any`. | Oracle-backed erased object/property model or explicit unsupported diagnostic. |
| `__hxhx_reflect_has_field_any` | `bounded_bringup_support`, `review_required` | Erased metadata field probe shape only; currently returns `false`. | Oracle-backed field presence semantics for anonymous objects, classes, strings, null, and missing fields. |
| `__hxhx_reflect_field` | `bounded_bringup_support`, `review_required` | Keeps `Reflect.field` expressions type-erased for call/isFunction/stringification smoke shapes. | Oracle-backed field lookup for anonymous objects, class instances, static fields, methods, strings, missing fields, and null. |
| `__hxhx_reflect_set_field` | `bounded_bringup_support`, `review_required` | Keeps Serializer/Unserializer object rendering compile-safe; currently no-op. | Oracle-backed mutation semantics or explicit unsupported diagnostic before runtime parity claims. |
| `__hxhx_reflect_call_method` | `bounded_bringup_support`, `review_required` | Keeps `Reflect.callMethod` lowering compile-safe for erased call shapes; currently returns empty `std::any`. | Oracle-backed function/method invocation semantics, receiver binding, arity behavior, null receiver behavior, and exception behavior. |
| Generic `__hxhx_reflect_is_function` | `bounded_bringup_support`, `review_required` | Returns `false` for unknown erased values; compile-shape support only. | Oracle cases for closures, methods, dynamic field results, strings, objects, and null. |
| `std::function` `__hxhx_reflect_is_function` overload | `bounded_bringup_support` | Returns `true` for generated C++ function carriers. | Promote only with broader `Reflect.isFunction` oracle matrix. |
| `__hxhx_method_identity` compareMethods support | `bounded_bringup_support` | Supports the current method-token runtime smoke. | Oracle cases for equal/unequal instance methods, static methods, closures, null, and cross-receiver identity. |
| Generic `__hxhx_reflect_compare_methods` fallbacks | `bounded_bringup_support`, `review_required` | Return `false` for unsupported method carriers. | Oracle-backed comparison semantics or unsupported diagnostics for unsupported carriers. |
| `Any.__promote` / `anySupportLines` | `bounded_bringup_support`, `review_required` | Compile-shape conversion helper; unsupported conversions can default-construct. | Dynamic/Any conversion behavior matrix and oracle cases. |
| `__hxhx_is_type(std::any, type)` | `bounded_bringup_support`, `review_required` | Partial carrier checks for a small set of generated C++ values. | Oracle cases for `Std.isOfType`, `is`, nullability, class/interface/enum carriers, Dynamic, and abstracts where applicable. |
| `__hxhx_enum_value_ptr` | `bounded_bringup_support`, `review_required` | Extracts generated enum carriers from `std::any`; unsupported values return `nullptr`. | Enum carrier behavior matrix and oracle cases. |
| `__hxhx_string_vector_any` | `bounded_bringup_support`, `review_required` | Extracts generated string-vector carriers from `std::any`; unsupported values return `{}`. | Array/Dynamic extraction oracle cases or unsupported diagnostics for unsupported carriers. |
| `__hxhx_any_double` | `bounded_bringup_support`, `review_required` | Numeric extraction for compile-safe Math/compare shapes; unsupported values and parse failures return `0.0`. | Use [`FLOAT_NUMERIC_REVIEW_GATE.md`](FLOAT_NUMERIC_REVIEW_GATE.md) before any behavior change. |
| `__hxhx_any_add` | `bounded_bringup_support`, `review_required` | Erased `Dynamic` plus/add-or-concat support for focused Cpp compile/runtime smokes; null numeric operands throw instead of becoming zero. | Upstream oracle matrix for Dynamic `+`, null behavior, numeric/string coercion, abstracts, and exceptions before expansion. |
| `__hxhx_any_eq` | `bounded_bringup_support`, `review_required` | Erased `Dynamic` equality support for null, bool, string-like, and numeric carriers; unsupported erased values compare false and do not stringify or become null. | Upstream oracle matrix for Dynamic equality/inequality across null, bool, numeric, string, enum/class/abstract/object/function carriers before expansion. |
| `__hxhx_compare(std::any, std::any)` | `review_required` | Partial enum/string/int/double comparison plus stringification fallback. | Use [`FLOAT_NUMERIC_REVIEW_GATE.md`](FLOAT_NUMERIC_REVIEW_GATE.md) and Reflect comparison oracle cases before expansion. |

## Required Oracle Cases

Before broad Cpp Reflect/Dynamic semantics are implemented, add upstream Haxe
4.3.7 oracle cases for:

- `Reflect.field`, `Reflect.hasField`, `Reflect.getProperty`, and
  `Reflect.setField` on anonymous objects, class instances, static fields,
  strings, missing fields, and null values.
- `Reflect.callMethod` with null receiver, explicit receiver, instance method
  values, static function values, closures, varying arity, and thrown errors.
- `Reflect.isFunction` for closures, instance methods, static methods, dynamic
  field results, strings, objects, and null.
- `Reflect.compareMethods` for same/different static methods, same/different
  receivers, closures, null, and unsupported carriers.
- Metadata/RTTI access through `haxe.rtti.Meta`, including missing metadata and
  method/field metadata.
- Dynamic carrier behavior for `Std.isOfType`, `is`, enum values, arrays, null,
  and unsupported carriers.
- Serializer/Unserializer object mutation and dynamic field reads, linked to
  [`SERIALIZER_UNSERIALIZER_BEHAVIOR_MATRIX.md`](SERIALIZER_UNSERIALIZER_BEHAVIOR_MATRIX.md).
- Numeric Dynamic extraction and comparison, linked to
  [`FLOAT_NUMERIC_REVIEW_GATE.md`](FLOAT_NUMERIC_REVIEW_GATE.md).

## Validation

Local coverage must prove classification is visible:

- generated Cpp support includes `hxhx-cpp-bounded-bringup` markers beside the
  Reflect/Dynamic default-return helpers;
- `test/M14CppNativeBackendSmokeIntegrationTest.hx` asserts those markers in
  generated source;
- broad behavior work remains blocked until oracle cases classify Cpp results as
  `pass`, `unsupported_diagnostic`, or `known_divergence`.

These local checks are supporting evidence only. They do not replace upstream
Haxe 4.3.7 oracle evidence or strict Full 1.0 gates.
