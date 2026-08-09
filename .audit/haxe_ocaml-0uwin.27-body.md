## User-visible outcome

Maintainers can see every current place where the compiler constructs or writes
an internal `Hx...` runtime reference, and CI prevents that legacy surface from
growing while occurrence-level authority is introduced.

This is an inventory and no-growth gate. It does not explain the existing uses,
change generated OCaml, or make runtime authority complete.

## Scope

Inventory structured expression, type, and pattern constructors plus compiler-
generated text and raw-injection paths. Record the owning Haxe module, domain,
construction shape, and migration family in a deterministic machine-readable
file. Add a guard that detects new or changed unbound references.

Keep the report honest: any non-empty legacy inventory continues to block
`authorityStatus: complete`.
