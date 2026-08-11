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

	static function add(left:Int, right:Int):Int
		return left + right;

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
	}
}
