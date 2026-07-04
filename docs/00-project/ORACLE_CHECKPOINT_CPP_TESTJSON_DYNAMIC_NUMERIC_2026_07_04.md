# Oracle Checkpoint: Cpp TestJson Dynamic Numeric Frontier

Last prepared: 2026-07-04
Status: pending external Oracle/GPT 5.5 Pro review; implementation blocked

Related bead:

- `haxe_ocaml-0rfy` - Cpp strict: review TestJson JSON dynamic/numeric frontier

## Purpose

Record the review request for the current strict Cpp `TestJson` frontier before
changing JSON, `Dynamic`, or Float special-value behavior.

This checkpoint is required because the first C++ diagnostics mix several
guarded surfaces:

- `haxe.Json.stringify` on structural values;
- `haxe.format.JsonPrinter.print` and `JsonParser.parse` carrier behavior;
- `Dynamic` value representation through `std::any` and generated structural
  records;
- local function calls with omitted `?pos:haxe.PosInfos`;
- JSON printing of positive Infinity, negative Infinity, and `NaN`.

The review output should be a seam recommendation, invariants, and validation
plan. It must not provide implementation code for direct transcription.

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
implementation before the external review response is accepted.

Target-stability probe on 2026-07-04:

- Neko output matched the `--interp` seed for finite numeric formatting, signed
  zero, non-finite JSON `null`, `JsonPrinter` function behavior, and the invalid
  JSON error.
- Neko differed from `--interp` for Unicode string length/code units after
  parsing `"\\u00E9"`: `--interp` reports length `1` and code `233`, while Neko
  reports length `2` and byte codes `195,169`.
- JS did not run the seed as written because `Sys.println` requires a system
  target. Use a deliberately target-neutral emitter before treating JS as
  target-stability evidence.
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

Review should decide whether `--interp` is sufficient for the implementation
scope or whether selected targets also need oracle runs before behavior changes.
Object field order should not be treated as a stable contract unless a selected
oracle target proves it stable.

## Local Hypothesis For Review

The current frontier should probably be split into two implementation seams
after review:

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

## Review Prompt

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

## Implementation Freeze

Do not implement Cpp JSON, Float special-value, or broad `Dynamic`
stringification changes from this checkpoint until an external review response
is recorded and accepted in the bead or in this document.

Allowed before review:

- collect behavior-level evidence;
- add or refine this checkpoint/prompt;
- prepare repo-owned oracle case descriptions;
- record current strict logs and review blockers.

Blocked before review:

- new `Json.stringify`/`JsonPrinter` runtime semantics;
- new special Float formatting or JSON behavior;
- broad `__hxhx_stringify` overload expansion for structural values;
- new erased `Dynamic` defaults that silently turn unsupported values into
  strings, nulls, zeroes, empty objects, or empty arrays;
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
