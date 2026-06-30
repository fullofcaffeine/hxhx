# Serializer/Unserializer Behavior Matrix

This note is the behavior-level spec and oracle matrix for `haxe_ocaml-z15k`.
It exists before any broader Cpp `haxe.Serializer` or `haxe.Unserializer`
runtime work resumes.

Strict Cpp Gate3 remains red. Serializer work is internal blocker burn-down
unless upstream-derived strict gates and public usability evidence change.
README and North Star progress bars stay unchanged by default.

## Proof Rule

Use upstream Haxe `4.3.7` as a black-box behavior oracle:

- write repo-owned case programs from this matrix;
- run them with upstream Haxe `4.3.7` on the chosen oracle target;
- record observable output, decoded value shape, and stable error category;
- run the same cases through the Cpp strict/native lane only after the relevant
  Cpp support is classified;
- keep copied upstream tests and upstream compiler source out of this repo.

Local smoke tests and generated-C++ shape assertions are supporting evidence
only. They do not prove Serializer/Unserializer parity.

## Current Support Classification

| Surface | Current classification | Notes |
| --- | --- | --- |
| Portable `reflaxe.ocaml` fixture coverage | supporting evidence | `haxe_core_bucket02_basic` covers int, string, and anonymous object round trips through the portable lane. It is not Cpp parity evidence. |
| Source-native PHP serializer runtime smoke | supporting evidence | The PHP source-native smoke exercises arrays, nulls, anonymous objects, classes, maps, lists, bytes, and Unicode. It can seed oracle cases but does not prove Cpp behavior. |
| Cpp `Unserializer.unserializeObject` compact helper | `bounded_bringup_support`, `review_required` | Shape-only Cpp smoke checks parser loop, object terminator, key validation, recursive value parse, and Reflect-based field mutation. It still depends on partial Reflect/Dynamic support. |
| Cpp `Unserializer.unserializeEnum` compact helper | `bounded_bringup_support`, `review_required` | Shape-only Cpp smoke checks enum format, arg count, recursive parse, and Type.createEnum calls. Current Cpp payload stringification is not enum parity. |
| Cpp full `Serializer` body rendering | `review_required` | Rendering or compacting Serializer methods must wait for oracle cases, especially references, class fields, maps, enums, bytes, floats, and custom serializers. |
| Cpp full `Unserializer.unserialize` body rendering | `review_required` | Recent strict timing shows the main switch/body is a render hotspot. Do not replace it with broad runtime semantics without this matrix and follow-up implementation beads. |
| Cpp Reflect/Dynamic dependencies | `review_required` | Field mutation, dynamic field read/write, type checks, and enum carriers can silently default today. They must not be treated as Serializer parity. |
| Cpp Float/compare/JSON/binary-float dependencies | `review_required` | Float tokens and numeric round trips must use the Float/NaN/Infinity review gate before implementation. |

## Behavior Scope

Serializer/Unserializer support is behaviorally safe only when these observable
properties are pinned by oracle cases:

- exact serialized strings where they are stable and intentionally part of the
  format;
- decoded value shape, including nullability, type identity, fields, enum
  constructor, enum args, map keys, array/list order, and byte contents;
- object identity, reference cache, string cache, and cycle behavior;
- custom resolver behavior for classes and enums;
- custom serialization hooks and their side effects;
- invalid-input error category and error position where stable;
- interactions with `Std.string`, `Std.parseFloat`, `Math`, `haxe.Json`,
  `haxe.io.Bytes`, `Reflect`, `Type`, and comparison helpers.

Do not turn an unsupported case into a silent default value. Prefer an
`unsupported_diagnostic` or keep it explicitly `bounded_bringup_support`.

## Oracle Matrix

Each case should be generated from repo-owned source and compared against
upstream Haxe `4.3.7`. The Cpp lane may report `pass`, `unsupported_diagnostic`,
or `known_divergence`; only `pass` with oracle evidence can become
`parity_support`.

