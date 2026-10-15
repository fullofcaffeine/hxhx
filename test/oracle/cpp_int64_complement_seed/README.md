# Int64 complement

Run `haxe test/m14_cpp_int64_complement_integration_test.hxml` from the repository root.

The test executes the real Haxe Int64 provider. All original output cases remain,
including signed boundaries, the 32-bit word boundary, and double complement.
Contract independently checks that a side-effecting operand runs exactly once.
The prepared program selects two add calls and sixteen complement calls.

Upstream eval, native execution, and O0/O2 address and undefined-behavior
sanitizer builds must match the original output. The sanitizer observer forces
collection at every allocation and checks temporary roots. Typed source bodies
must remain unchanged.

Old generated-text assertions required a retired handwritten signed carrier
helper. Typed provider selection, exact boundary outputs, and sanitizers now
prove that behavior through authored Haxe. Generated code must not invoke an
unbound class helper or bypass the provider with the legacy complement helper.
This focused evidence does not establish general target readiness.
