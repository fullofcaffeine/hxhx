Change Int64 words in place and check that aliases see the change.

Haxe 4.3.7 stores a `haxe.Int64` as a reference to an object with a high and a
low 32-bit word. The private `set_low` and `set_high` setters (used by
`haxe.io.FPHelper`) change that object, so an alias prints the new value while
`copy()` and arithmetic results such as `words + 1` remain separate. The output also
checks signed-word wrapping, setter results, once-only receiver evaluation,
`Std.string`, and `Int64.isInt64`.

Run `haxe test/m14_stage3_int64_mutation_test.hxml` to compare upstream Haxe
with the generated native OCaml executable. The existing Int64 integration command,
`test/m14_stage3_int64_add_int_integration_test.hxml`, also runs this observer.
The temporary Stage3 Int64
provider remains excluded from shared-target readiness.
