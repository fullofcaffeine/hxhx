/** Constructor order and payloads must agree with the selected JavaScript Type provider. */
enum Item {
	Empty;
	Value(value:Int);
}

/** Same-named constructors must use their own enum metadata. */
enum Other {
	Value(text:String);
}

/** Nested patterns must inspect the singleton enum object inside the payload. */
enum Envelope {
	Wrapped(item:Item);
}

/** Generic constructors also remain visible at a Dynamic boundary. */
enum Container<T> {
	Boxed(value:T);
}

/** Constant values intentionally differ from their case labels. */
enum abstract Label(String) {
	var Ready = "ready-value";
	var Waiting = "waiting-value";
}

/** Exercise real reflection and structural map comparison on independently created enum values. */
class Main {
	static final initial:Int = switch Item.Empty {
			case Empty: 11;
			case Value(_): 0;
		};

	static function matcher():Item->Bool
		return function(value:Item):Bool return switch value {
			case Empty: true;
			case Value(_): false;
		};

	static function label(value:Label):Int
		return switch value {
			case Ready: 1;
			case Label.Waiting: 2;
			case _: 0;
		};

	static function other(value:Other):String
		return switch value {
			case Other.Value(text): text;
		};

	static function isEmpty(value:Item):Bool
		return switch value {
			case Item.Empty: true;
			case Item.Value(_): false;
		};

	static function nested(value:Envelope):Int
		return switch value {
			case Wrapped(Empty): 1;
			case Wrapped(Value(number)): number;
			case _: 0;
		};

	/** Dynamic is intentional here: this regression verifies the explicit untyped input boundary. */
	static function dynamicItem(value:Dynamic):Int
		return switch value {
			case Item.Empty: 0;
			case Item.Value(number): number;
			case _: -1;
		};

	/** A visible bare singleton must retain its declaration without a nominal input type. */
	static function dynamicBare(value:Dynamic):Bool
		return switch value {
			case Empty: true;
			case _: false;
		};

	/** The selected constructor supplies the concrete payload type below a Dynamic input. */
	static function dynamicNested(value:Dynamic):Int
		return switch value {
			case Envelope.Wrapped(Empty): 1;
			case Envelope.Wrapped(Value(number)): number;
			case _: 0;
		};

	/** Generic payload types are erased only at this explicitly Dynamic boundary. */
	static function dynamicContainer(value:Dynamic):Bool
		return switch value {
			case Container.Boxed(Item.Empty): true;
			case _: false;
		};

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
		if (!Type.enumEq(Item.Value(7), Item.Value(7))
			|| Type.enumEq(Item.Value(7), Item.Value(8))
			|| !Type.enumEq(Type.typeof(Item.Empty), Type.typeof(Item.Value(7))))
			throw "constrained enum comparison";
		if (dynamicItem(Item.Empty) != 0
			|| dynamicItem(Item.Value(7)) != 7
			|| !dynamicBare(Item.Empty)
			|| dynamicBare(Item.Value(7)))
			throw "dynamic pattern declaration";
		if (dynamicNested(Wrapped(Item.Empty)) != 1 || dynamicNested(Wrapped(Item.Value(7))) != 7)
			throw "dynamic nested pattern declaration";
		if (!dynamicContainer(Container.Boxed(Item.Empty)) || dynamicContainer(Container.Boxed(Item.Value(7))))
			throw "dynamic generic pattern declaration";
		final matches = matcher();
		if (initial != 11 || !matches(Item.Empty) || matches(Item.Value(3)))
			throw "initializer and closure pattern owner";
		if (label(Label.Ready) != 1 || label(Label.Waiting) != 2 || other(Other.Value("separate")) != "separate")
			throw "selected pattern declaration";
		if (!isEmpty(Item.Empty) || isEmpty(Item.Value(7)))
			throw "singleton expression pattern";
		if (nested(Wrapped(Item.Empty)) != 1 || nested(Wrapped(Item.Value(7))) != 7)
			throw "nested singleton pattern";
		var observed = 0;
		final singleton = Item.Empty;
		switch singleton {
			case Empty:
				observed = 3;
			case Value(_):
				observed = 9;
		}
		if (observed != 3)
			throw "singleton statement pattern";
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
