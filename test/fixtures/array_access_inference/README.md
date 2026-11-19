# Array access input inference

An omitted parameter used in array access receives its type from that use. As in Haxe 4.3.7, an unknown receiver becomes an `Array` whose element type later uses bind, and an unknown subscript becomes `Int`.

Run `node_modules/.bin/haxe test/m14_array_access_inference_test.hxml`. The operations are in class `Ops`, declared before `Main`, so the calls in `main` cannot supply the evidence. The upstream observer reads `Main.Ops`.
