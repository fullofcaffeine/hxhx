# Oracle Checkpoint: Cpp TestJson Dynamic Numeric Frontier

Last prepared: 2026-07-04
Status: external Oracle/GPT 5.5 Pro review accepted; implementation split

Related bead:

- `haxe_ocaml-0rfy` - Cpp strict: review TestJson JSON dynamic/numeric frontier
- `haxe_ocaml-ghy0` - Cpp TestJson frontier: split JSON seam and PosInfos
  implementation
- `haxe_ocaml-ghy0.1` - Cpp JSON carrier seam for TestJson frontier
- `haxe_ocaml-ghy0.2` - Cpp optional callable defaults and PosInfos injection

## Purpose

Record the review request and accepted response for the current strict Cpp
`TestJson` frontier before changing JSON, `Dynamic`, or Float special-value
behavior.

This checkpoint is required because the first C++ diagnostics mix several
guarded surfaces:

- `haxe.Json.stringify` on structural values;
- `haxe.format.JsonPrinter.print` and `JsonParser.parse` carrier behavior;
- `Dynamic` value representation through `std::any` and generated structural
  records;
- local function calls with omitted `?pos:haxe.PosInfos`;
- JSON printing of positive Infinity, negative Infinity, and `NaN`.

The review output is a seam recommendation, invariants, and validation plan. It
is not implementation code for direct transcription.

## Review Disposition

The external Oracle response accepted the local hypothesis with one correction:
the frontier must split into two independent implementation beads, and the
`?pos:haxe.PosInfos` bead must model call-site `PosInfos` injection rather than
ordinary optional-argument defaulting alone.

Accepted seams:

1. Add a Cpp-owned JSON carrier/runtime seam for `haxe.Json.stringify`,
   `haxe.format.JsonPrinter.print`, and scoped `haxe.format.JsonParser.parse`.
2. Add local callable optional/default argument support separately, including
   call-site injection for omitted `?pos:haxe.PosInfos`.

Rejected shortcut:

- Do not make the current C++ errors disappear by adding broad anonymous-struct,
  vector/map, or `std::any` overloads to `__hxhx_stringify`.

That shortcut would conflate separate semantics: `Std.string`, JSON encoding,
`Dynamic` erasure, structural records, non-finite float behavior, and unsupported
runtime values.

README/North Star progress bars remain unchanged from this checkpoint alone.
The review accepts an implementation plan; it does not prove Cpp strict parity,
Haxe JSON parity, broad `Dynamic`, `Reflect`, Float, or hxcpp compatibility.

## Accepted JSON Seam

JSON behavior is owned by a JSON-specific Cpp runtime seam, preferably extracted
out of `CppTargetCore.hx` into Cpp-owned runtime/helper support as the behavior
grows.

`haxe.Json.stringify` and `haxe.format.JsonPrinter.print` should lower into the
same behavior-scoped JSON path. They must not route arbitrary structural values
through:

- `std::to_string`;
- `__hxhx_stringify`;
- broad `Std.string` helpers;
- fallback `std::any` type-name rendering.

The JSON seam owns:

- conversion from supported Haxe values into a Cpp JSON carrier;
- recursive JSON printing;
- scoped JSON parse results;
- null representation;
- `JsonPrinter` function behavior;
- object field traversal;
- array traversal;
- numeric JSON formatting.

Use `std::any` only as a box around known supported JSON carrier shapes, not as a
universal replacement for Haxe `Dynamic`.

A safe first-slice carrier distinguishes:

- JSON null;
- bool;
- int;
- float;
- string;
- array/list of JSON values;
- object with named JSON values;
- generated anonymous-record adapters;
- function marker or callable predicate where `JsonPrinter` needs function
  behavior;
- unsupported value.

Unsupported values must not silently become `null`, `0`, `false`, `""`, `{}`,
`[]`, or type-name strings. Unsupported should be outside the accepted slice or
produce an explicit unsupported diagnostic.

## Accepted JSON Behavior Scope

For the observed `TestJson` frontier, `haxe.Json.stringify` support is limited
to:

- structural anonymous objects;
- nested anonymous objects;
- arrays;
- mixed dynamic arrays where every element is in the accepted JSON carrier set;
- strings with JSON escaping;
- ints;
- finite floats in the accepted numeric scope;
- bool;
- null;
- positive Infinity, negative Infinity, and `NaN` as JSON `null`.

