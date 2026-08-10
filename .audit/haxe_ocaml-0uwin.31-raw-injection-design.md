The raw escape hatch is intentionally target-specific, but it is not allowed
to name compiler-private runtime modules. Represent that completed validation
as a dedicated immutable-by-contract value and let the OCaml AST carry only
that value.

Planning happens before typed interpolation arguments are compiled, so an
invalid template cannot create request-local runtime occurrences as a side
effect. A sealed plan then materializes the injection from the exact number of
compiled expression children. The value returns copies of its segment list and
provides a checked mapping operation for structural traversal.

Use one raw-expression AST variant. Only the validated value's private
constructor can supply its payload. The printer reads authored text and
structural expression segments without deciding whether the text is allowed.
Runtime-use collection continues to see interpolated expression children and
continues to ignore authored text, which has already passed the private-name
boundary.

Stop and redesign if the change needs public unchecked construction, target
text parsing during runtime selection, a broad runtime permission for raw
code, generated-output repair, or a second raw representation kept for
compatibility.
