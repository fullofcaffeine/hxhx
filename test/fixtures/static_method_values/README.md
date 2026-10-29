# Static methods used as values

An imported method alias must still refer to its selected provider after assignment
to a local variable. Two providers expose `choose`; their results distinguish them.
A local variable also shadows the imported alias. Expected output is:

```text
3
4
105
107
```

Run the upstream Haxe 4.3.7 comparison from the repository root:

```sh
mkdir -p .tmp/static-method-upstream
node_modules/.bin/haxe -cp test/fixtures/static_method_values -main Main \
  -js .tmp/static-method-upstream/main.js
node .tmp/static-method-upstream/main.js
```

Run `haxe test/m14_static_method_value_identity_test.hxml` for the local contract.
It checks generated JavaScript output, exact provider dependencies, and revision
changes when an unchanged alias selects another provider.

The selected static declaration now travels with the typed member read. Projection
uses that identity after import context is gone. This integration uses the member
resolver from `haxe_ocaml-pmsr1.1.2` and preserves that task's existing ownership.
Instance receiver binding, overloaded or generic method values, default-argument
validation and complete task acceptance remain separate required work.
