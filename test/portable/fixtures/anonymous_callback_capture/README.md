# Capture a callback read from a typed record

A record stored in ObjectMap contains a function that returns the original
object. The program reads that function into a local and captures the local
in another closure. Calling the closure must return true. The lookup key runs
once, and reading the stored callback preserves its function identity.

This reproduces a native compilation failure where an anonymous field read
lost its declared function type. OCaml then rejected the captured call as an
ignored extra argument. The compiler must retain the function type without
creating a different callback.

Run `PORTABLE_FIXTURE_ALLOWLIST=anonymous_callback_capture bash scripts/test-portable.sh`.
The portable runner builds and runs native output against expected.stdout.
The extra test compares the same program with upstream Haxe eval.
