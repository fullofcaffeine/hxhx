# String search behavior

The original `src/Main.hx` contract checks computed receivers, offsets, missing
matches, and empty needles. Its `expected.stdout` applies to eval, JavaScript,
Neko, and the managed C++ target.

Run the original upstream comparison with:

```sh
npm run test:cpp-string-index-of-exact-oracle-seed
```

`IndexOfReference.hx` separately observes native Haxe 4.3.7 with hxcpp 4.3.2.
Its output is `expected.native.stdout`. Native positions count UTF-16 units:
the `Z` in `Aé😀Z😀` starts at position 4. A start inside the first emoji skips
that match. Embedded zero bytes remain part of the string.

```sh
haxe -cp test/oracle/cpp_string_index_of_exact_seed -main IndexOfReference \
  -cpp .tmp/index-of-reference
.tmp/index-of-reference/IndexOfReference > .tmp/index-of-reference/actual.stdout
diff -u test/oracle/cpp_string_index_of_exact_seed/expected.native.stdout \
  .tmp/index-of-reference/actual.stdout
```

Use the Windows executable suffix when applicable. These native observations
also cover null receivers, null needles, optional starts, and empty searches
beyond the end. Eval alone does not establish native Unicode behavior.

Haxe documents negative search starts as unspecified. Native Haxe/hxcpp on
macOS arm64 exits with signal 11 for the following opt-in reproduction:

```sh
.tmp/index-of-reference/IndexOfReference --minimum
```

This calls `"abc".indexOf("a", -2147483647 - 1)`. The managed runtime clamps
negative starts to zero. Its `INT_MIN` assertion proves that safety policy;
it does not claim equivalence with the upstream crash.

Run the compiler regression with:

```sh
npm run test:m14:cpp-string-index-of-exact
```

That command preserves the original program and expected output. It also runs
an authored Haxe program through full provider loading and native execution.
The added observer checks declaration ownership, argument order, exceptions,
collection between arguments, and temporary-root cleanup under both sanitizer
optimization profiles. User methods named `indexOf` retain ordinary dispatch.
