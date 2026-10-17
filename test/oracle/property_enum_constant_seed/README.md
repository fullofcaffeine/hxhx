# Enum constant reads

Reading an enum-abstract constant must preserve its declared type and value.
The constant does not need a property storage slot. This fixture checks integer
and string constants through their abstract instance methods.

Run the independent upstream checks from the repository root:

```sh
haxe -cp test/oracle/property_enum_constant_seed -main Main --interp
haxe -cp test/oracle/property_enum_constant_seed -main Main -neko /tmp/property_enum_constant_seed.n
neko /tmp/property_enum_constant_seed.n
```

Both commands must finish without output or an exception.

Run the shared compiler regression with:

```sh
haxe test/m14_typed_property_test.hxml
```

That test checks both constant values and their declared abstract types. It also
rejects constant writes, cyclic initializers, and fields from another declaration
index. The existing property accessor checks remain part of the same test.
