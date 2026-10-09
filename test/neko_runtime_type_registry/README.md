# Neko class objects and interface membership

This fixture compares authored Haxe with upstream Neko and both generated Neko
layouts. The base constructor observes the most-derived class. A class value
stored in an instance field equals the same class value from another chunk.
Type checks include inherited interfaces, a diamond, and unrelated classes.

Run the contract:

```sh
haxe test/m14_neko_runtime_type_registry_integration_test.hxml
```

The test also sends fabricated objects and a matching string directly to the
native predicate. Neither can replace an interned type object. An enum-style
constructor tag cannot masquerade as an instance class.

Ordinary fields and locals can use the preferred internal names. The compiler
selects different helper and instance-slot names for that program. Native
String and Array reflection names are also compared with upstream.

This fixture covers nominal class and interface checks. Static initialization,
exact Std.isOfType calls, and typed exception
conversion remain separate unfinished parts of haxe_ocaml-41m6r.
Special native carriers that bypass ordinary class construction still need
explicit type-object integration. This fixture does not prove their reflection.
