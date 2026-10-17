# Managed C++ reflection boundaries

The fixture keeps class instances, enum instances, and their metadata handles
distinct. Public lookup returns the same identity as a source type literal.
The standard class predicate accepts a class obtained through lookup. An enum
argument with a side effect runs once. Real `ValueType.TClass` and `TEnum`
constructors carry the two metadata categories through enum payloads.

The authored expected output is checked against upstream Haxe 4.3.7 eval:

```sh
haxe -cp test/oracle/cpp_managed_reflection_seed/src -main Main --interp
```

Run the native compiler, build, and process-output comparison with:

```sh
HXHX_M14_SMOKE_GROUP=reflection_boundaries npm run test:m14:cpp-runtime-class-value
```

The regular test command includes this fixture. The original metadata fixture
also runs its unchanged program with forced collection under ASan and UBSan.
Null lookup names have unspecified behavior in the public Haxe API; a separate
native observer checks the selected exception behavior without claiming it as
a portable guarantee.

The `unsupported` source uses a host class without a managed reflection binding.
The `unsupported_reflection` group requires a compile-time error and checks that
the target preserves prior output files. Identity-only host handles still work
in programs that do not select reflection.
