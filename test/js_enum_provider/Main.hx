/** Constructor order and payloads must agree with the selected JavaScript Type provider. */
enum Item {
	Empty;
	Value(value:Int);
}

/** Same-named constructors must use their own enum metadata. */
enum Other {
	Value(text:String);
}

/** Exercise real reflection and structural map comparison on independently created enum values. */
class Main {
	/**
		Boot's private untyped host API exposes an inferred structural parameter.
		Keep its required Dynamic boundary here, validate enum membership immediately,
		and return only the concrete String result used by the runtime assertion.
	 */
	static function providerString(value:Dynamic):String {
		if (!Reflect.isEnumValue(value))
			throw "provider formatter requires an enum value";
		return @:privateAccess js.Boot.__string_rec(value, "");
	}

	static function main():Void {
		if (Type.enumIndex(Item.Empty) != 0 || Type.enumIndex(Item.Value(7)) != 1)
			throw "enum index";
		if (Type.enumConstructor(Item.Empty) != "Empty" || Type.enumConstructor(Item.Value(7)) != "Value")
			throw "enum constructor";
		if (Type.getEnumName(Type.getEnum(Item.Value(7))) != "Item" || Type.getEnumName(Type.getEnum(Other.Value("text"))) != "Other")
			throw "enum owner";
		final otherPayload:String = Type.enumParameters(Other.Value("text"))[0];
		if (otherPayload != "text" || Type.enumIndex(Other.Value("text")) != 0)
			throw "same-named constructor metadata";
		if (!Reflect.isEnumValue(Item.Empty) || Reflect.isEnumValue({value: 7}))
			throw "enum recognition";
		if (Std.string(Item.Empty) != "Empty" || Std.string(Item.Value(7)) != "Value(7)")
			throw "enum stringification";
		// A first-class API value also exercises the retained Std.string body.
		final stringify = Std.string;
		final bootEmpty = stringify(Item.Empty);
		final bootValue = stringify(Item.Value(7));
		if (bootEmpty != "Empty" || bootValue != "Value(7)")
			throw "provider enum stringification";
		if (providerString(Item.Empty) != "Empty" || providerString(Item.Value(7)) != "Value(7)")
			throw "direct provider enum stringification";
		final value = Item.Value(7);
		// Type.enumParameters is the public Dynamic boundary. Narrow its value
		// through the checked enum argument contract before using it as an Int.
		final parameters = Type.enumParameters(value);
		final payload:Int = parameters[0];
		if (parameters.length != 1 || payload != 7 || Type.enumParameters(Item.Empty).length != 0)
			throw "enum parameters";
		parameters[0] = 9;
		final original:Int = Type.enumParameters(value)[0];
		if (original != 7)
			throw "enum parameter copy";
		final values = new Map<Item, Int>();
		values.set(Item.Value(1), 5);
		values.set(Item.Value(2), 6);
		if (values.get(Item.Value(1)) != 5 || values.get(Item.Value(2)) != 6)
			throw "structural enum keys";
		js.Syntax.code("console.log({0})", "JS_ENUM_PROVIDER:PASS");
	}
}
