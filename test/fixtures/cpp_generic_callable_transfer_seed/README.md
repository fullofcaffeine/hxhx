# Generic callback storage

This program stores concrete callbacks in generic fields and reads them through
nullable and non-nullable function aliases. Aliases must retain one identity.
Generic null survives a nullable result destination. A concrete Int or Bool
destination converts null to zero or false. Concrete callback parameters apply
the same conversion when generic code supplies null.

Int, Bool, and object callbacks also pass through generic function parameters.
Replacing or clearing a field must preserve earlier callback aliases. Object
callbacks retain the same returned object, observe changes to a captured variable,
and preserve null through generic parameters and results. Invocation counts detect
extra calls during conversion or reassignment. Forced collection checks that the
captured objects remain alive until their callbacks are released.

Conditional expressions check both branch orders for Int and Bool. A nullable
destination keeps the selected null, while a concrete destination converts it.
Only the selected callback runs, exactly once.
Switch expressions also preserve null: a null callback result does not match
zero or false, and an explicit null pattern can select it.

The program throws on a changed result, repeated invocation, changed identity,
or incorrect null conversion. Successful execution produces no output.

Run the local native and forced-collection sanitizer checks with:

```sh
haxe test/m14_cpp_generic_callable_transfer_test.hxml
```

The upstream reference is Haxe 4.3.7 with hxcpp 4.3.2. Interpreter behavior differs
for concrete scalar null conversion, so interpreter execution is not the native
expectation. Broader callback coverage, performance, and PR92 integration remain
tracked in `haxe_ocaml-dxkqh`.
