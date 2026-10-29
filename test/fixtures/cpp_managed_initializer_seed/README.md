# Static initializer expressions

The first field calls `supply(3)` and stores `4`. The second reads that field and
stores `8`. The third allocates a record with `8` and `startup` as its fields.

Run the source program with upstream Haxe 4.3.7:

```sh
haxe -cp test/fixtures/cpp_managed_initializer_seed -main OracleMain --interp
```

Its output must match `expected.stdout`. Run the generated C++ checks with:

```sh
haxe test/m14_cpp_managed_initializer_test.hxml
```

The C++ observer calls emitted initializers in an explicit order. It checks the
same output at O0 and O2, with strict warnings and address/undefined-behavior
sanitizers. It also checks that collection retains the initialized record. An
allocation failure must preserve the old record and release temporary roots.

The test rejects foreign initializer facts, copied expressions, and mutated
projections. `M14AnonymousHintTypingTest` checks the shared typing needed to keep
the written record annotation intact, including nested types and generic binders.
The `test:m14:cpp-managed-closure-abi` npm command includes both tests.

This fixture proves expression evaluation and field publication. The normal
compiler still needs a startup plan for default values, initialization order,
class startup methods, and once-only execution. Initializer locals and closures
also need their own storage plans. The observer does not establish those policies.
README Goals status is unchanged.
