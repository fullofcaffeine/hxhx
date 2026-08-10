Implemented the one-row nullable primitive field-default migration.

What changed:

- Exact `Null<Int>` and `Null<Bool>` instance/static field defaults now need a
  sealed, field-owned plan before they can emit `HxRuntime.hx_null`.
- The runtime requirement ledger records one representation-level reason, while
  each generated occurrence remains tied to its concrete field or static
  storage owner.
- The legacy private-runtime-reference inventory moved from 386 to 385 entries;
  the field materializer family is now empty.

Evidence:

- The focused representation contract was first red because the plan and
  materializer boundary did not exist, then passed after implementation.
- Focused representation, runtime-requirement, runtime-selection-shadow,
  inventory, no-`Dynamic`, formatting, shell syntax, and diff checks pass.
- Instance/static portable tracers each perform two deterministic target builds,
  compile and run generated OCaml, inspect its representation and requirements,
  and pass.
- The static tracer also compares nullable defaults and all mutations/results
  with installed Haxe 4.3.7, excluding only its separately documented non-null
  primitive-default and whole-number float-format differences.

Scope remains narrow. Requirements-only runtime source selection, README Goals,
and product readiness do not change. The known slow aggregate runtime-authority
guard remains owned by `haxe_ocaml-tqv34`; it was not counted as passing evidence.

The required xhigh second pass found and fixed an over-broad six-argument helper
API and wording that incorrectly described explicit initializers. Oracle was
deliberately skipped because the existing owner seam and local executable
evidence made this a bounded migration rather than an unresolved architecture
decision.
