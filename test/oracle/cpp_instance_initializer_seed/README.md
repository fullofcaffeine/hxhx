# Instance field initialization

Run `haxe test/m14_cpp_instance_initializer_test.hxml` from the repository root.

Upstream Haxe 4.3.7 and generated native C++ must execute the same authored assertions.
The event digits must be `786934125`: the constructor argument runs first, then
the child's initialized fields in reverse declaration order, then its body up to `super()`, then
the parent's field and body, then the rest of the child body.

The field names intentionally differ from their physical layout order. A final
field must receive its initializer. An initializer allocates a second object.
Another allocation forces collection while that object remains in an initializer local.
The block initializer records `9`, updates its local variable, then produces `3`.
The native observer repeats the program with collection before every allocation
under address and undefined-behavior sanitizers at O0 and O2.

The same test command also runs `cpp_instance_initializer_throw_seed`, which
checks initializer failure and native unwinding with a separate observer.

The same command runs `cpp_instance_initializer_capture_seed` to check callbacks
that share initializer locals and remain callable after construction.

These fixtures do not establish omitted constructors or full Haxe exception support.
Those remain requirements of haxe_ocaml-pggau and its owning integration work.
