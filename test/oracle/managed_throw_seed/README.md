# Values retained during native unwinding

This fixture throws strings, integers, arrays, and closures from authored Haxe.
The native observer forces collection after generated operand scopes unwind.
It checks value tags, array identity and mutation, transport copies, rethrow,
escaped mutable captures, and final storage release.
It also checks a throw inside a closure and one evaluation of an effectful operand.

Run the focused test from the repository root:

```sh
haxe test/m14_cpp_managed_throw_test.hxml
```

The test generates every method in `Thrown` with real standard-library type providers.
It then compiles and runs the native observer at `-O0` and `-O2` with address
and undefined-behavior sanitizers. Original typed function revisions must remain unchanged.

`ThrownValue` retains an existing managed value while C++ unwinds.
Its copies share one stable external root; they do not copy the managed allocation.
The heap must outlive all transport copies, including copies retained through `std::exception_ptr`.
This carrier must never be stored inside a managed payload.
Such storage can create a root cycle that prevents collection.

This test proves the transport and authored throw path, not complete Haxe exception support.
The original `cpp_typed_catch_seed` and source-try tests remain required under `haxe_ocaml-qrk0u`.
Ordered handlers, standard exception views, numeric matching, foreign errors, and ordinary target integration remain unfinished.
README Goals status is unchanged.
