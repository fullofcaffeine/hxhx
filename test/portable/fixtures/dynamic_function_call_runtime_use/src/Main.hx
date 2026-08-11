/** Proves evaluation order and runtime behavior for calls through `Dynamic`. */
class Main {
	static function argument(value:Int):Int {
		Sys.println("arg=" + value);
		return value;
	}

	static function textArgument(value:String):String {
		Sys.println("text=" + value);
		return value;
	}

	static function selectCallee(label:String):Int {
		Sys.println(label);
		return 0;
	}

	static function main():Void {
		final callables:Array<Dynamic> = [function(left:Int, right:Int):Int return left + right];
		final sum:Dynamic = callables[selectCallee("computed-callee")](argument(1), argument(2));
		Sys.println("sum=" + sum);
		final zeroCallables:Array<Dynamic> = [function():Int return 7];
		final zero:Dynamic = zeroCallables[selectCallee("zero-callee")]();
		Sys.println("zero=" + zero);
		final voidCallables:Array<Dynamic> = [function(value:Int):Void Sys.println("void=" + value)];
		voidCallables[selectCallee("void-callee")](argument(3));
		final variadic:Dynamic = Reflect.makeVarArgs(function(arguments:Array<Dynamic>):Dynamic {
			return arguments.join("|");
		});
		final varArgsCallables:Array<Dynamic> = [variadic];
		final joined:Dynamic = varArgsCallables[selectCallee("varargs-callee")](textArgument("a"), textArgument("b"));
		Sys.println("varargs=" + joined);
		final nested = function():Dynamic {
			final nestedCallables:Array<Dynamic> = [function(value:Int):Int return value * 2];
			return nestedCallables[selectCallee("nested-callee")](argument(4));
		};
		Sys.println("nested=" + nested());
	}
}
