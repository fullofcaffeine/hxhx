# Generic field initialization

Run `npm run test:m14:cpp-generic-initializers` for ownership and native lifetime checks.
Run `npm run test:m14:cpp-generic-storage-oracle` for the pinned upstream C++ comparison.

The program declares `value:T = null`, then constructs Int, Bool, String, and
reference applications. Each field must retain null until an assignment replaces
it. A false Boolean must remain distinct from null. A child without a written
constructor must initialize both its inherited generic field and its own field.
Function-valued fields contain an identity closure and a closure that captures
a generic local. Their generic parameters and results must preserve the field's
storage contract, including null, false, and reference values.

The native observer forces collection before allocations. One static Box keeps
its payload alive through the initialized generic field. Releasing the Box must
collect both objects, its closures, and their captured generic state.
Checks run at O0/O2 with address and undefined-behavior
sanitizers. Ownership checks reject wrong declaring classes, foreign projections,
and incomplete applications without changing shared generic facts.

Method calls from generic initializers and constructor calls
inside applied bodies remain separate acceptance cases for `haxe_ocaml-g85ze`.
