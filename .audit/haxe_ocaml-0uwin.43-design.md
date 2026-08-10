The existing `OcamlRepresentationDecision` remains the program-wide answer for
how exact Haxe `String` is represented. It must not become a reusable permission
for every String sentinel in the program because one decision can serve many
different fields, locals, call arguments, and expressions.

Add a small Haxe-authored String-default plan whose identity includes a
concrete owner and owner revision. It derives exactly one
`HxString.hx_null_string` occurrence from the already-recorded String
representation requirement. The materializer validates the String carrier and
domain, creates the identifier only through `OcamlRuntimeUseAuthority`, and
reconciles the returned default subtree before exposing it to the caller.

Callers that need only the OCaml `string` carrier must use a carrier-only path
and create no occurrence. Callers that emit the default must supply an existing
stable owner such as a static-storage entry, class field, sealed call slot,
local-storage decision, or function/body/source occurrence. A shared
representation ID, a generated-text scan, or syntax-time type recovery is not
an acceptable substitute.

Focused tests must first demonstrate that the current materializer can create
the sentinel without an owner-bound occurrence. They must then reject missing,
duplicated, stale, wrong-symbol, wrong-owner, wrong-representation,
wrong-domain, wrong-profile, and plain private references. A real fixture must
compile generated OCaml, build, and run instance-field, static-field, local,
explicit-null, and omitted/explicit call cases against an independent Haxe
4.3.7 behavior expectation.

Stop and redesign if callers cannot supply a stable concrete owner before
syntax construction, if the solution grants one reusable permission from the
shared representation decision, or if it needs generated-output repair or
handwritten OCaml semantics.
