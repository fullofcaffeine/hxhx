# Instance and aggregate string conversion

`InstanceContract.hx` checks ordinary instance conversion through the real `Std.string`
declaration. It covers inherited and overridden methods, receiver mutation, one-time
argument evaluation, allocation inside a conversion, null results, and thrown values.
It also checks ordinary and nested `haxe.ValueException` values.

Run `npm run test:m14:cpp-instance-string` for native execution and forced collection
under address and undefined-behavior sanitizers at `-O0` and `-O2`.

The independent reference is Haxe 4.3.7 with hxcpp 4.3.2:

```sh
haxe -cp test/oracle/cpp_object_string_seed -main InstanceContract \
  -cpp .tmp/cpp-object-string-reference -D HXCPP_COMPILE_THREADS=2
.tmp/cpp-object-string-reference/InstanceContract
```

Successful execution produces no output. Native C++ preserves a null returned by
`toString`. The interpreter converts that result to the text `null` instead.
Native default conversion prints a class's declared short name, including packaged
public and private classes. Compiler lookup paths remain separate identities.

`Main.hx` is the complete comparison. It also requires record callbacks, arrays,
record formatting, and two instantiations of a generic class. Run
`npm run test:m14:cpp-object-string` to compare candidate output with
`expected.cpp.stdout`. This broader test remains required even when the instance
contract passes. The complete native program now matches `expected.cpp.stdout`,
including records, record callbacks, arrays, and nested exception conversion.

`AggregateContract.hx` checks field order, nested records and arrays, null and thrown
callback results, and mutations made during conversion. A later field or array
element must see changes made by an earlier callback. Native record order differs
from alphabetical order and does not change when source fields are reordered.

Run `npm run test:m14:cpp-aggregate-string` for the focused native contract and
both sanitizer profiles with forced collection. Use the reference commands below
with `-main AggregateContract` to check it against upstream native C++. Successful
execution produces no output. This contract uses native expectations; interpreter
formatting and null-result behavior differ.

`GenericContract.hx` checks different applications of the same ordinary generic
class. `GenericBox<Int>` and `GenericBox<String>` must select their own compiled
methods while their class handles retain one public identity. The fixture also
covers repeated applications, interface calls, inherited overrides, explicit
`super` calls, field reads, and runtime class membership.

Run `npm run test:m14:cpp-generic-string` for normal native execution and both
sanitizer profiles with forced collection. Its compiler-fact controls reject
unrelated classes, malformed type arguments, stored-handle narrowing, and copied
or changed literal occurrences. Creating a class handle must not allocate an
instance layout. Use the reference commands above with `-main GenericContract`
and run the resulting `GenericContract` executable. Successful execution produces
no output. Both the reference interpreter and native target pass this contract.

Regenerate the upstream observations with the same compiler and hxcpp versions:

```sh
haxe -cp test/oracle/cpp_object_string_seed -main Main --interp
haxe -cp test/oracle/cpp_object_string_seed -main Main \
  -cpp .tmp/cpp-object-string-reference -D HXCPP_COMPILE_THREADS=2
.tmp/cpp-object-string-reference/Main
```

Compare each output with its own `expected.eval.stdout` or `expected.cpp.stdout`.
The different record formatting and null-result behavior are intentional reference
observations. Interpreter output must not replace the native expectation.

`haxe_ocaml-hcnk8` remains open for complete conversion, including
other callable signatures, non-callable conversion fields, cyclic aggregates,
field-hash collisions and Unicode ordering, and the separately reviewed Float
contract. These tests do not establish Full1 readiness or PR92 integration.
