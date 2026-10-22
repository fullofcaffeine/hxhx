# Int64 multiplication

Run `haxe test/m14_cpp_int64_mul_int_integration_test.hxml` from the repository root.

The test loads the real Haxe Int64 and Sys providers. It preserves the original
Main program and all 13 expected output lines. Contract adds independent checks
that each operand runs once, from left to right, for both operator spellings.
The same complete contract first runs with upstream Haxe eval.

The prepared typed program must select one `mul` and 14 `mulInt` calls from
`haxe.Int64`. The generated C++ must not call unbound Int64 class helpers
or use the old handwritten 64-bit multiplication helper.

Native execution must match the original output exactly. O0 and O2 builds
repeat that comparison with address and undefined-behavior sanitizers.
The observer forces collection at every allocation and checks temporary roots.
Real providers retain their static object graph.

Earlier assertions required a specific signed 64-bit carrier helper and its
unsigned multiplication text. Those assertions described the previous backend.
The current backend executes the authored Int64 operations on their selected
storage. Runtime operand-order checks replace helper-argument regexes.
Exact overflow output and sanitizers replace the helper's textual arithmetic
checks. This change does not declare general Int64 or target readiness.
