# Shared Map literal types

Arrow literals must have the standard library's `haxe.ds.Map<K, V>` type before
target generation. This fixture checks integer, string, object, and enum keys.
It also checks a written return type, a generic value type, and an ordinary array.

Array controls include anonymous objects, nested arrays, and a generic element.
Inferred element types must retain their structural fields and exact generic
binder. Converting these types to display text and parsing them again loses
that information before a target can select storage.

```sh
haxe -cp test/oracle/shared_map_literal_typing_seed/src -main Main --interp
haxe test/m14_shared_map_literal_typing_test.hxml
```

The runtime output must match `expected.stdout`. The shared typing test loads
real standard-library providers through the production resolver. It compares
provider identities and type arguments, including the generic method's binder.

This typing proof does not establish native Map behavior. The C++ runtime tests
and full-provider checks remain required. Context-dependent empty literals and
heterogeneous key/value inference require separate compatibility evidence.

The `contextual` program checks empty literals in fields, locals, returns,
arguments, and generic returns. It includes an empty `Array<Int>` control.
It also checks parameter contexts supplied by a generic call's other argument.
Upstream passes its expected stdout. The shared typing regression checks fifteen
literal nodes across thirteen contexts against exact collection types. Empty literals previously became
`Array<Dynamic>`.

Extension-call cases check the explicit argument's parameter offset and generic
evidence from the receiver. The generic case compares the Map value type with
the caller's exact type parameter, so an unrelated callee parameter cannot pass.

Conditional-expression cases check both branches of `?:`. An expected Map type
must reach both empty branches; an expected Array type must reach the empty
branch beside a populated array. The test counts every literal so a missing
branch cannot silently remove coverage.

The metadata-overload examples check their primary declaration's context. They
do not prove that all metadata overloads enter the shared declaration index.
The separate `ambiguous` fixture uses two explicit overload declarations and
checks that both are indexed. Both upstream and the shared typer must reject
its empty-literal call as ambiguous.

```sh
haxe -cp test/oracle/shared_map_literal_typing_seed/contextual -main Main --interp
haxe test/m14_contextual_map_literal_typing_test.hxml
haxe test/m14_empty_literal_overload_test.hxml
```

The fixtures import `haxe.ds.Map` explicitly. The unqualified root `Map` alias
and other nested expression contexts still need coverage
and implementation under `haxe_ocaml-ale78`. These checks do not establish
complete contextual typing or native Map runtime behavior.
