## User-visible outcome

Portable `__ocaml__` keeps accepting ordinary raw OCaml and checked typed
interpolation, but the target AST can no longer represent that source through
an unvalidated raw node. Compiler-private `Hx...` runtime names remain
rejected before target syntax is built.

## Scope

Replace the public plain and interpolated raw-expression variants with one
validated raw-injection value. Its factory owns private-runtime namespace
rejection, placeholder cardinality, and the structural typed-expression
children used by runtime occurrence checks. The printer remains mechanical.

Remove exactly the two `builder-raw-boundary` rows from the legacy private
runtime-reference migration inventory. Keep a separate focused contract that
detects any reintroduction of an unchecked raw constructor. Do not add a
private-runtime placeholder API, change metal policy, hard-cut runtime source
selection, or move README readiness.

## Acceptance criteria

1. A focused test is red because the AST still exposes unchecked `ERaw` and
   `ERawInterpolated` constructors.
2. Authored text reaches the AST only through a validated injection value;
   private runtime names, malformed placeholders, missing arguments,
   duplicated arguments, and identifier-splicing placeholders fail before an
   injection is created.
3. Interpolated typed expressions remain structural AST children and are
   evaluated exactly once in source order.
4. The raw node's payload cannot be mutated through a returned array, and
   traversal preserves the validated wrapper when children are unchanged.
5. Plain and interpolated portable fixtures compile generated OCaml, build,
   and run; private-runtime injection and metal raw injection remain rejected.
6. Exactly the two raw-boundary inventory rows disappear, while an independent
   source guard rejects future unchecked raw variants or construction.
7. Printer, traversal, runtime-use collection, inventory, formatting, and the
   relevant raw/metal vertical gates pass.
8. A written `thinking:xhigh` second pass challenges construction bypasses,
   child visibility, mutation, diagnostic timing, and claim boundaries.
9. Requirements-only runtime selection and README Goals remain unchanged.

## Required skills

calibrate-reasoning-effort, beads, explain-technical-work, show-me-your-work
