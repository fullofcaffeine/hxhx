/** Calls the same generic instance methods at distinct concrete types. */
class First {
	/** Observes receiver-first evaluation and eager, once-only callback creation. */
	public static function evaluation(scope:Scope):String {
		final events:Array<String> = [];
		final ignored = receiver(scope, events).skip(callback(events), fallback(events));
		final repeated = receiver(scope, events).twice(callback(events));
		return ignored + ":" + repeated + ":" + events.join(",");
	}

	static function receiver(scope:Scope, events:Array<String>):Scope {
		events.push("receiver");
		return scope;
	}

	static function callback(events:Array<String>):() -> Int {
		events.push("callback");
		var calls = 0;
		return () -> {
			events.push("invoke");
			return ++calls;
		};
	}

	static function fallback(events:Array<String>):Int {
		events.push("fallback");
		return 7;
	}

	public static function enter(scope:Scope):Void {
		scope.entered();
	}

	public static function number(scope:Scope, value:Int):Int {
		return scope.within(() -> value) + 1;
	}

	public static function text(scope:Scope):String {
		return scope.within(() -> "ready").toUpperCase();
	}

	public static function flag(scope:Scope, value:Bool):Bool {
		return scope.within(() -> value);
	}

	/** Nullable scalar storage must keep null distinct from zero and false. */
	public static function nullableNumber(scope:Scope, value:Null<Int>):Null<Int> {
		return scope.within(() -> value);
	}

	public static function nullableFlag(scope:Scope, value:Null<Bool>):Null<Bool> {
		var calls = 0;
		final result = scope.within(() -> {
			calls++;
			return value;
		});
		if (calls != 1)
			throw "nullable callback must execute once";
		return result;
	}

	public static function describeNullableFlag(scope:Scope, value:Null<Bool>):String {
		return scope.describe(value);
	}

	public static function values(scope:Scope, input:Array<Int>):Array<Int> {
		return scope.within(() -> input);
	}

	public static function missing(scope:Scope):Null<String> {
		return scope.within(() -> null);
	}

	public static function failing(scope:Scope):Int {
		return scope.within(() -> scope.fail("boom"));
	}

	public static function nested(scope:Scope):Bool {
		return scope.within(() -> {
			final inner = scope.within(() -> scope.active);
			return inner && scope.active;
		});
	}
}
