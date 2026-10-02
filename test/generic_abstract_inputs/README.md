# Applied abstract conversions

`Box<Int>` accepts and returns an integer through its declared header conversions.
`Box<String>` does the same for a string. The argument producer must run once,
before its returned value is printed.

Run `haxe test/m14_generic_abstract_conversion_test.hxml` from the repository root.
The test compares upstream Haxe with the native JavaScript target in Node.
It also checks exact conversion types, rejected undeclared
conversions, and conversion facts after typed expressions are rebuilt.
