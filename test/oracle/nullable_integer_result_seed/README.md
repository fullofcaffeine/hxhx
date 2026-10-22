# Nullable integer arithmetic results

A nullable integer operand remains nullable in the typed expression. Addition,
subtraction, multiplication, and remainder produce an `Int` result. The fixture
passes each result through an inferred local or directly to a named function.

Run the independent upstream Haxe 4.3.7 check:

```sh
haxe -cp test/oracle/nullable_integer_result_seed -main Main --macro 'TypeCheck.verify()' --interp
```

The macro checks twelve exact result types. The program checks twelve results
with present values. It does not assume that null arithmetic behaves identically
across targets. Existing null behavior belongs to `cpp_nullable_integer_seed`.

Run the local typing and native contract:

```sh
haxe test/m14_nullable_integer_result_test.hxml
```

The local check requires all twelve binary expressions to retain nullable
operands and produce `Int`. It then emits C++ and requests forced-collection
checks with AddressSanitizer and UndefinedBehaviorSanitizer at O0 and O2.

Native generation currently stops at remainder. Task `haxe_ocaml-6gjt1` owns
that missing operation and its zero-divisor exception prerequisite. The full
fixture remains intact. Shared result typing belongs to `haxe_ocaml-kk0df`.
This contract does not prove native acceptance, division or Float semantics,
or complete compatibility. README Goals readiness is unchanged.
