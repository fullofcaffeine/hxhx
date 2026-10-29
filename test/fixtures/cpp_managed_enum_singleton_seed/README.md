# Enum singleton startup

Run `npm run test:m14:cpp-managed-enum-singleton` from the repository root.
The command compiles authored Haxe through the normal managed C++ target.
An independent C++ observer runs the generated program with two collection budgets.
Both native builds use strict warnings and address/undefined-behavior sanitizers.

Parameterless enum constructors must exist before class startup methods run.
The fixture reads constructors during class startup, ordinary field initialization, and main.
The observer checks alias identity, distinct constructor tags, null defaults, and collection safety.
Separate heaps must own separate singleton allocations. A second startup on one heap must fail without replacing its values.

To check the source behavior against upstream Haxe 4.3.7, use an isolated hxcpp 4.3.2 installation:

```sh
haxe -cp /path/to/repository/test/fixtures/cpp_managed_enum_singleton_seed -main OracleMain -cpp native
./native/OracleMain
```

Compare stdout with `expected.stdout`. The managed observer adds heap lifetime checks that upstream source cannot inspect.
Payload constructors, enum equality lowering, reflection, and switches remain separate work.
This fixture does not establish the full enum acceptance contract or change README Goals status.
