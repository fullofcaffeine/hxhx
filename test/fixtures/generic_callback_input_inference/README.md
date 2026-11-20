# Generic callback input inference

An omitted input passed where a generic method expects a callback over its type parameter (`check<T>(value:T, test:T->Bool)`) takes the callback type from the binding, as in Haxe 4.3.7. A recursive call inside a generic method can pass that input back to the method itself, as `haxe.ds.ArraySort.rec` does.

Run `node_modules/.bin/haxe test/m14_generic_callback_input_inference_test.hxml`. The test compares types and types the full program; it does not run native output, because frozen Stage3 cannot emit `Walk.count` (haxe_ocaml-qypu2).
