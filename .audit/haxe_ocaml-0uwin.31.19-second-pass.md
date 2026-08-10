# Second-pass review: unobservable local defaults

## Outcome

The fix removes only a default that cannot be observed. Haxe can produce a
local declaration followed by an assignment. If the local is not mutable and
that assignment occurs before the first read, final OCaml already omits the
declaration. The builder now also avoids constructing the discarded default.

This matters for exact String values because constructing the default grants
one private `HxString.hx_null_string` use. The final output check correctly
rejected that permission when no reference reached the generated module.

## Challenged cases

- A named function returning an `Int -> String` closure now builds and runs.
- The closure's generated result local has no unused null-sentinel binding.
- A String local explicitly initialized to null and read before assignment
  still starts with Haxe null. Haxe 4.3.7 rejects reading an omitted local
  before initialization, so the test does not claim that invalid source case.
- Mutable locals still allocate storage and keep their required defaults.
- An initializer with side effects is still evaluated when its value is dead.
- The existing next-write analysis remains the single ordering decision. The
  fix does not add a second liveness model.
- Final runtime-use reconciliation remains unchanged and fail-closed.

No Oracle review was needed. The existing block-lowering rule exposed one
bounded construction-order defect, and direct Haxe 4.3.7 plus generated OCaml
behavior provides the independent oracle. README goals do not change.
