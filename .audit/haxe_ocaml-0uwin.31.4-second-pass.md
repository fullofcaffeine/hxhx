# Second-pass review: exceptional `Reflect.compare` runtime throws

## Outcome

This slice is safe to commit. Typed `Reflect.compare` keeps the same observable
behavior, but its generated OCaml can now call the private Haxe throw helper
only when the exact sealed comparison decision granted that permission.

Float comparison needs the helper for unordered `NaN` values. Non-nullable
String comparison needs it when one input is unexpectedly null. Each such
comparator owns exactly one `HxRuntime.hx_throw` occurrence. Int comparison and
explicitly nullable String comparison own none.

This removes one legacy inventory entry. It does not finish runtime authority,
change runtime source selection, or advance README readiness.

## Challenges and dispositions

### Does syntax decide for itself whether throwing is allowed?

No. The typed comparison planner chooses the comparison domain and seals the
exact requirement, helper name, semantic role, source identity, target
profiles, and one-use limit. The builder receives that decision and constructs
the helper expression through request-local runtime authority. Missing, stale,
duplicated, or changed evidence fails before the comparator is returned.

### Are ordinary comparisons accidentally coupled to the runtime helper?

No. Int and nullable-String decisions seal empty requirement and occurrence
lists. Inspection also rejects extra throw evidence for those domains, so a
future edit cannot quietly make every comparison depend on the exception
runtime.

### Are both comparator lifecycles covered?

Yes. Most decisions are sealed as part of function planning. The target also
creates a standalone static String comparator through a separate expression
path. The first vertical run exposed that second path because its requirement
was missing from the request ledger. Recording at both decision-sealing points
fixed the ownership gap without teaching syntax to invent a requirement.

### Does saved evidence contain the same facts used during emission?

Yes. The lowering report originally omitted the new rows because it publishes
only explicitly recognized requirement families. The report writer now derives
the expected requirement from each saved Reflect decision, validates it against
the request ledger, and publishes it. Public inspection checks the exact
decision occurrence and the matching ledger row.

### Did the generic ledger acquire a target-specific dependency?

No. An early implementation placed Reflect-specific mapping in the generic
runtime ledger. Its lightweight `reflaxe_runtime` fixture caught the resulting
dependency on Reflaxe compiler types. The mapping now lives in the dedicated
`OcamlReflectCompareRuntimeRequirementRecorder`; the ledger owns only the
capability identifier and generic storage behavior.

### Why is the decision model v3 while the proof prefix remains v2?

The serialized contract changed because decisions gained runtime requirement
and occurrence fields, so readers must reject v2-shaped records. The
independently tested comparison behavior did not change, so retaining the v2
proof prefix truthfully distinguishes a data-model revision from a new
semantic claim.

### Does corruption fail before private OCaml is printed?

Yes. The portable fixture changes the authorized helper name to an invalid
symbol, recomputes the outer decision checksum, and confirms that public
inspection still rejects the stale or conflicting occurrence. The focused
authority tests also cover missing, duplicate, stale, and unauthorized private
runtime uses.

## Evidence and remaining boundary

The real portable tracer compiled authored Haxe to OCaml, built the result with
Dune, ran normal and exceptional comparisons, and passed its inspection and
corruption checks. Focused Reflect planning, runtime-requirement, runtime-use
authority, inventory, formatting, no-`Dynamic`, local-path, and diff checks also
passed.

The private-runtime inventory moved from 381 to 380 entries. Only the
`Reflect.compare` builder's direct throw constructor was removed. The parent
runtime-authority migration remains open, and neither runtime source-selection
authority nor README progress changes in this slice.

Oracle review was deliberately skipped. The unsafe constructor, its sealed
decision owner, and the necessary lifecycle/report boundaries were directly
reproducible. The implementation converged through a red-first focused
contract, a real vertical run, and this independent second pass.
