# Methods on nested Map lookups

Retrieve an inner Map and use its ordinary methods without changing the Haxe
source between eval and native builds. Previously, native planning rejected the
nullable lookup result while preparing the method receiver.

This fixture keeps the original failing observer. It also checks outer and inner
Map key families, mutation through aliases, reference identity, and evaluation
order. A missing lookup must throw before evaluating the inner method arguments.
Only exact target lookup producers enter this checked storage path. Arbitrary
nullable locals and user methods do not gain that permission.

Expression lowering may store a lookup result in a temporary. Its proof is
retained only when one write precedes the read in the same statement block,
the value is not captured, and the producer still satisfies the lookup contract.
The focused `test:reflaxe-ocaml:single-write-source` check covers rejected writes,
captures, conditional assignments, and user methods.

Run from the repository root:

```sh
PATH="$PWD/node_modules/.bin:$PATH" \
  PORTABLE_FIXTURE_ALLOWLIST=nested_map_lookup bash scripts/test-portable.sh
```

Native execution and upstream Haxe/eval use the same independent expectation.
Report checks connect each nullable receiver to its checked native recovery.
