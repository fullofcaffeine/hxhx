# Int modulo by zero

Haxe leaves Int division by zero target-specific. Upstream eval returns the
Float NaN even for an Int-typed `%`. The OCaml runtime stores Int as an
unboxed 32-bit value that cannot hold NaN. `HxInt.rem` and `HxInt.div` used to
raise OCaml's `Division_by_zero`, which no Haxe `catch` can handle. Like the
static targets (Neko, JVM, C#), they now throw a catchable Haxe exception
(the String "Division by zero").

The fixture catches `%` and `%=` by zero and prints normal and negative modulo
results. The native output must match the expected output, and so must
upstream Neko (`test.sh`), which is this fixture's oracle instead of eval.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=int_modulo_by_zero bash scripts/test-portable.sh
```

This regression does not change README Goals status.
