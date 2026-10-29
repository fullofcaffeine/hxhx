# Catch-variable storage

Each execution of a handler creates its own catch variable. A closure returned
from that handler retains the variable and can replace its value. Another
handler execution must have a separate variable. An uncaptured catch retains
the selected value without an extra heap cell.

The Haxe program checks those requirements with two closures and plain catches.
Its independent success expectation is exit status zero and empty stdout/stderr.
Run the upstream reference with Haxe 4.3.7 and hxcpp:

```sh
haxe -cp test/oracle/cpp_catch_storage_seed -main Main -cpp .tmp/cpp-catch-storage-reference
.tmp/cpp-catch-storage-reference/Main
```

Apply the repository's background scheduling policy to the native build.

Run `haxe test/m14_cpp_catch_storage_test.hxml` for the candidate storage test.
It projects these actual catch bindings and emits the production cell,
environment, and closure-body code. Its independent C++ observer supplies a
selected value after native unwinding. It forces collection, checks payload
identity and separate mutable cells, and requires complete cleanup at O0/O2
with address and undefined-behavior sanitizers. It also rejects foreign binding
objects, changed projections, and declaration or loop events used as catches.

This observer proves function-owned catch-entry storage. It does not prove
native Haxe handler selection or wrapping. The sibling
[initializer fixture](../cpp_initializer_catch_storage_seed/README.md) checks
catch-entry storage in fields and their nested closures.
The complete `m14_cpp_typed_catch_test.hxml` and source-control workloads remain
required under `haxe_ocaml-qrk0u`; capture integration remains under
`haxe_ocaml-9jezt`. A passing storage test does not close either task.