| ID | Scope | Oracle expectation | Cpp gate before implementation |
| --- | --- | --- | --- |
| `ser-null-bool-01` | `null`, `true`, `false` | Pin exact serialized strings and decoded values. | Basic token support plus no silent `std::any` default. |
| `ser-int-01` | `0`, positive, negative, min/max interesting `Int` values | Pin exact strings and decoded numeric values. | Integer parse/stringify support is oracle-backed. |
| `ser-float-01` | finite floats, decimal forms, exponent forms | Pin strings, decoded values, and `Std.string` interaction. | Float review gate complete. |
| `ser-float-02` | `NaN`, positive Infinity, negative Infinity, signed zero | Pin token strings and observable predicates such as `Math.isNaN`, finite checks, and signed-zero probes where stable. | Float review gate complete; no target default conversion. |
| `ser-string-01` | empty, ASCII, Unicode, escaping, control characters | Pin serialized strings, decoded bytes/code units, and `String.length`. | String encode/decode and URL escaping behavior are oracle-backed. |
| `ser-string-cache-01` | repeated strings and cache references | Pin cache use when observable through serialized output and decoded equality. | String-cache model exists or unsupported diagnostic is explicit. |
| `ser-array-01` | arrays with values, nulls, repeated values, nested arrays | Pin serialized output, order, length, null slots, and nested shape. | Array/vector support does not default missing values silently. |
| `ser-list-01` | `haxe.ds.List` | Pin order, length, first/last values, and decoded type. | List runtime support is classified. |
| `ser-stringmap-01` | `haxe.ds.StringMap` with ASCII and Unicode keys | Pin key order if stable, decoded type, and lookups. | StringMap runtime support is classified. |
| `ser-intmap-01` | `haxe.ds.IntMap` with positive and negative keys | Pin decoded type and integer-key lookups. | IntMap runtime support is classified. |
| `ser-objectmap-01` | `haxe.ds.ObjectMap` with object keys | Pin object-key identity behavior and decoded lookup behavior. | Object identity/cache model is classified. |
| `ser-anon-01` | anonymous objects | Pin field names, values, field presence, and decoded dynamic field reads. | Reflect field read/write support is oracle-backed or diagnostic. |
| `ser-class-01` | class instances with constructor fields and mutable fields | Pin decoded class identity, field values, and constructor/hook behavior. | Type resolver and class allocation semantics are classified. |
| `ser-enum-01` | zero-arg and arg enums | Pin constructor names, arg order, value preservation, and decoded enum identity. | Enum carrier and Type.createEnum behavior are oracle-backed. |
| `ser-enum-index-01` | `Serializer.USE_ENUM_INDEX` | Pin indexed output and decoded enum behavior. | Enum index mode is explicitly supported or diagnosed. |
| `ser-bytes-01` | `haxe.io.Bytes` with empty, ASCII, binary, and non-ASCII payloads | Pin serialized bytes string, decoded length, and byte contents. | Bytes/base64/basecode helpers are oracle-backed. |
| `ser-date-01` | `Date` values around UTC/local boundaries | Pin serialized form and decoded time fields on stable oracle targets. | Date/timezone support is classified. |
| `ser-custom-01` | `hxSerialize` and `hxUnserialize` hooks | Pin hook call order, side effects, payload values, and decoded object shape. | Custom hook dispatch exists or diagnostic is explicit. |
| `ser-resolver-01` | custom class and enum resolver | Pin successful resolution, missing resolution behavior, and exception category. | Resolver interfaces and Type resolution are oracle-backed. |
| `ser-reference-01` | repeated object references and cycles | Pin object identity, cycle reconstruction, and cache tokens where stable. | Reference cache model exists or diagnostic is explicit. |
| `ser-error-01` | invalid token, truncated input, invalid object key, invalid enum format | Pin stable error category and position/message class. | Cpp errors do not silently return defaults. |
| `ser-json-interop-01` | values also encoded with `haxe.Json` | Pin non-equivalence boundaries and numeric/string differences. | JSON changes route through the Float/JSON review gate. |
| `ser-compare-interop-01` | decoded values compared with `Reflect.compare` and equality | Pin comparison/equality behavior where Serializer depends on it. | Compare helpers are oracle-backed or diagnostic. |

## Minimum Cpp Resume Criteria

Before adding new broad Cpp Serializer/Unserializer semantics:

- the touched case IDs above are selected and recorded in the implementation
  bead;
- upstream Haxe `4.3.7` oracle output is captured for those cases;
- Cpp current behavior is classified as `pass`, `unsupported_diagnostic`, or
  `known_divergence`;
- Reflect/Dynamic and Float-sensitive dependencies are linked to their owning
  beads;
- generated output changes remain target-owned and provenance-safe;
- README/North Star progress bars are reviewed and normally left unchanged.

## Follow-Up Boundaries

The next implementation beads should be narrow:

- an oracle runner and seed case set generated from this matrix;
- a Reflect/Dynamic prerequisite for anonymous object and class-field mutation;
- an enum carrier/resolver prerequisite before enum round trips;
- [`FLOAT_NUMERIC_REVIEW_GATE.md`](FLOAT_NUMERIC_REVIEW_GATE.md) before
  numeric serializer tokens;
- a Bytes/base64 prerequisite before bytes serializer tokens.

Do not add a monolithic Cpp Serializer runtime in one slice. Land one behavior
surface at a time with oracle evidence.
