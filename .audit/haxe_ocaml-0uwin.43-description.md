## User-visible outcome

Exact Haxe `String` values keep their current nullable behavior in fields,
locals, calls, and literal `null` expressions, while every generated reference
to the OCaml String null sentinel is tied to the concrete compiler decision
that emitted it.

## Scope

Introduce an immutable owner-bound plan for materializing
`HxString.hx_null_string`. The plan must name the exact field, local, call slot,
or source expression, the sealed String representation, its runtime
requirement, target profile, and one expression occurrence. Split carrier-only
inspection from default-value construction so representation planning does not
claim a runtime occurrence that is never emitted.

Migrate the one `string-representation-materializer` row from the private
runtime-reference inventory. Preserve generated OCaml bytes and Haxe behavior.
Do not migrate nullable primitive defaults, broaden String representation, cut
over runtime source selection, or change README readiness in this slice.
