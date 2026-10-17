# Native exception-stack timing

This independent Haxe program observes the most recent throw through nested
handlers. Run it with upstream Haxe 4.3.7 and hxcpp 4.3.2:

```sh
haxe -cp test/oracle/cpp_native_exception_stack_seed -main Main -cpp .tmp/exception-stack-upstream
.tmp/exception-stack-upstream/Main > .tmp/exception-stack-release.stdout
diff -u test/oracle/cpp_native_exception_stack_seed/release.expected.stdout .tmp/exception-stack-release.stdout

haxe -cp test/oracle/cpp_native_exception_stack_seed -main Main -debug -cpp .tmp/exception-stack-upstream
.tmp/exception-stack-upstream/Main-debug > .tmp/exception-stack-debug.stdout
diff -u test/oracle/cpp_native_exception_stack_seed/debug.expected.stdout .tmp/exception-stack-debug.stdout
```

These executable names were observed on macOS. Apply the repository's background
scheduling rules to the builds on an interactive host.

In debug builds, the initial exception stack is empty. Each throw replaces it,
and a catch does not clear it. A nested throw changes the most recent stack,
but an earlier returned snapshot remains unchanged. Rethrowing a caught String
records the rethrow site. Release builds return empty arrays throughout.

An exception object's stored origin has a separate contract. The sibling
`cpp_native_stack_seed` fixture checks that origin through rethrow of the same
exception object. Do not apply the String rethrow rule to that stored origin.

This is upstream reference evidence for `haxe_ocaml-k9scs` and
`haxe_ocaml-qrk0u`. The candidate's raw snapshot test uses a native catch observer.
It does not yet prove this complete Haxe catch and conversion workload.
