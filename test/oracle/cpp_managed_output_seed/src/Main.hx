/** Output operands exercise exact primitive types and calls with visible effects. */
class Main {
	public static function values(flag:Bool, value:Int, text:String):Void {
		Sys.print(flag);
		Sys.print("|");
		Sys.print(value);
		Sys.print("|");
		Sys.println(text);
	}

	public static function effect(next:Void->Int):Void {
		Sys.println(next());
	}

	public static function text(next:Void->String):Void {
		Sys.print(next());
		Sys.println("tail");
	}

	public static function deferred(value:Int):Void->Void {
		return function():Void {
			Sys.println(value);
		};
	}

	/** Retain the erased input contract so formatting must inspect the actual runtime tag. */
	public static function erased(value:Dynamic):Void {
		Sys.println(value);
	}

	/** A callback must finish and its value stay rooted before output begins. */
	public static function erasedEffect(next:Void->Dynamic):Void {
		Sys.println(next());
	}

	/** Callable formatting has no supported contract, whether its type is explicit or erased. */
	public static function unsupported(value:Void->Void):Void {
		Sys.println(value);
	}

	static function main():Void {
		values(true, -2147483648, "hé\x00z");
		values(false, 2147483647, null);
		effect(function():Int {
			Sys.print("effect:");
			return 23;
		});
		text(function():String {
			Sys.print("text:");
			return "value:";
		});
		final escaped = deferred(7);
		escaped();
		try {
			effect(function():Int {
				throw "argument failure";
			});
		} catch (_:Dynamic) {
			Sys.println("after");
		}
		erased(null);
		erased(true);
		erased(false);
		erased(-2147483648);
		erased(2147483647);
		erased("hé\x00z");
		erasedEffect(function():Dynamic {
			Sys.print("dynamic:");
			return 29;
		});
	}
}

/** A matching method name on another owner must never acquire the Sys native binding. */
class Other {
	public static function println(value:Dynamic):Void {}
}
