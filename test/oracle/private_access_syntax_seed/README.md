# Private access syntax

This independently authored observer prints expression trees from upstream
Haxe 4.3.7. It reads no upstream compiler implementation.
Assignment metadata includes the right operand. Ordinary binary metadata
applies only to the annotated operand.

```sh
haxe -cp test/oracle/private_access_syntax_seed -main Main --interp > actual.stdout
diff -u test/oracle/private_access_syntax_seed/expected.stdout actual.stdout
haxe test/m14_private_access_syntax_test.hxml
```

The local regression checks these shapes, typed quote reconstruction, source
positions, and revision identity. Executable permission checks belong to
`M14PrivateAccessTest`; native execution belongs to the property fixture.
This does not establish native macro metadata support. That target contract
remains with `haxe_ocaml-o25kr`; `haxe_ocaml-je6m9` owns this permission.
