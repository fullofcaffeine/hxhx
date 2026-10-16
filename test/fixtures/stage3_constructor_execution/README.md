# Native constructor execution

Run `haxe test/m14_stage3_constructor_execution_test.hxml`.

The same authored program must produce `expected.stdout` under upstream Haxe
4.3.7 and the native Stage3 OCaml emitter. It observes helper constructor bodies,
a parent constructor operating on the same receiver, inherited construction,
once-only argument evaluation in source order, a Boolean entering Dynamic,
defaulted parameters, and rest parameters supplied as values, an array spread,
or an empty list, including a spread forwarded to a parent constructor.
The reversed Pair assignments reject positional copying of arguments to fields.

Instance field initializers and nominal exception identity remain separate
acceptance work in haxe_ocaml-j5icf and haxe_ocaml-k93zp.
