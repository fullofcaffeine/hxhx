# Managed receiver transport

Run `haxe test/m14_cpp_managed_receiver_test.hxml` from the repository root.

The source checks receiver identity through direct returns, parameter capture,
escaping closures, and a closure that only forwards the receiver to its child.
Upstream Haxe runs the entire source and compares it with independent expected output.

The native observer calls the emitted method entries with opaque traced test
payloads. It checks receiver and argument lifetime with collection at every allocation,
then removes all roots and checks reclamation. Both optimization levels use sanitizers.
This proves the method transport boundary. It does not prove source construction,
class descriptors, field layout, virtual dispatch, or the full Map acceptance test.
