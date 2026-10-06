# Abstract static defaults

Run `npm run test:m14:cpp-managed-abstract-default` from the repository root.
The command compiles this authored source through the normal managed C++ target.
An independent native observer checks the resulting fields after class startup and garbage collection.
Both optimization levels use strict warnings and address/undefined-behavior sanitizers.

An abstract keeps its source type but stores values through its backing type.
For example, `Slot<Int>` has the zero default, while `View<Int>` has a null reference default.
The fixture also checks chained abstracts, Bool, and nullable Int-backed abstracts.
`Main.__init__` reads an abstract field before ordinary field initialization.
Malformed generic arity and unsupported Float storage must fail before publication.

The upstream source observer uses Haxe 4.3.7 with hxcpp 4.3.2:

```sh
haxe -cp /path/to/repository/test/fixtures/cpp_managed_abstract_default_seed -main OracleMain -cpp native
./native/OracleMain
```

Compare stdout with `expected.stdout`.
This contract covers defaults only. Abstract conversions and executable initializers require separate typed plans.
README Goals status is unchanged.
