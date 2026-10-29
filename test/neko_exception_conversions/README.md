# Standard exception conversions

Run `haxe test/m14_neko_exception_conversion_integration_test.hxml` from the repository root.

The fixture calls the actual standard-library exception conversion helpers.
Ordinary module loading must discover their parameter types, including `Any`.
Only `Main` is an explicit root. Both generated Neko layouts must match upstream
for exception messages, object identity, and primitive unwrapping.

The access metadata permits direct observation of these private compiler helpers.
This fixture does not exercise implicit typed-catch selection or stack formatting.
