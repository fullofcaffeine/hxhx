This program checks String and Array calls with omitted, null, zero, and explicit
bounds. Negative bounds are tested only where Haxe 4.3.7 defines their behavior.
Negative String search offsets are unspecified and are not a parity claim.

Run `haxe test/m14_stage3_optional_bounds_test.hxml`. The observer compares the
program with upstream Haxe, compiles it to native OCaml, and checks exact output.
Printed operand effects prove receiver-first, left-to-right evaluation without
depending on mutable compiler state. A custom `indexOf` method must still return
its own result. The observer also rejects copied markers, changed arguments,
and occurrences presented under a different executable owner.

The existing optional-Int null-padding test command includes this observer.
