# Class and interface membership

This fixture separates runtime type membership from constructor inheritance.
`Child` inherits `Parent`, which implements `Diamond`. That interface extends
both `Left` and `Right`, and both branches extend `Root`.

Upstream Haxe must report membership in all six types. An unrelated class and
the inverse parent-to-child check must return false. Both upstream interpreter
and Neko runs match `expected.stdout`.

Run the upstream reference:

```sh
haxe -cp test/runtime_type_assignability -main Main --interp
```

Run the shared parser and graph contract:

```sh
haxe test/m14_interface_inheritance_facts_integration_test.hxml
```

The shared graph retains every interface parent, rejects cycles, and reports
missing type information. Its constructor traversal follows only
`Child → Parent`. The separate inheritance-loading test covers aliases and
provider dependencies. Native Neko runtime predicates remain unfinished under
`haxe_ocaml-41m6r`; the graph test does not claim generated runtime parity.
