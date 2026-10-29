# Stored instance methods

Run `haxe test/m14_cpp_bound_callable_integration_test.hxml` for this regression.
The existing `npm run test:m14:cpp-static-callable` command also includes it.

The authored program stores methods, invokes them after receiver mutation, and
compares repeated reads with distinct methods and receivers. It also covers
one-time receiver evaluation, temporary receivers, optional arguments, an
override selected through a base reference, and repeated reads through base and
child references. Generic receivers cover String, Int, and a null Int value.
An instance field initializer and a nested closure also store methods.

The test compares upstream eval output with `expected.eval.stdout`, then
compiles and runs the production managed C++ output against `expected.stdout`.
Eval reports false for repeated method reads; hxcpp reports true. Keep these
expectations separate. Haxe 4.3.7 with hxcpp 4.3.2 verified the full native
expected output on macOS arm64. Reproduce that comparison with:

```sh
haxe -cp test/fixtures/cpp_bound_callable -main Main \
  -cpp .tmp/cpp-bound-callable-upstream -D HXCPP_COMPILE_THREADS=2
.tmp/cpp-bound-callable-upstream/Main
```

`Stress.cpp`
includes that generated output without modifying it. It forces collection at
every allocation and runs at both `-O0` and `-O2` with address and undefined-behavior
sanitizers. After execution, exactly one
program-storage allocation, 13 standard-library enum values, and one array must remain.
Those values are seven nullary `ValueType` constructors, `StackItem.CFunction`,
both `Encoding` constructors, and the three nullary `Error` constructors.
The array is `haxe.SysTools.winMetaCharacters`, also referenced by `StringTools`.
The fixed count also requires exactly one registered static root and no local roots.
This checks that a stored method keeps
its receiver alive and that an unreachable receiver/callable cycle is collected.

The separate native C++ equality oracle under `test/oracle/cpp_dynamic_equality_seed`
establishes the repeated-method identity contract. Interpreter agreement alone
does not establish the broader Dynamic equality matrix.
