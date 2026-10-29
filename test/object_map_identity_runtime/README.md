# Native identity-map correctness

Run from the repository root:

```sh
haxe test/reflaxe_ocaml_object_map_identity_runtime_test.hxml
```

The driver verifies and copies the production runtime's exact manifest closure.
It compiles an independently authored OCaml observer and compares stdout exactly.
The observer has a 30-second runtime limit.

The observer checks lookup after ordinary, nested and anonymous-cache mutation,
GC requests, physical distinction, replacement, map copying, removal and clear.
It checks fresh headers for empty records, anonymous copies and concurrent native
allocations. It also checks false markers, descriptor-only records, deliberate
hash collisions and mixed managed/opaque keys. A normal lazy-value force changes
an opaque key's native tag while its map association must remain accessible.

This native boundary is necessary to observe physical equality, runtime headers,
native tag changes and GC directly. It does not reconstruct compiler facts or
repair generated output. Fixed test descriptors and record layouts describe the
runtime contract; production Haxe still selects allocation sites and payloads.
The deliberate shared-header collision is a test control, not a permitted
generated allocation pattern.

Opaque keys use a constant hash and can require linear scans. This is a
correctness observer, not a benchmark or a constant-time performance claim.
GC calls do not prove that live objects moved. Compiler allocation coverage,
upstream key admission, String equality and workload cost require separate proof.
