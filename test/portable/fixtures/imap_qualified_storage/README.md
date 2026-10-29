# Qualified standard Map storage

An inferred field can expose `haxe.ds.Map<K,V>` while a written annotation exposes the global `Map<K,V>` typedef. Both select the same standard storage.

This fixture compares inferred, global-typedef, and qualified instance fields. It exercises iteration through compiler-generated aliases and ordinary `IMap` arguments. The runtime must print three `true` lines followed by `3`, `4`, and `5`.

`VerifyContract.hx` accepts both exact standard names, including nullable forms. It rejects different owners, generic arguments, null policies, and storage carriers.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=imap_qualified_storage npm run test:portable
```

This regression does not change README Goals status or prove complete compiler bootstrap readiness.
