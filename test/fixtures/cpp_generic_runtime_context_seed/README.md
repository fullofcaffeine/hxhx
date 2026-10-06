# Runtime tests in generic bodies

Generic methods and initializer closures must test the concrete argument supplied
by their caller. This program checks IntMap identity through real standard-library
providers. Int, Bool, String, another Map family, an ordinary object, and null must
not become IntMap instances. Matching and mismatched operands execute once.

Run `npm run test:m14:cpp-generic-runtime-context` for exact source-ownership checks
and native execution under O0/O2 address and undefined-behavior sanitizers.
The observer forces garbage collection before allocations and checks temporary
objects are released. The expected stdout is empty; authored assertions define
the behavioral contract.

The upstream comparison uses Haxe 4.3.7 and hxcpp 4.3.2 through
`npm run test:m14:cpp-generic-storage-oracle`; see the toolchain setup in
`../cpp_generic_storage_oracle/README.md`.

Erased values and unsupported runtime target categories remain rejected. This
fixture does not establish complete reflection or Full1 support. README Goals
status is unchanged.
