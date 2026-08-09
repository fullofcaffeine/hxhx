## User-visible outcome

The compiler will have an implementation-ready design for proving why every
generated reference to an internal `Hx...` runtime helper exists. This work
does not yet change generated OCaml or claim complete runtime ownership.

Today the compiler records detailed reasons for many Haxe operations, then
separately scans the completed OCaml syntax and remembers only module names.
For example, one valid reason for `HxArray` makes the report show that
`HxArray` has a reason, even if a second `HxArray` call has no reason of its
own. The report correctly stays `partial`, which blocks the authentic shared
target and release evidence.

## Scope

Choose the smallest durable link between one sealed semantic runtime
requirement and each concrete generated runtime reference. Cover expression,
type, and pattern references plus declared raw or generated-text boundaries.
Keep the final syntax scan as a consistency check only.

The design must fit the accepted target architecture: semantic choices stay
in Haxe-authored lowered plans, `OcamlExpr` remains target syntax rather than a
semantic annotation tree, the printer stays mechanical, and generated OCaml
is never edited directly.

## Deferred implementation

This review does not migrate all 426 direct runtime-reference constructors,
change runtime selection, remove the partial report, or move README progress.
Implementation work must be split into bounded children after the design and
its stop conditions are accepted.
