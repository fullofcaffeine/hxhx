# Nullable callback signatures in recursive modules

An optional callback can be absent or contain a function. A function can also
return a nullable callback. These declarations need precise exported types when
their modules depend on each other.

This fixture checks optional method and constructor callbacks, a returned
closure, and a null result. Its expected output is independently compared with
Haxe/eval. The portable runner compiles and executes the generated OCaml.

The macro checks the actual exported signatures. It also rejects an unknown
callback argument and storage that cannot preserve null. Existing recursive
module tests retain the unsafe-initializer rejection contract.

Run the focused fixture from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=module_nullable_callback_signature bash scripts/test-portable.sh
```
