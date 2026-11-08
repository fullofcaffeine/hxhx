# Int modulo by zero

Haxe leaves Int division by zero target-specific. Upstream eval returns the
Float NaN even for an Int-typed `%`. The OCaml runtime stores Int as an
unboxed 32-bit value that cannot hold NaN. `HxInt.rem` used to raise OCaml's
`Division_by_zero`, which only `catch (e:Dynamic)` could see as an untagged
native exception. Like the static targets (Neko, JVM, C#), it now throws a
tagged Haxe String ("Division by zero"), so `catch (e:String)` matches.

The fixture catches `%`, `%=`, and `haxe.Int32` `%` by zero. The `String`
clause comes before `haxe.Exception` and `Dynamic` clauses, and each clause
prints a fixed label instead of the message, because targets word the error
differently. It also prints normal and negative modulo results. The native output must match the expected output, and so must
upstream Neko (`test.sh`), which is this fixture's oracle instead of eval.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=int_modulo_by_zero bash scripts/test-portable.sh
```

This regression does not change README Goals status.
