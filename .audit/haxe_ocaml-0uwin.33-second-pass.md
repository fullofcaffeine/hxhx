# Structural-field runtime-use second pass

This review checks whether the change can remove two old source references without
creating a new way to emit unproved private-runtime calls. A private-runtime call
is a generated call to a repository-owned OCaml helper, such as `HxAnon.get`.
The compiler must now attach one exact use identity before it may create such a
call.

## Result

The boundary is sound for the covered field operations:

- stored reads authorize `HxAnon.get` and, for `Bool`, `HxRuntime.unbox_bool_or_obj`;
- stored writes authorize `HxAnon.set` and, for `Bool`, `HxRuntime.box_bool`;
- captured Iterator methods authorize the exact `HxIterator.hasNext` or
  `HxIterator.next` call;
- proven Map-pair projections use `Stdlib.fst` or `Stdlib.snd` and authorize no
  repository runtime call.

The syntax builder reconciles only the field operation it created. It does not
claim calls inside the receiver or assigned value because those expressions can
have separate plan owners.

## Findings and dispositions

1. The first implementation used the active nested-function control binding to
   check a field decision owned by the enclosing typed body. The real fixture
   rejected that stale revision. The builder now derives the runtime revision
   from the sealed field decision, which matches the planner's existing ownership
   model. Standalone expression roots also install their own binding while built.
2. The plain-reference guard initially named `HxIterator.has_next`, but generated
   OCaml uses `HxIterator.hasNext`. The spelling was corrected, and the focused
   unit test now tries every migrated structural helper without an authorization
   marker.
3. The six deterministic lowering reports changed only because the structural
   model and plan identities changed. Each fixture was regenerated through its
   normal compile, native build, and behavior check.

## Claim limit

This slice does not make runtime authority complete. The reviewed inventory now
contains 424 legacy references, so source-selection hard cut and README readiness
remain unchanged.
