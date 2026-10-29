# Structural views of interfaces

An interface value becomes a structural view whose methods retain the original receiver and state. This fixture covers an explicit cast after a null check and a contextual object-field conversion. The interface lives in a separate module. Its implementation has stored fields, so its method positions differ from the interface declaration.

Silent assertions also check inherited interface methods, overrides, capture-time receiver evaluation, object identity, class lookup, and downcasts. One structural consumer accepts both a class instance and an ordinary anonymous object. Constructor, static-initialization, and empty-instance calls check that dispatch is available before those values are used. The empty-instance test initializes its stored value explicitly; it does not assume a default value for uninitialized Haxe fields.

Run `PORTABLE_FIXTURE_ALLOWLIST=anonymous_structural_interface bash scripts/test-portable.sh` from the repository root. The runner compiles and executes the native result, then compares the same program with upstream Haxe eval. This focused contract does not change project readiness claims.
