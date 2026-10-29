# Parameter writes

Run `haxe test/m14_cpp_parameter_write_test.hxml` from the repository root.

Assigning to a parameter changes that call's local value. For example,
`replace(original, 3)` returns 3 while the caller's `original` remains 9.
The fixture checks assignment results, compound assignments, increments,
Boolean values, instance calls, nullable values, and shared captured parameters.
The compound assignment also changes its own parameter on the right side,
which checks that the original left value is read before that change.

The harness first runs the independent assertions with upstream Haxe eval.
It then compiles Main through the native C++ target and runs the executable.
Address and undefined-behavior sanitizers run at O0 and O2, with forced
collection and checks for leaked roots.

FloatTransport copies finite Float inputs through named and closure parameters.
An independent C++ observer checks returned doubles through the generated calling
convention. This avoids adding Float comparison support to test parameter writes.
It does not claim new floating-point arithmetic or conversion behavior.

Emission must preserve the typed source revision. Existing storage-plan tests
also check direct primitive calling conventions and rooted callable parameters.
