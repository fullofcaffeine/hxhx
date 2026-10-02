# Neko catch value views

Run `haxe test/m14_neko_typed_catch_integration_test.hxml` from the repository root.
The harness compares Haxe 4.3.7 with both generated Neko layouts.

Handlers select the first matching type. Ordinary catches can receive a real
ValueException payload. Dynamic catches retain the original carrier. Exception
subclass catches do not unwrap payloads or call conversion helpers on a mismatch.
An unmatched inner try rethrows the same carrier to its outer handler.

The fixture checks object identity and conversion side effects as well as text.
It does not prove native stack-origin parity or ordered static initialization.
