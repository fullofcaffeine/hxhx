# Native Neko String construction

Run `haxe test/m14_neko_native_string_constructor_integration_test.hxml` from the repository root.

The fixture loads the installed Neko standard-library String declaration. Native
construction must preserve its argument effect and produce a native string.
The qualified `ordinary.String` class must keep its object constructor and field.
Both generated Neko layouts must match the independent upstream output.

Project resolution also loads `StdTypes` implicitly. Its `ArrayAccess` declaration
must be available when the real Neko providers declare their implemented interfaces.
Run `haxe test/m14_standard_types_loading_integration_test.hxml` to check this
default scope, import aliases, local names, and initial field signatures.

The test rejects a generated object constructor for the core String type. It
does not establish general standard-library or exception compatibility.
