# Null local assignment

A local declared as bare `null` takes its type from the first assigned value, and a generic constructor assigned to it takes its type arguments from later uses, as in Haxe 4.3.7. `haxe.rtti.XmlParser` declares `var args = null` and `var t = null` this way.

Run `node_modules/.bin/haxe test/m14_null_local_assignment_test.hxml`. The test compares input types with upstream and runs the native output.
