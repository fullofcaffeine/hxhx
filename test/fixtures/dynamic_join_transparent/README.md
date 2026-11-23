# Dynamic join transparent

A Dynamic return or case value does not widen a concrete method result or switch value, as in Haxe 4.3.7. The other branches choose the type, in either order (`haxe.rtti.XmlParser.processElement`). A written result type casts each case to it, so `written(...):Dynamic` stays Dynamic.

When every branch is Dynamic, hxhx keeps a Dynamic result, while upstream leaves an open monomorph. The fixture does not cover that case.

Run `node_modules/.bin/haxe test/m14_dynamic_join_transparent_test.hxml`. The test compares input types and full signatures with upstream (observers in `test/fixtures/method_parameter_dynamic_context`), and runs the native output.
