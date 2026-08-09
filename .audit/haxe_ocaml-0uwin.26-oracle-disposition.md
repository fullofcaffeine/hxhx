# Oracle disposition: occurrence-level runtime-reference authority

## Practical decision

Keep runtime meaning in the existing Haxe-authored lowered plans, but give each
planned use of an internal OCaml runtime helper its own stable identity. The
syntax builder must consume that identity when it creates the corresponding
target identifier. A final structural check then proves that every planned use
appeared exactly once and that no plain, unexplained `Hx...` identifier entered
the generated syntax.

This is narrower than adding semantic annotations to the OCaml syntax tree. A
runtime-reference token says only which already-decided target identifier is
being printed and which planned occurrence authorized it. It does not carry a
Haxe type, lowering decision, representation choice, evaluation policy, or
fallback. The lowered plan remains the source of meaning; the target syntax and
printer remain mechanical consumers.

Oracle request `orq_20260809T121711Z_41cda046` was reviewed against current
`main`. Oracle did not run the repository test suite, so all implementation and
closure claims remain local responsibilities.

## Retained recommendations

### Separate requirements from concrete uses

One runtime requirement explains a semantic need such as Haxe array element
storage. That requirement may authorize several concrete target references.
Therefore a new immutable `RuntimeUseOccurrence` must be distinct from
`OcamlRuntimeRequirement` and contain at least:

- a deterministic use ID and plan revision;
- the owning lowered node or generated-output owner;
- the requirement ID that explains the use;
- the target domain: expression, type, pattern, checked generated text, or raw
  boundary;
- the exact target symbol and symbol kind;
- the owner-local materialization role and stable schedule slot;
- source information suitable for diagnostics;
- the eligible runtime profile; and
- an initial cardinality of exactly one.

Two uses of the same spelling receive different use IDs. Requirement identity,
module name, target spelling, and object identity are not occurrence identity.

### Carry restricted provenance through target syntax

Expression, type, and pattern target identifiers need a restricted reference
form that carries only `useId`, `planRevision`, domain, and exact target symbol.
The checked constructor receives a sealed occurrence, validates those fields,
records one request-local construction receipt, and creates the target
identifier. It rejects unknown, stale, duplicate, wrong-symbol, wrong-domain,
wrong-profile, and post-seal construction.

The receipt is diagnostic evidence, not semantic authority. The final syntax
must still carry the use ID so a later check cannot be fooled by a disconnected
side table. The printer renders only the exact symbol and never interprets the
use ID.

### Reconcile the completed structured syntax

Before printing or publication, an exhaustive structural traversal compares
the sealed use plan with the target identifiers that survived into the final
syntax. It fails on:

- missing, duplicated, unknown, or stale use IDs;
- a symbol, domain, profile, or plan-revision mismatch;
- a plain structured `Hx...` reference with no use ID;
- a use whose requirement does not directly name the referenced runtime root;
  and
- an owner-local schedule mismatch where the lowered plan declares ordered
  materialization roles.

Dependency closure may include additional modules, but transitive inclusion
does not explain a direct reference. The direct requirement root must match.

### Use the same ownership law for non-AST output

Compiler-generated text must use a checked text builder with literal chunks and
runtime-use placeholders. Sealing records the plan revision, ordered use IDs,
exact bytes, and content hash. Plain string concatenation containing private
`Hx...` references remains migration debt and cannot support complete
authority.

Portable `__ocaml__` remains an explicit escape hatch, but its literal text may
not forge compiler-private `Hx...` identifiers. If a real consumer later needs
that access, add checked placeholders that name declared raw-boundary uses.
Metal's existing no-raw rule remains unchanged.

### Separate occurrence authority from runtime selection

Occurrence reconciliation proves why generated references exist. It does not
by itself prove that runtime packaging can stop consulting compiler-observed
modules. `RuntimeCopier` currently adds those observations to selective roots.
A later shadow gate must show that requirements-only selection produces the
same complete runtime closure across the supported same-candidate matrix before
observations stop affecting selection.

