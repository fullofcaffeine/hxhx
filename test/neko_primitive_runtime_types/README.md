# Neko primitive runtime types

This fixture compares `is` and the real `Std.isOfType` for Int, Float, and Bool.
It covers native integer representation, integral floats, conversion boundaries,
exponent literals, NaN, infinities, signed zero, and nonnumeric values.

Run `haxe test/m14_neko_std_is_of_type_integration_test.hxml` from the repository
root. The test checks Haxe 4.3.7/Neko first, then both generated Neko layouts.
Runtime division creates special values without depending on Math lowering.
Catch dispatch, decimal formatting, and binary NaN payloads are outside this fixture.

With Haxe 4.3.7 and Neko 2.4.0, the `-1073741824.0` boundary differs between
the observed macOS ARM and Linux x86-64 runtimes. Both Int predicates return
`false` on macOS and `true` on Linux. All other rows match.
Running each host's bytecode on both runtimes shows that the result follows
the runtime, rather than the host that compiles the source.

`expected.stdout` preserves the macOS observation.
`expected.linux-x86_64.stdout` records the complete Linux observation.
These names describe measured configurations, not guarantees about every host.
The test accepts only an exact recorded upstream result. Both generated layouts
must then match that same runtime's upstream result. An unknown upstream result
fails the test, which saves and prints the actual output for diagnosis.
