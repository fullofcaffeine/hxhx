# Second-pass review: exact String null occurrence authority

## Outcome

The bounded source-construction migration is safe to commit. Exact Haxe
`String` still uses OCaml `string` for ordinary values and
`HxString.hx_null_string` for Haxe `null`, but the String materializer can no
longer print that private runtime name from a shared representation choice.
Each call now supplies a concrete field, storage site, local, call slot, or
typed-expression owner and consumes one checked runtime-use record.

This closes one migration-inventory row. It does not make runtime authority
complete, change runtime source selection, or advance README readiness.

## Challenges and dispositions

### Can the shared String representation authorize the entire program?

No. The representation still says only that exact Haxe `String` uses the
nullable OCaml `string` carrier. `OcamlStringDefaultPlan` adds the concrete
owner, owner revision, source span, exact requirement, target profile, symbol,
and one-use limit needed by one materialization.

### Can type/layout planning claim a value that is never emitted?

No. Carrier-only consumers now call `carrierType` or
`carrierForRepresentedField`. Only code that constructs a default value creates
runtime-use authority. The type-registry text path keeps its own checked-text
owner and merely validates the selected String carrier.

### Are field and storage owners concrete enough?

Yes for the migrated sites. Static declaration defaults, later source
initialization, normal instance construction, and empty-instance construction
receive different owner roles. This distinction matters because one static
field can produce both a predeclared cell default and a later assignment, while
one class record is emitted in both its normal and empty-instance constructors.
The first draft used only the field/storage identity; the second pass rejected
that weaker ownership and split the emission sites before commit.

### Are function-body uses tied to stable input facts?

Yes at this boundary. Planned calls use the sealed call ID and argument index;
locals use their stable local identity; other expressions use the sealed
function binding, semantic role, and normalized source span. A missing function
binding fails instead of falling back to the shared representation.

### Does corruption fail before OCaml printing?

Yes. The focused fixture rejects missing, duplicate, stale, wrong-owner,
wrong-representation, wrong-symbol, wrong-domain, wrong-profile, and plain
private references. The caller owns the request-local authority and reconciles
the completed default subtree before returning it.

### Did generated behavior change?

No observed target behavior changed. The String storage fixture compiled from
authored Haxe, built with Dune, and ran natively with the retained expected
output. Upstream Haxe 4.3.7 JavaScript and Neko runs produced the same result.
The optional static-call and function-value fixtures also compiled and built
their native artifacts with their existing generated-shape and corruption
checks.

### Is the inventory reduction exact?

Yes. The inventory moved from 389 to 388 entries. Only
`OcamlStringRepresentationMaterializer`'s direct
`HxString.hx_null_string` constructor disappeared. The remaining nullable
primitive default in `OcamlFieldRepresentationMaterializer` stays tracked for
its own migration.

## Verification limitation and parent boundary

The complete target tree does not yet have one global reconciliation pass that
can detect a previously reconciled subtree being embedded in two output
locations. That limitation affects all runtime-use families, not just String,
and runtime authority therefore remains explicitly partial until the parent
hard cut owns final-tree multiplicity. This slice does not use rendered-text
scanning as permission and does not claim complete source-selection authority.

The package-wide runtime-authority wrapper and its two direct generated-text
fixtures were stopped after remaining CPU-active in the known Haxe 4.3.7
null-safety traversal without reaching fixture output. The focused authority,
String representation, static-storage, real compile/build/run, independent
oracle, inventory, format, no-Dynamic, mega-file, local-path, and diff checks
all passed in this worktree.

Oracle review was deliberately skipped. The unsafe owner, corrected seam, and
remaining global-tree boundary were directly reproducible, and the bounded
implementation converged through a focused red/green test plus this written
second pass.
