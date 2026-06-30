# Cpp Compact Primitive Oracle Freeze

This note owns the `haxe_ocaml-ejja` checkpoint for compact Cpp
primitive/runtime helpers. It freezes the helpers that already exist as bounded
bring-up support until edge cases are checked against upstream Haxe `4.3.7`.

Strict Cpp Gate3 remains red. This is internal blocker burn-down only, so
README and North Star progress bars stay unchanged unless strict gates and
public usability evidence change.

## Proof Rule

Compact helper support becomes `parity_support` only after black-box oracle
evidence exists for the supported behavior scope:

- write repo-owned Haxe case programs from the matrix below;
- run them with upstream Haxe `4.3.7` on the selected oracle target;
- record observable stdout, stable error category, byte values, ordering, and
  value shape where relevant;
- run the same cases through the Cpp strict/native lane only after the helper is
  classified and compile/runtime support exists;
- report each Cpp case as `pass`, `unsupported_diagnostic`, or
  `known_divergence`;
- keep copied upstream tests and upstream compiler source out of this repo.

Local generated-C++ shape tests are useful smoke evidence. They do not prove
Haxe runtime parity for these helpers.

## Current Decision

The compact primitive helpers listed here remain `bounded_bringup_support`
unless a row explicitly says otherwise. They may continue to support the current
strict-Gate3 burn-down and M14 Cpp smoke path, but they must not be cited as
Full1 parity evidence until their oracle cases pass.

Broad semantic expansion is blocked for these surfaces during this checkpoint:

- new Serializer/Unserializer behavior;
- new Float/NaN/Infinity/Math/JSON/binary numeric behavior;
- new Reflect/Dynamic/default-return behavior;
- fake generated classes for runtime surfaces;
- moving broad helper semantics from `CppTargetCore.hx` into
  `CppRuntimeSupport.hx` without classification.

Bounded non-semantic render/cache work and helper classification work remain
allowed.

## Inventory

| Surface | Helper entry points | Current classification | Freeze note |
| --- | --- | --- | --- |
| Resources | `CppRuntimeSupport.resourceLines`, `renderResourceSupportHelper` for `Resource.listNames`, `getString`, `getBytes` | `bounded_bringup_support` | Missing `getString` currently falls back to an empty string while `getBytes` returns `null`. List order, missing-resource behavior, and byte/string conversion need oracle cases. |
| BaseCode | `CppRuntimeSupport.baseCodeLines`, `renderBaseCodeSupportHelper` for `encodeBytes`, `decodeBytes`, `encodeString`, `decodeString`, `encode`, `decode`, `initTable` | `bounded_bringup_support` | Empty input, invalid alphabets, invalid encoded characters, leftover bits, bytes above `0x7F`, and string/byte conversion need oracle cases. |
| Base64 | `renderBase64SupportHelper` for `encode`, `decode`, `urlEncode`, `urlDecode` | `bounded_bringup_support` | Standard vs URL alphabet, padding/complement handling, invalid input, empty bytes, and binary payloads need oracle cases. |
| Md5 | `renderMd5SupportHelper` for `encode`, `make`, and compact internal method fallbacks | `bounded_bringup_support` | Empty input, ASCII strings, non-ASCII strings, raw bytes, byte/string conversion, and hex casing need oracle cases. Internal fallback methods must not be treated as public parity. |
| Sha1 | `CppRuntimeSupport.sha1Lines`, `renderSha1SupportHelper` for `encode`, `make`, and compact internal method fallbacks | `bounded_bringup_support` | Same freeze requirements as Md5: empty input, bytes, non-ASCII strings, byte/string conversion, and hex casing. |
| StringTools | `renderStringToolsSupportHelper`, static StringTools intrinsic lowering, quoting helpers | `bounded_bringup_support` | URL encode/decode, HTML escape/unescape, trim/space detection, padding, replace, hex, codeAt/EOF, and platform quoting need oracle cases before parity claims. |
| Vector/array helpers | `CppRuntimeSupport.vectorSupportLines` plus generated calls for vector get/pop/remove/splice and selected array-style operations | `bounded_bringup_support` | Out-of-range access and empty `pop` currently use target defaults in helper code. Empty arrays, negative indexes, splice normalization, remove equality, and ordering need oracle cases. |
| Std integer helpers | `CppRuntimeSupport.stdIntrinsicLines` and `Std.parseInt`/literal lowering | `bounded_bringup_support` | Decimal/hex parsing, signs, partial parses, whitespace, overflow, null-like invalid values, and Int64 narrowing errors need oracle cases. |
| Date/time helpers | `CppRuntimeSupport.dateIntrinsicLines` plus `missingDeclarationLines("Date")` | `bounded_bringup_support`, `review_required` for Date parity | UTC construction is narrow support. `Date.toString` currently returns an empty string and must not be treated as parity. Timezone, invalid dates, DST boundaries, and string formatting need oracle cases. |
| StringMap declaration/partial runtime | `missingDeclarationLines("StringMap")`, `missingMethodReturnType` | `declaration_only_support` plus partial bring-up | `get` defaults to `V()` for missing keys and key iteration follows `std::map` order. This is not Map parity without oracle cases. |
| Binary float reinterpret helpers | `CppRuntimeSupport.fpReinterpretLines` | `review_required` | Covered by [`FLOAT_NUMERIC_REVIEW_GATE.md`](FLOAT_NUMERIC_REVIEW_GATE.md). Do not expand from this bead. |

