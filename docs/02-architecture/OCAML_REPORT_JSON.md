# Portable lowering-report digests

The report writer and inspector use the same JSON bytes to compute each aggregate digest.
A report generated through Haxe Eval can therefore pass inspection through a compiled Neko CLI.
Previously, host object-field order changed the digest even when every reported value matched.

`reflaxe.ocaml.reports.OcamlReportJson` owns this encoding boundary.
It validates incoming JSON-shaped values, copies them into a closed recursive type, and writes that type directly.
The writer does not depend on host object enumeration.

## Encoding contract

- Object members sort by the UTF-8 bytes of their names.
- Arrays retain their input order.
- Supported scalar values are null, Boolean, Haxe Int, and String.
- Integers and strings use Haxe JSON spelling. Whitespace is absent from digest input.
- SHA-256 receives explicit UTF-8 bytes through `Bytes.ofString`, rather than host string units.
- Digests use the prefix `sha256:` and lowercase hexadecimal output.
- Other classes, functions, enums, non-Int numbers, and nesting beyond 256 levels are rejected.

For example, both `{"b":2,"a":1}` and `{"a":1,"b":2}` encode as `{"a":1,"b":2}`.
Array order and the distinction between an absent member and an explicit null remain significant.
Readable report files use the same ordering with two-space indentation and one final newline.
Indentation does not enter an aggregate digest.

This contract covers integer-valued report facts. It does not define a general JSON canonicalization or floating-point protocol.

## Revision inventory

Lowering schema **88** requires this encoding for the following aggregate revision fields.
The named collections keep their existing semantic sorting and validation rules.

| Revision field | Digest input |
| --- | --- |
| `representationRevision` | representations |
| `representedArrayRevision` | represented arrays |
| `anonymousStructureRevision` | object with structures and operations |
| `structuralFieldRevision` | structural fields |
| `iMapInterfaceRevision` | object with conversions, calls, and storage aliases |
| `localConversionRevision` | local conversions |
| `containerElementRequiredConversionRevision` | required conversion IDs |
| `containerElementConversionRevision` | container-element conversions |
| `unsafeOperationRevision` | unsafe operations |
| `callRevision` | object with calls and callable boundaries |
| `reflectCompareRevision` | comparison decisions |
| `stdIsOfTypeRevision` | type-check decisions |
| `intUnaryRevision` | integer unary decisions |
| `functionResultBoundaryRevision` | function result boundaries |
| `controlRevision` | object with targets, decisions, and catch chains |
| `controlCatchRevision` | catch chains |
| `controlTargetRevision` | control targets |
| `controlAdmissionRevision` | control admissions |
| `admittedInputRevision` | admitted plans |
| `runtimeRequirementRevision` | included runtime requirements |

`arrayLiteralProducerRevision` and `staticStorageRevision` retain their explicit, non-JSON fingerprint contracts.
Individual semantic identities and other report formats retain their existing contracts.
This change does not establish portability for every compiler or runtime hash.

## Hard cut and cached output

The inspector rejects schema 87 and all other unsupported lowering schemas. Regenerate those reports with the current compiler.
There is no fallback digest algorithm.

`OcamlTargetImplementationRevision` hashes paths and bytes across the installed backend source tree.
Changes to this encoder or its callers therefore invalidate reusable target output.
Function-plan pipeline versions remain unchanged because this migration changes report encoding, not function semantics.

## Verification

Run `npm run test:reflaxe-ocaml:report-json` for fixed byte expectations through Eval and Neko.
The fixture checks non-ASCII strings and keys, signed integer limits, array order, nested mutations, rendering, and unsupported values.
Its expected SHA-256 comes from independently hashing the literal UTF-8 bytes.

Run `npm run test:reflaxe-ocaml:inspect` for generated-artifact acceptance and corrupt-report rejection.
Regenerate lowering snapshots through `scripts/test-portable.sh` with `PORTABLE_UPDATE_LOWERING_GOLDENS=1`.
That runner requires two byte-identical compiler reports before replacing a snapshot, then checks native behavior.

The [migration evidence](../00-project/OCAML_REPORT_JSON_MIGRATION_EVIDENCE.json) records the base revision, snapshot comparisons, and local checks.
