# Generic abstract storage on native C++

This program checks when generic null becomes a concrete scalar. A callback in
`Box<T>` returns null, which remains visible inside its constructor. A concrete
`Box<Int>` destination receives zero; `Box<Bool>` receives false. String storage
retains null. A generic holder retains null until a concrete assignment converts
a copy, leaving the original holder unchanged. The fixture also applies an
abstract as T and checks a non-generic Int receiver fed by a callback.

Run the upstream native reference with Haxe 4.3.7 and hxcpp 4.3.2:

```sh
haxe -cp test/oracle/cpp_generic_abstract_storage_seed -main Main -cpp .tmp/generic-abstract-upstream
.tmp/generic-abstract-upstream/Main
```

Success exits with code zero and no output. The interpreter preserves null in
concrete Int and Bool values, so it is not the reference for these native storage
assertions.

Run the managed target regression:

```sh
haxe test/m14_cpp_generic_abstract_storage_test.hxml
```

The driver executes authored Haxe through normal target generation, then runs
ASan and UBSan at O0 and O2 with collection before every allocation. Only the
program static root may remain afterward. The existing constructor-application
regression separately checks exact owner, binder, and source-revision rejection.
