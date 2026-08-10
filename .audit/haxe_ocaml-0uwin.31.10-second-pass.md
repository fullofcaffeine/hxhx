# Second-pass review: checked raw OCaml injection

## Outcome

The change is safe to close as a raw-boundary migration. It does not complete
requirements-only runtime selection or change public readiness.

## Construction bypasses

`OcamlExpr` now has one raw constructor, `ERawInjection`, and that constructor
accepts only `OcamlRawInjection`. The injection and plan constructors are
private. Public callers can inspect defensive copies of their segment lists,
but cannot turn those copies back into a validated injection. The inventory
scanner separately treats every other `ERaw...` declaration or construction as
a legacy raw boundary, so a future unchecked variant cannot silently replace
the old pair.

The older placeholder parser remains public, but it no longer constructs an
AST value. It therefore cannot bypass the private-runtime namespace check.

## Typed-child visibility and order

Planning validates authored text and placeholder positions before any typed
argument is compiled. Materialization then requires the exact argument count
and preserves the planned segment order. `OcamlASTTraversal` maps each typed
expression segment through the normal expression walk; runtime-use collection
and the two scope-aware identifier analyses therefore continue to see those
children. Identity traversal reuses the same validated wrapper when no child
changes.

The portable interpolation fixture builds, runs, and produces the same source
on a clean repeat. That vertical check also protects single evaluation and the
observable result.

## Mutation and lifetime

Both the plan and completed injection copy their input arrays. Their public
accessors return new array copies. A focused test clears a returned segment
array and proves the printer still sees the original validated payload. The
wrapper holds only target AST values for the current request; it introduces no
cross-request cache or host compiler object.

## Diagnostic timing

Private runtime names and malformed placeholders fail during planning, before
the builder compiles any interpolated expression. Materialization repeats the
argument-count and occurrence checks as a compiler invariant. The existing
source diagnostic remains attached to the raw template position. Source-map,
portable/private-negative, and metal-negative integration checks remain green.

## Claim boundary

Exactly two raw-boundary rows left the legacy inventory, reducing it from 355
to 353. No runtime requirement, manifest root, selected source file, profile
policy, generated output repair, or README goal changed. The remaining 353
structured private-runtime references still block the requirements-only hard
cut.
