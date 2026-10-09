# Output from managed functions

`Sys.print` writes a value. `Sys.println` also writes a newline. This fixture
checks Bool, Int, and String values, including null strings and embedded zero bytes.
It also checks these primitives across an authored Dynamic parameter and callback.

```sh
haxe -cp test/oracle/cpp_managed_output_seed/src -main Main --interp
haxe test/m14_cpp_managed_closure_abi_integration_test.hxml
```

The upstream Haxe 4.3.7 program must match `expected.stdout` byte for byte.
That file contains two zero bytes. The managed compiler uses the real C++ Sys
provider and emits six output methods through its production emitter.

An independent C++ observer calls those methods. It checks output at `-O0` and
`-O2` with AddressSanitizer and UndefinedBehaviorSanitizer. Callback arguments
collect memory before returning. A throwing argument must produce no output.
A returned closure prints its captured value after its creator has returned.

The emitter binds an explicit inventory of exact semantic declarations. It
rejects missing providers, duplicate identities, changed signatures, and declarations
from other owners. Haxe lowering owns formatting; `ManagedOutput.hpp` only writes
and flushes an exact byte span. Failed native writes or flushes raise an exception.

Dynamic inputs use the same primitive runtime-tag formatting as `Std.string`.
The observer verifies single callback evaluation and rejects erased callable values
before output. An explicitly typed callable also fails during emission.
Float and object formatting remain unsupported in the managed emitter.
This fixture does not prove the normal C++ target cutover or full Sys parity.
