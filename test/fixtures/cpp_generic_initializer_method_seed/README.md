# Method calls from generic initializer closures

Run `npm run test:m14:cpp-generic-initializer-methods` for ownership and native checks.
Run `npm run test:m14:cpp-generic-storage-oracle` for the pinned upstream C++ comparison.

Reader<T> initializes function-valued fields with closures that call Box<T>.read.
The fields must retain their own class arguments through call planning and native
emission. The program exercises Int, Bool, String, and reference results, an
inherited initializer, and a concrete virtual override.

Ownership checks reuse one lexical call under different applications. They reject
another field, a method context, foreign source, and a mutated projected call.
Frozen dispatch keeps each application separate and rejects an unplanned one.
The independent native observer forces collection and checks payload retention
and release. Native checks run at O0/O2 with address and undefined sanitizers.

Constructor calls inside applied bodies, callable reassignment conversions,
performance acceptance, and broader provider behavior remain separate requirements.
