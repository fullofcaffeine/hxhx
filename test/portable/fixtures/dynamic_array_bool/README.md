# Mixed Boolean array storage

This fixture passes a mixed array inside a record to a runtime observer.
Booleans must retain their type after storage, remain distinct from integers, and evaluate once.
Null values and mutations through an array alias must also retain their behavior.
The call boundary prevents the compiler from replacing the array with separate local values.

Run the upstream observer from this directory with `haxe -cp src --run Main`.
Run the native fixture from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=dynamic_array_bool PORTABLE_JOBS=1 bash scripts/test-portable.sh
```
