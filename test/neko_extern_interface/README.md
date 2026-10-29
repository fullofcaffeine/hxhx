# Extern interface runtime boundary

This fixture compares authored Haxe with upstream Haxe 4.3.7/Neko and both
generated Neko layouts. An extern interface has a null runtime type value.
Its class name is null and an instance check against it returns false.
An ordinary implemented interface still matches. An ordinary interface reached
only through an extern interface does not match at runtime.

Run `haxe test/m14_neko_extern_interface_integration_test.hxml`.

The test also checks parser integrity, declaration scanning, typed projection,
public revisions, and class rebuilding after generated members are added.
Those paths must preserve extern status and interface parents.

The real ArrayAccess declaration still requires standard-library loading work.
This fixture does not prove full extern-class, native binding, or typed-catch
support.