The following nearby helpers are intentionally excluded from this freeze because
they have separate owning checkpoints:

- Reflect/Dynamic/default-return helpers:
  [`CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md`](CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md).
- Serializer/Unserializer behavior:
  [`SERIALIZER_UNSERIALIZER_BEHAVIOR_MATRIX.md`](SERIALIZER_UNSERIALIZER_BEHAVIOR_MATRIX.md).
- Float/NaN/Infinity/JSON/binary numeric behavior:
  [`FLOAT_NUMERIC_REVIEW_GATE.md`](FLOAT_NUMERIC_REVIEW_GATE.md).
- Sys/event-loop and Http smoke scaffolding: `haxe_ocaml-zo90`.

## Oracle Matrix

Each case should be generated from repo-owned source and compared against
upstream Haxe `4.3.7`. The Cpp lane may report `pass`,
`unsupported_diagnostic`, or `known_divergence`; only `pass` with oracle
evidence can promote a helper row to `parity_support`.

| ID | Scope | Oracle expectation | Cpp gate before promotion |
| --- | --- | --- | --- |
| `cpp-prim-resource-01` | `Resource.listNames` with zero, one, and multiple embedded resources | Pin ordering and exact names. | Resource table order is deterministic and matches oracle behavior for the supported target. |
| `cpp-prim-resource-02` | `Resource.getString` and `getBytes` for present and missing names | Pin missing-name result, byte length, byte values, and string conversion. | Missing resources do not silently become successful empty resources unless oracle-backed. |
| `cpp-prim-basecode-01` | `BaseCode.encodeBytes`/`decodeBytes` for empty, ASCII, binary, and non-ASCII byte payloads | Pin encoded bytes, decoded bytes, and round-trip behavior. | Byte conversion and leftover-bit behavior match oracle. |
| `cpp-prim-basecode-02` | Invalid alphabet length and invalid encoded characters | Pin stable error category/message where stable. | Cpp throws or diagnoses unsupported cases instead of returning defaults. |
| `cpp-prim-base64-01` | `Base64.encode`/`decode` with complement true/false | Pin exact strings, decoded byte values, and padding behavior. | Standard alphabet and complement semantics match oracle. |
| `cpp-prim-base64-02` | `Base64.urlEncode`/`urlDecode` and invalid input | Pin URL alphabet behavior, padding, and stable error category. | URL alphabet and invalid-input behavior are classified. |
| `cpp-prim-hash-01` | `Md5.encode`/`Md5.make` for empty, ASCII, non-ASCII, and raw bytes | Pin hex casing, digest bytes, and string-vs-byte input behavior. | Cpp digest helpers match oracle for selected inputs. |
| `cpp-prim-hash-02` | `Sha1.encode`/`Sha1.make` for empty, ASCII, non-ASCII, and raw bytes | Pin hex casing, digest bytes, and string-vs-byte input behavior. | Cpp digest helpers match oracle for selected inputs. |
| `cpp-prim-stringtools-01` | URL encode/decode, HTML escape/unescape, and replace | Pin escaping tables, quote behavior, malformed percent input, and replacement behavior. | Cpp helpers match selected string cases or diagnose unsupported ones. |
| `cpp-prim-stringtools-02` | `contains`, `startsWith`, `endsWith`, `trim`, `ltrim`, `rtrim`, `isSpace`, `lpad`, `rpad` | Pin empty strings, Unicode/non-ASCII bytes, whitespace set, negative/large positions, and padding with empty pad strings. | Cpp helpers do not widen byte-level behavior into a Unicode parity claim without evidence. |
| `cpp-prim-stringtools-03` | `hex`, `fastCodeAt`, `unsafeCodeAt`, `isEof`, quoting helpers | Pin negative values, width/padding, out-of-range indexes, EOF sentinel behavior, and platform quoting. | Cpp output is oracle-backed for the selected platform or classified as target-specific. |
| `cpp-prim-vector-01` | Vector/array `get`, `pop`, `remove`, `splice`, `join`, `split`, `sort`, `map` smoke surfaces | Pin empty arrays, out-of-range access, negative splice indexes, equality behavior, mutation side effects, and ordering. | Cpp default-return cases are oracle-backed or replaced by diagnostics. |
| `cpp-prim-stdint-01` | `Std.parseInt` decimal/hex parsing | Pin signs, whitespace, partial parses, invalid strings, overflow, and null/empty cases where applicable. | Cpp `std::stoi` behavior is not assumed to be Haxe behavior without oracle output. |
| `cpp-prim-stdint-02` | Integer literal and Int64-to-Int narrowing helpers | Pin signed/unsigned suffixes, hex literals, overflow, and exception category. | Cpp narrowing and literal parsing are classified before parity claims. |
| `cpp-prim-date-01` | UTC date construction | Pin epoch seconds/time value for stable UTC inputs and invalid date normalization. | Cpp `timegm`/`_mkgmtime` behavior is accepted only for selected oracle-backed inputs. |
| `cpp-prim-date-02` | `Date.toString` and local/timezone-sensitive surfaces | Pin string formatting and timezone-sensitive behavior where stable. | Current empty-string `Date.toString` remains non-parity until replaced or diagnosed. |
| `cpp-prim-stringmap-01` | `StringMap.get`, `set`, `keys`, `toString` | Pin missing-key behavior, null/default values, key ordering where observable, Unicode keys, and string output. | Partial Cpp `StringMap` support is not treated as Map parity without oracle evidence. |

