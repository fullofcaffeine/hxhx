# Abstract inputs to ordinary calls

Run `haxe test/m14_abstract_input_conversion_integration_test.hxml` from the repository root.

The fixture passes a String and an object through declared abstract input
conversions. Shared typing must retain the selected method and an explicit
conversion to its parameter type. The argument runs once, and the stored value
keeps its content or object identity. Both Neko layouts must match upstream.

The focused checks ensure that missing declarations and incompatible storage
cannot select a plain cast. Executable conversion methods remain a separate requirement.
