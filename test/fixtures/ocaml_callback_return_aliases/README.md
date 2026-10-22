# Returned callback aliases

A method can store a callback in a local variable, invoke it, and return it.
The returned callback must preserve the original function identity and Boolean argument and result conversions.

This fixture covers aliases initialized from a callback parameter, a static method, and another method's callback result.
Each callback rejects a Dynamic argument that lost its Boolean type.
The independent expected output contains nine lines, shared by upstream Haxe eval and the native OCaml executable.

Run `haxe test/m14_dynamic_callable_conversion_test.hxml` for source generation, native compilation, execution, and report checks.
The report check substitutes absent and foreign local identities into each return and recomputes its digests.
The public reader must reject these records because the local does not belong to the returning function.

This fixture covers direct returns through immutable locals.
Early returns and multiple return paths require separate control-flow evidence.
