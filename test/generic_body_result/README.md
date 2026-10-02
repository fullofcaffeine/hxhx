# Body-inferred generic results

The entry point calls two generic functions before their declarations. Neither
function has a result annotation. `consume` completes with `Void`; `answer`
returns an `Int`. Calls must retain those exact result types after body inference.

Run `haxe test/m14_generic_body_result_inference_test.hxml` from the repository root.
The test compares upstream Haxe with generated JavaScript executed in Node.
Both must print `effect` and `9`, in that order. The test also checks the shared
typed call results before target emission.
