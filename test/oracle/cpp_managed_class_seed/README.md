# Managed class construction

Run `haxe test/m14_cpp_managed_class_test.hxml` from the repository root.

The fixture constructs ordinary classes through the normal C++ target. It checks
constructor argument order, nested object fields, final-field initialization,
field receiver effects before assigned values, static initialization, and
construction inside a closure. A second class has a same-named field.
Compound writes cover static, local, and instance storage. The instance test
changes the same field during the right-hand expression; the result must use
the value saved before that change.

Expected output is independently written and checked with upstream Haxe 4.3.7.
The native observer forces collection at every allocation and uses address and
undefined-behavior sanitizers at both optimization levels. Source construction
and field access must use exact typed declaration records.

This fixture does not replace the original Map contracts or prove inheritance,
virtual calls, generic class specialization, property accessors, or field initializer order.
