# Inherited Neko construction

Run `haxe test/m14_neko_inherited_construction_integration_test.hxml` from the repository root.

The base and derived classes observe field initialization, constructor effects,
virtual calls, inherited methods, and object identity. The base constructor must
receive the existing derived object. Its saved reference and inherited methods
must observe later changes to that same object.
The fixture also checks an omitted constructor with inherited defaults and a
third class level with explicit superclass calls.
An inherited setter has a parameter named `__hxhx_self`. That source name must
not shadow the generated receiver. A derived method also reads an inherited
field and calls an inherited method without an explicit receiver.

The expected output was authored for this fixture and verified with upstream
Haxe 4.3.7 on Neko. Both generated layouts must produce that output.
