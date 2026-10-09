# Generic abstract field initialization

Run `npm run test:m14:cpp-managed-abstract-initializer` from the repository root.
The compiler must retain the declared conversion from Int to Box<Int>.
The generated program must call `next()` once and store 7 in both observed abstract fields.

The command first checks generic header selection and cast provenance.
A conversion is permitted only when its substituted header accepts the source type.
Matching backing storage alone must not permit an undeclared conversion.
The native test then checks the normal generated runner at two optimization levels with address and undefined-behavior sanitizers.

The projected cast retains exact operand and result types, plus the compiler's guarantee that storage stays unchanged.
Authored casts do not receive this guarantee. Changing either semantic type clears it.
The type guarantee is part of the typed body revision, so cached code cannot confuse the two cases.

The upstream source observer uses Haxe 4.3.7 with hxcpp 4.3.2:

```sh
haxe -cp /path/to/repository/test/fixtures/cpp_managed_abstract_initializer_seed -main OracleMain -cpp native
./native/OracleMain
```

Compare stdout with `expected.stdout`.
Custom conversion methods, numeric conversions, and general runtime casts remain separate contracts.
This fixture does not establish full standard-library compatibility or change README Goals status.
