# Native C++ startup execution

This program records startup effects as digits in an integer. The expected result,
`123465`, includes an unused class initializer before the entry method runs.
The fixture also checks three signed integer products that exceed the Int range.
Upstream Haxe 4.3.7 with hxcpp 4.3.2 produces the values in `expected.stdout`.

Run the authored-source and native observer checks from the repository root:

```sh
npm run test:m14:cpp-managed-startup-execution
```

The test parses and types `Main.hx`, then calls the normal C++ target emitter.
The independent C++ observer calls the generated startup function and reads its
static fields. It also checks collection, rejection of repeated startup in one
heap, and independent startup in a fresh heap. Native builds use `-O0` and `-O2`,
strict warnings, AddressSanitizer, and UndefinedBehaviorSanitizer.

The entry method also calls an inline method on an extern class. Its throwing
initializer must not run, matching the numeric-free upstream extern probe.

The observer renames the generated process entry through an include macro so its
own entry can call the same generated startup function. It does not edit the
generated source. The fixture uses no replacement standard-library provider.
`OracleMain.hx` prints the same values when compiled with upstream Haxe.

This fixture proves execution for its loaded classes. It does not prove complete
standard-library startup, Float defaults, exception lowering, or arbitrary class
construction. The separate `test:m14:cpp-managed-startup-order` command checks
ordering across 11 programs with their real loaded dependencies. That command
does not prove native execution for those complete dependency sets.

The ordinary managed closure command includes this execution test. The ordering
command remains separate because it repeatedly loads and projects the standard
library. README Goals status is unchanged.
