# Native C++ stack observations

This fixture distinguishes an upstream build that records Haxe stack frames from
one that omits them. It also checks repeatable snapshot conversion, prefix
skipping, and exception identity and origin through two throws.

Haxe 4.3.7 with hxcpp 4.3.2 returns empty stack arrays in the default release
build. Its debug build returns populated arrays. Both builds must preserve the
captured exception origin after rethrow. The expected files record these
separate contracts. They do not compare machine-specific filenames or frame
addresses.

Run from the repository root with those upstream tool versions selected:

```sh
haxe -cp test/oracle/cpp_native_stack_seed -main Main -cpp .tmp/native-stack-upstream
.tmp/native-stack-upstream/Main > .tmp/native-stack-release.stdout
diff -u test/oracle/cpp_native_stack_seed/release.expected.stdout .tmp/native-stack-release.stdout

haxe -cp test/oracle/cpp_native_stack_seed -main Main -debug -cpp .tmp/native-stack-upstream
.tmp/native-stack-upstream/Main-debug > .tmp/native-stack-debug.stdout
diff -u test/oracle/cpp_native_stack_seed/debug.expected.stdout .tmp/native-stack-debug.stdout
```

These executable names were verified on macOS. Use the corresponding native
executable names on other hosts. Apply the repository's background scheduling
wrapper to native builds on an interactive host.

This is upstream reference evidence for `haxe_ocaml-k9scs`, not a passing test of
the candidate compiler. The candidate's unchanged exception-construction test
still rejects the missing `haxe.NativeStackTrace.callStack` native binding.
An always-empty replacement could pass the release observations while failing
the debug contract, so it is not an implementation of stack capture.

Further acceptance must cover implicit thrown-value stacks, derived-constructor
frame adjustment, populated frame contents, collection safety, and the complete
typed-catch fixture. This focused reference does not replace those requirements.
