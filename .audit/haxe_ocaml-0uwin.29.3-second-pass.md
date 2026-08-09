# Second-pass review: Dynamic stringifier generated text

## Outcome

No closure blocker remains for the Dynamic stringifier slice. A class whose
typed `toString` method is eligible for Dynamic dispatch still produces the same
OCaml registration line and runtime result. The difference is that
`HxDynamic.register_class_stringifier` now has one preplanned use, one exact
`HxDynamic` requirement, and one checked position in the complete generated
file before publication.

This closes generated-text inventory debt for `HxTypeRegistry.ml`; it does not
close the broader private-runtime reference inventory or prove requirements-only
runtime source selection.

## What callers can now rely on

- The compiler sorts eligible class names, selects the existing typed
  stringifier adapter, and plans one stable `dynamic-stringifier:<class>` use.
- The use is bound to the existing
  `compiler-type-registry-dynamic-string` capability. That capability names
  `HxDynamic` as its one exact runtime root and explains the generated registry
  behavior.
- The corresponding program module and method names remain on the separate
  sealed program-identifier list. They do not become runtime requirements just
  because a user-program OCaml identifier begins with `Hx`.
- Runtime uses now name their generated-file section. Constructor adapters are
  reconciled before empty-constructor metadata, while Dynamic stringifiers are
  reconciled after class-field metadata. Repeated uses must match sorted final
  output order.
- Missing, duplicate, stale, wrong-symbol, wrong-root, wrong-profile, and
  reordered checked uses fail before publication through the shared runtime-use
  authority. The focused fixture adds Dynamic-specific wrong-symbol and
  repeated-order failures.
- The type-registry-specific `legacyRuntimeToken`, `addLegacyRuntimeUse`, and
  legacy template-token branch are deleted. HxTypeRegistry has no path to add an
  unchecked private runtime identifier.

## Scope check

`OcamlCheckedGeneratedText` still contains a generic legacy placeholder facility
for other migration owners and its own negative fixtures. This task did not
delete that shared facility because its acceptance is specifically the
type-registry exception. A repository-wide search confirms that production
HxTypeRegistry generation no longer calls it, and the private-reference
inventory has no `generated-text` entries.

The generated-file section is authority metadata, not a second compiler mode.
It does not choose whether a class receives a stringifier, choose the target
method, change output text, or add a printer repair. Those semantic decisions
remain in the existing Haxe-owned compilation context and one emission loop.

## Evidence reviewed

- Behavior-first baseline and post-change vertical proof:
  `PORTABLE_FIXTURE_ALLOWLIST=inline_dynamic_carrier PORTABLE_JOBS=1 bash scripts/test-portable.sh`.
  The fixture compiles, builds, runs, and checks the exact registration shape.
- Exact generated `HxTypeRegistry.ml` SHA-256 before and after:
  `bde7f6264f979b840a5c3ea6ff257fadcd57714d9d14381b0f265e499fc838ca`.
- Focused expected red, then green owner:
  `npm run test:reflaxe-ocaml:type-registry-generated-text`.
- Shared missing, duplicate, stale, wrong-symbol, wrong-root, profile, order,
  marker, and changed-hash matrix:
  `npm run test:reflaxe-ocaml:runtime-use-authority`.
- Existing exact requirement model:
  `npm run test:reflaxe-ocaml:runtime-requirements`.
- Runtime source manifest integrity:
  `npm run test:reflaxe-ocaml:runtime-manifest`.
- Real compiler/runtime packaging, including the existing Dynamic-string
  requirement: `npm run test:m6:runtime`.
- Private-reference inventory:
  `npm run guard:reflaxe-ocaml-runtime-reference-inventory`, now 428 entries,
  revision `469c7cfa5ec41dabc2a6c8f350485ae43117c4948f466020ba4bc080966ded9a`,
  with zero `generated-text` rows.
- Repository Haxe formatting: `npm run guard:hx-format`.
- Patch whitespace: `git diff --check`.

## Test-design correction

The first finished fixture also expected a runtime-looking name inside an OCaml
string literal to fail. That expectation was wrong: a string is data and cannot
call the runtime. The old scenario mattered only because a legacy placeholder
could be inserted into a string while pretending to authorize executable code.
Once the type-registry legacy API was removed, the meaningful negative case was
the existing direct unchecked-code call. The invalid string-literal case was
removed and recorded in the decision trail rather than weakening the scanner.

## Oracle disposition

No additional Oracle review was requested. The accepted parent architecture
already defines this complete-file boundary, the implementation is a bounded
final migration, and focused tests directly exercise the only new ordering
choice. This written second pass satisfies the repository's `thinking:xhigh`
review requirement without spending an Oracle review on a converged seam.

## Deferred work

- `haxe_ocaml-0uwin.31` still owns the proof that recorded requirements alone
  select the complete runtime source set.
- The remaining 428 inventory rows belong to structured expression, pattern,
  raw-boundary, and type migrations; they are not generated-text exceptions.
- README goals and readiness remain unchanged. This change removes one unsafe
  migration bridge but does not establish product, Full1, or release closure.
