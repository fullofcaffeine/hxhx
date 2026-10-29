# Int64 subtraction

Run `haxe test/m14_cpp_int64_sub_int_integration_test.hxml` from the repository root.

The test loads the real Haxe Int64 provider and preserves all six original
output cases. Contract independently checks single evaluation and left-to-right
operand order. The prepared program must select two add calls and seven subInt
calls. Upstream eval and native execution must match the original output.

O0 and O2 builds repeat the exact output comparison with address and
undefined-behavior sanitizers and collection at every allocation. Typed source
bodies must remain unchanged. Exact signed-overflow outputs and sanitizers
replace the old assertions that required a retired handwritten carrier helper
and its unsigned arithmetic spelling. Unbound class helpers and the old carrier
helper remain forbidden. This test does not establish general target readiness.
