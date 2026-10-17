# Native class membership

The program checks class and inherited interface membership, aliases, null,
unrelated values, and a forged public type field. It also observes operand
effects and a value passed through `Any`. Upstream Haxe and the native OCaml
observer must both match `expected.stdout`.

Run `haxe test/m14_ocaml_nominal_type_predicates_test.hxml`. The test also checks
exact ownership of typed occurrences and rejection before output changes.

Native preparation types real provider bodies and expands required inline
methods, as production does. This includes the conversion from `Any`. The
focused observer then emits its original Main module and its nested classes.
It does not prove native execution of every loaded standard-library module.
Emitting the complete provider closure still reaches the unsupported
`Type.ValueType.TClass` payload containing `Class<Dynamic>`, tracked with
`haxe_ocaml-k93zp`. That separate acceptance requirement remains open.
