# Callback structure input inference

A callback whose untyped inputs read fields can come before the arguments that bind its type parameter: `leq(function(x, y) return x.name == y.name, a, b)` with `leq<T>(f:T->T->Bool, l1:Array<T>, l2:Array<T>)`. Upstream Haxe 4.3.7 joins the callback's provisional structure with the structure from the arrays.

Run `node_modules/.bin/haxe test/m14_callback_structure_input_inference_test.hxml`. The test compares types and types the full program; it does not run native output, because frozen Stage3 cannot emit `leq<T>` (haxe_ocaml-qypu2).
