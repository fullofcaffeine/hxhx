Keep helper methods in scope for static initializers that capture them as values.

Haxe lets a `static final` initializer call a helper method declared later in
the class. OCaml evaluates top-level bindings in order, so the native OCaml
emitter writes the helpers that static initializers need into an early
"prelude" group, before the static values. The emitter finds those helpers by
following references from each initializer and from each helper it already
selected.

The fixture checks references that are not direct calls:

- a helper that passes another static method to `map` (`map(shout)`),
- an initializer that stores a static method directly (`exclaim = bang`),
- a helper that reads a method into a local before it uses it
  (`final apply = quote`), where the captured method calls a further helper.

Run `haxe test/m14_stage3_static_init_method_value_test.hxml` (or
`npm run test:m14:stage3-static-init-method-value`) to compare upstream Haxe
with the generated native OCaml executable.
