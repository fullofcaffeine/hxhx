# Concrete generic constructor applications

One program constructs `Box<Int>` and `Box<String>` and checks both returned values.
The constructor copies its argument to a captured local and reads that local through a nested function.
This checks parameter storage, local identity, closure signatures, receiver assignment, and direct method results.
Success exits with code zero and no output. A wrong value throws.

Run the upstream reference with `haxe -cp test/oracle/cpp_constructor_application_seed -main Main --interp`.
Run the shared ownership checks with `haxe test/m14_cpp_constructor_application_test.hxml`.
Run the native observer with `haxe test/m14_cpp_constructor_application_native_test.hxml`.
The observer also executes the original `GenericResult<String>` constructor from the six-case annotation fixture.
It checks array representation and cleanup at O0 and O2 with sanitizers and collection before every allocation.
