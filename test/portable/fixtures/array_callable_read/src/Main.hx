class Main {
	static final afterHooks:Array<Void->Void> = [];
	static final typedHooks:Array<String->Int> = [];

	static function after():Void {
		Sys.println("after");
	}

	static function length(value:String):Int {
		return value.length;
	}

	static function register():Void {
		afterHooks.push(after);
		typedHooks.push(length);
	}

	static function run():Void {
		afterHooks[0]();
		Sys.println("typed=" + typedHooks[0]("hxhx"));
		Sys.println("guarded=" + guardedRead([10, 20], 1));
		Sys.println("missing=" + guardedRead([10, 20], null));
		Sys.println("direct=" + directRead([10, 20], 1));
		try {
			directRead([10, 20], null);
			Sys.println("null-index=accepted");
		} catch (_:Dynamic) {
			Sys.println("null-index=rejected");
		}
	}

	static function guardedRead(values:Array<Int>, index:Null<Int>):Int {
		if (index != null)
			return values[index];
		return -1;
	}

	static function directRead(values:Array<Int>, index:Null<Int>):Int {
		return values[index];
	}

	static function main():Void {
		register();
		run();
	}
}