## Modified recommendations

### Ordering is owner-local, not one global traversal sequence

Oracle proposed stable order keys. Current lowered place plans already own
semantic schedules such as receiver, index, right-hand side, store, and result.
Those owner-local slots are the correct place to validate relevant ordering.
The runtime layer must not turn incidental global AST traversal order into a
new semantic contract. Unrelated syntax wrapping or module organization may
change traversal order without changing Haxe behavior.

For generated text, placeholder order is part of the sealed text record and is
checked exactly. For structured syntax, the runtime check validates the
owner-local planned sequence where one exists; the existing lowered-plan
validator remains responsible for evaluation semantics.

### The target reference is a provenance-bearing identifier, not an expression wrapper

The accepted architecture rejects an annotation layer placed around arbitrary
`OcamlExpr` nodes. The implementation must therefore add narrow identifier
forms for expression, type, and pattern references, or an equally restricted
identifier value used by those constructors. It must not add a general
`EWithRuntimeRequirement(expr, ...)` wrapper or let runtime records carry Haxe
semantic choices into the syntax tree.

## Rejected alternatives

- **Module-name overlap as final authority:** one explained `HxArray` use hides
  another unexplained use.
- **Exact-symbol counting:** two distinct `HxArray.set` uses still collapse to
  the same spelling.
- **Object identity:** Haxe macro/compiler objects are request-local and not
  stable evidence.
- **Factory receipt without a syntax token:** later syntax replacement can
  leave a valid receipt for output that no longer contains the authorized use.
- **Rendered-text scanning as positive proof:** text is too late and loses the
  semantic owner. A private-namespace scan remains useful only as a negative
  guard.
- **A general semantic annotation layer on `OcamlExpr`:** duplicates the
  lowered model and violates the accepted architecture.
- **A universal target IR or new mega-file:** the use plan, checked reference,
  generated-text boundary, and reconciler belong in focused modules.

## Deferred or owner-controlled choices

- Direct portable-raw access to compiler-private `Hx...` helpers is deferred.
  The safe default is **no**. A future real consumer may justify checked
  placeholders; generic raw text must never gain implicit permission.
- Requirements-only runtime selection is a separate implementation and
  evidence gate.
- Fine-grained occurrence migration for all current direct constructors is
  staged work. This review does not claim it complete.

## First red/green tracer bullet

Use the already-sealed `Array<Int>` simple assignment path:

1. semantic requirement `R-array-set` explains Haxe array storage;
2. use `U-store` authorizes exactly one `HxArray.set` expression reference;
3. the place emitter consumes `U-store` through the checked identifier factory;
4. final traversal finds `U-store` exactly once; and
5. the ordinary compile/build/run fixture still returns the assigned value.

The focused same-symbol corruption case must plan `U1` and `U2`, both spelling
`HxArray.set`. `U1/U2` passes. `U2/U2` fails with both duplicate `U2` and missing
`U1`. Adding one plain `EIdent("HxArray")` reference also fails as unbound.

## Complete-authority gate

`authorityStatus` may change from `partial` only when all of the following are
true on one candidate:

- the frozen legacy inventory is empty;
- no plain structured private-runtime reference remains;
- no unchecked generated text or raw boundary can name a private runtime helper;
- every final use maps through occurrence, requirement, direct root, and locked
  runtime manifest;
- missing, duplicate, stale, wrong-symbol, wrong-domain, wrong-profile,
  owner-order, hash, corruption, and post-seal tests fail closed;
- requirements-only runtime selection matches the complete supported matrix
  without compiler observations contributing roots;
- reports and identities are deterministic across clean repeats; and
- the full portable portfolio, metal-positive/negative checks, and package
  examples pass on the exact candidate.

README goals and percentages remain unchanged until that executable evidence
exists.
