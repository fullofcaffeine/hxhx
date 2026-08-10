# Second-pass review: Array sort

## Outcome

The change is safe to close as a one-operation hard cut. Final typed calls to
`Array.sort` now carry their exact comparator shape, effect-only result, source
order, and runtime function into OCaml syntax. The old source-method branch was
removed from the late builder.

## Comparator identity

An installed Haxe 4.3.7 typed-AST probe showed that a comparator argument is a
two-argument function returning `Int`, while the sort call itself returns
`Void`. It also exposed an important reporting detail: `TypeTools.toString`
includes local parameter names such as `left` and `right`. Those names do not
change the function type and must not become cache or plan identity.

During macro typing, the selector therefore follows the actual `TFun` and
requires exactly two inputs whose final types equal the root `Array<T>` element
type plus an exact `Int` result. It then records the name-free identity
`(T,T)->Int` for both the formal and actual comparator. Post-macro validation
can reconstruct that exact identity from `T` and rejects a corrupted result
such as `(T,T)->Float` without parsing source text or trusting parameter names.

The sealed target returns effect-only `Void`, uses a receiver-first schedule,
and owns one exact `HxArray.sort` occurrence and runtime requirement. Common
corruption checks cover operation, arity, result, runtime function, unit
convention, owner, source occurrence, profile, revision, and plain private
references.

## Runtime behavior and storage families

The existing `HxArray.sort` implementation remains the storage primitive. It
sorts within the current object, integer, float, or string storage layout and
invokes the supplied comparator. The Haxe-authored compiler now owns when this
primitive may be called; target syntax no longer decides from a field name.

The shared Haxe 4.3.7/generated-OCaml tracer covers integer, float, string,
nullable, and object Arrays. New checks prove the receiver and comparator
expression are evaluated once in that order, the comparator is actually
called for a multi-element Array, the same Array is mutated, and empty and
single-element Arrays do not invoke the comparator.

No claim depends on the relative order of elements for which the comparator
returns zero. Sort stability remains outside this slice because Haxe's public
contract does not require it.

## Reports, inventory, and claim boundary

The function-plan revision is `v93`, the call-boundary model is `v27`, the
standard Array proof is `v7`, and the lowering schema is 78. The inspection
reader and independent JavaScript consumer validate the comparator identity
and effect result. Six deterministic reports were regenerated through the
repository updater and passed an ordinary comparison run.

The private-runtime inventory falls from 335 to 334 by removing exactly the
late `HxArray.sort` reference. No handwritten OCaml runtime source changed.

No generated OCaml was edited. Runtime source-selection authority and README
Goals did not move. Requirements-only runtime selection remains incomplete,
with 334 private-reference inventory entries still open.

Oracle review was deliberately skipped. The standard Array seam and storage
runtime already existed, Haxe 4.3.7 supplied a direct typed and behavioral
oracle, and focused, vertical, inspection, corruption, inventory, and
deterministic-report evidence converged without an unresolved architecture
decision.
