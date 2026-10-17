# JavaScript Array runtime types

Run `haxe test/m14_js_runtime_type_operands_test.hxml` from the repository root.
The command compares upstream Haxe 4.3.7 and candidate JavaScript through Node.

The authored program keeps Array type values in a field and a function result.
The host verifies that both values are the native Array constructor.
An Array-named parameter must not replace the type operand.
A closure must retain the same type and executable ownership.

The host supplies ordinary arrays, an array from another realm, an array-shaped
object, a string, null, the constructor, and an object with Array.prototype.
It also supplies forged interface metadata.
Every input must be read exactly once, in source order.
Upstream's JavaScript `is Array` uses prototype identity: the foreign-realm array
is false, and the object with Array.prototype is true.
Array-shaped objects and forged interface metadata remain false.

The final input replaces the host Array binding before returning an instance
of the replacement constructor. Both the instance test and a later type value
must observe that replacement. The host restores Array after the observations.

This focused test loads real Class and Array declaration providers.
The complete standard-library provider replay remains a separate acceptance
test; this fixture does not replace it or claim complete Std.isOfType behavior.
