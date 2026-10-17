# Managed enum acceptance fixture

This fixture defines the enum behavior required by the managed C++ target.
The candidate target supports singleton startup but does not yet support this complete fixture.
It is a retained failing workload, not a managed-target pass.

Three narrower commands support the implementation:

```sh
node scripts/ci/cpp-managed-heap-test.js ManagedEnumTest
npm run test:m14:cpp-managed-enum-descriptors
npm run test:m14:cpp-managed-enum-singleton
```

The first command checks enum payload tracing, erased references, cycle cleanup,
and rejected allocation. The second compiles descriptors from authored enum
declarations and observes allocation with those descriptors. Both use strict
native builds with sanitizers at `-O0` and `-O2`.
The third command observes singleton startup through the normal generated program.
It checks class startup reads, alias identity, collection safety, and separate heaps.
These commands do not prove the complete source fixture, including payload constructor calls and enum equality lowering.

Upstream Haxe 4.3.7 with hxcpp 4.3.2 produces `expected.stdout`. The observation
checks shared nullary values, null defaults, constructor indices, constructor
names, an array payload, and distinct enum declarations with the same constructor
name. `Main.__init__` also sees an initialized nullary constructor. The final
`false` means the constructor was not null during class startup.

This last observation distinguishes enum initialization from ordinary static
fields. Nullary enum values must exist before class startup methods execute.
Treating enum constructors as ordinary field initializers changes that behavior.

Run the upstream check in an isolated haxelib repository with hxcpp 4.3.2:

```sh
haxe -cp /path/to/repository/test/fixtures/cpp_managed_enum_seed \
  -main OracleMain -cpp native
./native/OracleMain
```

Compare stdout with `expected.stdout`. Native compilation must precede the
comparison. The interpreter does not substitute for the native startup contract.

The managed implementation must retain exact enum and constructor identities,
trace payload edges, and preserve values across collection and closure escape.
It must not infer enum identity from anonymous-record field names. Reflection,
switch lowering, generic constructors, exception transport, and payload lifetime
need their own focused checks as support grows. README Goals status is unchanged.
