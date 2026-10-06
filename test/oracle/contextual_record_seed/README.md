# Contextual object literals

A declared record field supplies the storage type for a fresh object literal.
For example, `{item: value}` in a `{item:Dynamic}` destination stores a Boolean
through Dynamic while retaining the Boolean type of the child expression.

Run the authored reference with upstream Haxe 4.3.7:

```sh
haxe -cp test/oracle/contextual_record_seed -main Main --interp
haxe test/m14_contextual_record_typing_test.hxml
```

The reference must match `expected.stdout`. The shared typing regression checks
locals, returns, assignments, calls, nested records, and optional field absence.
It also rejects wrong field types, extra literal fields, and missing required
fields. The optional contract uses a typedef, which retains field metadata.
The low-level inline hint reader does not yet accept optional field syntax;
this regression does not claim that separate parser capability.

Native construction and Boolean identity are covered by the contextual methods
in `cpp_managed_record_read_seed`, through
`haxe test/m14_cpp_managed_closure_abi_integration_test.hxml`.
These checks do not replace the full numeric erasure or exception workloads.