## Oracle Runner Plan

The first runner should be a seed runner, not a broad upstream-suite substitute.
Use repo-owned cases under:

```text
test/oracle/cpp_compact_primitives_seed/src/Main.hx
```

Recommended command shape:

```bash
npm run test:cpp-compact-primitives-oracle
```

The runner should:

- require exact upstream Haxe `4.3.7`;
- run the seed program through upstream Haxe, initially with `--interp` unless a
  specific target is needed for stable behavior;
- compare stdout to
  `test/oracle/cpp_compact_primitives_seed/expected.stdout`;
- write a local report to `.tmp/cpp-compact-primitives-oracle/report.json`;
- include Cpp results only when the Cpp lane can compile/run the selected cases;
- classify every Cpp case as `pass`, `unsupported_diagnostic`, or
  `known_divergence`.

Do not copy upstream Haxe tests into the seed directory. The cases should be
small repo-owned programs derived from the matrix above.

## Minimum Resume Criteria

Before expanding any compact primitive helper beyond its current bounded scope:

- name the touched inventory row and oracle case IDs in the implementation bead;
- capture upstream Haxe `4.3.7` oracle output for those cases;
- identify whether the Cpp lane is expected to pass, diagnose unsupported
  behavior, or report a known divergence;
- add focused local checks for generated helper routing or runtime behavior;
- route Float-sensitive cases through
  [`FLOAT_NUMERIC_REVIEW_GATE.md`](FLOAT_NUMERIC_REVIEW_GATE.md);
- route Serializer/Unserializer dependencies through
  [`SERIALIZER_UNSERIALIZER_BEHAVIOR_MATRIX.md`](SERIALIZER_UNSERIALIZER_BEHAVIOR_MATRIX.md);
- route Reflect/Dynamic dependencies through
  [`CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md`](CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md);
- review README/North Star progress bars and record the expected default:
  unchanged.

This checkpoint permits narrow cleanup, extraction, and oracle-runner work. It
does not permit broad runtime parity claims from compact helper smoke evidence.
