# Property access

The authored assertions check ordinary getters and setters through base references,
including overridden getters and direct parent calls. Assignments and prefix updates
return the setter result; postfix updates return the old getter result.

The fixture also checks implicit and static properties, read-only properties,
single evaluation, an allocating argument, explicit `@:isVar` storage, and a
`default,set` property whose setter accesses its own stored field.
An explicit `untyped` expression checks restricted access to a declared stored
field. The field's type and runtime expectation remain concrete.

Structured `@:privateAccess` expressions check restricted reads, assignment
scope, block scope, local declarations, returns, and prefix/postfix updates.
Annotated virtual properties still invoke their getter and setter.
The separate strict typing regression rejects permission leakage, type
mismatches, parenthesized writes, and forbidden `never` access:

```sh
haxe test/m14_private_access_test.hxml
haxe test/m14_private_access_syntax_test.hxml
```

Run the independent upstream reference:

```sh
haxe -cp test/oracle/cpp_property_accessor_seed -main Main --interp
```

Run the native regression:

```sh
haxe test/m14_cpp_property_accessor_test.hxml
```

Successful execution has no output. These focused checks do not establish full
exception support or Haxe compatibility. The tracked owner is `haxe_ocaml-17vd4`.
