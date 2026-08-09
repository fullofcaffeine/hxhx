## User-visible outcome

One real `Array<Int>` assignment can prove, before OCaml is printed, that its
single `HxArray.set` reference came from the sealed Haxe semantic plan and
appears exactly once in the completed target syntax.

The program still compiles, builds, and returns the assigned value. Corrupted
same-symbol output fails deterministically instead of being hidden by the
module-level `HxArray` observation.

## Scope

Add the request-local occurrence model, restricted target-identifier
provenance, checked constructor, construction receipt, and final structural
reconciler needed for the array-assignment tracer bullet. Do not migrate other
semantic families or claim complete runtime authority.
