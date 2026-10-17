# Nullable conditional results

These assertions require one result that can hold either a value or null.
They cover Int and Bool, both branch orders, assignment, nested conditionals,
and exactly one evaluation of the condition and selected arm.

```sh
haxe -cp test/oracle/cpp_nullable_ternary_seed -main Main --interp
npm run test:m14:cpp-nullable-ternary
```

Upstream Haxe 4.3.7 and native C++ assertions pass. Native checks use forced
collection, AddressSanitizer, and UndefinedBehaviorSanitizer at O0 and O2.

Shared typing keeps null in the conditional result type. Shared lowering uses
a typed result slot when branch types differ, so targets receive the selected
type rather than inferring it again. The original authored syntax remains
available for macros.

Task haxe_ocaml-5aatj owns this work. Its older full application replay and the
existing conditional-control regression still need a completed run: both hit
a wall timeout during severe host load. These focused results do not change
README Goals readiness or establish a complete release candidate.