Replacer and pretty-printing remain out of scope unless separate cases are
accepted. A non-null replacer or non-empty space must not silently behave
approximately.

`haxe.format.JsonPrinter.print` uses the same JSON printer, with scoped support
for:

- top-level function value prints as JSON string `"<fun>"`;
- object fields whose values are functions are skipped;
- supported non-function fields print normally;
- non-finite floats print as `null`.

`haxe.format.JsonParser.parse` should return a JSON carrier/object
representation, not a raw string and not an arbitrary `std::any` blob whose
meaning depends on broad `Dynamic` fallback.

For this slice, parser support is limited to objects, arrays, strings,
ints/floats in the accepted numeric scope, bool, null, and enough field/array
access to support the seed summaries and `deepId` round trips.

Invalid JSON error wording may match `--interp` for this seed, but it must not
be presented as a cross-target stability contract because JS already differs.

Generated anonymous C++ structs should participate in JSON through
JSON-context adapters/descriptors, not through generic stream operators or
string helpers.

Arrays adapt recursively into JSON values. Do not convert arrays to strings and
then print those strings as JSON.

Function behavior is scoped to JSON printing only. It does not complete general
`Reflect.isFunction`, `Dynamic`, or callable erasure support.

JSON null needs a real carrier state. Do not use empty `std::any` as both JSON
null and unsupported/missing value unless a separate tag distinguishes them.

## Numeric Scope

For this slice, JSON printing matches the observed upstream behavior:

- positive Infinity prints as `null`;
- negative Infinity prints as `null`;
- `NaN` prints as `null`.

This applies to both `haxe.Json.stringify` and
`haxe.format.JsonPrinter.print`, and remains scoped to JSON.

Do not use `std::to_string` for JSON floats. It produces fixed trailing zeros
and does not match the seed behavior.

The first finite float scope is bounded to the accepted seed and adjacent
`TestJson` cases:

- `0.15461`;
- `-485.15461`;
- `1.456`;
- `10000000000`;
- `-1e-10`;
- signed `0.0`;
- signed `-0.0`.

For Cpp JSON, use `--interp` as the selected oracle for negative zero, while
recording JS negative-zero divergence as target-specific. Do not claim hxcpp
parity because hxcpp was unavailable locally.

The `-1e-10` case should remain compact lowercase exponent form for the accepted
seed, without turning that into broad float exponent-formatting parity.

## PosInfos And Optional Callable Scope

The omitted `?pos:haxe.PosInfos` failure is independent of JSON.

Ordinary optional local-function arguments need a valid default/null
representation at the call boundary.

Omitted `?pos:haxe.PosInfos` arguments should receive a call-site `PosInfos`
value, not plain null. A bounded first slice may provide a non-null Cpp
`PosInfos` value sufficient for the current test. Exact file name, line number,
class name, and method name parity should remain bounded until oracle-backed by
field-specific tests.

The Cpp backend should make local lambdas or local callable wrappers callable
with the Haxe call shape, either by injecting omitted arguments at call sites,
emitting wrappers that supply defaults, or preserving enough function type
information for the call renderer to append missing optional arguments.

For `?pos:haxe.PosInfos`, call-site injection is the accepted semantic model.

## Invariants

- JSON behavior is owned by the JSON seam.
- `std::any` support in this slice is not general Haxe `Dynamic` support.
- Unsupported is not null, except for actual Haxe/JSON null and JSON
  non-finite float behavior.
- Anonymous structural records enter JSON only through JSON-context
  adapters/descriptors.
- Numeric behavior is surface-specific to JSON printing/parser round trips.
- Object field order is not a broad stable Haxe contract; Cpp may choose
  deterministic field emission for source stability, but validation should
  prefer parse summaries or explicitly Cpp-local canonical ordering.
- Function printing/skipping is JSON-printer behavior only.
- `JsonParser.parse` returns a structured value carrier, not a string.
- This frontier does not justify production-readiness claims or README/North
  Star movement.
- Upstream Haxe remains behavior evidence only; do not copy, translate, or
  mechanically rewrite upstream compiler or stdlib implementation code.

## Accepted Implementation Split

Proceed with two separate implementation beads:

1. Cpp JSON carrier/runtime seam for `Json.stringify`, `JsonPrinter.print`, and
   scoped `JsonParser.parse` support.
