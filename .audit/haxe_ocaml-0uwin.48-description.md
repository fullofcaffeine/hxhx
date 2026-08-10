## User-visible outcome

A Haxe `try`/`catch` compiled to OCaml still catches matching values and
rethrows an unmatched Haxe exception unchanged. Before target text is printed,
the compiler can now prove that the exact sealed catch chain authorized both
the private exception pattern and the private rethrow helper.

## Scope

Migrate the planned catch-chain constructions of `HxRuntime.Hx_exception` and
`HxRuntime.hx_throw_typed`. Derive one runtime-use plan from the existing
`OcamlCatchChainDecision`; do not infer permission from target names in the
builder.

Add a provenance-carrying pattern-constructor node because the runtime-use model
already distinguishes pattern identifiers from expression identifiers. Extend
local and final structural reconciliation so a missing, duplicated, stale,
wrong-owner, wrong-symbol, wrong-domain, wrong-profile, or plain private
reference fails before OCaml publication.

This child does not migrate the legacy catch path, private return/loop signals,
catch predicates, null/default values, all exception helpers, or Map carrier
types. It does not change runtime source-selection authority or README
readiness.

## Acceptance criteria

1. The smallest catch-chain/runtime-authority contract is red because the
   sealed chain has no runtime-use plan and patterns cannot carry checked
   runtime provenance.
2. Each admitted catch chain records one `HxRuntime` semantic requirement and
   exactly two owner-bound uses: the Haxe-exception pattern and unmatched-Haxe
   rethrow helper.
3. Syntax consumes those exact occurrences from the chain plan; it cannot
   create or reinterpret either private name.
4. Local and final reconciliation cover expression and pattern domains and
   reject missing, duplicate, stale, wrong-owner, wrong-symbol, wrong-domain,
   wrong-profile, and plain-reference corruption before printing/publication.
5. A real Haxe `try`/`catch` tracer compiles generated OCaml, builds and runs it,
   and agrees with an independent Haxe 4.3.7 expectation for matched and
   unmatched/rethrown behavior.
6. Exactly the two planned-catch construction sites leave the legacy
   inventory; the remaining exception, return/loop, predicate, and other
   runtime references remain visible.
7. Focused control/runtime-authority/AST-printer tests, runtime requirements,
   inventory, formatting, and the relevant vertical fixture pass.
8. A written `thinking:xhigh` second pass challenges pattern traversal, chain
   identity, local/final cardinality, and claim boundaries before closure.
9. Runtime source selection and README Goals remain unchanged.

## Required skills

calibrate-reasoning-effort, beads, explain-technical-work, show-me-your-work
