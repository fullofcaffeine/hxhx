# Private class descriptors

Run `haxe test/m14_nominal_carrier_runtime_test.hxml`.

The independent OCaml observer compiles against the manifest-verified production
runtime. It checks that public fields cannot install, replace, or delete a
private class descriptor. Anonymous values, field-map copies, invalid descriptors,
and enum descriptors must not acquire class identity. Existing native records
keep their descriptor behavior.

Forced major collection and compaction preserve live descriptors and inherited
type tags. A weak reference proves that the runtime does not retain an unreachable
instance. These assertions cover native representation only; the authored Haxe
exception observer proves class selection, inheritance, and typed rethrow behavior.