2. Cpp optional local callable defaults and `?pos:haxe.PosInfos` call-site
   injection.

Do not bundle `PosInfos` with JSON behavior. Do not implement broad
`__hxhx_stringify` overloads for anonymous structs. Do not treat `std::any` as a
universal `Dynamic` model.

## Current Evidence

Latest relevant commit before this checkpoint: `fcb969db`.

Strict source generation passed:

```text
.artifacts/full1/cpp-strict-current/direct-source-only-after-duplicate-local-overrides.log
```

Direct C++ compile then failed first in generated `TestMain.cpp` around
`TestJson`:

```text
.artifacts/full1/cpp-strict-current/direct-cpp-compile-after-duplicate-local-overrides.log
```

First diagnostic families:

- `haxe.Json.stringify` lowers a structural anonymous value through
  `std::to_string(<anonymous struct>)`.
- A local `id(v:Dynamic, ?pos:haxe.PosInfos)`-style function is rendered as a
  two-argument C++ lambda, while call sites provide only the value argument.
- A `deepId`-style path forces structural JSON round-trip values through
  `std::string` conversion instead of a JSON value carrier.
- Adjacent assertions check JSON output for positive Infinity, negative
  Infinity, and `NaN` as `null`.

This crosses [`FLOAT_NUMERIC_REVIEW_GATE.md`](FLOAT_NUMERIC_REVIEW_GATE.md),
[`CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md`](CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md),
and [`CPP_HELPER_RENDERING_POLICY.md`](CPP_HELPER_RENDERING_POLICY.md).

## Upstream Oracle Smoke

Initial black-box oracle run used the local upstream Haxe `4.3.7` binary with
`--interp` and a small repo-owned temporary program. This is preliminary
behavior evidence for the review, not a complete parity suite.

The repo-owned seed runner for this frontier is:

```bash
npm run test:cpp-testjson-oracle-seed
```

It executes cases under
`test/oracle/cpp_testjson_dynamic_numeric_seed/src/Main.hx`, compares stdout to
`test/oracle/cpp_testjson_dynamic_numeric_seed/expected.stdout`, and writes a
local report to `.tmp/cpp-testjson-dynamic-numeric-oracle-seed/report.json`.
The runner is upstream-oracle evidence only; it does not unblock Cpp
implementation outside the accepted review seams and does not prove Cpp parity by
itself.

Target-stability probe on 2026-07-04:

- Neko output matched the `--interp` seed for finite numeric formatting, signed
  zero, non-finite JSON `null`, `JsonPrinter` function behavior, and the invalid
  JSON error.
- Neko differed from `--interp` for Unicode string length/code units after
  parsing `"\\u00E9"`: `--interp` reports length `1` and code `233`, while Neko
  reports length `2` and byte codes `195,169`.
- JS now runs through a target-neutral fixture emitter. It matched `--interp`
  for Unicode length/code units, finite numeric formatting except signed
  negative zero, non-finite JSON `null`, `JsonPrinter` function behavior, and
  structural summary semantics.
- JS differed from `--interp` for the first structural object field order,
  signed negative zero (`0` instead of `-0`), and invalid JSON error wording
  (`SyntaxError: Expected ':' after property name in JSON at position 3` instead
  of `Invalid char 34 at position 3`).
- `hxcpp` was not available in the local haxelib list, so upstream Cpp target
  behavior was not checked locally.

Observed output:

```text
json.obj={"a":["hello","wor'\"\n\t\rd"],"x":-4500,"y":1.456}
id.pos=true
id.round=true
id.pos=true
id.round=null
id.pos=true
id.round=0.15461
id.pos=true
id.round=-1e-10
deep.field={"field":4}
deep.nested={"test":{"nested":null}}
deep.mix={"array":[1,2,3,"str"]}
unicode.code=233
json.posinf=null
json.neginf=null
json.nan=null
printer.posinf=null
printer.neginf=null
printer.nan=null
printer.fun="<fun>"
printer.skipfun={"b":1}
```

The accepted review uses `--interp` as the primary oracle for this bounded Cpp
slice, while retaining Neko and JS output as target-stability evidence. Object
field order should not be treated as a stable contract unless a selected oracle
target proves it stable.

## Accepted Local Hypothesis

The current frontier is split into two implementation seams:

