# Neko primitive runtime types

This fixture compares `is` and the real `Std.isOfType` for Int, Float, and Bool.
It covers native integer representation, integral floats, conversion boundaries,
exponent literals, NaN, infinities, signed zero, and nonnumeric values.

Run `haxe test/m14_neko_std_is_of_type_integration_test.hxml` from the repository
root. The test checks Haxe 4.3.7/Neko first, then both generated Neko layouts.
Runtime division creates special values without depending on Math lowering.
Catch dispatch, decimal formatting, and binary NaN payloads are outside this fixture.
