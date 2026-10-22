# C++ enum construction observer

Run `haxe test/m14_cpp_enum_constructor_integration_test.hxml` from the repository root.
The driver owns the authored Haxe program and checks native execution and source immutability.
This observer includes the generated C++ without edits. Both sanitizer builds force collection at every allocation.

The fixed static field order is omitted, order, retained, text. The observer checks exact constructor tags, payload values, null omission, generic String storage, and nested payload retention after a throwing operand.
Six allocations remain after execution: program storage, the omitted value, a pair, its two leaves, and the text leaf.
Removing the three enum roots must leave only program storage. The test repeats with a second heap.
A separate authored throwing program leaves the original pair intact. The observer catches its native exception and verifies payloads after unwinding.

This contract does not prove enum equality, pattern matching, or complete C++ parity.
