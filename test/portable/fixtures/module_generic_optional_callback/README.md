This fixture checks generic callback results when an instance method has optional arguments.
The callback returns an object through an exported concrete return type in a recursive module group.
That constraint exposes a missing conversion which a polymorphic local producer can hide.

The native program and upstream Haxe eval must agree on object identity, mutation, callback counts,
omitted and explicit-null arguments, default values, nested calls, and exception restoration.
An enum-bearing call preserves its enum and object arguments beside the generic callback.
Corrupted report cases must reject missing optional-slot evidence and misuse of enum argument proofs.
The existing module_generic_signature fixture retains negative checks for optional callback signatures.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=module_generic_optional_callback bash scripts/test-portable.sh
```
