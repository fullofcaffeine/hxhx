# Enum abstract context value

A bare value of an enum abstract declared in another module (`Fast` for `pk.Mode`) resolves through the expected type, as in Haxe 4.3.7: `Speeds.speed(fast ? Fast : Slow)`.

Run `node_modules/.bin/haxe test/m14_enum_abstract_context_value_test.hxml`. `pk/Mode.hx` is the second module; the observed class `Ops` takes simple inputs.
