# Anonymous record assignment

These authored methods assign through ordinary structural fields. They cover
assignment results, discarded results, aliases, nested records, object identity,
and creating an absent optional field.

Build `Main` with upstream Haxe 4.3.7 and hxcpp 4.3.2:

```sh
haxe -cp test/oracle/cpp_record_write_seed -main Main -cpp .tmp/cpp-record-write-reference
.tmp/cpp-record-write-reference/Main
haxe test/m14_cpp_record_write_test.hxml
```

The upstream output must match `expected.cpp.stdout`. `R` means the receiver
callback ran; `V` means the value callback ran. Both used and discarded
assignments run the receiver first. A throwing receiver skips the value. A
throwing value leaves the old field unchanged.

The native observer executes the complete `RecordWrite` methods with collection
inside callbacks. A fresh receiver has no outside root during value allocation.
The observer checks returned and stored identity, unchanged destinations on
failure, optional-field creation and replacement, and final root cleanup. It
runs with address and undefined-behavior sanitizers at O0 and O2. Compiler-side
controls reject inaccessible writes and foreign or changed source facts.

The separate upstream `Main null` process prints `receiver` then `value` before
a native segmentation fault on the pinned host. The managed target evaluates
both operands and then reports a checked native null failure. This test does
not claim an identical signal or Haxe-catchable null-error behavior. Runtime
error ingress remains part of the broader exception work. Compound field
updates remain explicitly rejected until their read-modify-write contract is
implemented; this fixture does not claim their support.
