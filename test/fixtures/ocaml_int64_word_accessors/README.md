Read Int64 high and low words through the real Haxe property declarations.
The fixed output checks signed limits, mixed signs, and once-only receiver effects.

Run `haxe test/m14_stage3_int64_word_accessors_test.hxml` to compare upstream Haxe
with the generated native OCaml executable. The existing Int64 integration command,
`test/m14_stage3_int64_add_int_integration_test.hxml`, also runs this observer.
The temporary Stage3 Int64 provider remains excluded from shared-target readiness.
