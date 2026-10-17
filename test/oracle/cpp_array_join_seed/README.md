# Native array joining

`Main.hx` asserts primitive element formatting, empty arrays and separators,
nullable elements, Unicode bytes, and once-only operand evaluation.
It also checks Boolean views recovered from known Dynamic array storage.
These views convert each element before formatting it.

Run the managed regression:

```sh
haxe test/m14_cpp_array_join_test.hxml
```

The driver checks exact declaration and expression ownership, compiles the
generated program, and executes its assertions. Its native observer forces
collection during separator evaluation. Both ASan/UBSan profiles check operand
exceptions, null receivers, and cleanup of temporary roots and allocations.

Run the independent upstream reference with Haxe 4.3.7 and hxcpp 4.3.2:

```sh
haxe -cp test/oracle/cpp_array_join_seed -main Main -debug -cpp .tmp/join-upstream
.tmp/join-upstream/Main-debug
haxe -cp test/oracle/cpp_array_join_seed -main Oracle -debug -cpp .tmp/join-oracle
.tmp/join-oracle/Oracle-debug values
```

`Main` must exit successfully with empty stdout. Run `Oracle` separately with
`values`, `success`, `receiver`, `separator`, and `null`. Compare each result
with the corresponding `expected.<mode>.stdout` file.

The native reference treats a null separator as empty bytes. A null receiver
fails before the separator executes. The native observer verifies that order
and rejection; it does not establish Haxe exception wrapping or catch selection.

`Oracle` also records nested arrays and object `toString()` effects. Those
conversions remain unfinished under haxe_ocaml-fwwv3 and haxe_ocaml-hcnk8.
The managed binding rejects unsupported element types before publication.
Float conversion remains subject to the numeric review gate. These focused
tests do not establish complete Array.join compatibility or release readiness.
