This fixture checks the name tree used by Neko standard-library startup.
It loads the real providers and compares upstream with both native layouts:

```sh
haxe test/m14_neko_boot_registry_test.hxml
```

The tree contains core types, the main class, and nested package entries.
Replacing the source Int binding does not replace its original tree entry.
The explicit untyped expressions observe this target runtime boundary; they
do not permit untyped compiler implementation.

The smaller renderer test is `m14_neko_named_type_registry_test.hxml`.
It checks nesting, identity, deterministic order, and conflicting-name rejection.
That test does not replace this real-provider startup contract.
