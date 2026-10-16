# Int minus Int64

Run `haxe test/m14_cpp_int_sub_int64_integration_test.hxml` from the repository root.

The test loads the real Haxe Int64 implementation and its dependencies. It keeps
the original six output cases unchanged, including signed 64-bit wraparound.
`Contract` also checks that the left operand runs before the right operand and
that each operand runs once. The prepared program must select two `add` calls
and seven `sub` calls from the authored Int64 implementation.

Upstream Haxe 4.3.7 eval and the generated native executable must produce the
original output. Builds at O0 and O2 repeat this check with address and
undefined-behavior sanitizers. The observer forces collection at every allocation
and checks that temporary roots leave scope. Preparation and emission must keep
the original typed function bodies unchanged.

Each sanitizer compilation has a five-minute limit, including native debug
information. Each sanitizer observer has a separate 30-second limit.

These checks replace the old assertions for a handwritten integer carrier helper
and its unsigned subtraction expression. Unbound class helpers and the retired
carrier helper remain forbidden. This fixture does not establish general C++
target readiness.
