The Dynamic operator integration test also executes these concrete Int operations.
Run `haxe test/m14_hxhx_stage3_dynamic_operator_integration_test.hxml`.

The test combines this helper with the original nested integer program in one
native build. Upstream Haxe 4.3.7 and the native executable must both print the
original result, `419`, followed by `expected.stdout`.

The helper covers all six bitwise operators, signed 32-bit results, shift-count
masking, parenthesized arithmetic, static initialization, and operand effects.
The `left` and `right` lines prove each operand executes once in source order.
A local with an internal-looking name must retain its value.

The projection check also retains a written Dynamic input. Its typed operation
must remain separate from native Int selection. Copied, foreign, and removed
expressions cannot borrow the original operation's type facts.
