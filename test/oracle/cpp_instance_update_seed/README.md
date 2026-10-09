# Instance field increments and decrements

This program checks prefix and postfix updates to an ordinary mutable `Int`
field. Each receiver expression runs once. Its allocation must not release the
selected instance. A returned callback updates the same captured instance.
Successful execution produces no output.

```sh
haxe -cp test/oracle/cpp_instance_update_seed -main Main --interp
npm run test:m14:cpp-instance-update
```

The native test compiles the authored Haxe through the normal managed C++
target. It then runs AddressSanitizer and UndefinedBehaviorSanitizer builds at
`-O0` and `-O2`, with collection before every allocation. The observer checks
that temporary roots and allocated objects disappear after the program returns.
Boundary checks reject final fields, unsupported operand types, and function
facts from a separate compilation.

The fixture also retains assertions for signed 32-bit integer wraparound. These
pass in the managed target. Upstream Haxe 4.3.7 with hxcpp 4.3.2 fails the minimum
integer decrement assertion in the observed optimized macOS build. A separate
probe prints `2147483647` for the result but reports inequality with that same
constant. This discrepancy remains under investigation in `haxe_ocaml-p749a`;
the fixture does not establish full upstream native parity at integer limits.
The unchanged fixture passes upstream interpretation and the native debug build.

Nullable instance-field updates remain unsupported by this change. The upstream
native probe crashes at a null field increment; `haxe_ocaml-ftw61` tracks that
reference failure. The new rejection keeps this unproved case explicit.
README Goals readiness remains unchanged.
