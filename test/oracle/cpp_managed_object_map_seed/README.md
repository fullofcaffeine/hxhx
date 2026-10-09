# Managed object-key Map storage

Run `haxe test/m14_cpp_managed_object_map_test.hxml` from the repository root.
Upstream Haxe 4.3.7 checks the authored factory and its independent expected
output. The test then loads real provider declarations and emits the factory
through the managed function emitter. A native observer checks the resulting
map with address and undefined behavior sanitizers at `-O0` and `-O2`.

Two records with equal fields must remain distinct keys. Reusing one key must
replace its previous array value. Null is a separate valid key. With collection
before every allocation, the map must retain both its keys and values after the
factory's result record leaves. The observer also creates a cycle from a key
back to the map, then proves that no allocation survives the final root release.

The native observer reads the physical container directly. This test does not
claim support for source Map.get calls, named class construction, or enum keys.
The normal target route's anonymous-object Map family test is covered separately
by `haxe test/m14_cpp_managed_map_type_test.hxml`. The original full Map native
acceptance remains required.