1. JSON value representation and printing. `haxe.Json.stringify` and
   `haxe.format.JsonPrinter.print` should share a behavior-scoped Cpp JSON
   carrier path rather than routing arbitrary structural values through
   `std::to_string` or broad `Std.string` helpers.
2. Optional local-function defaults and `PosInfos` injection. The omitted
   `?pos:haxe.PosInfos` calls look like a callable call-shape/defaulting issue,
   not a JSON printer issue.

The dangerous shortcut is adding broad `__hxhx_stringify` overloads for
anonymous structs and treating that as JSON support. That would make structural
values compile, but it risks conflating Haxe `Std.string` behavior, JSON
encoding, `Dynamic` erasure, and special Float handling.

## Original Review Prompt

Please review the whole repository architecture and the current strict Cpp
`TestJson` frontier.

Current evidence:

- commit `fcb969db` passed strict source-only Cpp generation in about 1303s;
- direct C++ compile first errors are in generated `TestJson` code around
  structural `Json.stringify`, omitted optional `PosInfos` arguments, and
  JSON special-Float assertions;
- docs already classify Float/NaN/Infinity/JSON, Reflect/Dynamic, and broad
  runtime helper behavior as review-required before semantic expansion.

Constraints:

- upstream Haxe `4.3.7` is a behavior oracle only;
- do not copy, translate, or mechanically rewrite upstream Haxe compiler or
  test code;
- preserve MIT/provenance discipline;
- keep `CppTargetCore.hx` changes bounded or extract new Cpp-owned helpers
  when behavior grows beyond a narrow seam;
- do not weaken Full 1.0 strict evidence or turn local smoke tests into parity
  claims;
- prefer explicit `unsupported_diagnostic` over fake default behavior when Cpp
  cannot support a case yet.

Please answer with:

1. Recommended seam for Cpp JSON value representation:
   `Json.stringify` lowering, `JsonPrinter`/`JsonParser` runtime support,
   `std::any` carriers, structural anonymous records, arrays, functions, and
   nulls.
2. Whether `__hxhx_stringify` should participate in JSON printing at all, and
   if so, under what narrow invariants.
3. How positive Infinity, negative Infinity, `NaN`, signed zero, finite Float
   precision, and exponent formatting should be scoped for this slice.
4. How omitted `?pos:haxe.PosInfos` local-function arguments should be handled,
   and whether that can be fixed independently of JSON.
5. Invariants that prevent target activation, Dynamic erasure, or
   stringification helpers from redefining Haxe typing or JSON semantics.
6. A minimal validation plan: upstream oracle cases, focused repo-owned smoke
   tests, strict Cpp source/direct-compile evidence, and README/North Star
   status review.

## Post-Review Guardrails

Implementation may proceed only through the accepted split:

- `haxe_ocaml-ghy0.1` owns the bounded Cpp JSON carrier/runtime seam.
- `haxe_ocaml-ghy0.2` owns Cpp optional callable defaults and call-site
  `?pos:haxe.PosInfos` injection.

Still blocked outside those seams:

- broad `__hxhx_stringify` overload expansion for structural values;
- treating `std::any` as a universal `Dynamic` runtime model;
- new special Float formatting or numeric behavior outside JSON;
- new erased `Dynamic` defaults that silently turn unsupported values into
  strings, nulls, zeroes, empty objects, or empty arrays;
- bundling `PosInfos` call-shape behavior with JSON carrier behavior;
- any README/North Star progress-bar movement from this internal frontier.

## Post-Review Validation Sketch

After review acceptance, the implementation bead should identify exact oracle
cases before code changes and then validate with:

- upstream Haxe `4.3.7` oracle output for structural JSON, nested objects,
  dynamic arrays, omitted `PosInfos`, functions in JSON printer output,
  positive Infinity, negative Infinity, `NaN`, and selected finite Float
  formatting;
- focused repo-owned Cpp smoke coverage for the accepted seam;
- `haxelib run formatter` on touched Haxe files;
- `npm run test:m14:cpp-native-backend-smoke`;
- `npm run guard:hx-format`;
- `npm run ci:guards`;
- strict current-source Cpp source-only and direct C++ evidence showing the
  frontier advanced past the current first diagnostics;
- README/North Star review, expected unchanged unless strict gates and public
  production-readiness evidence materially change.
