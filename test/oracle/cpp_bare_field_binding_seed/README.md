# Selected field bindings

An integer local named `int` can become `int_` in C++. A string field already has that name. The compiler must preserve both bindings.

The first two lines read an instance field and a static field. They must print `2WORD` and `3WORD`. The third line copies the integer into another local before it reads the instance field explicitly. It must print `2WORD`.

Upstream Haxe 4.3.7 confirms all three lines:

```sh
haxe -cp test/oracle/cpp_bare_field_binding_seed/src -main Main --interp
```

Run the C++ compiler and native observer:

```sh
haxe test/m14_cpp_bare_field_binding_integration_test.hxml
```

The field catalog selects the field and its owning class. Output names must not change that selection. A local initializer must also retain its selected local instead of guessing that a matching C++ spelling denotes a field.
