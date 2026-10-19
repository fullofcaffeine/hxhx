This program passes arrays through Dynamic values into ordinary typed parameters.
Mutations through each parameter must remain visible through the original array.
The test covers instance, static, and stored-function calls, Int and Bool slots,
retained array text, null, unused non-array arguments, and once-only argument order.

Run `haxe test/m14_stage3_dynamic_array_argument_test.hxml` to compare the fixed
output with upstream Haxe and an actual native OCaml executable.
The test also runs through `test/m14_stage3_call_argument_policy_integration_test.hxml`.
It does not establish behavior for dereferencing a non-array Dynamic value.
