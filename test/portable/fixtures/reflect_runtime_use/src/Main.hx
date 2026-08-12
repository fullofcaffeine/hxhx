enum ReflectRuntimeUseValue {
	Ready;
}

/**
	Proves the standard Reflect helpers through generated OCaml and its runtime.

	The fixture keeps the result observable. Stock Haxe 4.3.7 supplies the
	expected output, while the portable suite compiles and runs the same source.
**/
class Main {
	static final functionAtInitialization = Reflect.isFunction(add);
	static final fieldAtInitialization = Reflect.field({name: "ready"}, "name");

	static function add(left:Int, right:Int):Int
		return left + right;

	/** Records one Dynamic argument evaluation and returns the value unchanged. */
	static function observeDynamic(events:Array<String>, label:String, value:Dynamic):Dynamic {
		events.push(label);
		return value;
	}

	/** Records one String argument evaluation and returns the value unchanged. */
	static function observeString(events:Array<String>, label:String, value:String):String {
		events.push(label);
		return value;
	}

	/** Records one Int argument evaluation and returns the value unchanged. */
	static function observeInt(events:Array<String>, label:String, value:Int):Int {
		events.push(label);
		return value;
	}

	static function main():Void {
		final callable:Dynamic = add;
		final value = {name: "ready"};
		final enumValue = ReflectRuntimeUseValue.Ready;

		Sys.println("call=" + Reflect.callMethod(null, callable, [2, 3]));
		Sys.println("function=" + Reflect.isFunction(callable) + "," + Reflect.isFunction(value));
		Sys.println("object=" + Reflect.isObject(value) + "," + Reflect.isObject(1));
		Sys.println("enum=" + Reflect.isEnumValue(enumValue) + "," + Reflect.isEnumValue(value));
		Sys.println("methods=" + Reflect.compareMethods(callable, callable));
		Sys.println("initializer=" + functionAtInitialization);
		Sys.println("field-initializer=" + fieldAtInitialization);
		final nested = () -> Reflect.isFunction(callable);
		Sys.println("nested=" + nested());

		final variadic:Dynamic = Reflect.makeVarArgs(function(arguments:Array<Dynamic>):Dynamic {
			return arguments.length;
		});
		Sys.println("varargs=" + Reflect.callMethod(null, variadic, ["a", "b", "c"]));

		final observed:Array<String> = [];
		final variadicVoid:Dynamic = Reflect.makeVarArgs(function(arguments:Array<Dynamic>):Void {
			observed.push(arguments.join("|"));
		});
		Reflect.callMethod(null, variadicVoid, ["x", "y"]);
		Sys.println("void=" + observed.join(","));

		final fieldEvents:Array<String> = [];
		final fieldsValue:Dynamic = {name: "ready", value: 1};
		Sys.println("field=" + Reflect.field(observeDynamic(fieldEvents, "field-object", fieldsValue), observeString(fieldEvents, "field-name", "value")));
		final nestedField = () -> Reflect.field(fieldsValue, "name");
		Sys.println("nested-field=" + nestedField());
		Sys.println("property="
			+ Reflect.getProperty(observeDynamic(fieldEvents, "property-object", fieldsValue), observeString(fieldEvents, "property-name", "name")));
		Reflect.setField(observeDynamic(fieldEvents, "set-object", fieldsValue), observeString(fieldEvents, "set-name", "value"),
			observeInt(fieldEvents, "set-value", 7));
		Sys.println("set=" + fieldsValue.value);
		Sys.println("has=" + Reflect.hasField(observeDynamic(fieldEvents, "has-object", fieldsValue), observeString(fieldEvents, "has-name", "value")));
		final fieldNames = Reflect.fields(observeDynamic(fieldEvents, "fields-object", fieldsValue));
		fieldNames.sort(Reflect.compare);
		Sys.println("fields=" + fieldNames.join(","));
		final copied:Dynamic = Reflect.copy(observeDynamic(fieldEvents, "copy-object", fieldsValue));
		fieldsValue.value = 9;
		Sys.println("copy=" + copied.value + ",original=" + fieldsValue.value);
		Sys.println("delete="
			+ Reflect.deleteField(observeDynamic(fieldEvents, "delete-object", fieldsValue), observeString(fieldEvents, "delete-name", "value")));
		Sys.println("field-order=" + fieldEvents.join("|"));
	}
}
