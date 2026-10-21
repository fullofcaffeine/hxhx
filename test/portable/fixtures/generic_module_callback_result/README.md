# Generic module callback results

A generic function returns a callback result across an exception boundary. Its caller uses the result as a String, Int, Bool, or concrete class instance. The same helper forwards nullable values, whole arrays, anonymous records, and stored callbacks. A second helper restores unrelated state after success and failure, then returns the callback's original value.

Native output must match upstream Haxe eval. Assertions check value and callback identity, shared mutations, null preservation, producer counts, and exception messages. The record containing two maps reproduces the compiler's local-inference result shape.

`test.sh` also runs `contracts.hxml`. These macro checks admit immutable forwarding and reject inspection, manufactured values, mutation, escaping callbacks, nested captures, and generic element extraction. They reject a final body that no longer forwards the callback result and distinguish independent type-parameter scopes.

Run `PORTABLE_FIXTURE_ALLOWLIST=generic_module_callback_result bash scripts/test-portable.sh` from the repository root. This fixture does not claim general recursive-module or generic structural parity.
