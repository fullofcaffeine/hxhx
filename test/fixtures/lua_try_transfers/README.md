# Lua try/catch control

Run `haxe test/m14_lua_nominal_bodies_integration_test.hxml`.
The test compares upstream Haxe and generated Lua with the independent expected output.

Protected calls must preserve method returns, void returns, nested returns, and loop transfers.
A void return skips the remaining method body, and a returned null stays null.
Array, while, and do-while loops retain their break and continue destinations.
A nested closure returns to its caller without escaping the enclosing try block.
Loops inside a protected call keep their own break and continue destinations.
Catch clauses match exact typed bindings in source order; unmatched errors propagate outward.
An ordinary thrown child object matches its declared parent class.

Numeric and standard exception-wrapper catch policies remain outside this fixture's evidence.
