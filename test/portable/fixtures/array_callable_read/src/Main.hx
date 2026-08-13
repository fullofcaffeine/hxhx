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
	}

	static function main():Void {
		register();
		run();
	}
}
