# Real Neko exception construction

Run `haxe test/m14_neko_inherited_construction_integration_test.hxml` from the repository root.

The test loads the selected Neko standard library. A `haxe.ValueException`
must retain its inherited message and return the original value from `unwrap()`.
Both generated layouts must match upstream Haxe 4.3.7 output.
The fixture grants explicit access to the provider's private `unwrap()` method
so it can observe the original value without changing the standard library.

This construction test does not prove ordered typed catches or exception wrapping.
