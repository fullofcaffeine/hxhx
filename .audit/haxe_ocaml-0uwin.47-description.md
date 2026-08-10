## User-visible outcome

An instance or static field declared as `Null<Int>` or `Null<Bool>` still starts
as Haxe `null`, while the OCaml target can prove exactly which field declaration
authorized the private `HxRuntime.hx_null` reference.

## Scope

Replace the one remaining plain runtime reference in
`OcamlFieldRepresentationMaterializer` with an owner-bound occurrence derived
from the sealed nullable-primitive field representation. Keep carrier-only
inspection separate so asking for an OCaml field type does not claim a default
value that will never be emitted.

Cover `Null<Int>` and `Null<Bool>` instance and static fields, omitted defaults,
explicit initializers, and the distinct output roles used by normal and empty
constructors. Reject a missing, duplicate, stale, wrong-owner, wrong-symbol,
wrong-profile, wrong-domain, or plain private reference before OCaml is printed.

This child does not authorize other `HxRuntime.hx_null` sites, redesign nullable
local/call carriers, hard-cut runtime source selection, or change README
readiness.

## Acceptance criteria

1. A focused test is red because nullable primitive field defaults currently
   have no owner-bound runtime-use plan.
2. Every emitted `Null<Int>` or `Null<Bool>` field default owns one exact
   `HxRuntime.hx_null` occurrence and one sealed `HxRuntime` requirement.
3. Carrier-only field queries construct no runtime occurrence.
4. Corruption checks reject missing, duplicated, stale, wrong-owner,
   wrong-symbol, wrong-profile, wrong-domain, and plain references before
   printing or publication.
5. A real Haxe-to-OCaml fixture compiles, builds, and runs instance/static,
   omitted/explicit, Int/Bool, and constructor-copy behavior against an
   independent Haxe 4.3.7 expectation.
6. Exactly the `field-representation-materializer` inventory row disappears;
   unrelated inventory and output behavior remain visible.
7. Focused representation, runtime requirement/use authority, inventory,
   formatting, and relevant vertical gates pass.
8. A written `thinking:xhigh` second pass challenges owner identity,
   multiplicity, requirement scope, and claim boundaries before closure.
9. Runtime source selection and README Goals remain unchanged.

## Required skills

calibrate-reasoning-effort, beads, explain-technical-work, show-me-your-work
