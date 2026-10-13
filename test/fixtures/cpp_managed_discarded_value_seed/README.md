# Discarded C++ values preserve operand effects

The program discards two arithmetic results. Their four operands must still run
once, from left to right. The independently specified output is `1234`.

Run the upstream Haxe reference from the repository root:

```sh
haxe -cp test/fixtures/cpp_managed_discarded_value_seed -main OracleMain --interp
```

Run the generated C++ observer and the original startup fixtures with:

```sh
npm run test:m14:cpp-managed-startup-execution
```

The independent observer calls the generated program and reads its static field.
It forces collection and repeats the program in a separate heap. Both `-O0` and
`-O2` builds use strict warnings, AddressSanitizer, and UndefinedBehaviorSanitizer.
The original startup fixture also retains its discarded inline extern call,
which becomes a literal during compilation. No generated source is rewritten.

This fixture covers discarded supported values, not additional numeric types or
general standard-library compatibility. README Goals status is unchanged.
