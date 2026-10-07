# Integer string conversion

`Std.string` must preserve non-null `haxe.Int32` values and evaluate its input
once. This fixture covers positive and negative values, the two halves of an
`Int64`, and a function call that increments a counter.

The expected output is shared by upstream Haxe eval and native execution.
The original native failure replaced these values with `<unsupported>` and
removed the call effect. The unused Int64 halves then failed native compilation.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=int32_string bash scripts/test-portable.sh
```

This contract does not change Float text, binary encoding, or nullable conversion.
