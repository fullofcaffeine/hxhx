# Final runtime-use reconciliation: second-pass review

## Outcome

The OCaml target now rejects a private runtime helper when final target
assembly uses its checked permission too many times, omits it, changes its
owner or target symbol, changes its profile, or places owner-local uses in a
different order. This is an additional whole-request check; the smaller
lowering checks remain in place so a developer still gets an error near the
decision that first created a bad helper call.

For example, a lowering decision may authorize one `HxBytes.toString` call in
a Haxe catch body. The target emits that body for both Haxe's typed exception
channel and OCaml's native exception channel. The second channel now receives
a new explicit output-copy identity. Reusing the original hidden identity in
both channels fails before the OCaml printer or output transaction can publish
the program.

## Design review

- **One request owns the ledger.** `CompilationContext` starts a fresh final
  authority with the program revision and active portable/metal profile. The
  authority has no process-global state and is sealed once output assembly
  finishes.
- **Plans grant permission; text does not.** A local authority registers plain
  immutable occurrence facts only after its expression or checked generated
  text reconciles successfully. Rendered OCaml names cannot add permission.
- **Final structured output spends permission.** Class, enum, static-storage,
  standalone-expression, type-registry, and checked Dune/plugin entry output is
  observed at its last identity-preserving boundary. Hidden IDs are counted
  before structured printing or file publication.
- **Repeated planning is not repeated output.** The compiler may prepare the
  same sealed function more than once. Identical plan registration is therefore
  an idempotent set union. Reusing the corresponding hidden ID in final syntax
  remains a counted duplicate and fails. Reusing one key with different facts
  also fails.
- **Intentional copies are explicit.** Dispatch constructors and the second
  catch channel clone accepted hidden references to new owner-bound IDs. The
  copy operation verifies that nested original IDs did not survive the clone.
  Normal and empty instance construction already create their defaults through
  separate owner roles; the String tracer exercised both paths without adding
  a blanket duplication exception.
- **Legacy debt is not silently authorized.** The final ledger counts only
  `ERuntimeIdent` references and checked generated-text references that already
  carry authority. The remaining 388 plain private-runtime sites stay in the
  machine-checked migration inventory. A plain helper name is not upgraded to
  an authorized occurrence merely because another plan uses the same name.
- **Cached replay keeps the same trust boundary.** A new source-bundle cache
  entry can be admitted only after this miss-path check succeeds. A later exact
  replay validates that immutable admitted bundle; it does not reconstruct
  target plans from rendered text.
- **Packaging filters remain separately owned.** The ledger proves the complete
  compiler-produced structured module set before optional artifact exclusion.
  The artifact manifest and output transaction own which already-validated
  files are packaged and published. Excluding a file does not grant or repair
  a runtime helper occurrence.

## Test sensitivity and independent evidence

The focused red state was a missing `OcamlFinalRuntimeUseAuthority` type and
constructor contract. After implementation, focused fixtures prove valid
U1/U2 order, missing use, duplicate use, nested explicit copy, repeated-plan
idempotence, conflicting repeated facts, unplanned use, stale plan, wrong
owner, wrong symbol, wrong profile, checked-text duplication, and corruption
of otherwise immutable test-only boundary values.

The real tracer is `test/portable/fixtures/string_null_storage`. Its expected
stdout is independently authored and is also produced with upstream Haxe
4.3.7 on JavaScript and Neko. The target path generated OCaml, built it with
Dune, ran the native executable, reproduced the expected behavior, retained a
deterministic lowering report, and passed source-shape checks. The fixture now
writes its upstream oracle artifacts to a temporary directory, so those files
cannot pollute or influence the OCaml artifact inventory.

Two additional native paths passed: optional String function-value calls and
the exact Int/static-call fixture. They exercise existing runtime-use plan
families through the new whole-request check.

## Verification

- `RUNTIME_USE_AUTHORITY:PASS`
- `CHECKED_GENERATED_TEXT:PASS`
- `TYPE_REGISTRY_GENERATED_TEXT:PASS`
- `STRING_NULL_STORAGE_ORACLE_REPORT_AND_SOURCE_SHAPE:PASS`
- native output equality for `optional_args_non_field_call`
- native output equality for `call_exact_int_static`
- `REFLAXE_OCAML_RUNTIME_REFERENCE_INVENTORY:PASS entries=388`
- Haxe formatting, no-Dynamic, local-path, mega-file, shell-syntax, and diff
  checks passed

The aggregate npm runtime-use command was not used as closure evidence because
its repository-wide `nullSafety("reflaxe.ocaml")` traversal has the separately
tracked Haxe 4.3.7 performance problem `haxe_ocaml-850ii.23`. The three direct
focused fixtures compile the same owners without that unrelated traversal, and
the native tracers exercise the real macro target route.

## Residual scope and review disposition

This slice does not reduce the 388-entry migration inventory, complete runtime
source-selection authority, Full1 compatibility scope, or README readiness.
Those remain owned by the parent work. No generated OCaml was hand-edited, no
Haxe compiler objects are retained, and no handwritten OCaml semantics were
added.

GPT-5.6 Pro Oracle was deliberately skipped. The failing boundary was concrete,
the real compiler exposed each intentional duplication, focused tests could
state the invariant directly, and the implementation converged without an
undefined cross-layer design decision.
